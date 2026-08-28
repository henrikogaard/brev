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

import CryptoKit
import Foundation

public protocol IMAPSessionTransport: Sendable {
    func connect(to server: MailServerSettings) async throws
    func upgradeToTLS(server: MailServerSettings) async throws
    func readLine() async throws -> String
    func readData(maxLength: Int) async throws -> Data
    func writeLine(_ line: String) async throws
    func writeData(_ data: Data) async throws
    func disconnect() async
}

public extension IMAPSessionTransport {
    func upgradeToTLS(server: MailServerSettings) async throws {
        _ = server
        throw IMAPClientError.unsupportedTLSMode(.startTLS)
    }

    func writeData(_ data: Data) async throws {
        _ = data
        throw IMAPClientError.transport("IMAP transport does not support raw data writes.")
    }

    func readData(maxLength: Int) async throws -> Data {
        _ = maxLength
        throw IMAPClientError.transport("IMAP transport does not support raw data reads.")
    }
}

public enum IMAPClientError: Error, Equatable, LocalizedError, Sendable {
    case invalidServerKind(MailServerProtocolKind)
    case unsupportedTLSMode(MailServerTLSMode)
    case unsupportedSearchCriterion(String)
    case connectionRejected(String)
    case authenticationFailed(String)
    /// Provider refused the session because too many IMAP connections are open.
    /// Distinct from credential failure so callers can retry after cooldown.
    case connectionLimitExceeded(String)
    case commandFailed(command: String, response: String)
    /// The server does not provide a safe implementation for a requested command.
    case commandNotSupported(command: String, response: String)
    case malformedResponse(String)
    case transport(String)
    /// Server sent `* BYE` — the connection was closed gracefully by the server.
    /// Distinct from a transport error so callers can apply immediate-reconnect policy.
    case serverBye(reason: String)
    /// Server replied `NO` to IDLE — mailbox does not support IDLE for this session.
    /// Callers should fall back to polling rather than retrying IDLE.
    case idleNotSupported(response: String)

    public var errorDescription: String? {
        switch self {
        case .invalidServerKind:
            String(localized: "IMAP client received non-IMAP server settings.", bundle: .module)
        case .unsupportedTLSMode(let mode):
            String(localized: "IMAP transport does not support \(mode.rawValue) yet.", bundle: .module)
        case .unsupportedSearchCriterion(let criterion):
            String(localized: "IMAP search does not support \(criterion) yet.", bundle: .module)
        case .connectionRejected(let response):
            String(localized: "IMAP server rejected the connection: \(response)", bundle: .module)
        case .authenticationFailed:
            String(localized: "IMAP authentication failed.", bundle: .module)
        case .connectionLimitExceeded:
            String(localized: "IMAP connection limit exceeded. Wait a moment and try again.", bundle: .module)
        case .commandFailed(let command, let response):
            String(localized: "IMAP command \(command) failed: \(response)", bundle: .module)
        case .commandNotSupported(let command, let response):
            String(localized: "IMAP command \(command) is not supported: \(response)", bundle: .module)
        case .malformedResponse(let response):
            String(localized: "IMAP server returned an unreadable response: \(response)", bundle: .module)
        case .transport(let message):
            String(localized: "IMAP transport failed: \(message)", bundle: .module)
        case .serverBye(let reason):
            String(localized: "IMAP server closed the connection: \(reason)", bundle: .module)
        case .idleNotSupported(let response):
            String(localized: "IMAP server does not support IDLE: \(response)", bundle: .module)
        }
    }

    /// Returns `true` when an IMAP server response indicates a concurrent-session
    /// / connection-slot limit rather than bad credentials.
    public static func isConnectionLimitResponse(_ response: String) -> Bool {
        let uppercased = response.uppercased()
        // Gmail
        if uppercased.contains("TOO MANY SIMULTANEOUS CONNECTIONS") {
            return true
        }
        // Generic / provider variants
        if uppercased.contains("TOO MANY CONNECTIONS") {
            return true
        }
        if uppercased.contains("MAXIMUM NUMBER OF CONNECTIONS") {
            return true
        }
        if uppercased.contains("CONNECTION LIMIT") {
            return true
        }
        if uppercased.contains("CONNECTIONLIMIT") {
            return true
        }
        if uppercased.contains("MAX CONNECTIONS") {
            return true
        }
        if uppercased.contains("EXCEEDED THE CONNECTION") {
            return true
        }
        if uppercased.contains("TOO MANY OPEN CONNECTIONS") {
            return true
        }
        // Common IMAP response-code style
        if uppercased.contains("[UNAVAILABLE]") && uppercased.contains("CONNECTION") {
            return true
        }
        return false
    }

    /// Suggested cooldown before retrying after a connection-limit response.
    public static let connectionLimitRetryCooldownNanoseconds: UInt64 = 45_000_000_000

    /// Maps a tagged `NO` login/authenticate response to the most specific client error.
    static func authenticationOrConnectionLimitFailed(_ response: String) -> IMAPClientError {
        if isConnectionLimitResponse(response) {
            return .connectionLimitExceeded(response)
        }
        return .authenticationFailed(response)
    }
}

public struct IMAPAppendResult: Sendable, Hashable {
    public let uidValidity: Int?
    public let uid: Int?

    public init(uidValidity: Int? = nil, uid: Int? = nil) {
        self.uidValidity = uidValidity
        self.uid = uid
    }

    static func parse(from taggedResponse: String) -> IMAPAppendResult {
        // Search and slice the same string (see parseRawFlags): `uppercased()`
        // can change UTF-8 length, so indices from it must not slice the original.
        guard let markerRange = taggedResponse.range(of: "[APPENDUID ", options: .caseInsensitive) else {
            return IMAPAppendResult()
        }
        let payloadStart = markerRange.upperBound
        guard let payloadEnd = taggedResponse[payloadStart...].firstIndex(of: "]") else {
            return IMAPAppendResult()
        }
        let payload = taggedResponse[payloadStart ..< payloadEnd]
        let tokens = payload.split(whereSeparator: \.isWhitespace)
        guard tokens.count >= 2 else {
            return IMAPAppendResult()
        }
        return IMAPAppendResult(
            uidValidity: Int(tokens[0]),
            uid: Int(tokens[1])
        )
    }
}

struct IMAPLineBuffer: Sendable {
    private var storage = Data()

    /// Bytes buffered but not yet consumed as a line. Lets the reader bound
    /// memory when a server streams without a line terminator (MailTransportLimits).
    var pendingByteCount: Int { storage.count }

    mutating func append(_ data: Data) {
        storage.append(data)
    }

    mutating func takeLine() -> String? {
        if let crlfRange = storage.firstRange(of: Data([13, 10])) {
            let line = Data(storage[..<crlfRange.lowerBound])
            storage.removeSubrange(..<crlfRange.upperBound)
            return String(data: line, encoding: .utf8)
        }

        guard let lineFeedIndex = storage.firstIndex(of: 10) else {
            return nil
        }
        var line = Data(storage[..<lineFeedIndex])
        if line.last == 13 {
            line.removeLast()
        }
        storage.removeSubrange(...lineFeedIndex)
        return String(data: line, encoding: .utf8)
    }

    mutating func takeData(maxLength: Int) -> Data? {
        guard maxLength > 0, !storage.isEmpty else { return nil }
        let count = min(maxLength, storage.count)
        let data = Data(storage.prefix(count))
        storage.removeSubrange(..<storage.index(storage.startIndex, offsetBy: count))
        return data
    }
}

enum IMAPMailboxNameCodec {
    static func decode(_ value: String) -> String {
        var result = ""
        var index = value.startIndex

        while index < value.endIndex {
            guard value[index] == "&" else {
                result.append(value[index])
                value.formIndex(after: &index)
                continue
            }

            let sequenceStart = index
            let encodedStart = value.index(after: index)
            guard let end = value[encodedStart...].firstIndex(of: "-") else {
                result.append(value[index])
                value.formIndex(after: &index)
                continue
            }

            if encodedStart == end {
                result.append("&")
            } else {
                let encoded = String(value[encodedStart ..< end])
                result += decodeShiftedSequence(encoded)
                    ?? String(value[sequenceStart ... end])
            }
            index = value.index(after: end)
        }

        return result
    }

    static func encode(_ value: String) -> String {
        var result = ""
        var shifted = ""

        func flushShifted() {
            guard !shifted.isEmpty else { return }
            result += "&\(encodeShiftedSequence(shifted))-"
            shifted = ""
        }

        for character in value {
            if isDirectASCII(character) {
                flushShifted()
                if character == "&" {
                    result += "&-"
                } else {
                    result.append(character)
                }
            } else {
                shifted.append(character)
            }
        }
        flushShifted()
        return result
    }

    private static func decodeShiftedSequence(_ value: String) -> String? {
        var base64 = value.replacingOccurrences(of: ",", with: "/")
        while !base64.count.isMultiple(of: 4) {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64),
              let decoded = String(data: data, encoding: .utf16BigEndian)
        else {
            return nil
        }
        return decoded
    }

    private static func encodeShiftedSequence(_ value: String) -> String {
        let data = value.data(using: .utf16BigEndian) ?? Data()
        return data.base64EncodedString()
            .replacingOccurrences(of: "/", with: ",")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func isDirectASCII(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first
        else {
            return false
        }
        return scalar.value >= 0x20 && scalar.value <= 0x7E
    }
}

public struct IMAPFolderListing: Sendable, Hashable {
    public let path: String
    public let displayName: String
    public let delimiter: String
    public let flags: Set<String>
    public let role: FolderRole
    /// Populated only when the listing was fetched with unread counts
    /// (`loginAndListFolders(..., includingUnreadCounts: true)`); zero otherwise.
    public let totalCount: Int
    public let unreadCount: Int

    public init(
        path: String,
        displayName: String,
        delimiter: String,
        flags: Set<String>,
        role: FolderRole,
        totalCount: Int = 0,
        unreadCount: Int = 0
    ) {
        self.path = path
        self.displayName = displayName
        self.delimiter = delimiter
        self.flags = flags
        self.role = role
        self.totalCount = totalCount
        self.unreadCount = unreadCount
    }

    /// A copy of this listing carrying server-reported STATUS counts.
    func withCounts(totalCount: Int, unreadCount: Int) -> IMAPFolderListing {
        IMAPFolderListing(
            path: path,
            displayName: displayName,
            delimiter: delimiter,
            flags: flags,
            role: role,
            totalCount: totalCount,
            unreadCount: unreadCount
        )
    }

    public static func parse(_ line: String) -> IMAPFolderListing? {
        guard line.hasPrefix("* "),
              line.range(of: " LIST ", options: .caseInsensitive) != nil
        else { return nil }
        guard let flagsOpen = line.firstIndex(of: "("),
              let flagsClose = line[flagsOpen...].firstIndex(of: ")")
        else {
            return nil
        }

        let flags = parseFlags(String(line[line.index(after: flagsOpen) ..< flagsClose]))
        var index = line.index(after: flagsClose)
        guard let delimiter = parseToken(in: line, from: &index),
              let path = parseToken(in: line, from: &index)
        else {
            return nil
        }
        let normalizedDelimiter = delimiter.uppercased() == "NIL" ? "" : delimiter
        let decodedPath = IMAPMailboxNameCodec.decode(path)
        return IMAPFolderListing(
            path: decodedPath,
            displayName: displayName(for: decodedPath, delimiter: normalizedDelimiter),
            delimiter: normalizedDelimiter,
            flags: flags,
            role: role(for: decodedPath, flags: flags)
        )
    }

    private static func parseFlags(_ rawFlags: String) -> Set<String> {
        Set(rawFlags.split(whereSeparator: \.isWhitespace).map { flag in
            flag.trimmingCharacters(in: CharacterSet(charactersIn: "\\"))
                .lowercased()
        })
    }

    private static func parseToken(in line: String, from index: inout String.Index) -> String? {
        skipSpaces(in: line, from: &index)
        guard index < line.endIndex else { return nil }

        if line[index] == "\"" {
            line.formIndex(after: &index)
            var value = ""
            while index < line.endIndex {
                let character = line[index]
                line.formIndex(after: &index)
                if character == "\"" {
                    return value
                }
                if character == "\\", index < line.endIndex {
                    value.append(line[index])
                    line.formIndex(after: &index)
                } else {
                    value.append(character)
                }
            }
            return nil
        }

        let start = index
        while index < line.endIndex, !line[index].isWhitespace {
            line.formIndex(after: &index)
        }
        return String(line[start ..< index])
    }

    private static func skipSpaces(in line: String, from index: inout String.Index) {
        while index < line.endIndex, line[index].isWhitespace {
            line.formIndex(after: &index)
        }
    }

    private static func displayName(for path: String, delimiter: String) -> String {
        guard !delimiter.isEmpty else { return path }
        return path.components(separatedBy: delimiter).last ?? path
    }

    // Provider folder names by role (lower-cased). The IMAP special-use
    // attribute (RFC 6154, e.g. `\Sent`) is matched first; these cover servers
    // that don't advertise special-use, where role detection by name is the
    // only signal. Missing the Sent folder here means the Sent copy is never
    // filed (#194) — Gmail's "Sent Mail" and Outlook's "Sent Items" both used
    // to fall through to `.custom`.
    static let sentFolderNames: Set<String> = ["sent", "sent mail", "sent messages", "sent items", "sendt e-post", "sendt"]
    static let draftsFolderNames: Set<String> = ["drafts", "draft", "utkast"]
    static let trashFolderNames: Set<String> = [
        "trash", "deleted messages", "deleted items", "deleted", "bin",
    ]
    static let junkFolderNames: Set<String> = [
        "junk", "spam", "junk e-mail", "junk email", "bulk mail",
    ]
    static let archiveFolderNames: Set<String> = ["archive", "archives"]
    static let allMailFolderNames: Set<String> = [
        "all mail", "all messages", "all",
    ]

