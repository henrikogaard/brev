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

// MARK: - IMAP configuration

/// Connection parameters for an IMAP mailbox server.
///
/// Account setup may authenticate with password/app-password or
/// OAuth/XOAUTH2 depending on provider capabilities. TLS is required.
public struct IMAPConfiguration: Sendable, Hashable, Codable {
    /// TLS connection mode for an IMAP socket.
    public enum TLSMode: String, Sendable, Hashable, Codable {
        /// Implicit TLS from the first byte (port 993). Preferred.
        case implicit
        /// STARTTLS upgrade on a plain connection (port 143).
        case startTLS
    }

    public var host: String
    public var port: UInt16
    public var tlsMode: TLSMode

    public init(host: String, port: UInt16 = 993, tlsMode: TLSMode = .implicit) {
        self.host = host
        self.port = port
        self.tlsMode = tlsMode
    }
}

// MARK: - SMTP configuration

/// Connection parameters for an SMTP submission server.
///
/// Used alongside `IMAPConfiguration` to provide outgoing mail for
/// standards-first IMAP accounts.
public struct SMTPConfiguration: Sendable, Hashable, Codable {
    public enum TLSMode: String, Sendable, Hashable, Codable {
        case implicit
        case startTLS
    }

    public var host: String
    public var port: UInt16
    public var tlsMode: TLSMode

    public init(host: String, port: UInt16 = 465, tlsMode: TLSMode = .implicit) {
        self.host = host
        self.port = port
        self.tlsMode = tlsMode
    }
}

// MARK: - MIME message builder

/// A concrete attachment payload ready to be embedded in an outbound
/// MIME message.
public struct MIMEMessageAttachment: Sendable, Hashable {
    public let id: String
    public let filename: String
    public let mimeType: String
    public let data: Data
    /// Inline (body-referenced) part: emitted as Content-Disposition: inline with a Content-ID.
    public let isInline: Bool
    /// RFC 2392 Content-ID (no angle brackets), required when `isInline` is true.
    public let contentID: String?

    public init(id: String, filename: String, mimeType: String, data: Data,
                isInline: Bool = false, contentID: String? = nil) {
        self.id = id; self.filename = filename; self.mimeType = mimeType
        self.data = data; self.isInline = isInline; self.contentID = contentID
    }
}

/// Constructs RFC 2822 / MIME messages for SMTP submission.
///
/// Supports plain text, HTML, and mixed-content messages with
/// attachments. Header values are encoded as UTF-8 encoded-words
/// (RFC 2047 Q-encoding) where non-ASCII characters appear.
public struct MIMEMessageBuilder: Sendable {
    private let draft: Draft
    private let from: Correspondent
    private let attachments: [MIMEMessageAttachment]
    private let boundary: String

    public init(
        draft: Draft,
        from: Correspondent,
        attachments: [MIMEMessageAttachment] = [],
        boundary: String = UUID().uuidString
    ) {
        self.draft = draft
        self.from = from
        self.attachments = attachments
        self.boundary = boundary
    }

    /// A stable, draft-derived `Message-ID`.
    ///
    /// Stability matters: a retried or replayed send must produce the SAME
    /// Message-ID so a receiving server can collapse a duplicate delivery
    /// instead of showing two copies (the at-least-once send hazard). RFC 5322
    /// §3.6.4 also recommends every message carry one; previously outgoing mail
    /// had none, which hurts deliverability and threading.
    func messageIDHeaderValue() -> String {
        let domainSource = from.email.split(separator: "@", maxSplits: 1).last.map(String.init) ?? ""
        let domain = Self.sanitizedMessageIDComponent(domainSource, fallback: "localhost")
        let localPart = "brev-" + Self.sanitizedMessageIDComponent(draft.id, fallback: "draft")
        return "<\(localPart)@\(domain)>"
    }

    /// Reduces an arbitrary string to RFC 5322 dot-atom-safe characters so it
    /// can sit inside a `<local@domain>` msg-id without breaking the header.
    private static func sanitizedMessageIDComponent(_ raw: String, fallback: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._")
        let mapped = String(raw.map { allowed.contains($0) ? $0 : "-" })
        return mapped.isEmpty ? fallback : mapped
    }

