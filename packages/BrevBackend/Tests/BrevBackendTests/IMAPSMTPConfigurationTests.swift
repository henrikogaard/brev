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

@testable import BrevBackend
import Foundation
import Testing

@Suite("IMAPConfiguration")
struct IMAPConfigurationTests {
    @Test("default port is 993 with implicit TLS")
    func defaultPortAndTLS() {
        let config = IMAPConfiguration(host: "imap.example.com")
        #expect(config.port == 993)
        #expect(config.tlsMode == .implicit)
    }

    @Test("config round-trips through Codable")
    func codableRoundTrip() throws {
        let config = IMAPConfiguration(host: "imap.example.com", port: 143, tlsMode: .startTLS)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(IMAPConfiguration.self, from: data)
        #expect(decoded == config)
    }
}

@Suite("SMTPConfiguration")
struct SMTPConfigurationTests {
    @Test("config round-trips through Codable")
    func codableRoundTrip() throws {
        let config = SMTPConfiguration(host: "smtp.example.com", port: 465, tlsMode: .implicit)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SMTPConfiguration.self, from: data)
        #expect(decoded == config)
    }
}

@Suite("MailAccountAutodiscovery")
struct MailAccountAutodiscoveryTests {
    @Test("ProtonMail Bridge profile is matched for proton.me")
    func protonMailBridge() {
        let settings = MailAccountAutodiscovery.matchBuiltInProfile(for: "proton.me")
        #expect(settings?.imap.host == "127.0.0.1")
        #expect(settings?.authMode == .appPassword)
    }

    @Test("ProtonMail Bridge profile is matched for protonmail.com")
    func protonMailBridgeAlternateDomain() {
        let settings = MailAccountAutodiscovery.matchBuiltInProfile(for: "protonmail.com")
        #expect(settings?.imap.host == "127.0.0.1")
    }

    @Test("Zoho Mail profile is matched for zoho.com")
    func zohoMail() {
        let settings = MailAccountAutodiscovery.matchBuiltInProfile(for: "zoho.com")
        #expect(settings?.imap.host == "imap.zoho.com")
        #expect(settings?.authMode == .password)
    }

    @Test("GMX profile is matched for gmx.net")
    func gmx() {
        let settings = MailAccountAutodiscovery.matchBuiltInProfile(for: "gmx.net")
        #expect(settings?.imap.host == "imap.gmx.com")
    }

    @Test("Fastmail profile is matched and flags app-password auth")
    func fastmail() {
        let settings = MailAccountAutodiscovery.matchBuiltInProfile(for: "fastmail.com")
        #expect(settings?.imap.host == "imap.fastmail.com")
        #expect(settings?.smtp.host == "smtp.fastmail.com")
        #expect(settings?.smtp.port == 465)
        #expect(settings?.smtp.tlsMode == .implicit)
        #expect(settings?.authMode == .appPassword)
    }

    @Test("iCloud profile uses Apple mail hosts and app-password auth")
    func iCloud() {
        let settings = MailAccountAutodiscovery.matchBuiltInProfile(for: "icloud.com")
        #expect(settings?.providerName == "iCloud Mail")
        #expect(settings?.imap.host == "imap.mail.me.com")
        #expect(settings?.smtp.host == "smtp.mail.me.com")
        #expect(settings?.smtp.port == 587)
        #expect(settings?.authMode == .appPassword)
        #expect(settings?.incomingUsernameTemplate == "%LOCALPART%")
        #expect(settings?.outgoingUsernameTemplate == "%EMAILADDRESS%")
    }

    @Test("Web.de profile is matched for web.de")
    func webDe() {
        let settings = MailAccountAutodiscovery.matchBuiltInProfile(for: "web.de")
        #expect(settings?.imap.host == "imap.web.de")
    }

    @Test("Mailbox.org profile is matched for mailbox.org")
    func mailboxOrg() {
        let settings = MailAccountAutodiscovery.matchBuiltInProfile(for: "mailbox.org")
        #expect(settings?.imap.host == "imap.mailbox.org")
    }