    static func role(for path: String, flags: Set<String>) -> FolderRole {
        let lowercasedPath = path.lowercased()
        let lastComponent = (lowercasedPath
            .components(separatedBy: CharacterSet(charactersIn: "/."))
            .last ?? lowercasedPath)
            .trimmingCharacters(in: .whitespaces)

        if lowercasedPath == "inbox" { return .inbox }
        if flags.contains("sent") || sentFolderNames.contains(lastComponent) { return .sent }
        if flags.contains("drafts") || draftsFolderNames.contains(lastComponent) { return .drafts }
        if flags.contains("trash") || trashFolderNames.contains(lastComponent) { return .trash }
        if flags.contains("junk") || junkFolderNames.contains(lastComponent) { return .spam }
        if flags.contains("archive") || archiveFolderNames.contains(lastComponent) { return .archive }
        if flags.contains("all") || allMailFolderNames.contains(lastComponent) { return .allMail }
        if flags.contains("starred") || lastComponent == "starred" { return .starred }
        // Gmail's \Important is a message label, not a mailbox role. Keep the
        // listing custom so the label remains available through X-GM-LABELS
        // without inventing a folder semantic that the UI cannot act on.
        return .custom
    }
}

/// The IMAP extension atoms a server advertised (RFC 3501 §7.2.1). Captured
/// passively from the greeting, the tagged authentication `OK`, and any
/// untagged `CAPABILITY` line; Brev issues no extra round trip for it.
public struct IMAPServerCapabilities: Sendable, Hashable {
    /// Upper-cased capability atoms, e.g. `IMAP4REV1`, `CONDSTORE`, `X-GM-EXT-1`.
    public let atoms: Set<String>

    public init(atoms: Set<String> = []) {
        self.atoms = atoms
    }

    /// Case-insensitive membership test.
    public func contains(_ atom: String) -> Bool {
        atoms.contains(atom.uppercased())
    }

    /// `X-GM-EXT-1`: Gmail's IMAP extensions (`X-GM-LABELS`, `X-GM-THRID`,
    /// `X-GM-MSGID`, `X-GM-RAW`).
    public var supportsGmailExtensions: Bool {
        contains("X-GM-EXT-1")
    }

    /// `UIDPLUS`: the RFC 4315 capability required for UID-targeted expunge.
    public var supportsUIDPlus: Bool {
        contains("UIDPLUS")
    }

    /// Parses one response line. Recognises `* CAPABILITY …`, and the
    /// `[CAPABILITY …]` response code on `* OK` or a tagged `OK`.
    /// Returns nil for any other line.
    public static func parse(responseLine line: String) -> IMAPServerCapabilities? {
        let uppercased = line.uppercased()
        if let range = uppercased.range(of: "* CAPABILITY ", options: .anchored) {
            return IMAPServerCapabilities(atoms: atoms(in: uppercased[range.upperBound...]))
        }
        guard let codeStart = uppercased.range(of: "[CAPABILITY "),
              let codeEnd = uppercased[codeStart.upperBound...].firstIndex(of: "]")
        else {
            return nil
        }
        // Only trust the response code on a status line, never inside FETCH data.
        let prefix = uppercased[..<codeStart.lowerBound]
        guard prefix.hasPrefix("* OK ") || prefix.range(of: #"^[A-Z0-9]+ OK "#, options: .regularExpression) != nil else {
            return nil
        }
        return IMAPServerCapabilities(atoms: atoms(in: uppercased[codeStart.upperBound ..< codeEnd]))
    }

    private static func atoms(in text: Substring) -> Set<String> {
        Set(text.split(whereSeparator: \.isWhitespace).map(String.init))
    }
}

public struct IMAPMessageListing: Sendable, Hashable {
    private static let maximumSnippetCharacters = 500

    public let uid: Int
    public let messageID: String
    /// RFC 5322 `In-Reply-To` from the ENVELOPE, when the message has one.
    /// Brev derives conversations from this link; see ADR-0052.
    public let inReplyTo: String?
    /// RFC 5322 `Reply-To` recipients advertised by the ENVELOPE.
    public let replyTo: [Correspondent]
    public let subject: String
    public let snippet: String
    public let from: Correspondent
    public let to: [Correspondent]
    public let cc: [Correspondent]
    public let bcc: [Correspondent]
    public let date: Date
    public let isRead: Bool
    public let isFlagged: Bool
    public let isAnswered: Bool
    /// Gmail `X-GM-LABELS` values in server order, decoded from modified
    /// UTF-7. System labels keep their backslash prefix (`\Inbox`). Empty
    /// when the server did not return the attribute.
    public let labels: [String]

    public init(
        uid: Int,
        messageID: String,
        inReplyTo: String? = nil,
        replyTo: [Correspondent] = [],
        subject: String,
        snippet: String = "",
        from: Correspondent,
        to: [Correspondent],
        cc: [Correspondent],
        bcc: [Correspondent],
        date: Date,
        isRead: Bool,
        isFlagged: Bool,
        isAnswered: Bool,
        labels: [String] = []
    ) {
        self.uid = uid
        self.messageID = messageID
        self.inReplyTo = inReplyTo
        self.replyTo = replyTo
        self.subject = subject
        self.snippet = snippet
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.date = date
        self.isRead = isRead
        self.isFlagged = isFlagged
        self.isAnswered = isAnswered
        self.labels = labels
    }

    public static func parse(_ line: String) -> IMAPMessageListing? {
        guard line.hasPrefix("* "),
              line.range(of: " FETCH ", options: .caseInsensitive) != nil,
              let uid = parseUID(in: line),
              let flags = parseFlags(in: line),
              let envelope = parseEnvelope(in: line)
        else {
            return nil
        }

        return IMAPMessageListing(
            uid: uid,
            messageID: envelope.messageID,
            inReplyTo: envelope.inReplyTo,
            replyTo: envelope.replyTo,
            subject: envelope.subject,
            snippet: parseSnippet(in: line, subject: envelope.subject),
            from: envelope.from.first ?? Correspondent(email: "unknown"),
            to: envelope.to,
            cc: envelope.cc,
            bcc: envelope.bcc,
            date: envelope.date,
            isRead: flags.contains("seen"),
            isFlagged: flags.contains("flagged"),
            isAnswered: flags.contains("answered"),
            labels: parseGmailLabels(in: line)
        )
    }

    private static func parseSnippet(in line: String, subject: String) -> String {
        guard let valueStart = bodyTextValueStart(in: line) else { return "" }
        var parser = IMAPSExpressionParser(String(line[valueStart...]))
        guard let value = parser.parseValue(),
              let rawSnippet = value.stringValue else {
            return ""
        }
        return normalizedSnippet(rawSnippet, subject: subject)
    }

    private static func bodyTextValueStart(in line: String) -> String.Index? {
        var index = line.startIndex
        var isInsideQuotedString = false
        var isEscaped = false
        while index < line.endIndex {
            let character = line[index]
            if isInsideQuotedString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideQuotedString = false
                }
                line.formIndex(after: &index)
                continue
            }

            if character == "\"" {
                isInsideQuotedString = true
                line.formIndex(after: &index)
                continue
            }

            if isAttributeBoundary(before: index, in: line),
               let valueStart = bodyTextValueStart(startingAt: index, in: line) {
                return valueStart
            }

            line.formIndex(after: &index)
        }
        return nil
    }

    private static func bodyTextValueStart(
        startingAt index: String.Index,
        in line: String
    ) -> String.Index? {
        for label in ["BODY.PEEK[TEXT]", "BODY[TEXT]"] {
            guard let range = line[index...].range(
                of: label,
                options: [.anchored, .caseInsensitive]
            ) else {
                continue
            }

            var valueIndex = range.upperBound
            if valueIndex < line.endIndex, line[valueIndex] == "<" {
                guard let closeIndex = line[valueIndex...].firstIndex(of: ">") else {
                    return nil
                }
                valueIndex = line.index(after: closeIndex)
            }
            guard valueIndex == line.endIndex || line[valueIndex].isWhitespace else {
                return nil
            }
            while valueIndex < line.endIndex, line[valueIndex].isWhitespace {
                line.formIndex(after: &valueIndex)
            }
            return valueIndex < line.endIndex ? valueIndex : nil
        }
        return nil
    }

    private static func normalizedSnippet(_ rawSnippet: String, subject: String) -> String {
        // Listing peeks are raw BODY[TEXT] bytes — often still quoted-printable.
        let decodedSnippet = IMAPListingSnippetTransferEncoding.decodeIfNeeded(rawSnippet)
        // Framing before markup: part-header lines can carry angle brackets
        // (Content-ID) that the tag strip would otherwise mangle.
        let withoutMIMEFraming = strippingMIMEFraming(decodedSnippet, subject: subject)
        // A base64 body part decodes into markup the next step strips.
        let withoutEncodedRuns = SnippetBase64RunDecoder.decodingBase64Runs(in: withoutMIMEFraming)
        let withoutHTMLMarkup = strippingHTMLMarkup(withoutEncodedRuns)
        // Template merge tags (*|SUBJECT|*) are unexpanded artifacts,
        // never prose.
        let withoutMergeTags = withoutHTMLMarkup.replacingOccurrences(
            of: #"\*\|[A-Za-z0-9_:]+\|\*"#,
            with: " ",
            options: .regularExpression
        )
        let withoutCommonEntities = withoutMergeTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        let collapsed = withoutCommonEntities
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > maximumSnippetCharacters else { return collapsed }
        return String(collapsed.prefix(maximumSnippetCharacters))
    }

    private static let skippedMIMEHeaderPrefixes = [
        "content-type:",
        "content-transfer-encoding:",
        "content-disposition:",
        "content-id:",
        "content-description:",
        "mime-version:",
    ]

    /// Drops boundary markers, part headers (including their RFC 2045 folded
    /// continuation lines, which start with whitespace), and the stock
    /// multipart preamble.
    private static func strippingMIMEFraming(_ text: String, subject: String) -> String {
        var keptLines: [String] = []
        var isInsideSkippedHeader = false
        var hasSeenProse = false
        // Normalize CRLF first: splitting on `.newlines` treats it as two
        // separators, and the empty artifact between them would end a folded
        // header one line early.
        let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n")
        for line in normalizedText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowercased = trimmed.lowercased()
            if skippedMIMEHeaderPrefixes.contains(where: { lowercased.hasPrefix($0) }) {
                isInsideSkippedHeader = true
                continue
            }
            if isInsideSkippedHeader, line.first == " " || line.first == "\t" {
                continue
            }
            isInsideSkippedHeader = false
            if trimmed.hasPrefix("--") {
                continue
            }
            if lowercased.hasPrefix("this is a multi-part message in mime format") {
                continue
            }
            if trimmed.isEmpty {
                continue
            }
            // Newsletters open with branding link rows and a line repeating
            // the subject before any prose; a preview should start where the
            // prose does.
            if !hasSeenProse, isLeadingNoiseLine(trimmed, subject: subject) {
                continue
            }
            hasSeenProse = true
            keptLines.append(trimmed)
        }
        return keptLines.joined(separator: " ")
    }

    /// A leading line is noise when it echoes the subject, or when it is
    /// made of links (bare URLs, `Brand (url)`, markdown `[label](url)`)
    /// with at most a couple of words left once the links are removed. A
    /// line that never contained a link is prose no matter how short —
    /// "Hi Henrik," must survive.
    private static func isLeadingNoiseLine(_ line: String, subject: String) -> Bool {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespaces)
        if !trimmedSubject.isEmpty,
           line.compare(trimmedSubject, options: .caseInsensitive) == .orderedSame {
            return true
        }
        let withoutLinks = line
            .replacingOccurrences(
                of: #"\[[^\[\]]*\]\(\s*[^)\s]+\s*\)"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\(?https?://\S+\)?"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\*\|[A-Za-z0-9_:]+\|\*"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard withoutLinks != line else { return false }
        let remainingWords = withoutLinks
            .split(whereSeparator: \.isWhitespace)
            .count
        return remainingWords <= 2
    }

    /// Strips tags plus the two things a plain tag strip leaves behind:
    /// style/script content (not prose) and a final tag the byte-limited
    /// peek cut in half, which then has no closing bracket to match.
    private static func strippingHTMLMarkup(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"(?is)<(style|script)\b[^>]*>.*?</\1\s*>"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?is)<(style|script)\b[^>]*>.*\z"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?s)<!--.*?-->"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(
                of: #"(?s)<[^>]*\z"#,
                with: " ",
                options: .regularExpression
            )
    }

    private static func parseUID(in line: String) -> Int? {
        var index = line.startIndex
        var isInsideQuotedString = false
        var isEscaped = false
        while index < line.endIndex {
            let character = line[index]
            if isInsideQuotedString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideQuotedString = false
                }
                line.formIndex(after: &index)
                continue
            }

            if character == "\"" {
                isInsideQuotedString = true
                line.formIndex(after: &index)
                continue
            }

            if isAttributeBoundary(before: index, in: line),
               let range = line[index...].range(
                   of: "UID",
                   options: [.anchored, .caseInsensitive]
               ) {
                var valueIndex = range.upperBound
                if valueIndex < line.endIndex,
                   !line[valueIndex].isWhitespace {
                    line.formIndex(after: &index)
                    continue
                }
                while valueIndex < line.endIndex, line[valueIndex].isWhitespace {
                    line.formIndex(after: &valueIndex)
                }
                let start = valueIndex
                while valueIndex < line.endIndex, line[valueIndex].isNumber {
                    line.formIndex(after: &valueIndex)
                }
                guard start < valueIndex else { return nil }
                return Int(line[start ..< valueIndex])
            }

            line.formIndex(after: &index)
        }
        return nil
    }

    private static func isAttributeBoundary(before index: String.Index, in line: String) -> Bool {
        guard index > line.startIndex else { return true }
        let previousIndex = line.index(before: index)
        return line[previousIndex].isWhitespace || line[previousIndex] == "("
    }

    /// Parses `X-GM-LABELS (…)`. Items are atoms or quoted strings; quoted
    /// values are unescaped and every label is decoded from modified UTF-7.
    static func parseGmailLabels(in line: String) -> [String] {
        guard let start = attributeListStart(named: "X-GM-LABELS", in: line) else { return [] }
        var parser = IMAPSExpressionParser("(" + String(line[start...]))
        guard case .list(let values)? = parser.parseValue() else { return [] }
        return values.compactMap { value -> String? in
            switch value {
            case .atom(let atom):
                return IMAPMailboxNameCodec.decode(atom)
            case .string(let string):
                return IMAPMailboxNameCodec.decode(string)
            case .nilValue, .list:
                return nil
            }
        }
    }

    private static func parseFlags(in line: String) -> Set<String>? {
        guard var index = attributeListStart(named: "FLAGS", in: line) else { return nil }
        let start = index
        while index < line.endIndex, line[index] != ")" {
            line.formIndex(after: &index)
        }
        guard index < line.endIndex else { return nil }
        return Set(line[start ..< index].split(whereSeparator: \.isWhitespace).map { flag in
            flag.trimmingCharacters(in: CharacterSet(charactersIn: "\\"))
                .lowercased()
        })
    }

    /// Index just past the `(` opening the parenthesised value of the fetch
    /// attribute `name` (matched at an attribute boundary, outside quotes).
    private static func attributeListStart(named name: String, in line: String) -> String.Index? {
        var index = line.startIndex
        var isInsideQuotedString = false
        var isEscaped = false
        while index < line.endIndex {
            let character = line[index]
            if isInsideQuotedString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideQuotedString = false
                }
                line.formIndex(after: &index)
                continue
            }

            if character == "\"" {
                isInsideQuotedString = true
                line.formIndex(after: &index)
                continue
            }

            if isAttributeBoundary(before: index, in: line),
               let range = line[index...].range(
                   of: name,
                   options: [.anchored, .caseInsensitive]
               ) {
                var valueIndex = range.upperBound
                if valueIndex < line.endIndex,
                   !line[valueIndex].isWhitespace,
                   line[valueIndex] != "(" {
                    line.formIndex(after: &index)
                    continue
                }
                while valueIndex < line.endIndex, line[valueIndex].isWhitespace {
                    line.formIndex(after: &valueIndex)
                }
                guard valueIndex < line.endIndex, line[valueIndex] == "(" else {
                    return nil
                }
                return line.index(after: valueIndex)
            }

            line.formIndex(after: &index)
        }
        return nil
    }

    private static func parseEnvelope(in line: String) -> IMAPEnvelope? {
        guard let range = line.range(of: "ENVELOPE ", options: .caseInsensitive) else { return nil }
        var parser = IMAPSExpressionParser(String(line[range.upperBound...]))
        guard let value = parser.parseValue(),
              case .list(let envelope) = value,
              envelope.count >= 10
        else {
            return nil
        }

        let dateString = envelope[0].stringValue
        let subject = envelope[1].stringValue.map(decodeEnvelopeHeaderString) ?? ""
        let from = correspondents(from: envelope[2])
        let replyTo = correspondents(from: envelope[4])
        let to = correspondents(from: envelope[5])
        let cc = correspondents(from: envelope[6])
        let bcc = correspondents(from: envelope[7])
        // RFC 3501 orders the envelope fields date, subject, from, sender,
        // reply-to, to, cc, bcc, in-reply-to, message-id — so the reply link
        // Brev threads on is already in every FETCH response (ADR-0052).
        let inReplyTo = envelope[8].stringValue.map(unfoldHeaderValue)
        let messageID = envelope[9].stringValue ?? "uid-message"
        return IMAPEnvelope(
            date: IMAPDateParser.date(from: dateString) ?? Date.distantPast,
            subject: subject,
            from: from,
            replyTo: replyTo,
            to: to,
            cc: cc,
            bcc: bcc,
            inReplyTo: inReplyTo,
            messageID: messageID
        )
    }

    private static func correspondents(from value: IMAPSExpressionValue) -> [Correspondent] {
        guard case .list(let addresses) = value else { return [] }
        return addresses.compactMap { address in
            guard case .list(let parts) = address,
                  parts.count >= 4,
                  let mailbox = parts[2].stringValue,
                  let host = parts[3].stringValue,
                  !mailbox.isEmpty,
                  !host.isEmpty
            else {
                return nil
            }
            let name = parts[0].stringValue.map(decodeEnvelopeHeaderString)
            return Correspondent(
                name: name?.isEmpty == false ? name : nil,
                email: "\(mailbox)@\(host)"
            )
        }
    }

    private static func decodeEnvelopeHeaderString(_ value: String) -> String {
        RFC2047HeaderDecoder.decode(unfoldHeaderValue(value))
    }

    private static func unfoldHeaderValue(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: #"\r\n[ \t]*|\r[ \t]*|\n[ \t]*"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct IMAPMessageListingPage: Sendable, Hashable {
    public let messages: [IMAPMessageListing]
    public let uidValidity: Int?
    /// CONDSTORE HIGHESTMODSEQ from the SELECT response, if the server
    /// supports CONDSTORE. Propagated to the header cache for delta-sync.
    public let highestModSeq: UInt64?
    public let nextPageToken: String?
    /// True when the server advertised `X-GM-EXT-1`, so `messages[*].labels`
    /// reflect Gmail labels and the backend may advertise `.labels`.
    public let supportsGmailLabels: Bool

    public init(
        messages: [IMAPMessageListing],
        uidValidity: Int? = nil,
        highestModSeq: UInt64? = nil,
        nextPageToken: String? = nil,
        supportsGmailLabels: Bool = false
    ) {
        self.messages = messages
        self.uidValidity = uidValidity
        self.highestModSeq = highestModSeq
        self.nextPageToken = nextPageToken
        self.supportsGmailLabels = supportsGmailLabels
    }
}

