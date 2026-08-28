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

public struct IMAPMessageBodyParser: Sendable {
    public init() {}

    public func parse(
        messageID: String,
        rawMessage: String
    ) -> MessageBody {
        let part = MIMEPart.parse(rawMessage)
        var collector = MIMEBodyCollector(messageID: messageID)
        collector.consume(part)
        let authResults = part.headers.value(named: "Authentication-Results")
        let readReceiptRequest = part.headers.value(named: "Disposition-Notification-To").map {
            ReadReceiptRequest(notificationTo: $0)
        }
        return MessageBody(
            messageID: messageID,
            html: collector.html,
            plainText: collector.plainText,
            attachments: collector.attachments,
            readReceiptRequest: readReceiptRequest,
            readReceiptNotification: collector.readReceiptNotification,
            authenticationResults: authResults
        )
    }

    public func rawMessageString(from data: Data) -> String {
        if let declaredEncoding = Self.declaredRawMessageEncoding(in: data),
           let decoded = String(data: data, encoding: declaredEncoding) {
            return decoded
        }
        if let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        if let declaredPartEncoding = Self.declaredBodyPartEncoding(in: data),
           let decoded = String(data: data, encoding: declaredPartEncoding) {
            return decoded
        }
        return String(data: data, encoding: .isoLatin1)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(decoding: data, as: UTF8.self)
    }

    func decodedStructuredPart(
        _ data: Data,
        part: IMAPBodyStructurePart
    ) -> MessageBody {
        var prefix = "Content-Type: \(part.mimeType)"
        if let charset = part.charset, !charset.isEmpty {
            prefix += "; charset=\"\(charset)\""
        }
        prefix += "\r\nContent-Transfer-Encoding: \(part.transferEncoding)\r\n\r\n"
        var rawData = Data(prefix.utf8)
        rawData.append(data)
        return parse(messageID: "structured-part", rawMessage: rawMessageString(from: rawData))
    }

    func structuredBody(
        messageID: String,
        headerBlock: String,
        plainText: String?,
        html: String?,
        attachments: [Attachment],
        readReceiptNotification: ReadReceiptNotification?
    ) -> MessageBody {
        let headers = MIMEHeader.parse(
            headerBlock
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
        )
        return MessageBody(
            messageID: messageID,
            html: html,
            plainText: plainText,
            attachments: attachments,
            readReceiptRequest: headers.value(named: "Disposition-Notification-To").map {
                ReadReceiptRequest(notificationTo: $0)
            },
            readReceiptNotification: readReceiptNotification,
            authenticationResults: headers.value(named: "Authentication-Results")
        )
    }

    func attachmentData(
        attachmentIndex: Int,
        rawMessage: String
    ) -> Data? {
        guard attachmentIndex > 0 else { return nil }
        let part = MIMEPart.parse(rawMessage)
        var collector = MIMEBodyCollector(messageID: "message")
        collector.consume(part)
        let payloadIndex = attachmentIndex - 1
        guard collector.attachmentPayloads.indices.contains(payloadIndex) else {
            return nil
        }
        return collector.attachmentPayloads[payloadIndex]
    }

    private static func declaredRawMessageEncoding(in data: Data) -> String.Encoding? {
        guard let headerData = rawHeaderData(in: data),
              let headerBlock = String(data: headerData, encoding: .ascii)
              ?? String(data: headerData, encoding: .utf8),
              let charset = contentTypeCharset(in: headerBlock)
        else {
            return nil
        }
        // Strict lookup: an unknown charset returns nil so `rawMessageString`
        // falls through to UTF-8 then the Latin-1/CP1252 heuristics rather than
        // being forced to UTF-8.
        return MIMECharset.recognizedEncoding(for: charset)
    }

    private static func declaredBodyPartEncoding(in data: Data) -> String.Encoding? {
        let raw = String(data: data, encoding: .isoLatin1)
            ?? String(decoding: data, as: UTF8.self)
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        for headerBlock in normalized.components(separatedBy: "\n\n") {
            guard let charset = contentTypeCharset(in: headerBlock) else { continue }
            return MIMECharset.recognizedEncoding(for: charset)
        }
        return nil
    }

    private static func rawHeaderData(in data: Data) -> Data? {
        if let range = data.firstRange(of: Data([13, 10, 13, 10])) {
            return Data(data[..<range.lowerBound])
        }
        if let range = data.firstRange(of: Data([10, 10])) {
            return Data(data[..<range.lowerBound])
        }
        return nil
    }