    /// Builds the complete RFC 2822 message as a UTF-8 `Data` blob.
    public func build() -> Data {
        var lines: [String] = []

        // Headers
        lines.append("From: \(formatAddress(from))")
        lines.append("To: \(draft.to.map { formatAddress($0) }.joined(separator: ", "))")
        if !draft.cc.isEmpty {
            lines.append("Cc: \(draft.cc.map { formatAddress($0) }.joined(separator: ", "))")
        }
        lines.append("Subject: \(encodeHeader(draft.subject))")
        lines.append("MIME-Version: 1.0")
        lines.append("Date: \(rfc2822Date(Date()))")
        lines.append("Message-ID: \(messageIDHeaderValue())")
        if draft.readReceiptResponse == nil, let readReceiptRequest = draft.readReceiptRequest {
            lines.append("Disposition-Notification-To: \(Self.headerSafe(readReceiptRequest.notificationTo))")
        }
        if let replyToID = draft.inReplyToMessageID {
            // The replied-to Message-ID comes from the original (possibly
            // malicious) message, so it must be sanitized before sitting in the
            // header — otherwise a crafted id injects extra headers.
            let safeID = Self.headerSafeReference(replyToID)
            lines.append("In-Reply-To: <\(safeID)>")
            lines.append("References: <\(safeID)>")
        }
        if let forwardedID = draft.forwardedMessageID {
            lines.append("References: <\(Self.headerSafeReference(forwardedID))>")
        }
        if let readReceiptResponse = draft.readReceiptResponse {
            appendReadReceiptResponse(readReceiptResponse, to: &lines)
            return Data(lines.joined(separator: "\r\n").utf8)
        }

        let inlineAttachments = attachments.filter { $0.isInline && $0.contentID != nil }
        let regularAttachments = attachments.filter { !$0.isInline }
        let hasRegular = !regularAttachments.isEmpty || !draft.attachmentIDs.isEmpty
        let hasInline = !inlineAttachments.isEmpty
        let hasHTML = !draft.htmlBody.isEmpty

        // Top-level wrapper: multipart/mixed when regular attachments are present.
        if hasRegular {
            lines.append("Content-Type: multipart/mixed; boundary=\"\(boundary)\"")
            lines.append("")
            lines.append("--\(boundary)")
        }

        if hasHTML {
            let textBoundary = "text-\(boundary)"
            let relatedBoundary = "related-\(boundary)"
            lines.append("Content-Type: multipart/alternative; boundary=\"\(textBoundary)\"")
            lines.append("")
            lines.append("--\(textBoundary)")
            lines.append("Content-Type: text/plain; charset=utf-8")
            lines.append("Content-Transfer-Encoding: quoted-printable")
            lines.append("")
            lines.append(quotedPrintableEncodedBody(htmlToPlainText(draft.htmlBody)))
            lines.append("--\(textBoundary)")
            if hasInline {
                // Wrap text/html + inline image parts in multipart/related so
                // mail clients resolve cid: references (RFC 2387).
                lines.append("Content-Type: multipart/related; type=\"text/html\"; boundary=\"\(relatedBoundary)\"")
                lines.append("")
                lines.append("--\(relatedBoundary)")
            }
            lines.append("Content-Type: text/html; charset=utf-8")
            lines.append("Content-Transfer-Encoding: quoted-printable")
            lines.append("")
            lines.append(quotedPrintableEncodedBody(draft.htmlBody))
            if hasInline {
                for attachment in inlineAttachments {
                    lines.append("--\(relatedBoundary)")
                    lines.append("Content-Type: \(attachment.mimeType); \(filenameParameter("name", attachment.filename))")
                    // swiftlint:disable:next force_unwrapping
                    lines.append("Content-ID: <\(Self.headerSafe(attachment.contentID!))>")
                    lines.append("Content-Disposition: inline; \(filenameParameter("filename", attachment.filename))")
                    lines.append("Content-Transfer-Encoding: base64")
                    lines.append("")
                    lines.append(attachment.data.base64EncodedString(options: [.lineLength76Characters]))
                }
                lines.append("--\(relatedBoundary)--")
            }
            lines.append("--\(textBoundary)--")
        } else {
            lines.append("Content-Type: text/plain; charset=utf-8")
            lines.append("Content-Transfer-Encoding: quoted-printable")
            lines.append("")
            lines.append(quotedPrintableEncodedBody(draft.htmlBody))
        }

        if hasRegular {
            for attachment in regularAttachments {
                lines.append("--\(boundary)")
                lines.append("Content-Type: \(attachment.mimeType); \(filenameParameter("name", attachment.filename))")
                lines.append("Content-Disposition: attachment; \(filenameParameter("filename", attachment.filename))")
                lines.append("Content-Transfer-Encoding: base64")
                lines.append("")
                lines.append(attachment.data.base64EncodedString(options: [.lineLength76Characters]))
            }
            lines.append("--\(boundary)--")
        }

        lines.append("")
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    // MARK: - Helpers

    private func formatAddress(_ correspondent: Correspondent) -> String {
        // Sanitize the address too — a CR/LF in an email value would otherwise
        // break out of the To/Cc/From line and inject a header.
        let email = Self.headerSafe(correspondent.email)
        if let name = correspondent.name, !name.isEmpty {
            return "\(encodeHeader(name)) <\(email)>"
        }
        return email
    }

    private func appendReadReceiptResponse(_ response: ReadReceiptResponse, to lines: inout [String]) {
        lines.append("Content-Type: multipart/report; report-type=disposition-notification; boundary=\"\(boundary)\"")
        lines.append("")
        lines.append("--\(boundary)")
        lines.append("Content-Type: text/plain; charset=utf-8")
        lines.append("Content-Transfer-Encoding: 7bit")
        lines.append("")
        lines.append("This is a read receipt for the message displayed by \(Self.headerSafe(response.finalRecipient)).")
        lines.append("--\(boundary)")
        lines.append("Content-Type: message/disposition-notification")
        lines.append("Content-Transfer-Encoding: 7bit")
        lines.append("")
        lines.append("Final-Recipient: rfc822;\(Self.headerSafe(response.finalRecipient))")
        if let originalMessageID = response.originalMessageID {
            lines.append("Original-Message-ID: <\(Self.headerSafeReference(originalMessageID))>")
        }
        lines.append("Disposition: manual-action/MDN-sent-manually; displayed")
        lines.append("--\(boundary)--")
        lines.append("")
    }

    /// Removes the characters that can break header framing — CR, LF, NUL — from
    /// a header value so input can't inject additional headers (CWE-93).
    ///
    /// Filters on unicode scalars, not `Character`s: Swift fuses `\r\n` into a
    /// single grapheme cluster, so a `Character`-level `!= "\r" && != "\n"` test
    /// would let a CRLF pair through untouched.
    private static func headerSafe(_ value: String) -> String {
        String(String.UnicodeScalarView(
            value.unicodeScalars.filter { $0 != "\r" && $0 != "\n" && $0 != "\0" }
        ))
    }

    /// Sanitizes a value destined to sit inside `<…>` as a msg-id (In-Reply-To,
    /// References). Drops header-breaking characters plus angle brackets and
    /// whitespace, which a msg-id must not contain.
    private static func headerSafeReference(_ value: String) -> String {
        String(String.UnicodeScalarView(
            headerSafe(value).unicodeScalars.filter {
                !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "<" && $0 != ">"
            }
        ))
    }

    /// RFC 2047 Q-encoding for non-ASCII header values. The result is split into
    /// encoded-words of at most 75 characters (the RFC 2047 limit) and folded
    /// with CRLF+space, so a long subject can't overflow the SMTP line limit. A
    /// receiver unfolds the words and, per RFC 2047, concatenates adjacent
    /// encoded-words without the separating whitespace.
    private func encodeHeader(_ value: String) -> String {
        // Strip CR/LF/NUL before anything else. RFC 5322 forbids bare CR/LF in a
        // header value; left in, a crafted subject or display name — which can be
        // auto-populated from a malicious sender when the user replies/forwards —
        // would inject additional headers (e.g. an extra `Bcc:`). This is CWE-93.
        // Folding is added deliberately by the builder, never carried in.
        let value = Self.headerSafe(value)
        let ascii = value.unicodeScalars.allSatisfy { $0.value < 128 }
        if ascii { return value }

        let prefix = "=?UTF-8?Q?"
        let suffix = "?="
        let maxEncoded = 75 - prefix.count - suffix.count

        var words: [String] = []
        var current = ""
        for character in value {
            let chunk = qEncodedChunk(character)
            if !current.isEmpty, current.count + chunk.count > maxEncoded {
                words.append(prefix + current + suffix)
                current = ""
            }
            current += chunk
        }
        if !current.isEmpty {
            words.append(prefix + current + suffix)
        }
        return words.joined(separator: "\r\n ")
    }

    /// Q-encodes a single character, keeping its UTF-8 bytes together so a
    /// multi-byte sequence is never split across two encoded-words.
    private func qEncodedChunk(_ character: Character) -> String {
        Data(String(character).utf8)
            .map { byte -> String in
                // RFC 2047 §4.2: only printable ASCII may stay literal. Space,
                // controls, 8-bit bytes, and the special characters "=", "?",
                // and "_" must be hex-escaped — a literal "_" in an encoded
                // word otherwise decodes back to a space on the receiver, and a
                // literal "=" or "?" corrupts the word.
                if byte < 33 || byte > 126 || byte == 61 || byte == 63 || byte == 95 {
                    return String(format: "=%02X", byte)
                }
                return String(UnicodeScalar(byte))
            }
            .joined()
    }

    private func rfc2822Date(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")!
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss +0000"
        return f.string(from: date)
    }

    private func quoteParameter(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Builds a `name`/`filename` content parameter. ASCII names use the quoted
    /// form; non-ASCII names use the RFC 2231 / RFC 6266 extended form
    /// (`name*=UTF-8''…`) so the raw 8-bit bytes never land in the header.
    private func filenameParameter(_ name: String, _ filename: String) -> String {
        // The ASCII quoted form below escapes `\` and `"` but not CR/LF, so strip
        // header-breaking characters first. (The RFC 2231 form percent-escapes
        // them already, but sanitizing keeps both paths consistent.)
        let filename = Self.headerSafe(filename)
        if filename.unicodeScalars.allSatisfy({ $0.value < 128 }) {
            return "\(name)=\"\(quoteParameter(filename))\""
        }
        return "\(name)*=UTF-8''\(rfc2231Encoded(filename))"
    }

    /// Percent-encodes a value per RFC 2231: only `attr-char`s stay literal;
    /// space, 8-bit, and reserved characters are `%`-escaped.
    private func rfc2231Encoded(_ value: String) -> String {
        let attrChars = Set(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$&+-.^_`|~".utf8
        )
        return Data(value.utf8)
            .map { attrChars.contains($0) ? String(UnicodeScalar($0)) : String(format: "%%%02X", $0) }
            .joined()
    }

    /// Very basic HTML → plain-text strip for the text/plain part.
    private func htmlToPlainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    /// Quoted-printable-encodes body text per RFC 2045 §6.7, matching the
    /// declared `Content-Transfer-Encoding: quoted-printable`. The body was
    /// previously appended raw, so a literal "=" (e.g. "total = 5"), 8-bit UTF-8,
    /// or an over-long line was not valid QP and a strict receiver could
    /// mis-decode or corrupt the message.
    private func quotedPrintableEncodedBody(_ text: String) -> String {
        // Existing line breaks are hard breaks, re-emitted as CRLF. Each line's
        // bytes are then encoded and soft-wrapped to <= 76 characters.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(Self.encodeQuotedPrintableLine)
            .joined(separator: "\r\n")
    }

    private static func encodeQuotedPrintableLine(_ line: Substring) -> String {
        let bytes = Array(line.utf8)
        var tokens: [String] = []
        tokens.reserveCapacity(bytes.count)
        for (offset, byte) in bytes.enumerated() {
            let isTrailing = offset == bytes.count - 1
            switch byte {
            case 9, 32: // TAB or SPACE — literal unless trailing (then encoded).
                tokens.append(isTrailing ? String(format: "=%02X", byte) : String(UnicodeScalar(byte)))
            case 33 ... 60, 62 ... 126: // printable ASCII except '='
                tokens.append(String(UnicodeScalar(byte)))
            default: // '=', control bytes, and 8-bit bytes.
                tokens.append(String(format: "=%02X", byte))
            }
        }
        // Soft-wrap so no encoded line (including the trailing '=') exceeds 76
        // characters. Tokens are atomic (a "=XX" escape is never split).
        var result = ""
        var lineLength = 0
        for token in tokens {
            if lineLength + token.count > 75 {
                result += "=\r\n"
                lineLength = 0
            }
            result += token
            lineLength += token.count
        }
        return result
    }
}