public struct IMAPSelectedMailbox: Sendable, Hashable {
    public let uidValidity: Int?
    /// The HIGHESTMODSEQ value from the SELECT OK response (RFC 4551 CONDSTORE).
    /// Nil when the server does not advertise CONDSTORE support.
    public let highestModSeq: UInt64?

    public init(uidValidity: Int? = nil, highestModSeq: UInt64? = nil) {
        self.uidValidity = uidValidity
        self.highestModSeq = highestModSeq
    }

    static func parse(from responses: [String]) -> IMAPSelectedMailbox {
        var uidValidity: Int?
        var highestModSeq: UInt64?
        for response in responses {
            if uidValidity == nil, let parsed = parseUIDValidity(from: response) {
                uidValidity = parsed
            }
            if highestModSeq == nil, let parsed = parseHighestModSeq(from: response) {
                highestModSeq = parsed
            }
        }
        return IMAPSelectedMailbox(uidValidity: uidValidity, highestModSeq: highestModSeq)
    }

    private static func parseUIDValidity(from response: String) -> Int? {
        // Search and slice the same string (see parseRawFlags): indices from
        // `response.uppercased()` could point past `response`'s end and trap.
        guard let markerRange = response.range(of: "[UIDVALIDITY ", options: .caseInsensitive) else {
            return nil
        }
        let payloadStart = markerRange.upperBound
        guard let payloadEnd = response[payloadStart...].firstIndex(of: "]") else {
            return nil
        }
        let value = response[payloadStart ..< payloadEnd]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(value)
    }

    private static func parseHighestModSeq(from response: String) -> UInt64? {
        // Search and slice the same string (see parseRawFlags).
        guard let markerRange = response.range(of: "[HIGHESTMODSEQ ", options: .caseInsensitive) else {
            return nil
        }
        let payloadStart = markerRange.upperBound
        guard let payloadEnd = response[payloadStart...].firstIndex(of: "]") else {
            return nil
        }
        let value = response[payloadStart ..< payloadEnd]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return UInt64(value)
    }
}

public struct IMAPMessageSource: Sendable, Hashable, Codable {
    public let uid: Int
    public let rawMessage: String

    public init(uid: Int, rawMessage: String) {
        self.uid = uid
        self.rawMessage = rawMessage
    }

    public static func parse(
        _ responses: [String],
        uid: Int
    ) -> IMAPMessageSource? {
        guard let fetchIndex = responses.firstIndex(where: { response in
            return response.range(of: " FETCH ", options: .caseInsensitive) != nil
                && response.range(of: "UID \(uid)", options: .caseInsensitive) != nil
                && IMAPRawMessageFetchLabel.isPresent(in: response)
        }) else {
            return nil
        }

        var literalLines = Array(responses[(fetchIndex + 1)...])
        if literalLines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == ")" {
            literalLines.removeLast()
        }
        let rawMessage = literalLines.joined(separator: "\n")
        guard !rawMessage.isEmpty else { return nil }
        return IMAPMessageSource(uid: uid, rawMessage: rawMessage)
    }
}

private enum IMAPRawMessageFetchLabel {
    static func isPresent(in line: String) -> Bool {
        let uppercased = line.uppercased()
        return uppercased.contains("BODY[]")
            || uppercased.contains("BODY.PEEK[]")
            || containsFullRFC822Label(in: uppercased)
    }