    @Test("Posteo profile is matched for posteo.de")
    func posteoDe() {
        let settings = MailAccountAutodiscovery.matchBuiltInProfile(for: "posteo.de")
        #expect(settings?.imap.host == "posteo.de")
    }

    @Test("Runbox profile is matched for runbox.com")
    func runbox() {
        let settings = MailAccountAutodiscovery.matchBuiltInProfile(for: "runbox.com")
        #expect(settings?.imap.host == "imap.runbox.com")
    }

    @Test("Fastmail profile is matched for fastmail.com")
    func fastmailProfile() {
        let settings = MailAccountAutodiscovery.matchBuiltInProfile(for: "fastmail.com")
        #expect(settings?.imap.host == "imap.fastmail.com")
    }

    @Test("unknown domain returns nil")
    func unknownDomain() {
        let settings = MailAccountAutodiscovery.matchBuiltInProfile(for: "custom-mail.example.org")
        #expect(settings == nil)
    }

    @Test("domain lookup is case-insensitive")
    func caseInsensitiveLookup() {
        let lower = MailAccountAutodiscovery.matchBuiltInProfile(for: "proton.me")
        let upper = MailAccountAutodiscovery.matchBuiltInProfile(for: "Proton.ME")
        #expect(lower?.imap == upper?.imap)
    }
}

@Suite("MIMEMessageBuilder")
struct MIMEMessageBuilderTests {
    private static func makeDraft(
        subject: String = "Test subject",
        htmlBody: String = "<p>Hello</p>",
        to: [Correspondent] = [Correspondent(name: "Bob", email: "bob@example.com")],
        readReceiptRequest: ReadReceiptRequest? = nil
    ) -> Draft {
        Draft(
            id: "local-1",
            to: to,
            subject: subject,
            htmlBody: htmlBody,
            readReceiptRequest: readReceiptRequest
        )
    }

    @Test("built message contains required RFC 2822 headers")
    func requiredHeaders() {
        let draft = Self.makeDraft()
        let from = Correspondent(name: "Alice", email: "alice@example.com")
        let builder = MIMEMessageBuilder(draft: draft, from: from)
        let message = String(data: builder.build(), encoding: .utf8) ?? ""

        #expect(message.contains("From: "))
        #expect(message.contains("alice@example.com"))
        #expect(message.contains("To: "))
        #expect(message.contains("bob@example.com"))
        #expect(message.contains("Subject: "))
        #expect(message.contains("MIME-Version: 1.0"))
        #expect(message.contains("Date: "))
        #expect(message.contains("Message-ID: <"))
    }

    @Test("built message carries a stable, well-formed Message-ID")
    func stableMessageID() {
        let from = Correspondent(name: "Alice", email: "alice@example.com")
        let draft = Self.makeDraft()

        func messageIDLine(in message: String) -> String? {
            message.split(separator: "\r\n").first { $0.hasPrefix("Message-ID: ") }.map(String.init)
        }

        let first = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""
        let second = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""
        let id = messageIDLine(in: first)

        #expect(id == "Message-ID: <brev-local-1@example.com>")
        // Stable across rebuilds of the same draft so a retried/replayed send
        // dedups at the receiver instead of delivering two copies.
        #expect(messageIDLine(in: first) == messageIDLine(in: second))
    }

