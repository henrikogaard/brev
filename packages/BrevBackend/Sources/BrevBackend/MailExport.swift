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

public struct MBOXExporter: Sendable {
    public init() {}

    public func export(
        messages: [ImportedMessage],
        to url: URL,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws {
        let total = messages.count
        let fm = FileManager.default
        fm.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw MailExportError.cannotOpenFile(url.lastPathComponent)
        }
        defer { try? handle.close() }

        for (index, message) in messages.enumerated() {
            try append(message: message, to: handle)
            progress?(index + 1, total)
        }
    }

    /// Appends one message to an mbox stream.
    ///
    /// `message.bodyData` is written verbatim after the `From ` envelope line, so
    /// it must be the **complete** RFC 822 message (headers + blank line + body).
    /// `message.from`/`message.date` populate only the envelope line.
    public func append(message: ImportedMessage, to handle: FileHandle) throws {
        let fromLine = mboxFromLine(for: message)
        if let fromData = (fromLine + "\n").data(using: .utf8) {
            try handle.write(contentsOf: fromData)
        }
        let escapedBody = escapeFromLines(message.bodyData)
        try handle.write(contentsOf: escapedBody)
        let separator = "\n".data(using: .utf8)!
        try handle.write(contentsOf: separator)
    }

    /// Writes one message as a standalone `.eml` file.
    ///
    /// This emits `message.headers`, a blank line, then `message.bodyData`, so
    /// `bodyData` must be the **body only** — passing a full raw message would
    /// duplicate the header block. (Note this is the opposite expectation from
    /// `append(message:to:)`, which takes the complete message.)
    public func exportToEML(
        message: ImportedMessage,
        to url: URL
    ) throws {
        var data = Data()
        for (name, value) in message.headers {
            if let line = "\(name): \(value)\n".data(using: .utf8) {
                data.append(line)
            }
        }
        data.append("\n".data(using: .utf8)!)
        data.append(message.bodyData)
        try data.write(to: url)
    }

    private func mboxFromLine(for message: ImportedMessage) -> String {
        let sender = message.from ?? "unknown@unknown"
        let dateStr = message.date ?? "Thu Jan  1 00:00:00 1970"
        return "From \(sender) \(dateStr)"
    }

    private func escapeFromLines(_ data: Data) -> Data {
        guard let content = String(data: data, encoding: .utf8) else {
            return data
        }
        let lines = content.components(separatedBy: "\n")
        let escaped = lines.map { line -> String in
            // mboxrd: prepend ">" to any line that is "From " possibly already
            // preceded by ">" quotes (not just the unquoted form), so the reader
            // can strip exactly one level back and the round-trip is lossless.
            // Escaping only "From " here would let an original ">From " line be
            // mis-unquoted to "From " on import.
            if line.drop(while: { $0 == ">" }).hasPrefix("From ") {
                return ">" + line
            }
            return line
        }
        return Data(escaped.joined(separator: "\n").utf8)
    }
}

public enum MailExportError: Error, Sendable, LocalizedError {
    case cannotOpenFile(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cannotOpenFile(let name):
            String(localized: "Cannot open file for writing: \(name)", bundle: .module)
        case .writeFailed(let reason):
            String(localized: "Export write failed: \(reason)", bundle: .module)
        }
    }
}
