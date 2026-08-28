/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the conditions in the LICENSE file.
 */

import Foundation

// MARK: - Shared result type

/// The result of parsing a single mail message from an archive.
public struct ImportedMessage: Sendable {
    /// RFC 2822 headers, ordered as they appeared in the file.
    public let headers: [(name: String, value: String)]
    /// Raw body bytes (may be MIME multi-part, encoded, etc.).
    public let bodyData: Data
    /// Source file path, if known.
    public let sourceURL: URL?

    public init(
        headers: [(name: String, value: String)],
        bodyData: Data,
        sourceURL: URL? = nil
    ) {
        self.headers = headers
        self.bodyData = bodyData
        self.sourceURL = sourceURL
    }

    /// Convenience accessor for a named header (case-insensitive, first match).
    public func header(_ name: String) -> String? {
        let lower = name.lowercased()
        return headers.first { $0.name.lowercased() == lower }?.value
    }

    public var subject: String? { header("Subject") }
    public var from: String? { header("From") }
    public var date: String? { header("Date") }
    public var messageID: String? { header("Message-ID") }
}

/// Summary of an import/parse operation.
public struct MailImportResult: Sendable {
    public let messages: [ImportedMessage]
    public let parseErrors: [String]
    public let sourceURL: URL?

    public init(messages: [ImportedMessage], parseErrors: [String] = [], sourceURL: URL? = nil) {
        self.messages = messages
        self.parseErrors = parseErrors
        self.sourceURL = sourceURL
    }
}

/// Summary for streaming/chunked import operations.
public struct MailImportStreamSummary: Sendable, Hashable {
    public let messageCount: Int
    public let parseErrors: [String]
    public let sourceURL: URL?

    public init(messageCount: Int, parseErrors: [String] = [], sourceURL: URL? = nil) {
        self.messageCount = messageCount
        self.parseErrors = parseErrors
        self.sourceURL = sourceURL
    }
}

public enum MailImportReadError: Error, Sendable, LocalizedError {
    case cannotOpenFile(String)
    case readFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cannotOpenFile(let name):
            String(localized: "Cannot open mail import source: \(name)", bundle: .module)
        case .readFailed(let reason):
            String(localized: "Mail import read failed: \(reason)", bundle: .module)
        }
    }
}

// MARK: - MBOX parser

/// Parser for the Unix MBOX format (RFC 4155).
///
/// Messages are separated by `From ` lines. The parser handles both
/// `mboxrd` (quoted `From` lines) and `mboxo`/`mboxcl` variants by
/// unescaping any `>From ` lines in the body.
///
/// The parser is deliberately lenient: it returns as many complete
/// messages as it can and records errors for malformed messages
/// instead of aborting. This matches user expectations when importing
/// archives that may have been produced by different mail clients.
public struct MBOXParser: Sendable {
    public init() {}

    /// Parse an MBOX file from disk.
    public func parse(contentsOf url: URL) -> MailImportResult {
        var messages: [ImportedMessage] = []
        do {
            let summary = try parseBatches(contentsOf: url) { batch in
                messages.append(contentsOf: batch)
            }
            return MailImportResult(
                messages: messages,
                parseErrors: summary.parseErrors,
                sourceURL: url
            )
        } catch {
            return MailImportResult(
                messages: [],
                parseErrors: [error.localizedDescription],
                sourceURL: url
            )
        }
    }

    /// Parse MBOX content from in-memory data.
    public func parse(data: Data) -> MailImportResult {
        guard let content = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else {
            return MailImportResult(
                messages: [],
                parseErrors: ["MBOX data is not valid UTF-8 or Latin-1."]
            )
        }
        return parseString(content)
    }

    /// Stream an MBOX file and emit messages in bounded batches.
    ///
    /// This avoids loading large archives into memory before the backend can
    /// persist imported messages. The callback is invoked on the caller's task.
    public func parseBatches(
        contentsOf url: URL,
        batchSize: Int = 100,
        onBatch: ([ImportedMessage]) throws -> Void
    ) throws -> MailImportStreamSummary {
        var accumulator = MBOXBatchAccumulator(batchSize: batchSize, sourceURL: url)
        try ChunkedLineReader(url: url).readLines { line in
            if let batch = accumulator.consume(line: line) {
                try onBatch(batch)
            }
        }
        if let batch = accumulator.finish() {
            try onBatch(batch)
        }
        return MailImportStreamSummary(
            messageCount: accumulator.messageCount,
            parseErrors: accumulator.errors,
            sourceURL: url
        )
    }