    private static func containsFullRFC822Label(in uppercased: String) -> Bool {
        var searchStart = uppercased.startIndex
        while let range = uppercased[searchStart...].range(of: "RFC822") {
            if hasFetchAttributeBoundary(before: range.lowerBound, in: uppercased),
               hasFetchAttributeTerminator(after: range.upperBound, in: uppercased) {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private static func hasFetchAttributeBoundary(
        before index: String.Index,
        in line: String
    ) -> Bool {
        guard index > line.startIndex else { return true }
        let previous = line[line.index(before: index)]
        return previous.isWhitespace || previous == "("
    }

    private static func hasFetchAttributeTerminator(
        after index: String.Index,
        in line: String
    ) -> Bool {
        guard index < line.endIndex else { return true }
        let next = line[index]
        return next.isWhitespace || next == "{" || next == ")"
    }
}

public enum IMAPIdleEvent: Sendable, Hashable {
    case exists(count: Int)
    case recent(count: Int)
    case expunged(sequenceNumber: Int)
    case flagsChanged(sequenceNumber: Int)

    public static func parse(_ line: String) -> IMAPIdleEvent? {
        guard line.hasPrefix("* ") else { return nil }
        let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count >= 3,
              let number = Int(parts[1])
        else {
            return nil
        }

        let response = parts[2].uppercased()
        if response == "EXISTS" {
            return .exists(count: number)
        }
        if response == "RECENT" {
            return .recent(count: number)
        }
        if response == "EXPUNGE" {
            return .expunged(sequenceNumber: number)
        }
        if response == "FETCH", line.uppercased().contains("FLAGS") {
            return .flagsChanged(sequenceNumber: number)
        }
        return nil
    }
}

public enum IMAPSystemFlag: Sendable, Hashable {
    case seen
    case flagged
    case deleted
    case draft

    var commandToken: String {
        switch self {
        case .seen:
            "\\Seen"
        case .flagged:
            "\\Flagged"
        case .deleted:
            "\\Deleted"
        case .draft:
            "\\Draft"
        }
    }
}

public enum IMAPMessageKeyword: Sendable, Hashable {
    case junk
    case notJunk

    var commandToken: String {
        switch self {
        case .junk:
            "$Junk"
        case .notJunk:
            "$NotJunk"
        }
    }
}

enum IMAPSessionOperationClass: Int, Comparable, Sendable {
    case background
    case standard
    case foreground

    static func < (lhs: IMAPSessionOperationClass, rhs: IMAPSessionOperationClass) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum IMAPSessionOperationScheduling {
    static func operationClass(for priority: TaskPriority) -> IMAPSessionOperationClass {
        if priority >= .userInitiated {
            return .foreground
        }
        if priority <= .utility {
            return .background
        }
        return .standard
    }

    static func nextIndex(in queued: [IMAPSessionOperationClass]) -> Int? {
        guard var selectedIndex = queued.indices.first else { return nil }
        for index in queued.indices.dropFirst() where queued[index] > queued[selectedIndex] {
            selectedIndex = index
        }
        return selectedIndex
    }
}

public actor IMAPSessionClient {
    private static let messageListingPreviewByteLimit = 1024
    /// Search pages stay bounded so attachment filtering never turns one IMAP
    /// response into an unbounded fetch window.
    private static let maximumSearchPageSize = 50

    private struct AuthenticatedSessionIdentity: Equatable, Sendable {
        let configuration: IMAPAccountConfiguration
        let incomingUsername: String
        let outgoingUsername: String
        let authentication: MailServerAuthentication
        /// A one-way digest lets the client detect a rotated access token
        /// without retaining the bearer secret in reusable-session state.
        let secretDigest: Data

        init(configuration: IMAPAccountConfiguration, credential: MailAccountCredential) {
            self.configuration = configuration
            incomingUsername = credential.incomingUsername
            outgoingUsername = credential.outgoingUsername
            authentication = credential.authentication
            secretDigest = Data(SHA256.hash(data: Data(credential.secret.utf8)))
        }
    }

    private struct SelectedMailboxState: Sendable {
        let folderPath: String
        let mailbox: IMAPSelectedMailbox
    }

    private let transport: any IMAPSessionTransport
    private let responseTimeoutNanoseconds: UInt64?
    /// Maximum lifetime of one IDLE command. Servers commonly require the
    /// command to be refreshed before roughly 30 minutes; keeping a slightly
    /// shorter bound also prevents a stale reader from surviving indefinitely.
    private let idleMaximumDurationNanoseconds: UInt64?
    private let reusesAuthenticatedSession: Bool
    private var authenticatedSessionIdentity: AuthenticatedSessionIdentity?
    private var selectedMailboxState: SelectedMailboxState?
    /// Lease for the active IDLE stream; stale cancellation must not tear down
    /// a newer stream using the same transport.
    private var idleSessionGeneration = 0
    /// Capabilities the current (or most recent) session's server advertised.
    private var serverCapabilities = IMAPServerCapabilities()
    private var sessionTagCounter = 1
    private var sessionOperationInProgress = false
    private struct SessionOperationWaiter {
        let operationClass: IMAPSessionOperationClass
        let continuation: CheckedContinuation<Void, Never>
    }

    private var sessionOperationWaiters: [SessionOperationWaiter] = []

    public init(
        transport: any IMAPSessionTransport,
        responseTimeoutNanoseconds: UInt64? = 60_000_000_000,
        idleMaximumDurationNanoseconds: UInt64? = 29 * 60 * 1_000_000_000,
        reusesAuthenticatedSession: Bool = false
    ) {
        self.transport = transport
        self.responseTimeoutNanoseconds = responseTimeoutNanoseconds
        self.idleMaximumDurationNanoseconds = idleMaximumDurationNanoseconds
        self.reusesAuthenticatedSession = reusesAuthenticatedSession
    }

    /// Closes the current authenticated session and clears selected-mailbox state.
    public func disconnect() async {
        await acquireSessionOperation(.foreground)
        defer { releaseSessionOperation() }
        await resetAuthenticatedSession()
    }

    /// Capabilities advertised by the server during the most recent login.
    public func advertisedServerCapabilities() -> IMAPServerCapabilities {
        serverCapabilities
    }

    private func noteServerCapabilities(fromResponseLine line: String) {
        if let parsed = IMAPServerCapabilities.parse(responseLine: line) {
            serverCapabilities = parsed
        }
    }

    private func withAuthenticatedSession<Result: Sendable>(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        retriesAfterDisconnect: Bool = true,
        operationClass: IMAPSessionOperationClass? = nil,
        operation: (inout Int) async throws -> Result
    ) async throws -> Result {
        await acquireSessionOperation(operationClass)
        defer { releaseSessionOperation() }

        let maximumAttempts = reusesAuthenticatedSession && retriesAfterDisconnect ? 2 : 1
        for attempt in 0 ..< maximumAttempts {
            var tagCounter = sessionTagCounter
            do {
                tagCounter = try await prepareAuthenticatedSession(
                    configuration: configuration,
                    credential: credential
                )
                let result = try await operation(&tagCounter)
                if reusesAuthenticatedSession {
                    sessionTagCounter = tagCounter
                }
                return result
            } catch {
                if reusesAuthenticatedSession {
                    sessionTagCounter = tagCounter
                }
                let isReconnectable = Self.isReconnectableSessionError(error)
                let shouldRetry = reusesAuthenticatedSession
                    && retriesAfterDisconnect
                    && attempt + 1 < maximumAttempts
                    && isReconnectable
                if shouldRetry {
                    await resetAuthenticatedSession()
                    continue
                }
                if reusesAuthenticatedSession, isReconnectable {
                    await resetAuthenticatedSession()
                }
                throw error
            }
        }

        throw IMAPClientError.transport("IMAP session retry ended unexpectedly.")
    }

    private func prepareAuthenticatedSession(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential
    ) async throws -> Int {
        let identity = AuthenticatedSessionIdentity(
            configuration: configuration,
            credential: credential
        )
        if reusesAuthenticatedSession,
           authenticatedSessionIdentity == identity {
            return sessionTagCounter
        }

        if reusesAuthenticatedSession,
           authenticatedSessionIdentity != nil {
            await resetAuthenticatedSession()
        } else if reusesAuthenticatedSession {
            selectedMailboxState = nil
            sessionTagCounter = 1
        }
        var tagCounter = 1
        try await connectAndLogin(
            configuration: configuration,
            credential: credential,
            tagCounter: &tagCounter
        )
        if reusesAuthenticatedSession {
            authenticatedSessionIdentity = identity
            selectedMailboxState = nil
            sessionTagCounter = tagCounter
        }
        return tagCounter
    }

    private func resetAuthenticatedSession() async {
        authenticatedSessionIdentity = nil
        selectedMailboxState = nil
        serverCapabilities = IMAPServerCapabilities()
        sessionTagCounter = 1
        await transport.disconnect()
    }

    /// Clears reusable-session bookkeeping after a bounded read has already
    /// closed the transport.
    private func invalidateAuthenticatedSessionAfterTransportClose(generation: Int) {
        guard generation == idleSessionGeneration else { return }
        authenticatedSessionIdentity = nil
        selectedMailboxState = nil
        serverCapabilities = IMAPServerCapabilities()
        sessionTagCounter = 1
    }

    private func acquireSessionOperation(_ requestedClass: IMAPSessionOperationClass? = nil) async {
        if !sessionOperationInProgress {
            sessionOperationInProgress = true
            return
        }
        let operationClass = requestedClass
            ?? IMAPSessionOperationScheduling.operationClass(for: Task.currentPriority)
        await withCheckedContinuation { continuation in
            sessionOperationWaiters.append(SessionOperationWaiter(
                operationClass: operationClass,
                continuation: continuation
            ))
        }
    }

    private func releaseSessionOperation() {
        if sessionOperationWaiters.isEmpty {
            sessionOperationInProgress = false
        } else {
            let priorities = sessionOperationWaiters.map(\.operationClass)
            guard let index = IMAPSessionOperationScheduling.nextIndex(in: priorities) else {
                sessionOperationInProgress = false
                return
            }
            sessionOperationWaiters.remove(at: index).continuation.resume()
        }
    }

    private static func isReconnectableSessionError(_ error: any Error) -> Bool {
        guard let error = error as? IMAPClientError else { return false }
        switch error {
        case .transport, .serverBye, .connectionRejected:
            return true
        default:
            return false
        }
    }

    public func loginAndListFolders(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        includingUnreadCounts: Bool = false
    ) async throws -> [IMAPFolderListing] {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }

        return try await withAuthenticatedSession(
            configuration: configuration,
            credential: credential
        ) { tagCounter in
            let listResponses = try await execute(
                tag: nextTag(&tagCounter),
                commandName: "LIST",
                command: #"LIST "" "*""#
            )
            let listings = listResponses.compactMap(IMAPFolderListing.parse)
            guard includingUnreadCounts else { return listings }
            return await withFolderCounts(listings: listings, tagCounter: &tagCounter)
        }
    }

    /// Fetches `STATUS (MESSAGES UNSEEN)` for every selectable listing.
    ///
    /// A refused or failed STATUS leaves that folder's counts at zero —
    /// counts are a progressive enhancement over the listing itself.
    private func withFolderCounts(
        listings: [IMAPFolderListing],
        tagCounter: inout Int
    ) async -> [IMAPFolderListing] {
        var updated: [IMAPFolderListing] = []
        for listing in listings {
            guard !listing.flags.contains("noselect") else {
                updated.append(listing)
                continue
            }
            let responses = try? await execute(
                tag: nextTag(&tagCounter),
                commandName: "STATUS",
                command: "STATUS \(Self.quotedMailboxName(listing.path)) (MESSAGES UNSEEN)"
            )
            // The response window belongs to this folder's STATUS command,
            // so the counts pair with the requested path — no need to match
            // the server's (possibly re-encoded) mailbox name.
            if let counts = responses?.compactMap({ Self.parseStatusCounts(in: $0) }).first {
                updated.append(listing.withCounts(
                    totalCount: counts.messages,
                    unreadCount: counts.unseen
                ))
            } else {
                updated.append(listing)
            }
        }
        return updated
    }

    /// Parses `* STATUS <mailbox> (MESSAGES n UNSEEN n)`; attribute order
    /// is server-chosen.
    static func parseStatusCounts(in line: String) -> (messages: Int, unseen: Int)? {
        guard line.hasPrefix("* "),
              line.range(of: " STATUS ", options: .caseInsensitive) != nil,
              let attributesOpen = line.lastIndex(of: "("),
              let attributesClose = line[attributesOpen...].firstIndex(of: ")")
        else {
            return nil
        }
        let tokens = line[line.index(after: attributesOpen) ..< attributesClose]
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        var messages = 0
        var unseen = 0
        for (name, value) in zip(tokens, tokens.dropFirst()) {
            switch name.uppercased() {
            case "MESSAGES":
                messages = Int(value) ?? 0
            case "UNSEEN":
                unseen = Int(value) ?? 0
            default:
                break
            }
        }
        return (messages: messages, unseen: unseen)
    }

    public func loginAndCreateFolder(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderPath: String
    ) async throws {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }

        try await withAuthenticatedSession(
            configuration: configuration,
            credential: credential,
            retriesAfterDisconnect: false
        ) { tagCounter in
            _ = try await execute(
                tag: nextTag(&tagCounter),
                commandName: "CREATE",
                command: "CREATE \(Self.quotedMailboxName(folderPath))"
            )
        }
    }

    public func loginAndRenameFolder(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderPath: String,
        newFolderPath: String
    ) async throws {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }
        guard folderPath != newFolderPath else { return }

        try await withAuthenticatedSession(
            configuration: configuration,
            credential: credential,
            retriesAfterDisconnect: false
        ) { tagCounter in
            _ = try await execute(
                tag: nextTag(&tagCounter),
                commandName: "RENAME",
                command: "RENAME \(Self.quotedMailboxName(folderPath)) \(Self.quotedMailboxName(newFolderPath))"
            )
            if selectedMailboxState?.folderPath == folderPath {
                selectedMailboxState = nil
            }
        }
    }

    public func loginAndDeleteFolder(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderPath: String
    ) async throws {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }

        try await withAuthenticatedSession(
            configuration: configuration,
            credential: credential,
            retriesAfterDisconnect: false
        ) { tagCounter in
            _ = try await execute(
                tag: nextTag(&tagCounter),
                commandName: "DELETE",
                command: "DELETE \(Self.quotedMailboxName(folderPath))"
            )
            if selectedMailboxState?.folderPath == folderPath {
                selectedMailboxState = nil
            }
        }
    }

    public func loginAndListMessages(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderPath: String,
        pageToken: String? = nil,
        limit: Int = 50
    ) async throws -> IMAPMessageListingPage {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }
        guard limit > 0 else {
            return IMAPMessageListingPage(messages: [])
        }