    @Test("HTML body appears in message")
    func htmlBodyAppears() {
        let draft = Self.makeDraft(htmlBody: "<p>Test body</p>")
        let from = Correspondent(email: "a@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""
        #expect(message.contains("Test body"))
    }

    @Test("non-ASCII subject is Q-encoded")
    func nonAsciiSubjectIsQEncoded() {
        let draft = Self.makeDraft(subject: "Møte om prosjektet")
        let from = Correspondent(email: "a@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""
        #expect(message.contains("=?UTF-8?Q?"))
    }

    @Test("Q-encoded subject escapes _, =, ? and round-trips through the decoder")
    func qEncodedSubjectRoundTripsAndEscapesSpecials() {
        // Underscore is the dangerous one: left literal, the receiver's RFC 2047
        // Q-decoder turns it back into a space.
        let subject = "Café_5=10? plan"
        let draft = Self.makeDraft(subject: subject)
        let from = Correspondent(email: "a@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""

        let subjectLine = message
            .components(separatedBy: "\r\n")
            .first { $0.hasPrefix("Subject: ") }
        let encodedValue = subjectLine.map { String($0.dropFirst("Subject: ".count)) } ?? ""

        // Specials must be escaped, not left literal in the encoded word.
        #expect(encodedValue.contains("=5F")) // "_"
        #expect(encodedValue.contains("=3D")) // "="
        #expect(encodedValue.contains("=3F")) // "?"
        #expect(!encodedValue.contains("_")) // never a literal underscore

        // And the whole thing must decode back to exactly what we sent.
        #expect(RFC2047HeaderDecoder.decode(encodedValue) == subject)
    }

    @Test("a long non-ASCII subject folds into <=75-char encoded-words and round-trips")
    func longNonAsciiSubjectFoldsAndRoundTrips() {
        let subject = String(repeating: "Møte øm prosjektet ", count: 8)
            .trimmingCharacters(in: .whitespaces)
        let draft = Self.makeDraft(subject: subject)
        let from = Correspondent(email: "a@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""

        // Reassemble the (folded) Subject header the way a receiver unfolds it:
        // drop the CRLF, keep the leading space of each continuation line.
        let lines = message.components(separatedBy: "\r\n")
        let subjectIndex = lines.firstIndex { $0.hasPrefix("Subject: ") } ?? 0
        var headerValue = String(lines[subjectIndex].dropFirst("Subject: ".count))
        var next = subjectIndex + 1
        while next < lines.count, lines[next].first == " " || lines[next].first == "\t" {
            headerValue += lines[next]
            next += 1
        }

        // It must have actually split (multiple encoded-words), each <= 75 chars.
        let words = headerValue.split(separator: " ").map(String.init)
        #expect(words.count > 1)
        for word in words where word.hasPrefix("=?") {
            #expect(word.count <= 75)
        }
        // No physical line may exceed the SMTP hard limit.
        #expect(lines.allSatisfy { $0.utf8.count <= 998 })

        // And the receiver reconstructs the original subject exactly.
        #expect(RFC2047HeaderDecoder.decode(headerValue) == subject)
    }

    @Test("In-Reply-To header is included when inReplyToMessageID is set")
    func inReplyToHeader() {
        var draft = Self.makeDraft()
        draft = Draft(
            id: "local-2",
            inReplyToMessageID: "original@example.com",
            to: draft.to,
            subject: draft.subject,
            htmlBody: draft.htmlBody
        )
        let from = Correspondent(email: "a@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""
        #expect(message.contains("In-Reply-To: <original@example.com>"))
    }

    // The builder emits no Bcc header itself, so any "\r\nBcc:" in the output is
    // an injected header. CRLF in a subject, display name, recipient address, or
    // replied-to Message-ID — any of which can be auto-populated from a malicious
    // sender on reply/forward — must not break out of its header line (CWE-93).

    @Test("CRLF in subject cannot inject a header")
    func subjectHeaderInjectionIsBlocked() {
        let draft = Self.makeDraft(subject: "Meeting\r\nBcc: evil@example.com")
        let from = Correspondent(email: "a@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""
        #expect(!message.contains("\r\nBcc:"))
        #expect(message.contains("Subject: "))
    }

    @Test("CRLF in a recipient display name cannot inject a header")
    func displayNameHeaderInjectionIsBlocked() {
        let draft = Self.makeDraft(
            to: [Correspondent(name: "Bob\r\nBcc: evil@example.com", email: "bob@example.com")]
        )
        let from = Correspondent(email: "a@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""
        #expect(!message.contains("\r\nBcc:"))
    }

    @Test("CRLF in a recipient address cannot inject a header")
    func recipientAddressHeaderInjectionIsBlocked() {
        let draft = Self.makeDraft(
            to: [Correspondent(email: "bob@example.com\r\nBcc: evil@example.com")]
        )
        let from = Correspondent(email: "a@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""
        #expect(!message.contains("\r\nBcc:"))
    }

    @Test("CRLF in the replied-to Message-ID cannot inject a header")
    func inReplyToHeaderInjectionIsBlocked() {
        let base = Self.makeDraft()
        let draft = Draft(
            id: "local-injection",
            inReplyToMessageID: "original@example.com>\r\nBcc: evil@example.com",
            to: base.to,
            subject: base.subject,
            htmlBody: base.htmlBody
        )
        let from = Correspondent(email: "a@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""
        #expect(!message.contains("\r\nBcc:"))
        // The In-Reply-To stays a single, well-formed angle-bracketed line.
        // headerSafeReference also drops whitespace and angle brackets, so the
        // injected "> Bcc: evil@…" collapses into the id instead of a new header.
        #expect(message.contains("In-Reply-To: <original@example.comBcc:evil@example.com>"))
    }

    @Test("read receipt request emits Disposition-Notification-To")
    func readReceiptRequestHeader() {
        let draft = Self.makeDraft(readReceiptRequest: ReadReceiptRequest(notificationTo: "alice@example.com"))
        let from = Correspondent(name: "Alice", email: "alice@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""
        #expect(message.contains("Disposition-Notification-To: alice@example.com"))
    }

    @Test("read receipt request cannot inject a header")
    func readReceiptRequestHeaderInjectionIsBlocked() {
        let draft = Self.makeDraft(
            readReceiptRequest: ReadReceiptRequest(notificationTo: "alice@example.com\r\nBcc: evil@example.com")
        )
        let from = Correspondent(email: "alice@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""
        #expect(!message.contains("\r\nBcc:"))
        #expect(message.contains("Disposition-Notification-To: alice@example.comBcc: evil@example.com"))
    }

    @Test("read receipt response builds a multipart report MDN")
    func readReceiptResponseBuildsMultipartReport() {
        let draft = Draft(
            id: "mdn-1",
            to: [Correspondent(email: "sender@example.org")],
            subject: "Read: Planning",
            readReceiptResponse: ReadReceiptResponse(
                finalRecipient: "reader@example.com",
                originalMessageID: "<original@example.org>"
            )
        )
        let from = Correspondent(email: "reader@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""

        #expect(message.contains("Content-Type: multipart/report; report-type=disposition-notification;"))
        #expect(message.contains("Content-Type: message/disposition-notification"))
        #expect(message.contains("Final-Recipient: rfc822;reader@example.com"))
        #expect(message.contains("Original-Message-ID: <original@example.org>"))
        #expect(message.contains("Disposition: manual-action/MDN-sent-manually; displayed"))
        #expect(!message.contains("Disposition-Notification-To:"))
    }

    // The body parts declare `Content-Transfer-Encoding: quoted-printable`, so
    // the body must actually be QP-encoded — appending it raw produced invalid
    // QP that a strict receiver could mis-decode.

    @Test("a literal = in the body is quoted-printable encoded")
    func bodyEqualsSignIsQuotedPrintableEncoded() {
        let draft = Self.makeDraft(htmlBody: "The total = 5 today")
        let from = Correspondent(email: "a@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""
        #expect(message.contains("The total =3D 5 today"))
        #expect(!message.contains("The total = 5 today"))
    }

    @Test("non-ASCII body bytes are quoted-printable encoded and the message stays 7-bit")
    func bodyNonASCIIIsEncodedAndMessageIsSevenBit() {
        let draft = Self.makeDraft(subject: "Møte", htmlBody: "Møte i går")
        let from = Correspondent(email: "a@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""
        // ø → UTF-8 C3 B8 → "=C3=B8".
        #expect(message.contains("M=C3=B8te"))
        // The whole message must be 7-bit clean (QP body + Q-encoded headers).
        #expect(message.unicodeScalars.allSatisfy { $0.value < 128 })
    }

    @Test("a long body line is soft-wrapped so no encoded run exceeds the QP limit")
    func bodyLongLineIsSoftWrapped() {
        let draft = Self.makeDraft(htmlBody: String(repeating: "a", count: 200))
        let from = Correspondent(email: "a@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""
        // The 200-char body run must be broken by soft line breaks; no single
        // encoded line carries an unbroken run of 76+ characters.
        #expect(!message.contains(String(repeating: "a", count: 76)))
        #expect(message.contains("a=\r\n"))
    }

    @Test("a plain ASCII body is still human-readable after encoding")
    func bodyPlainASCIIStaysReadable() {
        let draft = Self.makeDraft(htmlBody: "Hello there, how are you?")
        let from = Correspondent(email: "a@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""
        #expect(message.contains("Hello there, how are you?"))
    }

    @Test("reply-all payload includes CC recipients")
    func replyAllIncludesCC() {
        let draft = Draft(
            id: "reply-all-1",
            inReplyToMessageID: "source-message@example.com",
            to: [Correspondent(name: "Alice", email: "alice@example.com")],
            cc: [Correspondent(name: "Carol", email: "carol@example.com")],
            subject: "Re: Planning",
            htmlBody: "<p>Sounds good</p>"
        )
        let from = Correspondent(name: "Bob", email: "bob@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""
        #expect(message.contains("To: "))
        #expect(message.contains("alice@example.com"))
        #expect(message.contains("Cc: "))
        #expect(message.contains("carol@example.com"))
    }

    @Test("forward payload preserves forwarded message id in headers")
    func forwardIncludesForwardedReferences() {
        let draft = Draft(
            id: "forward-1",
            forwardedMessageID: "forwarded-message-id@example.com",
            to: [Correspondent(email: "team@example.com")],
            subject: "Fwd: Weekly report",
            htmlBody: "<p>Forwarding the report.</p>"
        )
        let from = Correspondent(email: "sender@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""
        #expect(message.contains("References: <forwarded-message-id@example.com>"))
    }

    @Test("attachment payload uses multipart/mixed boundary")
    func attachmentPayloadUsesMultipartMixed() {
        let draft = Draft(
            id: "attachment-1",
            to: [Correspondent(email: "recipient@example.com")],
            subject: "Attachment test",
            htmlBody: "Please see attachment",
            attachmentIDs: ["attachment-123"]
        )
        let from = Correspondent(email: "sender@example.com")
        let message = String(data: MIMEMessageBuilder(draft: draft, from: from).build(), encoding: .utf8) ?? ""
        #expect(message.contains("Content-Type: multipart/mixed;"))
    }

    @Test("non-ASCII attachment filename uses RFC 2231 extended form and round-trips")
    func nonAsciiAttachmentFilenameRoundTrips() {
        let draft = Draft(
            id: "attachment-2",
            to: [Correspondent(email: "recipient@example.com")],
            subject: "Attachment",
            htmlBody: "See attached",
            attachmentIDs: []
        )
        let from = Correspondent(email: "sender@example.com")
        let attachment = MIMEMessageAttachment(
            id: "a1",
            filename: "résumé.pdf",
            mimeType: "application/pdf",
            data: Data("%PDF-1.4".utf8)
        )
        let message = String(
            data: MIMEMessageBuilder(draft: draft, from: from, attachments: [attachment]).build(),
            encoding: .utf8
        ) ?? ""

        // The raw 8-bit name must not appear; the RFC 2231 extended form must.
        #expect(message.contains("filename*=UTF-8''r%C3%A9sum%C3%A9.pdf"))
        #expect(!message.contains("filename=\"résumé.pdf\""))

        // Full round-trip: the body parser recovers the original filename.
        let parsed = IMAPMessageBodyParser().parse(messageID: "m", rawMessage: message)
        #expect(parsed.attachments.first?.name == "résumé.pdf")
    }
}