    /// Stream an MBOX file and emit messages in bounded async batches.
    public func parseBatches(
        contentsOf url: URL,
        batchSize: Int = 100,
        onBatch: ([ImportedMessage]) async throws -> Void
    ) async throws -> MailImportStreamSummary {
        var accumulator = MBOXBatchAccumulator(batchSize: batchSize, sourceURL: url)
        try await ChunkedLineReader(url: url).readLines { line in
            if let batch = accumulator.consume(line: line) {
                try await onBatch(batch)
            }
        }
        if let batch = accumulator.finish() {
            try await onBatch(batch)
        }
        return MailImportStreamSummary(
            messageCount: accumulator.messageCount,
            parseErrors: accumulator.errors,
            sourceURL: url
        )
    }

    // MARK: - Private

    private func parseString(_ content: String) -> MailImportResult {
        var messages: [ImportedMessage] = []
        var errors: [String] = []

        // Split on From_ separator lines.
        // A From_ line starts with "From " followed by the envelope sender
        // and a date. We use a simple scan rather than a regex to handle
        // edge cases like embedded newlines in long headers.
        var currentRaw: [String] = []
        var inMessage = false

        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("From "), !line.isEmpty {
                if inMessage, !currentRaw.isEmpty {
                    if let msg = parseMessage(currentRaw) {
                        messages.append(msg)
                    } else {
                        errors.append("Malformed message #\(messages.count + 1)")
                    }
                }
                currentRaw = []
                inMessage = true
            } else if inMessage {
                // Unescape mboxrd-style ">From " lines.
                let unescaped = line.hasPrefix(">From ") ? String(line.dropFirst()) : line
                currentRaw.append(unescaped)
            }
        }
        // Final message.
        if inMessage, !currentRaw.isEmpty {
            if let msg = parseMessage(currentRaw) {
                messages.append(msg)
            } else {
                errors.append("Malformed final message")
            }
        }
        return MailImportResult(messages: messages, parseErrors: errors)
    }

    private func parseMessage(_ lines: [String]) -> ImportedMessage? {
        var headers: [(String, String)] = []
        var bodyLines: [String] = []
        var inHeaders = true
        var currentHeaderName: String?
        var currentHeaderValue = ""

        for line in lines {
            if inHeaders {
                if line.isEmpty {
                    // Flush the last header.
                    if let name = currentHeaderName {
                        headers.append((name, currentHeaderValue.trimmingCharacters(in: .whitespaces)))
                    }
                    inHeaders = false
                    currentHeaderName = nil
                    currentHeaderValue = ""
                } else if line.hasPrefix(" ") || line.hasPrefix("\t") {
                    // Header folding (RFC 2822 §2.2.3).
                    currentHeaderValue += " " + line.trimmingCharacters(in: .whitespaces)
                } else if let colonIdx = line.firstIndex(of: ":") {
                    // New header.
                    if let name = currentHeaderName {
                        headers.append((name, currentHeaderValue.trimmingCharacters(in: .whitespaces)))
                    }
                    currentHeaderName = String(line[..<colonIdx])
                    currentHeaderValue = String(line[line.index(after: colonIdx)...])
                        .trimmingCharacters(in: .whitespaces)
                }
            } else {
                bodyLines.append(Self.unquotedMBOXBodyLine(line))
            }
        }
        // Flush any trailing header.
        if let name = currentHeaderName {
            headers.append((name, currentHeaderValue.trimmingCharacters(in: .whitespaces)))
        }
        guard !headers.isEmpty else { return nil }
        let body = bodyLines.joined(separator: "\n")
        return ImportedMessage(headers: headers, bodyData: Data(body.utf8))
    }

    /// mboxrd escapes a body line that begins with one or more ">" followed by
    /// "From " by prepending an extra ">". Undo that one level so the imported
    /// body matches the original message text (">From " → "From ", ">>From " →
    /// ">From "). Lines that aren't an escaped From-line are left untouched.
    private static func unquotedMBOXBodyLine(_ line: String) -> String {
        guard line.hasPrefix(">") else { return line }
        return line.drop(while: { $0 == ">" }).hasPrefix("From ")
            ? String(line.dropFirst())
            : line
    }

    private struct MBOXBatchAccumulator {
        let batchSize: Int
        let sourceURL: URL
        var currentRaw: [String] = []
        var inMessage = false
        var batch: [ImportedMessage] = []
        var errors: [String] = []
        var messageCount = 0

        init(batchSize: Int, sourceURL: URL) {
            self.batchSize = max(1, batchSize)
            self.sourceURL = sourceURL
        }

        mutating func consume(line: String) -> [ImportedMessage]? {
            if line.hasPrefix("From "), !line.isEmpty {
                let ready = flushCurrentMessage(final: false)
                currentRaw = []
                inMessage = true
                return ready
            }

            if inMessage {
                let unescaped = line.hasPrefix(">From ") ? String(line.dropFirst()) : line
                currentRaw.append(unescaped)
            }
            return nil
        }

        mutating func finish() -> [ImportedMessage]? {
            if let ready = flushCurrentMessage(final: true) {
                return ready
            }
            return drainBatchIfNeeded(force: true)
        }

        private mutating func flushCurrentMessage(final: Bool) -> [ImportedMessage]? {
            guard inMessage, !currentRaw.isEmpty else { return nil }
            if let message = MBOXParser().parseMessage(currentRaw) {
                batch.append(ImportedMessage(
                    headers: message.headers,
                    bodyData: message.bodyData,
                    sourceURL: sourceURL
                ))
                messageCount += 1
            } else {
                errors.append(final ? "Malformed final message" : "Malformed message #\(messageCount + 1)")
            }
            currentRaw = []
            return drainBatchIfNeeded(force: false)
        }

        private mutating func drainBatchIfNeeded(force: Bool) -> [ImportedMessage]? {
            guard !batch.isEmpty, force || batch.count >= batchSize else { return nil }
            let ready = batch
            batch.removeAll(keepingCapacity: true)
            return ready
        }
    }

    private struct ChunkedLineReader {
        let url: URL

        func readLines(_ handleLine: (String) throws -> Void) throws {
            guard let stream = InputStream(url: url) else {
                throw MailImportReadError.cannotOpenFile(url.lastPathComponent)
            }
            stream.open()
            defer { stream.close() }

            var pending = Data()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)

            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count < 0 {
                    throw MailImportReadError.readFailed(stream.streamError?.localizedDescription ?? "unknown error")
                }
                if count == 0 { break }

                pending.append(contentsOf: buffer[..<count])
                try emitCompleteLines(from: &pending, handleLine)
            }

            if !pending.isEmpty {
                try handleLine(Self.decodeLine(pending))
            }
        }

        func readLines(_ handleLine: (String) async throws -> Void) async throws {
            guard let stream = InputStream(url: url) else {
                throw MailImportReadError.cannotOpenFile(url.lastPathComponent)
            }
            stream.open()
            defer { stream.close() }

            var pending = Data()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)

            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count < 0 {
                    throw MailImportReadError.readFailed(stream.streamError?.localizedDescription ?? "unknown error")
                }
                if count == 0 { break }

                pending.append(contentsOf: buffer[..<count])
                try await emitCompleteLines(from: &pending, handleLine)
            }

            if !pending.isEmpty {
                try await handleLine(Self.decodeLine(pending))
            }
        }

        private func emitCompleteLines(
            from pending: inout Data,
            _ handleLine: (String) throws -> Void
        ) throws {
            while let newlineIndex = pending.firstIndex(of: 0x0A) {
                let lineData = Self.lineData(upTo: newlineIndex, in: pending)
                let removeEnd = pending.index(after: newlineIndex)
                pending.removeSubrange(pending.startIndex ..< removeEnd)
                try handleLine(Self.decodeLine(lineData))
            }
        }

        private func emitCompleteLines(
            from pending: inout Data,
            _ handleLine: (String) async throws -> Void
        ) async throws {
            while let newlineIndex = pending.firstIndex(of: 0x0A) {
                let lineData = Self.lineData(upTo: newlineIndex, in: pending)
                let removeEnd = pending.index(after: newlineIndex)
                pending.removeSubrange(pending.startIndex ..< removeEnd)
                try await handleLine(Self.decodeLine(lineData))
            }
        }

        private static func lineData(upTo newlineIndex: Data.Index, in data: Data) -> Data {
            var lineData = Data(data[data.startIndex ..< newlineIndex])
            if lineData.last == 0x0D {
                lineData.removeLast()
            }
            return lineData
        }

        private static func decodeLine(_ data: Data) -> String {
            String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
        }
    }
}