        return try await withAuthenticatedSession(
            configuration: configuration,
            credential: credential
        ) { tagCounter in
            let selectedMailbox = try await select(folderPath: folderPath, tagCounter: &tagCounter)
            return try await searchMessagePage(
                criteria: [.atom("ALL")],
                pageToken: pageToken,
                limit: limit,
                uidValidity: selectedMailbox.uidValidity,
                highestModSeq: selectedMailbox.highestModSeq,
                tagCounter: &tagCounter
            )
        }
    }

    public func loginAndSearchMessages(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderPath: String,
        query: SearchQuery,
        limit: Int = 50
    ) async throws -> [IMAPMessageListing] {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }
        guard limit > 0 else { return [] }

        return try await withAuthenticatedSession(
            configuration: configuration,
            credential: credential
        ) { tagCounter in
            _ = try await select(folderPath: folderPath, tagCounter: &tagCounter)
            let page = try await searchMessagePage(
                criteria: Self.searchTokens(for: query),
                pageToken: nil,
                limit: limit,
                uidValidity: nil,
                tagCounter: &tagCounter
            )
            return page.messages
        }
    }

    /// Searches one bounded UID page, preserving a cursor for older matches.
    /// The cursor is intentionally server-independent (`before:<uid>`) so the
    /// backend can inspect each page for attachment metadata without retaining
    /// the entire server result set in memory.
    public func loginAndSearchMessagePage(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderPath: String,
        query: SearchQuery,
        pageToken: String? = nil,
        limit: Int = 50
    ) async throws -> IMAPMessageListingPage {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }
        guard limit > 0 else { return IMAPMessageListingPage(messages: []) }
        let boundedLimit = min(limit, Self.maximumSearchPageSize)

        return try await withAuthenticatedSession(
            configuration: configuration,
            credential: credential
        ) { tagCounter in
            let selectedMailbox = try await select(folderPath: folderPath, tagCounter: &tagCounter)
            return try await searchMessagePage(
                criteria: Self.searchTokens(for: query),
                pageToken: pageToken,
                limit: boundedLimit,
                uidValidity: selectedMailbox.uidValidity,
                highestModSeq: selectedMailbox.highestModSeq,
                tagCounter: &tagCounter
            )
        }
    }

    private func searchMessagePage(
        criteria: [IMAPSearchToken],
        pageToken: String?,
        limit: Int,
        uidValidity: Int?,
        highestModSeq: UInt64? = nil,
        tagCounter: inout Int
    ) async throws -> IMAPMessageListingPage {
        try Task.checkCancellation()
        let searchResponses = try await executeSearch(
            tokens: criteria,
            tag: nextTag(&tagCounter)
        )
        let searchableUIDs = try Self.pageUIDs(
            from: Self.messageUIDs(from: searchResponses),
            before: pageToken
        )
        let uids = Array(searchableUIDs.suffix(limit))
        let supportsGmailLabels = serverCapabilities.supportsGmailExtensions
        guard !uids.isEmpty else {
            return IMAPMessageListingPage(
                messages: [],
                highestModSeq: highestModSeq,
                supportsGmailLabels: supportsGmailLabels
            )
        }

        try Task.checkCancellation()
        let messages = try await fetchMessageListings(
            uids: uids,
            tagCounter: &tagCounter
        )
        let nextPageToken = searchableUIDs.count > uids.count
            ? "before:\(uids.min() ?? 0)"
            : nil
        return IMAPMessageListingPage(
            messages: messages,
            uidValidity: uidValidity,
            highestModSeq: highestModSeq,
            nextPageToken: nextPageToken,
            supportsGmailLabels: supportsGmailLabels
        )
    }

    /// Send a `UID SEARCH` built from structured tokens and return its
    /// untagged responses.
    ///
    /// RFC 3501: SEARCH defaults to US-ASCII, so a non-ASCII term requires
    /// a `CHARSET UTF-8` declaration *and* must be transmitted as a
    /// synchronizing literal (`{n}` + continuation + raw octets) — a quoted
    /// string with 8-bit bytes is rejected (`BAD`/`BADCHARSET`) or
    /// mis-searched by strict servers (e.g. Dovecot). When every value is
    /// ASCII this collapses to a single `writeLine` whose bytes are
    /// identical to the previous quoted-string form, so the common path is
    /// unchanged.
    private func executeSearch(
        tokens: [IMAPSearchToken],
        tag: String
    ) async throws -> [String] {
        let needsCharset = tokens.contains { token in
            if case .astring(let value) = token {
                return !value.unicodeScalars.allSatisfy(\.isASCII)
            }
            return false
        }

        var pending = "\(tag) UID SEARCH"
        if needsCharset {
            pending += " CHARSET UTF-8"
        }

        for token in tokens {
            switch token {
            case .atom(let text):
                pending += " \(text)"
            case .astring(let value):
                if value.unicodeScalars.allSatisfy(\.isASCII) {
                    pending += try " \(Self.quoted(value))"
                } else {
                    // Emit a synchronizing literal: flush the line so far with
                    // the `{byteCount}` marker, wait for the server's `+`
                    // continuation, write the raw UTF-8 octets, then keep
                    // appending the rest of the command on the same logical line.
                    let octets = Data(value.utf8)
                    pending += " {\(octets.count)}"
                    try await transport.writeLine(pending)
                    try await readLiteralContinuation(tag: tag, commandName: "UID SEARCH")
                    try await transport.writeData(octets)
                    pending = ""
                }
            }
        }

        try await transport.writeLine(pending)
        return try await readTaggedResponses(tag: tag, commandName: "UID SEARCH")
    }

    private func fetchMessageSource(
        uid: Int,
        tagCounter: inout Int
    ) async throws -> IMAPMessageSource {
        let tag = nextTag(&tagCounter)
        try await transport.writeLine("\(tag) UID FETCH \(uid) (BODY.PEEK[])")

        var fetchResponses: [String] = []
        while true {
            let line = try await readLine(commandName: "UID FETCH")
            if line.hasPrefix("\(tag) ") {
                try Self.validateTaggedResponse(line, tag: tag, commandName: "UID FETCH")
                guard let source = IMAPMessageSource.parse(fetchResponses, uid: uid) else {
                    throw IMAPClientError.malformedResponse(fetchResponses.joined(separator: "\n"))
                }
                return source
            }

            if let literalByteCount = Self.bodyLiteralByteCount(in: line, uid: uid) {
                let literal = try await readLiteralData(
                    byteCount: literalByteCount,
                    commandName: "UID FETCH"
                )
                try await readFetchLiteralCompletion(tag: tag)
                let rawMessage = IMAPMessageBodyParser().rawMessageString(from: literal)
                guard !rawMessage.isEmpty else {
                    throw IMAPClientError.malformedResponse(line)
                }
                return IMAPMessageSource(uid: uid, rawMessage: rawMessage)
            }

            fetchResponses.append(line)
        }
    }

    private func fetchMessageBody(
        messageID: MessageHeader.ID,
        uid: Int,
        tagCounter: inout Int
    ) async throws -> MessageBody {
        let structureTag = nextTag(&tagCounter)
        let structureResponses = try await execute(
            tag: structureTag,
            commandName: "UID FETCH BODYSTRUCTURE",
            command: "UID FETCH \(uid) (BODYSTRUCTURE)"
        )
        guard let plan = IMAPBodyStructurePlan.parse(fetchResponses: structureResponses, uid: uid) else {
            throw IMAPClientError.malformedResponse(structureResponses.joined(separator: "\n"))
        }

        let headerData = try await fetchMessagePartData(
            uid: uid,
            section: "HEADER",
            tagCounter: &tagCounter
        )
        let parser = IMAPMessageBodyParser()
        let plainBody: MessageBody?
        if let part = plan.plainTextPart {
            plainBody = try await fetchAndDecodeStructuredPart(
                part,
                uid: uid,
                parser: parser,
                tagCounter: &tagCounter
            )
        } else {
            plainBody = nil
        }
        let htmlBody: MessageBody?
        if let part = plan.htmlPart {
            htmlBody = try await fetchAndDecodeStructuredPart(
                part,
                uid: uid,
                parser: parser,
                tagCounter: &tagCounter
            )
        } else {
            htmlBody = nil
        }
        let receiptBody: MessageBody?
        if let part = plan.readReceiptPart {
            receiptBody = try await fetchAndDecodeStructuredPart(
                part,
                uid: uid,
                parser: parser,
                tagCounter: &tagCounter
            )
        } else {
            receiptBody = nil
        }
        let attachments = plan.attachments.enumerated().map { index, part in
            let reference = IMAPMessagePartReference(
                messageID: messageID,
                section: part.section,
                transferEncoding: part.transferEncoding
            )
            return Attachment(
                id: "\(messageID):attachment:\(index + 1)",
                name: part.name ?? "Attachment \(index + 1)",
                mimeType: part.mimeType,
                sizeBytes: part.sizeBytes,
                isInline: part.isInline,
                contentID: part.contentID,
                resource: reference.resource
            )
        }
        return parser.structuredBody(
            messageID: messageID,
            headerBlock: parser.rawMessageString(from: headerData),
            plainText: plainBody?.plainText,
            html: htmlBody?.html,
            attachments: attachments,
            readReceiptNotification: receiptBody?.readReceiptNotification
        )
    }

    private func fetchAndDecodeStructuredPart(
        _ part: IMAPBodyStructurePart,
        uid: Int,
        parser: IMAPMessageBodyParser,
        tagCounter: inout Int
    ) async throws -> MessageBody {
        let data = try await fetchMessagePartData(
            uid: uid,
            section: part.section,
            tagCounter: &tagCounter
        )
        return parser.decodedStructuredPart(data, part: part)
    }

    private func fetchMessagePartData(
        uid: Int,
        section: String,
        tagCounter: inout Int
    ) async throws -> Data {
        let tag = nextTag(&tagCounter)
        try await transport.writeLine("\(tag) UID FETCH \(uid) (BODY.PEEK[\(section)])")
        while true {
            let line = try await readLine(commandName: "UID FETCH")
            if line.hasPrefix("\(tag) ") {
                try Self.validateTaggedResponse(line, tag: tag, commandName: "UID FETCH")
                throw IMAPClientError.malformedResponse(line)
            }
            guard let literalByteCount = Self.fetchLiteralByteCount(in: line, uid: uid) else {
                continue
            }
            let literal = try await readLiteralData(
                byteCount: literalByteCount,
                commandName: "UID FETCH"
            )
            try await readFetchLiteralCompletion(tag: tag)
            return literal
        }
    }

    private func readLiteralData(
        byteCount: Int,
        commandName: String
    ) async throws -> Data {
        var remaining = byteCount
        var data = Data()
        while remaining > 0 {
            let chunk = try await readData(maxLength: remaining, commandName: commandName)
            guard !chunk.isEmpty else {
                throw IMAPClientError.transport("Connection closed while reading IMAP literal.")
            }
            let consumed = min(chunk.count, remaining)
            data.append(chunk.prefix(consumed))
            remaining -= consumed
        }
        return data
    }

    private func readFetchLiteralCompletion(tag: String) async throws {
        while true {
            let line = try await readLine(commandName: "UID FETCH")
            if line.hasPrefix("\(tag) ") {
                try Self.validateTaggedResponse(line, tag: tag, commandName: "UID FETCH")
                return
            }
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == ")" {
                continue
            }
        }
    }

    public func loginAndFetchMessageSource(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderPath: String,
        uid: Int
    ) async throws -> IMAPMessageSource {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }

        return try await withAuthenticatedSession(
            configuration: configuration,
            credential: credential,
            operationClass: .foreground
        ) { tagCounter in
            _ = try await select(folderPath: folderPath, tagCounter: &tagCounter)
            return try await fetchMessageSource(uid: uid, tagCounter: &tagCounter)
        }
    }

    public func loginAndFetchMessageBody(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        messageID: MessageHeader.ID,
        folderPath: String,
        uid: Int
    ) async throws -> MessageBody {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }
        return try await withAuthenticatedSession(
            configuration: configuration,
            credential: credential,
            operationClass: .foreground
        ) { tagCounter in
            _ = try await select(folderPath: folderPath, tagCounter: &tagCounter)
            return try await fetchMessageBody(
                messageID: messageID,
                uid: uid,
                tagCounter: &tagCounter
            )
        }
    }

    public func loginAndFetchMessagePart(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderPath: String,
        uid: Int,
        section: String,
        transferEncoding: String
    ) async throws -> Data {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }
        return try await withAuthenticatedSession(
            configuration: configuration,
            credential: credential,
            operationClass: .foreground
        ) { tagCounter in
            _ = try await select(folderPath: folderPath, tagCounter: &tagCounter)
            let data = try await fetchMessagePartData(
                uid: uid,
                section: section,
                tagCounter: &tagCounter
            )
            return try Self.decodeTransferEncoding(data, encoding: transferEncoding)
        }
    }

    public func loginAndSetMessageFlag(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderPath: String,
        uids: [Int],
        flag: IMAPSystemFlag,
        isEnabled: Bool
    ) async throws {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }
        guard !uids.isEmpty else { return }

        try await withAuthenticatedSession(
            configuration: configuration,
            credential: credential,
            retriesAfterDisconnect: false
        ) { tagCounter in
            _ = try await select(folderPath: folderPath, tagCounter: &tagCounter)
            try await storeFlag(
                uids: uids,
                flag: flag,
                isEnabled: isEnabled,
                tagCounter: &tagCounter
            )
        }
    }

    public func loginAndSetMessageKeyword(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderPath: String,
        uids: [Int],
        keyword: IMAPMessageKeyword,
        isEnabled: Bool
    ) async throws {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }
        guard !uids.isEmpty else { return }

        try await withAuthenticatedSession(
            configuration: configuration,
            credential: credential,
            retriesAfterDisconnect: false
        ) { tagCounter in
            _ = try await select(folderPath: folderPath, tagCounter: &tagCounter)
            try await storeKeyword(
                uids: uids,
                keyword: keyword,
                isEnabled: isEnabled,
                tagCounter: &tagCounter
            )
        }
    }

    /// Adds or removes Gmail labels with `UID STORE ±X-GM-LABELS`. Callers must
    /// only invoke this against servers advertising `X-GM-EXT-1`.
    public func loginAndSetMessageLabels(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderPath: String,
        uids: [Int],
        labels: [String],
        isEnabled: Bool
    ) async throws {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }
        guard !uids.isEmpty, !labels.isEmpty else { return }
        let command = try Self.storeLabelsCommand(uids: uids, labels: labels, isEnabled: isEnabled)

        try await withAuthenticatedSession(
            configuration: configuration,
            credential: credential,
            retriesAfterDisconnect: false
        ) { tagCounter in
            _ = try await select(folderPath: folderPath, tagCounter: &tagCounter)
            _ = try await execute(
                tag: nextTag(&tagCounter),
                commandName: "UID STORE",
                command: command
            )
        }
    }

    /// Renders `UID STORE <set> ±X-GM-LABELS (<labels>)`. System labels
    /// (`\Inbox`, `\Starred`, …) go out as backslash atoms; user labels are
    /// quoted modified-UTF-7 mailbox names, mirroring how Gmail lists them.
    static func storeLabelsCommand(uids: [Int], labels: [String], isEnabled: Bool) throws -> String {
        let operation = isEnabled ? "+X-GM-LABELS" : "-X-GM-LABELS"
        let tokens = try labels.map { label -> String in
            if label.hasPrefix("\\"), label.dropFirst().allSatisfy(\.isLetter) {
                return label
            }
            return try quotedMailboxName(label)
        }
        return "UID STORE \(uidSet(uids)) \(operation) (\(tokens.joined(separator: " ")))"
    }

    public func loginAndMoveMessages(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        sourceFolderPath: String,
        uids: [Int],
        destinationFolderPath: String
    ) async throws {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }
        guard !uids.isEmpty, sourceFolderPath != destinationFolderPath else { return }

        try await withAuthenticatedSession(
            configuration: configuration,
            credential: credential,
            retriesAfterDisconnect: false
        ) { tagCounter in
            _ = try await select(folderPath: sourceFolderPath, tagCounter: &tagCounter)

            do {
                _ = try await execute(
                    tag: nextTag(&tagCounter),
                    commandName: "UID MOVE",
                    command: "UID MOVE \(Self.uidSet(uids)) \(Self.quotedMailboxName(destinationFolderPath))"
                )
            } catch IMAPClientError.commandFailed {
                try await copyThenDeleteMessages(
                    uids: uids,
                    destinationFolderPath: destinationFolderPath,
                    tagCounter: &tagCounter
                )
            }
        }
    }

    public func loginAndCopyMessages(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        sourceFolderPath: String,
        uids: [Int],
        destinationFolderPath: String
    ) async throws {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }
        guard !uids.isEmpty, sourceFolderPath != destinationFolderPath else { return }

        try await withAuthenticatedSession(
            configuration: configuration,
            credential: credential,
            retriesAfterDisconnect: false
        ) { tagCounter in
            _ = try await select(folderPath: sourceFolderPath, tagCounter: &tagCounter)
            try await copyMessages(
                uids: uids,
                destinationFolderPath: destinationFolderPath,
                tagCounter: &tagCounter
            )
        }
    }

    public func loginAndPermanentlyDeleteMessages(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderPath: String,
        uids: [Int]
    ) async throws {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }
        guard !uids.isEmpty else { return }

        try await withAuthenticatedSession(
            configuration: configuration,
            credential: credential,
            retriesAfterDisconnect: false
        ) { tagCounter in
            _ = try await select(folderPath: folderPath, tagCounter: &tagCounter)
            try requireTargetedExpungeSupport()
            try await storeFlag(
                uids: uids,
                flag: .deleted,
                isEnabled: true,
                tagCounter: &tagCounter
            )
            try await expungeDeletedMessages(uids: uids, tagCounter: &tagCounter)
        }
    }

    @discardableResult
    public func loginAndAppendMessage(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderPath: String,
        messageData: Data,
        flags: Set<IMAPSystemFlag> = [.seen]
    ) async throws -> IMAPAppendResult {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }

        return try await withAuthenticatedSession(
            configuration: configuration,
            credential: credential,
            retriesAfterDisconnect: false
        ) { tagCounter in
            try await appendMessage(
                folderPath: folderPath,
                messageData: messageData,
                flags: flags,
                tagCounter: &tagCounter
            )
        }
    }

    public func loginAndIdleEvents(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderPath: String,
        stopAfterEventCount: Int? = nil
    ) async -> AsyncThrowingStream<IMAPIdleEvent, any Error> {
        // Folder switches replace the dedicated IDLE lease. Close the old
        // transport and await its socket teardown before allowing a new stream
        // to authenticate, otherwise the old blocked reader could consume the
        // new session's protocol bytes.
        if idleSessionGeneration != 0 {
            idleSessionGeneration &+= 1
            await resetAuthenticatedSession()
        }
        idleSessionGeneration &+= 1
        let generation = idleSessionGeneration
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await runIdleSession(
                        configuration: configuration,
                        credential: credential,
                        folderPath: folderPath,
                        stopAfterEventCount: stopAfterEventCount,
                        generation: generation,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    // A timed-out/cancelled IDLE read closes the transport to
                    // prevent an orphan reader from consuming future protocol
                    // bytes. Clear the cached session identity as well so the
                    // next subscription performs a fresh connect/login.
                    if case IMAPClientError.transport(let message) = error,
                       message.hasPrefix("Timed out waiting for IMAP") {
                        invalidateAuthenticatedSessionAfterTransportClose(generation: generation)
                    } else {
                        await self.teardownIdleSession(generation: generation)
                    }
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.cancelIdleSession(generation: generation) }
            }
        }
    }

    private func cancelIdleSession(generation: Int) async {
        guard generation == idleSessionGeneration else { return }
        await teardownIdleSession(generation: generation)
    }

    private func teardownIdleSession(generation: Int) async {
        guard generation == idleSessionGeneration else { return }
        idleSessionGeneration &+= 1
        await resetAuthenticatedSession()
    }

    private func connectAndLogin(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        tagCounter: inout Int
    ) async throws {
        // Validate before opening any socket so callers never see a partial connection.
        try Self.validateLoginCredential(credential)

        try await transport.connect(to: configuration.incoming)
        let greeting = try await readLine(commandName: "CONNECT")
        guard greeting.uppercased().hasPrefix("* OK") else {
            throw IMAPClientError.connectionRejected(greeting)
        }
        noteServerCapabilities(fromResponseLine: greeting)

        if configuration.incoming.tlsMode == .startTLS {
            // Verify the server actually advertises STARTTLS before issuing it.
            // A server that does not offer STARTTLS may be a stripping attacker;
            // refuse to fall through to a plaintext LOGIN. Mirrors the SMTP path.
            let capabilityResponses = try await execute(
                tag: nextTag(&tagCounter),
                commandName: "CAPABILITY",
                command: "CAPABILITY"
            )
            guard Self.responseAdvertisesSTARTTLS(capabilityResponses) else {
                throw IMAPClientError.unsupportedTLSMode(.startTLS)
            }
            _ = try await execute(
                tag: nextTag(&tagCounter),
                commandName: "STARTTLS",
                command: "STARTTLS"
            )
            try await transport.upgradeToTLS(server: configuration.incoming)
        }

        switch credential.authentication {
        case .xoauth2:
            let sasl = XOAuth2SASLEncoder.encode(
                email: credential.incomingUsername,
                accessToken: credential.secret
            )
            try await authenticateXOAuth2(sasl: sasl, tagCounter: &tagCounter)
        case .password, .appPassword, .encryptedPassword:
            _ = try await execute(
                tag: nextTag(&tagCounter),
                commandName: "LOGIN",
                command: "LOGIN \(Self.quoted(credential.incomingUsername)) \(Self.quoted(credential.secret))"
            )
        case .none:
            // Refuse to send a LOGIN command without an authentication method.
            throw IMAPClientError.authenticationFailed(
                "IMAP login requires an authentication method."
            )
        }
    }

    /// Returns `true` if any untagged `CAPABILITY` response advertises STARTTLS.
    private static func responseAdvertisesSTARTTLS(_ responses: [String]) -> Bool {
        responses.contains { line in
            guard line.range(of: "CAPABILITY", options: .caseInsensitive) != nil else {
                return false
            }
            return line.uppercased()
                .split(whereSeparator: \.isWhitespace)
                .contains("STARTTLS")
        }
    }

    /// Issues `AUTHENTICATE XOAUTH2 <sasl>` and handles the optional `+` error
    /// challenge that servers send before returning `NO`.
    private func authenticateXOAuth2(sasl: String, tagCounter: inout Int) async throws {
        let tag = nextTag(&tagCounter)
        try await transport.writeLine("\(tag) AUTHENTICATE XOAUTH2 \(sasl)")

        while true {
            let line = try await readLine(commandName: "AUTHENTICATE XOAUTH2")
            if line.hasPrefix("\(tag) ") {
                let response = line.dropFirst(tag.count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                if response.hasPrefix("OK") {
                    noteServerCapabilities(fromResponseLine: line)
                    return
                }
                throw IMAPClientError.authenticationOrConnectionLimitFailed(line)
            }
            if line.hasPrefix("+ ") {
                // Server sent a base64-encoded error JSON — respond with an empty
                // string to let the server surface the tagged NO response.
                try await transport.writeLine("")
                continue
            }
            // Untagged capabilities or status lines — ignore.
        }
    }

    private static func validateLoginCredential(
        _ credential: MailAccountCredential
    ) throws {
        guard !containsNUL(credential.incomingUsername),
              !containsNUL(credential.secret)
        else {
            throw IMAPClientError.malformedResponse(
                "IMAP credentials cannot contain NUL characters."
            )
        }
    }

    private static func containsNUL(_ value: String) -> Bool {
        value.unicodeScalars.contains { $0.value == 0 }
    }

    private func execute(
        tag: String,
        commandName: String,
        command: String
    ) async throws -> [String] {
        try await transport.writeLine("\(tag) \(command)")
        return try await readTaggedResponses(tag: tag, commandName: commandName)
    }

    private func readTaggedResponses(
        tag: String,
        commandName: String
    ) async throws -> [String] {
        var untaggedResponses: [String] = []

        while true {
            let line = try await readResponseLineResolvingLiterals(
                readLine(commandName: commandName),
                commandName: commandName
            )
            guard line.hasPrefix("\(tag) ") else {
                if commandName == "CAPABILITY" {
                    noteServerCapabilities(fromResponseLine: line)
                }
                untaggedResponses.append(line)
                continue
            }

            let response = line.dropFirst(tag.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let uppercasedResponse = response.uppercased()
            if uppercasedResponse.hasPrefix("OK") {
                if commandName == "LOGIN" {
                    noteServerCapabilities(fromResponseLine: line)
                }
                return untaggedResponses
            }
            if commandName == "LOGIN",
               uppercasedResponse.hasPrefix("NO")
               || uppercasedResponse.contains("AUTHENTICATION") {
                throw IMAPClientError.authenticationOrConnectionLimitFailed(line)
            }
            throw IMAPClientError.commandFailed(command: commandName, response: line)
        }
    }

    private func readResponseLineResolvingLiterals(
        _ line: String,
        commandName: String
    ) async throws -> String {
        // Resolve chained literals iteratively (not recursively) and bound the
        // total: each literal is individually capped by `trailingLiteral`, but a
        // single logical line may carry many of them. Without an aggregate cap a
        // server could chain thousands of near-cap literals (OOM) or millions of
        // zero-byte literals (unbounded recursion/iteration).
        var current = line
        var cumulativeLiteralBytes = 0
        var literalCount = 0
        while let literal = Self.trailingLiteral(in: current) {
            literalCount += 1
            guard literalCount <= Self.maxLiteralsPerResponseLine else {
                throw IMAPClientError.malformedResponse(
                    "IMAP response line contains too many literals."
                )
            }
            cumulativeLiteralBytes += literal.byteCount
            guard cumulativeLiteralBytes <= Self.maxLiteralByteCount else {
                throw IMAPClientError.malformedResponse(
                    "IMAP response line literals exceeded the maximum aggregate length."
                )
            }

            let prefix = String(current[..<literal.range.lowerBound])
            let literalData = try await readLiteralData(
                byteCount: literal.byteCount,
                commandName: commandName
            )
            let literalString = String(decoding: literalData, as: UTF8.self)
            let suffix = try await readLine(commandName: commandName)
            current = "\(prefix)\(Self.responseLiteralToken(literalString))\(suffix)"
        }
        return current
    }

    private func readLine(
        commandName: String,
        timeoutNanoseconds: UInt64? = nil,
        teardownGeneration: Int? = nil
    ) async throws -> String {
        try await withResponseTimeout(
            commandName: commandName,
            timeoutNanoseconds: timeoutNanoseconds,
            teardownGeneration: teardownGeneration
        ) {
            try await self.transport.readLine()
        }
    }

    private func readData(
        maxLength: Int,
        commandName: String
    ) async throws -> Data {
        try await withResponseTimeout(commandName: commandName) {
            try await self.transport.readData(maxLength: maxLength)
        }
    }

    private func withResponseTimeout<T: Sendable>(
        commandName: String,
        timeoutNanoseconds: UInt64? = nil,
        teardownGeneration: Int? = nil,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let timeoutNanoseconds = timeoutNanoseconds ?? responseTimeoutNanoseconds
        guard let timeoutNanoseconds else {
            return try await operation()
        }

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    try await operation()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    throw IMAPClientError.transport(
                        "Timed out waiting for IMAP \(commandName) response."
                    )
                }

                do {
                    guard let result = try await group.next() else {
                        throw IMAPClientError.transport(
                            "Timed out waiting for IMAP \(commandName) response."
                        )
                    }
                    group.cancelAll()
                    return result
                } catch {
                    // Cancelling a Swift task does not necessarily interrupt a
                    // socket read. Close the transport before leaving the task
                    // group so an orphan reader cannot consume the next
                    // command's protocol bytes and desynchronise the session.
                    if case IMAPClientError.transport(let message) = error,
                       message.hasPrefix("Timed out waiting for IMAP") {
                        await self.disconnectTransportIfCurrent(generation: teardownGeneration)
                    }
                    group.cancelAll()
                    throw error
                }
            }
        } onCancel: {
            Task { await self.disconnectTransportIfCurrent(generation: teardownGeneration) }
        }
    }

    private func disconnectTransportIfCurrent(generation: Int?) async {
        if let generation {
            guard generation == idleSessionGeneration else { return }
            await transport.disconnect()
            return
        }
        // A command-session read torn down out of band takes the shared
        // authenticated session with it. Clearing only the socket left
        // `authenticatedSessionIdentity` set, so the next operation skipped
        // login and issued commands on a dead transport — every message open
        // that cancelled background work poisoned the following body fetch.
        await resetAuthenticatedSession()
    }

    private func runIdleSession(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderPath: String,
        stopAfterEventCount: Int?,
        generation: Int,
        continuation: AsyncThrowingStream<IMAPIdleEvent, any Error>.Continuation
    ) async throws {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }

        var tagCounter = 1
        try await connectAndLogin(
            configuration: configuration,
            credential: credential,
            tagCounter: &tagCounter
        )
        _ = try await select(folderPath: folderPath, tagCounter: &tagCounter)

        let tag = nextTag(&tagCounter)
        try await transport.writeLine("\(tag) IDLE")
        try await readIdleContinuation(tag: tag, generation: generation)

        var emittedEvents = 0
        let idleDeadline = idleMaximumDurationNanoseconds.map {
            DispatchTime.now().uptimeNanoseconds + $0
        }
        while !Task.isCancelled {
            let timeoutNanoseconds = idleDeadline.map { deadline in
                max(1, deadline > DispatchTime.now().uptimeNanoseconds
                    ? deadline - DispatchTime.now().uptimeNanoseconds
                    : 1)
            }
            let line = try await readLine(
                commandName: "IDLE",
                timeoutNanoseconds: timeoutNanoseconds,
                teardownGeneration: generation
            )
            if line.hasPrefix("\(tag) ") {
                try Self.validateTaggedResponse(line, tag: tag, commandName: "IDLE")
                return
            }
            guard let event = IMAPIdleEvent.parse(line) else { continue }
            continuation.yield(event)
            emittedEvents += 1

            if let stopAfterEventCount,
               emittedEvents >= stopAfterEventCount {
                try await transport.writeLine("DONE")
                _ = try await readTaggedResponses(tag: tag, commandName: "IDLE")
                return
            }
        }

        try? await transport.writeLine("DONE")
    }

    private func readIdleContinuation(tag: String, generation: Int) async throws {
        while true {
            let line = try await readLine(
                commandName: "IDLE",
                teardownGeneration: generation
            )
            if line.hasPrefix("+") {
                return
            }
            if line.hasPrefix("*") {
                continue
            }
            if line.hasPrefix("\(tag) ") {
                let response = line.dropFirst(tag.count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                if response.hasPrefix("NO") {
                    throw IMAPClientError.idleNotSupported(response: line)
                }
                try Self.validateTaggedResponse(line, tag: tag, commandName: "IDLE")
                throw IMAPClientError.commandFailed(command: "IDLE", response: line)
            }
            throw IMAPClientError.malformedResponse(line)
        }
    }

    private static func validateTaggedResponse(
        _ line: String,
        tag: String,
        commandName: String
    ) throws {
        let response = line.dropFirst(tag.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if response.hasPrefix("OK") {
            return
        }
        throw IMAPClientError.commandFailed(command: commandName, response: line)
    }

    private func appendMessage(
        folderPath: String,
        messageData: Data,
        flags: Set<IMAPSystemFlag>,
        tagCounter: inout Int
    ) async throws -> IMAPAppendResult {
        // Strict IMAP servers (e.g. Fastmail) reject bare LF/CR in APPEND
        // literals. Normalize here so Sent-copy, drafts, and local fixtures
        // built with Swift multiline strings still APPEND cleanly.
        let wireMessageData = MIMEWireEncoding.crlfNormalizedMessageData(messageData)
        let tag = nextTag(&tagCounter)
        let flagTokens = flags
            .map(\.commandToken)
            .sorted()
            .joined(separator: " ")
        let flagsClause = flagTokens.isEmpty ? "" : " (\(flagTokens))"
        try await transport.writeLine(
            "\(tag) APPEND \(Self.quotedMailboxName(folderPath))\(flagsClause) {\(wireMessageData.count)}"
        )
        try await readLiteralContinuation(tag: tag, commandName: "APPEND")
        try await transport.writeData(wireMessageData)
        try await transport.writeData(Data("\r\n".utf8))
        let taggedResponse = try await readAppendTaggedResponse(tag: tag)
        return IMAPAppendResult.parse(from: taggedResponse)
    }

    private func readAppendTaggedResponse(tag: String) async throws -> String {
        while true {
            let line = try await readLine(commandName: "APPEND")
            guard line.hasPrefix("\(tag) ") else {
                continue
            }
            let response = line.dropFirst(tag.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            if response.hasPrefix("OK") {
                return line
            }
            throw IMAPClientError.commandFailed(command: "APPEND", response: line)
        }
    }

    private func readLiteralContinuation(
        tag: String,
        commandName: String
    ) async throws {
        while true {
            let line = try await readLine(commandName: commandName)
            if line.hasPrefix("+") {
                return
            }
            if line.hasPrefix("*") {
                continue
            }
            if line.hasPrefix("\(tag) ") {
                throw IMAPClientError.commandFailed(command: commandName, response: line)
            }
            throw IMAPClientError.malformedResponse(line)
        }
    }

    private func select(
        folderPath: String,
        tagCounter: inout Int
    ) async throws -> IMAPSelectedMailbox {
        if reusesAuthenticatedSession,
           let selectedMailboxState,
           selectedMailboxState.folderPath == folderPath {
            return selectedMailboxState.mailbox
        }
        // Always request CONDSTORE; servers that don't support it ignore the modifier.
        let responses = try await execute(
            tag: nextTag(&tagCounter),
            commandName: "SELECT",
            command: "SELECT \(Self.quotedMailboxName(folderPath)) (CONDSTORE)"
        )
        let selectedMailbox = IMAPSelectedMailbox.parse(from: responses)
        if reusesAuthenticatedSession {
            selectedMailboxState = SelectedMailboxState(
                folderPath: folderPath,
                mailbox: selectedMailbox
            )
        }
        return selectedMailbox
    }

    private func storeFlag(
        uids: [Int],
        flag: IMAPSystemFlag,
        isEnabled: Bool,
        tagCounter: inout Int
    ) async throws {
        let operation = isEnabled ? "+FLAGS.SILENT" : "-FLAGS.SILENT"
        _ = try await execute(
            tag: nextTag(&tagCounter),
            commandName: "UID STORE",
            command: "UID STORE \(Self.uidSet(uids)) \(operation) (\(flag.commandToken))"
        )
    }

    private func storeKeyword(
        uids: [Int],
        keyword: IMAPMessageKeyword,
        isEnabled: Bool,
        tagCounter: inout Int
    ) async throws {
        let operation = isEnabled ? "+FLAGS.SILENT" : "-FLAGS.SILENT"
        _ = try await execute(
            tag: nextTag(&tagCounter),
            commandName: "UID STORE",
            command: "UID STORE \(Self.uidSet(uids)) \(operation) (\(keyword.commandToken))"
        )
    }

    private func copyThenDeleteMessages(
        uids: [Int],
        destinationFolderPath: String,
        tagCounter: inout Int
    ) async throws {
        try requireTargetedExpungeSupport()
        try await copyMessages(
            uids: uids,
            destinationFolderPath: destinationFolderPath,
            tagCounter: &tagCounter
        )
        try await storeFlag(
            uids: uids,
            flag: .deleted,
            isEnabled: true,
            tagCounter: &tagCounter
        )
        try await expungeDeletedMessages(uids: uids, tagCounter: &tagCounter)
    }

    private func copyMessages(
        uids: [Int],
        destinationFolderPath: String,
        tagCounter: inout Int
    ) async throws {
        _ = try await execute(
            tag: nextTag(&tagCounter),
            commandName: "UID COPY",
            command: "UID COPY \(Self.uidSet(uids)) \(Self.quotedMailboxName(destinationFolderPath))"
        )
    }

    private func expungeDeletedMessages(
        uids: [Int],
        tagCounter: inout Int
    ) async throws {
        try requireTargetedExpungeSupport()
        _ = try await execute(
            tag: nextTag(&tagCounter),
            commandName: "UID EXPUNGE",
            command: "UID EXPUNGE \(Self.uidSet(uids))"
        )
    }

    /// Plain EXPUNGE can delete unrelated messages that already carry
    /// `\\Deleted`. Refuse to use it unless the server advertises UIDPLUS.
    private func requireTargetedExpungeSupport() throws {
        guard serverCapabilities.supportsUIDPlus else {
            throw IMAPClientError.commandNotSupported(
                command: "UID EXPUNGE",
                response: "Server did not advertise UIDPLUS."
            )
        }
    }

    private func fetchMessageListings(
        uids: [Int],
        tagCounter: inout Int
    ) async throws -> [IMAPMessageListing] {
        // X-GM-LABELS is only valid on servers advertising X-GM-EXT-1; others
        // reject the whole FETCH, so it is added strictly behind the capability.
        let labelAttribute = serverCapabilities.supportsGmailExtensions ? " X-GM-LABELS" : ""
        let fetchResponses = try await execute(
            tag: nextTag(&tagCounter),
            commandName: "UID FETCH",
            command: "UID FETCH \(uids.map(String.init).joined(separator: ",")) "
                + "(FLAGS ENVELOPE\(labelAttribute) BODY.PEEK[TEXT]<0.\(Self.messageListingPreviewByteLimit)>)"
        )
        return fetchResponses
            .compactMap(IMAPMessageListing.parse)
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.uid > rhs.uid
                }
                return lhs.date > rhs.date
            }
    }

    private func nextTag(_ counter: inout Int) -> String {
        defer { counter += 1 }
        return String(format: "A%04d", counter)
    }

    private static func messageUIDs(from responses: [String]) -> [Int] {
        responses
            .flatMap { response -> [Int] in
                guard let searchRange = response.range(
                    of: "* SEARCH",
                    options: [.anchored, .caseInsensitive]
                ) else {
                    return []
                }
                return response
                    .suffix(from: searchRange.upperBound)
                    .split(whereSeparator: \.isWhitespace)
                    .compactMap { Int($0) }
            }
    }

    private static func bodyLiteralByteCount(in line: String, uid: Int) -> Int? {
        guard line.hasPrefix("* "),
              line.range(of: " FETCH ", options: .caseInsensitive) != nil,
              fetchLine(line, containsUID: uid),
              isRawMessageFetchLine(line),
              line.hasSuffix("}"),
              let openBrace = line.lastIndex(of: "{")
        else {
            return nil
        }

        let countStart = line.index(after: openBrace)
        let countEnd = line.index(before: line.endIndex)
        guard countStart < countEnd else { return nil }
        guard let count = Int(line[countStart ..< countEnd]),
              count >= 0,
              count <= maxLiteralByteCount
        else {
            return nil
        }
        return count
    }

    private static func fetchLiteralByteCount(in line: String, uid: Int) -> Int? {
        guard line.hasPrefix("* "),
              line.range(of: " FETCH ", options: .caseInsensitive) != nil,
              fetchLine(line, containsUID: uid),
              line.range(of: "BODY[", options: .caseInsensitive) != nil,
              line.hasSuffix("}"),
              let openBrace = line.lastIndex(of: "{")
        else { return nil }
        let countStart = line.index(after: openBrace)
        let countEnd = line.index(before: line.endIndex)
        guard countStart < countEnd,
              let count = Int(line[countStart ..< countEnd]),
              count >= 0,
              count <= maxLiteralByteCount
        else { return nil }
        return count
    }

    private static func decodeTransferEncoding(_ data: Data, encoding: String) throws -> Data {
        switch encoding.lowercased() {
        case "base64":
            let compact = String(decoding: data, as: UTF8.self)
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()
            guard let decoded = Data(base64Encoded: compact) else {
                throw IMAPClientError.malformedResponse("Invalid base64 message part.")
            }
            return decoded
        case "quoted-printable":
            return MIMEQuotedPrintableDecoder.decode(String(decoding: data, as: UTF8.self))
        default:
            return data
        }
    }

    private static func fetchLine(_ line: String, containsUID uid: Int) -> Bool {
        var index = line.startIndex
        var isInsideQuotedString = false
        var isEscaped = false
        while index < line.endIndex {
            let character = line[index]
            if isInsideQuotedString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideQuotedString = false
                }
                line.formIndex(after: &index)
                continue
            }

            if character == "\"" {
                isInsideQuotedString = true
                line.formIndex(after: &index)
                continue
            }

            if isFetchAttributeBoundary(before: index, in: line),
               let range = line[index...].range(
                   of: "UID",
                   options: [.anchored, .caseInsensitive]
               ) {
                var valueIndex = range.upperBound
                if valueIndex < line.endIndex,
                   !line[valueIndex].isWhitespace {
                    line.formIndex(after: &index)
                    continue
                }
                while valueIndex < line.endIndex, line[valueIndex].isWhitespace {
                    line.formIndex(after: &valueIndex)
                }
                let start = valueIndex
                while valueIndex < line.endIndex, line[valueIndex].isNumber {
                    line.formIndex(after: &valueIndex)
                }
                guard start < valueIndex,
                      Int(line[start ..< valueIndex]) == uid
                else {
                    line.formIndex(after: &index)
                    continue
                }
                if valueIndex == line.endIndex || line[valueIndex].isWhitespace || line[valueIndex] == ")" {
                    return true
                }
            }

            line.formIndex(after: &index)
        }
        return false
    }

    private static func isFetchAttributeBoundary(
        before index: String.Index,
        in line: String
    ) -> Bool {
        guard index > line.startIndex else { return true }
        let previousIndex = line.index(before: index)
        return line[previousIndex].isWhitespace || line[previousIndex] == "("
    }

    private static func isRawMessageFetchLine(_ line: String) -> Bool {
        IMAPRawMessageFetchLabel.isPresent(in: line)
    }

    /// Upper bound on an IMAP literal byte count. A literal announces how many
    /// bytes the client must then read; an absurd value (a buggy or hostile
    /// server sending `{999999999999}` and streaming data) would otherwise make
    /// `readLiteralData` accumulate unbounded memory. 512 MiB is far above any
    /// realistic message/attachment yet bounds the read.
    static let maxLiteralByteCount = 512 * 1024 * 1024

    /// Upper bound on the number of chained literals resolved within a single
    /// logical response line. Real IMAP lines carry at most a few dozen; this
    /// stops a server from spinning the resolver with a flood of tiny literals.
    static let maxLiteralsPerResponseLine = 65536

    static func trailingLiteral(in line: String) -> (range: Range<String.Index>, byteCount: Int)? {
        guard line.hasSuffix("}"),
              let openBrace = line.lastIndex(of: "{")
        else {
            return nil
        }

        let countStart = line.index(after: openBrace)
        let countEnd = line.index(before: line.endIndex)
        guard countStart < countEnd else { return nil }
        var countText = String(line[countStart ..< countEnd])
        if countText.last == "+" {
            countText.removeLast()
        }
        guard let byteCount = Int(countText),
              byteCount >= 0,
              byteCount <= maxLiteralByteCount
        else {
            return nil
        }
        return (openBrace ..< line.endIndex, byteCount)
    }

    private static func pageUIDs(
        from uids: [Int],
        before pageToken: String?
    ) throws -> [Int] {
        let sortedUIDs = uids.sorted()
        guard let pageToken else { return sortedUIDs }
        guard let boundary = pageBoundary(from: pageToken) else {
            throw IMAPClientError.malformedResponse("Invalid IMAP page token: \(pageToken)")
        }
        return sortedUIDs.filter { $0 < boundary }
    }

    private static func pageBoundary(from pageToken: String) -> Int? {
        guard pageToken.hasPrefix("before:") else { return nil }
        return Int(pageToken.dropFirst("before:".count))
    }

    /// One element of a SEARCH command. `.atom` is a verbatim keyword or
    /// token (`ALL`, `SEEN`, `TEXT`, `OR`, `SINCE 01-Jan-2024`, …);
    /// `.astring` is a user-supplied value that is quoted when ASCII and
    /// sent as an RFC 3501 synchronizing literal when it carries non-ASCII
    /// octets (so accented/non-Latin terms search correctly — see
    /// `executeSearch`).
    private enum IMAPSearchToken: Equatable {
        case atom(String)
        case astring(String)
    }

    private static func searchTokens(for query: SearchQuery) throws -> [IMAPSearchToken] {
        if query.hasAttachments != nil {
            throw IMAPClientError.unsupportedSearchCriterion("attachment predicates")
        }

        var tokens: [IMAPSearchToken] = []
        appendTextTokens(query.text, to: &tokens)
        appendValueKey("FROM", value: query.from, to: &tokens)
        appendRecipientTokens(query.to, to: &tokens)
        appendReadTokens(query.isUnread, to: &tokens)
        appendFlaggedTokens(query.isFlagged, to: &tokens)
        appendValueKey("SUBJECT", value: query.subject, to: &tokens)
        appendDateTokens(query.dateRange, to: &tokens)
        return tokens.isEmpty ? [.atom("ALL")] : tokens
    }

    private static func appendTextTokens(
        _ value: String,
        to tokens: inout [IMAPSearchToken]
    ) {
        let terms = searchTerms(in: value)
        guard !terms.isEmpty else { return }
        for term in terms {
            tokens.append(.atom("TEXT"))
            tokens.append(.astring(term))
        }
    }

    private static func searchTerms(in value: String) -> [String] {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }
    }

    private static func appendValueKey(
        _ key: String,
        value: String?,
        to tokens: inout [IMAPSearchToken]
    ) {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isEmpty else { return }
        tokens.append(.atom(key))
        tokens.append(.astring(normalized))
    }

    private static func appendRecipientTokens(
        _ value: String?,
        to tokens: inout [IMAPSearchToken]
    ) {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isEmpty else { return }
        tokens.append(.atom("OR"))
        tokens.append(.atom("OR"))
        tokens.append(.atom("TO"))
        tokens.append(.astring(normalized))
        tokens.append(.atom("CC"))
        tokens.append(.astring(normalized))
        tokens.append(.atom("BCC"))
        tokens.append(.astring(normalized))
    }

    private static func appendReadTokens(
        _ isUnread: Bool?,
        to tokens: inout [IMAPSearchToken]
    ) {
        guard let isUnread else { return }
        tokens.append(.atom(isUnread ? "UNSEEN" : "SEEN"))
    }

    private static func appendFlaggedTokens(
        _ isFlagged: Bool?,
        to tokens: inout [IMAPSearchToken]
    ) {
        guard let isFlagged else { return }
        tokens.append(.atom(isFlagged ? "FLAGGED" : "UNFLAGGED"))
    }

    private static func appendDateTokens(
        _ range: ClosedRange<Date>?,
        to tokens: inout [IMAPSearchToken]
    ) {
        guard let range else { return }
        tokens.append(.atom("SINCE \(imapSearchDate(range.lowerBound))"))
        let exclusiveUpperBound = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: 1, to: range.upperBound) ?? range.upperBound
        tokens.append(.atom("BEFORE \(imapSearchDate(exclusiveUpperBound))"))
    }

    private static func imapSearchDate(_ date: Date) -> String {
        searchDateFormatter.string(from: date)
    }

    private static let searchDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd-MMM-yyyy"
        return formatter
    }()

    private static func uidSet(_ uids: [Int]) -> String {
        uids.map(String.init).joined(separator: ",")
    }

    private static func quoted(_ value: String) throws -> String {
        guard value.rangeOfCharacter(from: .newlines) == nil else {
            throw IMAPClientError.malformedResponse(
                "IMAP quoted strings cannot contain line breaks."
            )
        }

        var escaped = ""
        for character in value {
            switch character {
            case "\\":
                escaped.append("\\\\")
            case "\"":
                escaped.append("\\\"")
            default:
                escaped.append(character)
            }
        }
        return "\"\(escaped)\""
    }

    private static func responseLiteralToken(_ value: String) -> String {
        var escaped = ""
        for character in value {
            switch character {
            case "\\":
                escaped.append("\\\\")
            case "\"":
                escaped.append("\\\"")
            default:
                escaped.append(character)
            }
        }
        return "\"\(escaped)\""
    }

    private static func quotedMailboxName(_ value: String) throws -> String {
        try quoted(IMAPMailboxNameCodec.encode(value))
    }

    // MARK: - CONDSTORE (RFC 4551) delta-sync

    /// Connects, logs in, and performs a CONDSTORE delta sync for a folder.
    ///
    /// Selects the mailbox with `(CONDSTORE)` to get the current `HIGHESTMODSEQ`.
    /// If `sinceModSeq` equals the new value, returns immediately with empty
    /// changes — nothing changed since the last sync. Otherwise issues a
    /// `UID FETCH 1:* (UID FLAGS) (CHANGEDSINCE sinceModSeq)` to retrieve
    /// changed messages and returns both the new modseq and the changes.
    ///
    /// When `sinceModSeq` is nil (first sync), returns the current modseq with
    /// empty changes so callers can seed the cache watermark.
    public func loginAndCONDSTORESync(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderPath: String,
        since sinceModSeq: UInt64?
    ) async throws -> (highestModSeq: UInt64?, uidValidity: Int?, changes: [(uid: Int, flags: [String])]) {
        guard configuration.incoming.kind == .imap else {
            throw IMAPClientError.invalidServerKind(configuration.incoming.kind)
        }
        return try await withAuthenticatedSession(
            configuration: configuration,
            credential: credential
        ) { tagCounter in
            let selected = try await selectCONDSTORE(folderPath: folderPath, tagCounter: &tagCounter)
            // UIDVALIDITY is returned alongside the modseq so the caller can detect a
            // mailbox renumber even when HIGHESTMODSEQ is unchanged.
            guard let newModSeq = selected.highestModSeq else {
                return (nil, selected.uidValidity, [])
            }
            // Nothing changed — skip the fetch
            if let since = sinceModSeq, since == newModSeq {
                return (newModSeq, selected.uidValidity, [])
            }
            // First sync or modseq advanced — fetch changed messages
            guard let since = sinceModSeq else {
                return (newModSeq, selected.uidValidity, [])
            }
            let changes = try await fetchChangedMessages(since: since, tagCounter: &tagCounter)
            return (newModSeq, selected.uidValidity, changes)
        }
    }

    private func selectCONDSTORE(folderPath: String, tagCounter: inout Int) async throws -> IMAPSelectedMailbox {
        let responses = try await execute(
            tag: nextTag(&tagCounter),
            commandName: "SELECT",
            command: "SELECT \(Self.quotedMailboxName(folderPath)) (CONDSTORE)"
        )
        let selectedMailbox = IMAPSelectedMailbox.parse(from: responses)
        if reusesAuthenticatedSession {
            selectedMailboxState = SelectedMailboxState(
                folderPath: folderPath,
                mailbox: selectedMailbox
            )
        }
        return selectedMailbox
    }

    private func fetchChangedMessages(since modSeq: UInt64, tagCounter: inout Int) async throws -> [(uid: Int, flags: [String])] {
        let responses = try await execute(
            tag: nextTag(&tagCounter),
            commandName: "UID FETCH",
            command: "UID FETCH 1:* (UID FLAGS) (CHANGEDSINCE \(modSeq))"
        )
        return responses.compactMap { Self.parseChangedMessageEntry(from: $0) }
    }

    // Internal (not private) so the delta-sync flag parse — a server-controlled,
    // crash-sensitive path — can be regression-tested directly.
    static func parseChangedMessageEntry(from line: String) -> (uid: Int, flags: [String])? {
        guard line.hasPrefix("* "),
              line.range(of: " FETCH ", options: .caseInsensitive) != nil,
              let uid = parseFetchUID(in: line)
        else {
            return nil
        }
        return (uid: uid, flags: parseRawFlags(in: line))
    }

    private static func parseFetchUID(in line: String) -> Int? {
        let uppercased = line.uppercased()
        var searchFrom = uppercased.startIndex
        while let range = uppercased[searchFrom...].range(of: "UID ") {
            let before = range.lowerBound
            if before > uppercased.startIndex {
                let prev = uppercased[uppercased.index(before: before)]
                guard prev.isWhitespace || prev == "(" else {
                    searchFrom = range.upperBound
                    continue
                }
            }
            var valueIndex = range.upperBound
            let numStart = valueIndex
            while valueIndex < uppercased.endIndex, uppercased[valueIndex].isNumber {
                uppercased.formIndex(after: &valueIndex)
            }
            if numStart < valueIndex, let uid = Int(uppercased[numStart ..< valueIndex]) {
                return uid
            }
            searchFrom = range.upperBound
        }
        return nil
    }

    private static func parseRawFlags(in line: String) -> [String] {
        // Search and slice the SAME string. Computing the marker range on
        // `line.uppercased()` and then slicing `line` is unsafe: `uppercased()`
        // can change a string's UTF-8 length (e.g. U+0250 'ɐ' → 'Ɐ' is 2→3
        // bytes), so a `String.Index` from the uppercased copy can point past
        // `line`'s end and trap. IMAP FLAGS keyword atoms and X-GM-LABELS are
        // server-controlled, so a hostile/buggy server could crash delta-sync.
        // A case-insensitive search on `line` keeps the indices and the slice in
        // one string and preserves the flags' original case.
        guard let flagsRange = line.range(of: "FLAGS (", options: .caseInsensitive) else { return [] }
        let start = flagsRange.upperBound
        guard let end = line[start...].firstIndex(of: ")") else { return [] }
        return String(line[start ..< end])
            .split(whereSeparator: \.isWhitespace)
            .map { String($0) }
    }
}