    private static func contentTypeCharset(in headerBlock: String) -> String? {
        let unfolded = unfoldHeaderLines(headerBlock)
        guard let contentTypeLine = unfolded.first(where: { line in
            line.lowercased().hasPrefix("content-type:")
        }) else {
            return nil
        }
        let pieces = contentTypeLine.split(separator: ";", omittingEmptySubsequences: false)
        for piece in pieces.dropFirst() {
            guard let equals = piece.firstIndex(of: "=") else { continue }
            let key = piece[..<equals]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard key == "charset" else { continue }
            return String(piece[piece.index(after: equals)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    private static func unfoldHeaderLines(_ headerBlock: String) -> [String] {
        var lines: [String] = []
        for rawLine in headerBlock
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n") {
            if rawLine.hasPrefix(" ") || rawLine.hasPrefix("\t"),
               let last = lines.indices.last {
                lines[last] += " " + rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                lines.append(rawLine)
            }
        }
        return lines
    }
}

private struct MIMEBodyCollector {
    /// Upper bound on MIME multipart nesting. Real messages nest only a few
    /// levels (e.g. multipart/mixed › multipart/alternative); this stops a
    /// crafted message with thousands of nested boundaries from overflowing the
    /// stack. Parts deeper than this are treated as opaque leaf content.
    private static let maxMultipartDepth = 100

    let messageID: String
    var html: String?
    var plainText: String?
    var attachments: [Attachment] = []
    var attachmentPayloads: [Data] = []
    var readReceiptNotification: ReadReceiptNotification?

    mutating func consume(_ part: MIMEPart) {
        consume(part, depth: 0)
    }

    private mutating func consume(_ part: MIMEPart, depth: Int) {
        let contentType = part.contentType.mediaType
        if depth < Self.maxMultipartDepth,
           contentType.hasPrefix("multipart/"),
           let boundary = part.contentType.parameters["boundary"] {
            for child in part.multipartChildren(boundary: boundary) {
                consume(child, depth: depth + 1)
            }
            return
        }

        let body = part.decodedBodyString()
        if contentType == "message/disposition-notification" {
            readReceiptNotification = readReceiptNotification ?? Self.readReceiptNotification(from: body)
        } else if part.isAttachment {
            appendAttachment(part)
        } else if contentType == "text/html" {
            html = html ?? body
        } else if contentType == "text/plain" {
            plainText = plainText ?? body
        } else if !body.isEmpty, plainText == nil {
            plainText = body
        }
    }

    private static func readReceiptNotification(from body: String) -> ReadReceiptNotification? {
        let fields = MIMEHeader.parse(body)
        guard let disposition = fields.value(named: "Disposition"),
              !disposition.isEmpty
        else { return nil }

        return ReadReceiptNotification(
            finalRecipient: normalizeFinalRecipient(fields.value(named: "Final-Recipient")),
            originalMessageID: fields.value(named: "Original-Message-ID"),
            disposition: disposition
        )
    }

    private static func normalizeFinalRecipient(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let separator = trimmed.firstIndex(of: ";") else { return trimmed }
        let recipient = trimmed[trimmed.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return recipient.isEmpty ? nil : recipient
    }

    private mutating func appendAttachment(_ part: MIMEPart) {
        let index = attachments.count + 1
        let name = part.filename ?? "Attachment \(index)"
        let data = part.decodedBodyData()
        attachmentPayloads.append(data)
        attachments.append(Attachment(
            id: "\(messageID):attachment:\(index)",
            name: name,
            mimeType: part.contentType.mediaType,
            sizeBytes: data.count,
            isInline: part.isInline,
            contentID: part.contentID,
            resource: "imap-source:\(messageID):\(index)"
        ))
    }
}

private struct MIMEPart: Sendable {
    let headers: [MIMEHeader]
    let body: String

    var contentType: MIMEContentType {
        MIMEContentType(headers.value(named: "Content-Type") ?? "text/plain")
    }

    var transferEncoding: String {
        headers.value(named: "Content-Transfer-Encoding")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "7bit"
    }

    var disposition: MIMEContentType? {
        guard let value = headers.value(named: "Content-Disposition") else {
            return nil
        }
        return MIMEContentType(value)
    }

    var filename: String? {
        MIMEParameterFilenameDecoder.filename(
            preferredName: "filename",
            parameters: disposition?.parameters ?? [:]
        )
            ?? MIMEParameterFilenameDecoder.filename(
                preferredName: "name",
                parameters: contentType.parameters
            )
    }

    var contentID: String? {
        guard let value = headers.value(named: "Content-ID") else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var normalized = trimmed
        if normalized.hasPrefix("<") {
            normalized.removeFirst()
        }
        if normalized.hasSuffix(">") {
            normalized.removeLast()
        }
        guard !normalized.isEmpty else { return nil }
        return normalized
    }

    var isInline: Bool {
        disposition?.mediaType == "inline" || contentID != nil
    }

    var isAttachment: Bool {
        if disposition?.mediaType == "attachment" {
            return true
        }
        if disposition?.mediaType == "inline",
           filename != nil || (contentID != nil && !contentType.mediaType.hasPrefix("text/")) {
            return true
        }
        if contentID != nil,
           !contentType.mediaType.hasPrefix("text/") {
            return true
        }
        if !contentType.mediaType.hasPrefix("text/"),
           !contentType.mediaType.hasPrefix("multipart/") {
            return true
        }
        return filename != nil
    }

    static func parse(_ raw: String) -> MIMEPart {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let pieces = normalized.components(separatedBy: "\n\n")
        guard pieces.count > 1 else {
            return MIMEPart(headers: [], body: normalized)
        }
        let headerBlock = pieces[0]
        let body = pieces.dropFirst().joined(separator: "\n\n")
        return MIMEPart(
            headers: MIMEHeader.parse(headerBlock),
            body: body
        )
    }

    func multipartChildren(boundary: String) -> [MIMEPart] {
        let marker = "--\(boundary)"
        var children: [MIMEPart] = []
        var current: [String] = []
        var isInsidePart = false

        for line in body.components(separatedBy: "\n") {
            let delimiterLine = Self.removingTrailingTransportPadding(from: line)
            if delimiterLine == "\(marker)--" {
                if !current.isEmpty {
                    children.append(MIMEPart.parse(current.joined(separator: "\n")))
                }
                return children
            }
            if delimiterLine == marker {
                if isInsidePart, !current.isEmpty {
                    children.append(MIMEPart.parse(current.joined(separator: "\n")))
                    current = []
                }
                isInsidePart = true
                continue
            }
            if isInsidePart {
                current.append(line)
            }
        }

        if !current.isEmpty {
            children.append(MIMEPart.parse(current.joined(separator: "\n")))
        }
        return children
    }

    private static func removingTrailingTransportPadding(from line: String) -> String {
        var end = line.endIndex
        while end > line.startIndex {
            let previous = line.index(before: end)
            guard line[previous] == " " || line[previous] == "\t" else { break }
            end = previous
        }
        return String(line[..<end])
    }

    func decodedBodyString() -> String {
        if isUnencodedTextBody {
            return normalizedTextBody(bodyRemovingTrailingTransportNewlines())
        }

        let data = decodedBodyData()
        let decoded = String(data: data, encoding: declaredStringEncoding)
            ?? String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? body
        return normalizedTextBody(decoded)
    }

    func decodedBodyData() -> Data {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if transferEncoding == "base64" {
            let compact = trimmedBody
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()
            return Data(base64Encoded: compact) ?? Data(trimmedBody.utf8)
        }
        if transferEncoding == "quoted-printable" {
            return MIMEQuotedPrintableDecoder.decode(trimmedBody)
        }
        return Data(bodyRemovingTrailingTransportNewlines().utf8)
    }

    private var isUnencodedTextBody: Bool {
        contentType.mediaType.hasPrefix("text/")
            && ["7bit", "8bit", "binary"].contains(transferEncoding)
    }

    private func bodyRemovingTrailingTransportNewlines() -> String {
        var end = body.endIndex
        while end > body.startIndex {
            let previous = body.index(before: end)
            guard body[previous] == "\n" || body[previous] == "\r" else { break }
            end = previous
        }
        return String(body[..<end])
    }

    private func normalizedTextBody(_ value: String) -> String {
        guard contentType.mediaType == "text/plain",
              contentType.parameters["format"]?.lowercased() == "flowed"
        else {
            return value
        }
        let deleteSpace = contentType.parameters["delsp"]?.lowercased() == "yes"
        return MIMEFlowedTextDecoder.decode(value, deleteSpace: deleteSpace)
    }

    private var declaredStringEncoding: String.Encoding {
        MIMECharset.encoding(for: contentType.parameters["charset"] ?? "utf-8")
    }
}

private enum MIMEParameterFilenameDecoder {
    static func filename(
        preferredName: String,
        parameters: [String: String]
    ) -> String? {
        if let continued = continuedValue(named: preferredName, in: parameters) {
            return sanitizedFilename(
                decodeExtendedValue(continued) ?? RFC2047HeaderDecoder.decode(continued)
            )
        }
        if let extended = parameters["\(preferredName)*"] {
            return sanitizedFilename(
                decodeExtendedValue(extended) ?? RFC2047HeaderDecoder.decode(extended)
            )
        }
        return parameters[preferredName].flatMap {
            sanitizedFilename(RFC2047HeaderDecoder.decode($0))
        }
    }

    private static func sanitizedFilename(_ filename: String) -> String? {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func continuedValue(
        named preferredName: String,
        in parameters: [String: String]
    ) -> String? {
        let prefix = "\(preferredName)*"
        let segments = parameters.compactMap { key, value -> (index: Int, value: String)? in
            guard key.hasPrefix(prefix) else { return nil }
            let suffix = key.dropFirst(prefix.count)
            let normalizedSuffix = suffix.hasSuffix("*") ? suffix.dropLast() : suffix
            guard !normalizedSuffix.isEmpty,
                  normalizedSuffix.allSatisfy(\.isNumber),
                  let index = Int(normalizedSuffix)
            else {
                return nil
            }
            return (index, value)
        }
        guard !segments.isEmpty else { return nil }
        let sorted = segments.sorted { lhs, rhs in lhs.index < rhs.index }
        guard sorted.first?.index == 0 else { return nil }
        for (expectedIndex, segment) in sorted.enumerated() {
            guard segment.index == expectedIndex else { return nil }
        }
        return sorted.map(\.value).joined()
    }

    private static func decodeExtendedValue(_ value: String) -> String? {
        let parts = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let charset = String(parts[0])
        let encodedText = String(parts[2])
        let data = percentDecodedData(encodedText)
        return String(data: data, encoding: MIMECharset.encoding(for: charset))
    }

    private static func percentDecodedData(_ value: String) -> Data {
        let bytes = Array(value.utf8)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = 0

        while index < bytes.count {
            if bytes[index] == CharacterCode.percent,
               index + 2 < bytes.count,
               let high = hexValue(bytes[index + 1]),
               let low = hexValue(bytes[index + 2]) {
                output.append((high << 4) | low)
                index += 3
            } else {
                output.append(bytes[index])
                index += 1
            }
        }

        return Data(output)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case CharacterCode.zero ... CharacterCode.nine:
            byte - CharacterCode.zero
        case CharacterCode.uppercaseA ... CharacterCode.uppercaseF:
            byte - CharacterCode.uppercaseA + 10
        case CharacterCode.lowercaseA ... CharacterCode.lowercaseF:
            byte - CharacterCode.lowercaseA + 10
        default:
            nil
        }
    }
}

private enum MIMEFlowedTextDecoder {
    static func decode(_ value: String, deleteSpace: Bool) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var output: [String] = []
        var pending = ""
        var hasPending = false

        for rawLine in normalized.components(separatedBy: "\n") {
            let line = unstuffed(rawLine)
            let isFlowed = isFlowedLine(line)
            let content = isFlowed ? flowedContent(line, deleteSpace: deleteSpace) : line

            if hasPending {
                pending += content
            } else {
                pending = content
                hasPending = true
            }

            if !isFlowed {
                output.append(pending)
                pending = ""
                hasPending = false
            }
        }

        if hasPending {
            output.append(pending)
        }
        return output.joined(separator: "\n")
    }

    private static func unstuffed(_ line: String) -> String {
        line.hasPrefix(" ") ? String(line.dropFirst()) : line
    }

    private static func isFlowedLine(_ line: String) -> Bool {
        !line.isEmpty && line != "-- " && line.hasSuffix(" ")
    }

    private static func flowedContent(_ line: String, deleteSpace: Bool) -> String {
        guard deleteSpace, line.hasSuffix(" ") else { return line }
        return String(line.dropLast())
    }
}

/// Decodes MIME quoted-printable payloads used by body parts and listing peeks.
enum MIMEQuotedPrintableDecoder {
    static func decode(_ value: String) -> Data {
        let bytes = Array(value.utf8)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]
            guard byte == CharacterCode.equals else {
                output.append(byte)
                index += 1
                continue
            }

            if isSoftLineBreak(bytes, at: index) {
                index += softLineBreakLength(bytes, at: index)
                continue
            }
            if index + 2 < bytes.count,
               let high = hexValue(bytes[index + 1]),
               let low = hexValue(bytes[index + 2]) {
                output.append((high << 4) | low)
                index += 3
                continue
            }

            output.append(byte)
            index += 1
        }

        return Data(output)
    }

    private static func isSoftLineBreak(_ bytes: [UInt8], at index: Int) -> Bool {
        guard index + 1 < bytes.count else { return false }
        if bytes[index + 1] == CharacterCode.lineFeed {
            return true
        }
        return index + 2 < bytes.count
            && bytes[index + 1] == CharacterCode.carriageReturn
            && bytes[index + 2] == CharacterCode.lineFeed
    }

    private static func softLineBreakLength(_ bytes: [UInt8], at index: Int) -> Int {
        bytes[index + 1] == CharacterCode.lineFeed ? 2 : 3
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case CharacterCode.zero ... CharacterCode.nine:
            byte - CharacterCode.zero
        case CharacterCode.uppercaseA ... CharacterCode.uppercaseF:
            byte - CharacterCode.uppercaseA + 10
        case CharacterCode.lowercaseA ... CharacterCode.lowercaseF:
            byte - CharacterCode.lowercaseA + 10
        default:
            nil
        }
    }
}