// MARK: - EML reader

/// Reader for individual RFC 2822 / `.eml` message files.
public struct EMLReader: Sendable {
    public init() {}

    /// Reads a single EML file from disk.
    public func read(contentsOf url: URL) -> MailImportResult {
        do {
            let data = try Data(contentsOf: url)
            return read(data: data, sourceURL: url)
        } catch {
            return MailImportResult(
                messages: [],
                parseErrors: [error.localizedDescription],
                sourceURL: url
            )
        }
    }

    /// Reads a single EML message from memory.
    public func read(data: Data, sourceURL: URL? = nil) -> MailImportResult {
        guard let content = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else {
            return MailImportResult(
                messages: [],
                parseErrors: ["EML data is not valid UTF-8 or Latin-1."],
                sourceURL: sourceURL
            )
        }

        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let wrapped = "From dummy@eml Thu Jan  1 00:00:00 1970\n" + normalized
        let result = MBOXParser().parse(data: Data(wrapped.utf8))
        let messages = result.messages.map {
            ImportedMessage(headers: $0.headers, bodyData: $0.bodyData, sourceURL: sourceURL)
        }
        let errors = messages.isEmpty && result.parseErrors.isEmpty
            ? ["Malformed EML message."]
            : result.parseErrors
        return MailImportResult(messages: messages, parseErrors: errors, sourceURL: sourceURL)
    }
}