private struct IMAPEnvelope {
    let date: Date
    let subject: String
    let from: [Correspondent]
    let replyTo: [Correspondent]
    let to: [Correspondent]
    let cc: [Correspondent]
    let bcc: [Correspondent]
    let inReplyTo: String?
    let messageID: String
}

enum IMAPDateParser {
    private static let formats = [
        "EEE, d MMM yyyy HH:mm:ss Z",
        "d MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm Z",
        "d MMM yyyy HH:mm Z",
        "EEE, d MMM yyyy HH:mm:ss zzz",
        "d MMM yyyy HH:mm:ss zzz",
        "EEE, d MMM yyyy HH:mm zzz",
        "d MMM yyyy HH:mm zzz",
        // Zone-less dates are malformed per RFC 5322 but appear in the
        // wild; tried last after every zone-bearing form. The formatter's
        // UTC time zone is assumed, which beats dropping the date.
        "EEE, d MMM yyyy HH:mm:ss",
        "d MMM yyyy HH:mm:ss",
        "EEE, d MMM yyyy HH:mm",
        "d MMM yyyy HH:mm"
    ]

    // Date headers are parsed for every envelope in a FETCH response. Keep
    // configured formatters around instead of rebuilding and mutating one for
    // every candidate. Foundation's configured DateFormatter instances are
    // safe for concurrent reads on the modern 64-bit platforms Brev supports.
    private static let formatterLock = NSLock()
    private nonisolated(unsafe) static var formatterCache: [String: DateFormatter] = [:]

    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var candidates = [trimmed]
        let withoutTrailingComments = strippingTrailingComments(from: trimmed)
        if withoutTrailingComments != trimmed {
            candidates.append(withoutTrailingComments)
        }