private enum CharacterCode {
    static let equals = UInt8(ascii: "=")
    static let percent = UInt8(ascii: "%")
    static let lineFeed = UInt8(ascii: "\n")
    static let carriageReturn = UInt8(ascii: "\r")
    static let zero = UInt8(ascii: "0")
    static let nine = UInt8(ascii: "9")
    static let uppercaseA = UInt8(ascii: "A")
    static let uppercaseF = UInt8(ascii: "F")
    static let lowercaseA = UInt8(ascii: "a")
    static let lowercaseF = UInt8(ascii: "f")
}

private struct MIMEHeader: Sendable {
    let name: String
    let value: String

    static func parse(_ block: String) -> [MIMEHeader] {
        var headers: [MIMEHeader] = []
        var currentName: String?
        var currentValue = ""

        func flush() {
            guard let currentName else { return }
            headers.append(MIMEHeader(
                name: currentName,
                value: currentValue.trimmingCharacters(in: .whitespaces)
            ))
        }

        for line in block.components(separatedBy: "\n") {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                currentValue += " " + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            flush()
            currentName = String(line[..<colon])
            currentValue = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
        }
        flush()
        return headers
    }
}

private extension [MIMEHeader] {
    func value(named name: String) -> String? {
        first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private struct MIMEContentType: Sendable {
    let mediaType: String
    let parameters: [String: String]

    init(_ rawValue: String) {
        let pieces = Self.parameterPieces(from: rawValue)
        mediaType = pieces.first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "text/plain"
        var parsedParameters: [String: String] = [:]
        for piece in pieces.dropFirst() {
            guard let equals = piece.firstIndex(of: "=") else { continue }
            let key = piece[..<equals]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !key.isEmpty, parsedParameters[key] == nil else { continue }
            let rawValue = String(piece[piece.index(after: equals)...]
                .trimmingCharacters(in: .whitespacesAndNewlines))
            let value = Self.unquotedValue(rawValue) ?? rawValue
            parsedParameters[key] = value
        }
        parameters = parsedParameters
    }

    private static func parameterPieces(from rawValue: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var isQuoted = false
        var isEscaped = false

        for character in rawValue {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            if isQuoted, character == "\\" {
                current.append(character)
                isEscaped = true
                continue
            }
            if character == "\"" {
                isQuoted.toggle()
                current.append(character)
                continue
            }
            if character == ";", !isQuoted {
                pieces.append(current)
                current = ""
                continue
            }
            current.append(character)
        }

        pieces.append(current)
        return pieces
    }

    private static func unquotedValue(_ value: String) -> String? {
        guard value.hasPrefix("\""),
              value.hasSuffix("\""),
              value.count >= 2
        else {
            return nil
        }
        let body = value.dropFirst().dropLast()
        var output = ""
        var isEscaped = false

        for character in body {
            if isEscaped {
                output.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else {
                output.append(character)
            }
        }
        if isEscaped {
            output.append("\\")
        }
        return output
    }
}