// MARK: - Maildir reader

/// Reader for the Maildir format (Bernstein, 1995).
///
/// A Maildir folder contains three subdirectories: `cur` (read mail),
/// `new` (unread mail), and `tmp` (mail being delivered). Each message
/// is a separate file. File names encode flags in a colon-delimited
/// suffix after the unique ID.
public struct MaildirReader: Sendable {
    public init() {}

    /// Reads all messages from a Maildir directory.
    ///
    /// Returns messages from both `cur` and `new`. Files in `tmp` are
    /// skipped — they are delivery in progress and may be incomplete.
    public func read(contentsOf maildirURL: URL) -> MailImportResult {
        var messages: [ImportedMessage] = []
        var errors: [String] = []

        let fm = FileManager.default
        for subdir in ["cur", "new"] {
            let subdirURL = maildirURL.appendingPathComponent(subdir)
            guard let contents = try? fm.contentsOfDirectory(
                at: subdirURL,
                includingPropertiesForKeys: nil
            ) else { continue }

            for fileURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard fileURL.hasDirectoryPath == false else { continue }
                if let data = try? Data(contentsOf: fileURL) {
                    let result = EMLReader().read(data: data, sourceURL: fileURL)
                    messages.append(contentsOf: result.messages)
                    errors.append(contentsOf: result.parseErrors)
                } else {
                    errors.append("Cannot read Maildir file: \(fileURL.lastPathComponent)")
                }
            }
        }
        return MailImportResult(messages: messages, parseErrors: errors, sourceURL: maildirURL)
    }

    /// Reads Maildir messages in bounded batches.
    ///
    /// Each Maildir entry is still read as a single message file, but the
    /// folder import no longer retains every message before persistence.
    public func readBatches(
        contentsOf maildirURL: URL,
        batchSize: Int = 100,
        onBatch: ([ImportedMessage]) async throws -> Void
    ) async throws -> MailImportStreamSummary {
        var batch: [ImportedMessage] = []
        var messageCount = 0
        var errors: [String] = []
        let flushThreshold = max(1, batchSize)

        func flushBatchIfNeeded(force: Bool) async throws {
            guard !batch.isEmpty, force || batch.count >= flushThreshold else { return }
            let ready = batch
            batch.removeAll(keepingCapacity: true)
            try await onBatch(ready)
        }

        let fm = FileManager.default
        for subdir in ["cur", "new"] {
            let subdirURL = maildirURL.appendingPathComponent(subdir)
            guard let contents = try? fm.contentsOfDirectory(
                at: subdirURL,
                includingPropertiesForKeys: nil
            ) else { continue }

            for fileURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard fileURL.hasDirectoryPath == false else { continue }
                if let data = try? Data(contentsOf: fileURL) {
                    let result = EMLReader().read(data: data, sourceURL: fileURL)
                    errors.append(contentsOf: result.parseErrors)
                    for message in result.messages {
                        batch.append(message)
                        messageCount += 1
                    }
                    try await flushBatchIfNeeded(force: false)
                } else {
                    errors.append("Cannot read Maildir file: \(fileURL.lastPathComponent)")
                }
            }
        }

        try await flushBatchIfNeeded(force: true)
        return MailImportStreamSummary(
            messageCount: messageCount,
            parseErrors: errors,
            sourceURL: maildirURL
        )
    }

    /// Parse a Maildir filename into its unique ID and flags.
    ///
    /// Format: `<unique-id>:2,<flags>` where flags is a sorted string
    /// of flag characters (`D`=draft, `F`=flagged, `P`=passed/forwarded,
    /// `R`=replied, `S`=seen, `T`=trashed).
    public static func parseFilename(_ filename: String) -> (uniqueID: String, flags: Set<MaildirFlag>) {
        let lastComponent = URL(fileURLWithPath: filename).lastPathComponent
        let parts = lastComponent.components(separatedBy: ":2,")
        let uniqueID = parts[0]
        let flagChars = parts.count > 1 ? parts[1] : ""
        let flags = Set(flagChars.compactMap { MaildirFlag(rawValue: $0) })
        return (uniqueID, flags)
    }
}

/// Standard Maildir flag characters.
public enum MaildirFlag: Character, Sendable, Hashable {
    case draft = "D"
    case flagged = "F"
    case passed = "P"
    case replied = "R"
    case seen = "S"
    case trashed = "T"
}