        for candidate in candidates {
            for format in formats {
                if let date = formatter(for: format).date(from: candidate) {
                    return date
                }
            }
        }
        return nil
    }

    private static func formatter(for format: String) -> DateFormatter {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        if let cached = formatterCache[format] {
            return cached
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        formatterCache[format] = formatter
        return formatter
    }

    static func dateHeader(from rawMessage: String) -> Date? {
        guard let value = headerValue(named: "Date", in: rawMessage) else { return nil }
        return date(from: value)
    }

    private static func strippingTrailingComments(from value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasSuffix(")") {
            guard let opening = result.lastIndex(of: "(") else { break }
            let prefix = result[..<opening].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prefix.isEmpty else { break }
            result = String(prefix)
        }
        return result
    }

    private static func headerValue(named name: String, in rawMessage: String) -> String? {
        let normalized = rawMessage
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let expectedName = name.lowercased()
        var activeName: String?
        var activeValue = ""

        func matchingActiveValue() -> String? {
            guard activeName?.lowercased() == expectedName else { return nil }
            return activeValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty {
                return matchingActiveValue()
            }
            if line.first == " " || line.first == "\t" {
                if activeName != nil {
                    activeValue += " " + line.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                continue
            }
            if let value = matchingActiveValue() {
                return value
            }
            guard let separator = line.firstIndex(of: ":") else {
                activeName = nil
                activeValue = ""
                continue
            }
            activeName = String(line[..<separator])
            let valueStart = line.index(after: separator)
            activeValue = String(line[valueStart...])
        }

        return matchingActiveValue()
    }
}

enum IMAPSExpressionValue: Equatable {
    case string(String)
    case atom(String)
    case nilValue
    case list([IMAPSExpressionValue])

    var stringValue: String? {
        switch self {
        case .string(let value), .atom(let value):
            value
        case .nilValue, .list:
            nil
        }
    }
}

struct IMAPSExpressionParser {
    /// Upper bound on parenthesis nesting. Real IMAP ENVELOPE/BODYSTRUCTURE
    /// S-expressions are only a handful of levels deep; this guards against a
    /// malicious server sending `(((((…` to overflow the parser's stack.
    private static let maxNestingDepth = 64

    private let text: String
    private var index: String.Index

    init(_ text: String) {
        self.text = text
        index = text.startIndex
    }

    mutating func parseValue() -> IMAPSExpressionValue? {
        parseValue(depth: 0)
    }

    private mutating func parseValue(depth: Int) -> IMAPSExpressionValue? {
        skipSpaces()
        guard index < text.endIndex else { return nil }
        if text[index] == "(" {
            return parseList(depth: depth)
        }
        if text[index] == "\"" {
            return parseQuotedString().map(IMAPSExpressionValue.string)
        }
        return parseAtom()
    }

    private mutating func parseList(depth: Int) -> IMAPSExpressionValue? {
        // Treat over-deep nesting as malformed rather than recursing into a crash.
        guard depth < Self.maxNestingDepth else { return nil }
        guard index < text.endIndex, text[index] == "(" else { return nil }
        text.formIndex(after: &index)
        var values: [IMAPSExpressionValue] = []
        while index < text.endIndex {
            skipSpaces()
            guard index < text.endIndex else { return nil }
            if text[index] == ")" {
                text.formIndex(after: &index)
                return .list(values)
            }
            guard let value = parseValue(depth: depth + 1) else { return nil }
            values.append(value)
        }
        return nil
    }

    private mutating func parseQuotedString() -> String? {
        guard index < text.endIndex, text[index] == "\"" else { return nil }
        text.formIndex(after: &index)
        var value = ""
        while index < text.endIndex {
            let character = text[index]
            text.formIndex(after: &index)
            if character == "\"" {
                return value
            }
            if character == "\\", index < text.endIndex {
                value.append(text[index])
                text.formIndex(after: &index)
            } else {
                value.append(character)
            }
        }
        return nil
    }

    private mutating func parseAtom() -> IMAPSExpressionValue? {
        let start = index
        while index < text.endIndex,
              !text[index].isWhitespace,
              text[index] != "(",
              text[index] != ")" {
            text.formIndex(after: &index)
        }
        guard start < index else { return nil }
        let atom = String(text[start ..< index])
        if atom.uppercased() == "NIL" {
            return .nilValue
        }
        return .atom(atom)
    }

    private mutating func skipSpaces() {
        while index < text.endIndex, text[index].isWhitespace {
            text.formIndex(after: &index)
        }
    }
}

/// Decodes long base64 runs that appear where prose should be: an encoded
/// body part captured by the listing peek, either freshly fetched or cached
/// by an older build. Groups of consecutive base64-looking tokens (wrapped
/// encoder lines joined by spaces) are decoded as one unit. Short runs (hex
/// digests, tokens) and runs that do not decode to clean UTF-8 text stay
/// untouched.
public enum SnippetBase64RunDecoder {
    private static let minimumCombinedLength = 64

    /// Replaces every qualifying base64 run in `text` with its decoded text.
    public static func decodingBase64Runs(in text: String) -> String {
        let pattern = #"[A-Za-z0-9+/]{16,}={0,2}(?:\s+[A-Za-z0-9+/]{8,}={0,2})*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            result += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let run = nsText.substring(with: match.range)
            result += decodedRun(run) ?? run
            cursor = match.range.location + match.range.length
        }
        result += nsText.substring(from: cursor)
        return result
    }

    private static func decodedRun(_ run: String) -> String? {
        let joined = run.components(separatedBy: .whitespacesAndNewlines).joined()
        guard joined.count >= minimumCombinedLength else { return nil }
        let aligned = String(joined.prefix(joined.count - joined.count % 4))
        guard let data = Data(base64Encoded: aligned),
              let decoded = String(data: data, encoding: .utf8),
              isMostlyText(decoded) else {
            return nil
        }
        return decoded
    }

    /// Random bytes that happen to be valid UTF-8 are still control-heavy;
    /// real text (prose or HTML) is not.
    private static func isMostlyText(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        guard !scalars.isEmpty else { return false }
        let textual = scalars.filter { scalar in
            if scalar == "\n" || scalar == "\t" || scalar == "\r" { return true }
            return scalar.properties.generalCategory != .control
        }.count
        return Double(textual) / Double(scalars.count) >= 0.95
    }
}
