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

@Suite("SMTP session client")
struct SMTPSessionClientTests {
    @Test("client times out when SMTP server stops responding")
    func clientTimesOutWhenSMTPServerStopsResponding() async {
        let transport = ScriptedSMTPTransport(
            lines: [],
            suspendsWhenOutOfLines: true
        )
        let client = SMTPSessionClient(
            transport: transport,
            responseTimeoutNanoseconds: 1_000_000
        )

        await #expect(throws: SMTPClientError.transport("Timed out waiting for SMTP CONNECT response.")) {
            try await client.loginAndValidateCredentials(
                configuration: Self.configuration(),
                credential: Self.credential()
            )
        }
    }

    @Test("SMTP timeout closes a non-cancellation-aware read before returning")
    func timeoutClosesNonCancellationAwareRead() async {
        let transport = ScriptedSMTPTransport(
            lines: [],
            suspendsWhenOutOfLines: true
        )
        let client = SMTPSessionClient(
            transport: transport,
            responseTimeoutNanoseconds: 1_000_000
        )

        await #expect(throws: SMTPClientError.transport("Timed out waiting for SMTP CONNECT response.")) {
            try await client.loginAndValidateCredentials(
                configuration: Self.configuration(),
                credential: Self.credential()
            )
        }
        #expect(await transport.disconnectCount == 1)
    }

    @Test("client authenticates and quits without sending mail while validating credentials")
    func clientAuthenticatesAndQuitsWhileValidatingCredentials() async throws {
        let transport = ScriptedSMTPTransport(lines: [
            "220 smtp.example.org ESMTP ready",
            "250 AUTH PLAIN",
            "235 2.7.0 Authentication successful",
            "221 2.0.0 Bye",
        ])
        let client = SMTPSessionClient(transport: transport)

        try await client.loginAndValidateCredentials(
            configuration: Self.configuration(),
            credential: Self.credential()
        )

        #expect(await transport.connectedServer == Self.configuration().outgoing)
        #expect(await transport.sentLines == [
            "EHLO brev.local",
            "AUTH PLAIN AHBlcnNvbkBleGFtcGxlLm9yZwBzZWNyZXQ=",
            "QUIT",
        ])
    }

    @Test("client rejects an SMTP multiline reply that exceeds the line count bound")
    func clientRejectsOversizedMultilineReplyLineCount() async {
        let transport = ScriptedSMTPTransport(lines: [
            "220 smtp.example.org ESMTP ready",
        ] + Array(repeating: "250-extension", count: 129))
        let client = SMTPSessionClient(transport: transport)

        await #expect(throws: SMTPClientError.malformedResponse(
            "SMTP response exceeded the maximum line count."
        )) {
            try await client.loginAndValidateCredentials(
                configuration: Self.configuration(),
                credential: Self.credential()
            )
        }
    }

    @Test("client rejects an SMTP multiline reply that exceeds the byte bound")
    func clientRejectsOversizedMultilineReplyByteCount() async {
        let oversizedExtension = String(repeating: "x", count: 65530)
        let transport = ScriptedSMTPTransport(lines: [
            "220 smtp.example.org ESMTP ready",
            "250-\(oversizedExtension)",
            "250 extension",
        ])
        let client = SMTPSessionClient(transport: transport)

        await #expect(throws: SMTPClientError.malformedResponse(
            "SMTP response exceeded the maximum aggregate size."
        )) {
            try await client.loginAndValidateCredentials(
                configuration: Self.configuration(),
                credential: Self.credential()
            )
        }
    }

    @Test("client rejects SMTP servers that do not advertise AUTH PLAIN")
    func clientRejectsSMTPServersThatDoNotAdvertiseAUTHPLAIN() async {
        let transport = ScriptedSMTPTransport(lines: [
            "220 smtp.example.org ESMTP ready",
            "250 smtp.example.org",
        ])
        let client = SMTPSessionClient(transport: transport)

        await #expect(throws: SMTPClientError.authenticationUnavailable("AUTH PLAIN")) {
            try await client.loginAndValidateCredentials(
                configuration: Self.configuration(),
                credential: Self.credential()
            )
        }

        #expect(await transport.sentLines == [
            "EHLO brev.local",
        ])
    }

    @Test("client classifies XOAUTH2 authentication rejection as an auth failure")
    func clientClassifiesXOAUTH2AuthenticationRejectionAsAuthFailure() async {
        let transport = ScriptedSMTPTransport(lines: [
            "220 smtp.gmail.com ESMTP ready",
            "250 AUTH XOAUTH2",
            "535 5.7.8 Authentication credentials invalid",
        ])
        let client = SMTPSessionClient(transport: transport)
        let credential = MailAccountCredential(
            incomingUsername: "person@gmail.com",
            outgoingUsername: "person@gmail.com",
            secret: "expired-access-token",
            authentication: .xoauth2
        )

        await #expect(throws: SMTPClientError.authenticationFailed(
            "535 5.7.8 Authentication credentials invalid"
        )) {
            try await client.loginAndValidateCredentials(
                configuration: Self.configuration(
                    outgoing: MailServerSettings(
                        kind: .smtp,
                        host: "smtp.gmail.com",
                        port: 465,
                        tlsMode: .implicit,
                        authentication: .xoauth2
                    )
                ),
                credential: credential
            )
        }
    }

    @Test("client authenticates and submits message data")
    func clientAuthenticatesAndSubmitsMessageData() async throws {
        let transport = ScriptedSMTPTransport(lines: [
            "220 smtp.example.org ESMTP ready",
            "250-smtp.example.org",
            "250 AUTH PLAIN",
            "235 2.7.0 Authentication successful",
            "250 2.1.0 Ok",
            "250 2.1.5 Ok",
            "354 End data with <CR><LF>.<CR><LF>",
            "250 2.0.0 queued",
            "221 2.0.0 Bye",
        ])
        let client = SMTPSessionClient(transport: transport)

        try await client.loginAndSubmitMessage(
            configuration: Self.configuration(),
            credential: Self.credential(),
            submission: SMTPMessageSubmission(
                messageData: Data("Subject: Test\r\n\r\nHello".utf8),
                senderEmail: "person@example.org",
                recipientEmails: ["bob@example.com"]
            )
        )

        #expect(await transport.connectedServer == Self.configuration().outgoing)
        #expect(await transport.sentLines == [
            "EHLO brev.local",
            "AUTH PLAIN AHBlcnNvbkBleGFtcGxlLm9yZwBzZWNyZXQ=",
            "MAIL FROM:<person@example.org>",
            "RCPT TO:<bob@example.com>",
            "DATA",
            "Subject: Test\r\n\r\nHello\r\n.",
            "QUIT",
        ])
    }

    @Test("client marks a lost DATA confirmation as an unknown delivery outcome")
    func clientMarksLostDataConfirmationAsUnknownDeliveryOutcome() async {
        let transport = ScriptedSMTPTransport(
            lines: [
                "220 smtp.example.org ESMTP ready",
                "250 AUTH PLAIN",
                "235 2.7.0 Authentication successful",
                "250 2.1.0 Ok",
                "250 2.1.5 Ok",
                "354 End data with <CR><LF>.<CR><LF>",
            ],
            suspendsWhenOutOfLines: true
        )
        let client = SMTPSessionClient(
            transport: transport,
            responseTimeoutNanoseconds: 1_000_000
        )

        await #expect(throws: SMTPClientError.deliveryOutcomeUnknown(
            underlying: "Timed out waiting for SMTP DATA response."
        )) {
            try await client.loginAndSubmitMessage(
                configuration: Self.configuration(),
                credential: Self.credential(),
                submission: SMTPMessageSubmission(
                    messageData: Data("Subject: Test\r\n\r\nHello".utf8),
                    senderEmail: "person@example.org",
                    recipientEmails: ["bob@example.com"]
                )
            )
        }

        #expect(await transport.sentLines.last == "Subject: Test\r\n\r\nHello\r\n.")
    }

    @Test("client dot stuffs message data before SMTP DATA terminator")
    func clientDotStuffsMessageDataBeforeSMTPDATATerminator() async throws {
        let transport = ScriptedSMTPTransport(lines: [
            "220 smtp.example.org ESMTP ready",
            "250 AUTH PLAIN",
            "235 2.7.0 Authentication successful",
            "250 2.1.0 Ok",
            "250 2.1.5 Ok",
            "354 End data with <CR><LF>.<CR><LF>",
            "250 2.0.0 queued",
            "221 2.0.0 Bye",
        ])
        let client = SMTPSessionClient(transport: transport)

        try await client.loginAndSubmitMessage(
            configuration: Self.configuration(),
            credential: Self.credential(),
            submission: SMTPMessageSubmission(
                messageData: Data("Line one\r\n.Starts with dot".utf8),
                senderEmail: "person@example.org",
                recipientEmails: ["bob@example.com"]
            )
        )

        #expect(await transport.sentLines.contains(
            "Line one\r\n..Starts with dot\r\n."
        ))
    }

    @Test("client dot-stuffs a lone '.' line so it can't terminate DATA early")
    func clientDotStuffsBareDotLine() async throws {
        let transport = ScriptedSMTPTransport(lines: [
            "220 smtp.example.org ESMTP ready",
            "250 AUTH PLAIN",
            "235 2.7.0 Authentication successful",
            "250 2.1.0 Ok",
            "250 2.1.5 Ok",
            "354 End data with <CR><LF>.<CR><LF>",
            "250 2.0.0 queued",
            "221 2.0.0 Bye",
        ])
        let client = SMTPSessionClient(transport: transport)

        try await client.loginAndSubmitMessage(
            configuration: Self.configuration(),
            credential: Self.credential(),
            submission: SMTPMessageSubmission(
                messageData: Data("Before\r\n.\r\nAfter".utf8),
                senderEmail: "person@example.org",
                recipientEmails: ["bob@example.com"]
            )
        )

        // The lone "." must be sent as ".." — otherwise the server reads it as
        // the end-of-data terminator and silently truncates the message.
        #expect(await transport.sentLines.contains("Before\r\n..\r\nAfter\r\n."))
    }

    @Test("client normalizes bare LF line endings to CRLF in DATA")
    func clientNormalizesBareLFToCRLF() async throws {
        let transport = ScriptedSMTPTransport(lines: [
            "220 smtp.example.org ESMTP ready",
            "250 AUTH PLAIN",
            "235 2.7.0 Authentication successful",
            "250 2.1.0 Ok",
            "250 2.1.5 Ok",
            "354 End data with <CR><LF>.<CR><LF>",
            "250 2.0.0 queued",
            "221 2.0.0 Bye",
        ])
        let client = SMTPSessionClient(transport: transport)

        try await client.loginAndSubmitMessage(
            configuration: Self.configuration(),
            credential: Self.credential(),
            submission: SMTPMessageSubmission(
                messageData: Data("Header: x\nBody line".utf8), // bare LF
                senderEmail: "person@example.org",
                recipientEmails: ["bob@example.com"]
            )
        )

        #expect(await transport.sentLines.contains("Header: x\r\nBody line\r\n."))
    }

    @Test("client trims envelope addresses before SMTP commands")
    func clientTrimsEnvelopeAddressesBeforeSMTPCommands() async throws {
        let transport = ScriptedSMTPTransport(lines: [
            "220 smtp.example.org ESMTP ready",
            "250 AUTH PLAIN",
            "235 2.7.0 Authentication successful",
            "250 2.1.0 Ok",
            "250 2.1.5 Ok",
            "354 End data with <CR><LF>.<CR><LF>",
            "250 2.0.0 queued",
            "221 2.0.0 Bye",
        ])
        let client = SMTPSessionClient(transport: transport)

        try await client.loginAndSubmitMessage(
            configuration: Self.configuration(),
            credential: Self.credential(),
            submission: SMTPMessageSubmission(
                messageData: Data("Subject: Test\r\n\r\nHello".utf8),
                senderEmail: " person@example.org ",
                recipientEmails: [" bob@example.com "]
            )
        )

        #expect(await transport.sentLines.contains("MAIL FROM:<person@example.org>"))
        #expect(await transport.sentLines.contains("RCPT TO:<bob@example.com>"))
    }

    @Test("client rejects CRLF in envelope addresses before SMTP connect")
    func clientRejectsCRLFInEnvelopeAddressesBeforeSMTPConnect() async {
        let transport = ScriptedSMTPTransport(lines: [])
        let client = SMTPSessionClient(transport: transport)

        await #expect(throws: SMTPClientError.malformedResponse(
            "SMTP envelope addresses cannot contain line breaks."
        )) {
            try await client.loginAndSubmitMessage(
                configuration: Self.configuration(),
                credential: Self.credential(),
                submission: SMTPMessageSubmission(
                    messageData: Data("Subject: Test\r\n\r\nHello".utf8),
                    senderEmail: "person@example.org\r\nRCPT TO:<attacker@example.org>",
                    recipientEmails: ["bob@example.com"]
                )
            )
        }
        #expect(await transport.connectedServer == nil)
        #expect(await transport.sentLines.isEmpty)
    }

    @Test("client rejects NUL in SMTP credentials before connect")
    func clientRejectsNULInSMTPCredentialsBeforeConnect() async {
        let transport = ScriptedSMTPTransport(lines: [])
        let client = SMTPSessionClient(transport: transport)

        await #expect(throws: SMTPClientError.malformedResponse("SMTP credentials cannot contain NUL characters.")) {
            try await client.loginAndValidateCredentials(
                configuration: Self.configuration(),
                credential: MailAccountCredential(
                    incomingUsername: "person@example.org",
                    outgoingUsername: "person@example.org",
                    secret: "sec\u{0}ret",
                    authentication: .password
                )
            )
        }
        #expect(await transport.connectedServer == nil)
        #expect(await transport.sentLines.isEmpty)
    }

    @Test("client upgrades STARTTLS sessions before authenticating")
    func clientUpgradesSTARTTLSSessionsBeforeAuthenticating() async throws {
        let transport = ScriptedSMTPTransport(lines: [
            "220 smtp.example.org ESMTP ready",
            "250-smtp.example.org",
            "250-STARTTLS",
            "250 AUTH PLAIN",
            "220 2.0.0 Ready to start TLS",
            "250-smtp.example.org",
            "250 AUTH PLAIN",
            "235 2.7.0 Authentication successful",
            "250 2.1.0 Ok",
            "250 2.1.5 Ok",
            "354 End data with <CR><LF>.<CR><LF>",
            "250 2.0.0 queued",
            "221 2.0.0 Bye",
        ])
        let client = SMTPSessionClient(transport: transport)

        try await client.loginAndSubmitMessage(
            configuration: Self.configuration(
                outgoing: MailServerSettings(
                    kind: .smtp,
                    host: "smtp.example.org",
                    port: 587,
                    tlsMode: .startTLS,
                    authentication: .password
                )
            ),
            credential: Self.credential(),
            submission: SMTPMessageSubmission(
                messageData: Data("Subject: Test\r\n\r\nHello".utf8),
                senderEmail: "person@example.org",
                recipientEmails: ["bob@example.com"]
            )
        )

        #expect(await transport.upgradedServers == [
            MailServerSettings(
                kind: .smtp,
                host: "smtp.example.org",
                port: 587,
                tlsMode: .startTLS,
                authentication: .password
            ),
        ])
        #expect(await transport.sentLines == [
            "EHLO brev.local",
            "STARTTLS",
            "EHLO brev.local",
            "AUTH PLAIN AHBlcnNvbkBleGFtcGxlLm9yZwBzZWNyZXQ=",
            "MAIL FROM:<person@example.org>",
            "RCPT TO:<bob@example.com>",
            "DATA",
            "Subject: Test\r\n\r\nHello\r\n.",
            "QUIT",
        ])
    }

    @Test("client rejects encrypted password authentication before SMTP connect")
    func clientRejectsEncryptedPasswordAuthenticationBeforeSMTPConnect() async {
        let transport = ScriptedSMTPTransport(lines: [])
        let client = SMTPSessionClient(transport: transport)

        await #expect(throws: SMTPClientError.unsupportedAuthentication(.encryptedPassword)) {
            try await client.loginAndSubmitMessage(
                configuration: Self.configuration(
                    outgoing: MailServerSettings(
                        kind: .smtp,
                        host: "smtp.example.org",
                        port: 465,
                        tlsMode: .implicit,
                        authentication: .encryptedPassword
                    )
                ),
                credential: Self.credential(),
                submission: SMTPMessageSubmission(
                    messageData: Data("Subject: Test\r\n\r\nHello".utf8),
                    senderEmail: "person@example.org",
                    recipientEmails: ["bob@example.com"]
                )
            )
        }
        #expect(await transport.connectedServer == nil)
        #expect(await transport.sentLines.isEmpty)
    }

    private static func configuration(
        outgoing: MailServerSettings = MailServerSettings(
            kind: .smtp,
            host: "smtp.example.org",
            port: 465,
            tlsMode: .implicit,
            authentication: .password
        )
    ) -> IMAPAccountConfiguration {
        IMAPAccountConfiguration(
            accountID: "imap-smtp:person@example.org",
            emailAddress: "person@example.org",
            displayName: "Person",
            incoming: MailServerSettings(
                kind: .imap,
                host: "imap.example.org",
                port: 993,
                tlsMode: .implicit,
                authentication: .password
            ),
            outgoing: outgoing,
            credentialID: "imap-smtp:person@example.org"
        )
    }

    private static func credential() -> MailAccountCredential {
        MailAccountCredential(
            incomingUsername: "person@example.org",
            outgoingUsername: "person@example.org",
            secret: "secret",
            authentication: .password
        )
    }
}

private actor ScriptedSMTPTransport: SMTPSessionTransport {
    private var lines: [String]
    private var writes: [String] = []
    private var server: MailServerSettings?
    private var tlsUpgrades: [MailServerSettings] = []
    private let suspendsWhenOutOfLines: Bool
    private var blockedRead: CheckedContinuation<String, any Error>?
    private var disconnects = 0

    init(lines: [String], suspendsWhenOutOfLines: Bool = false) {
        self.lines = lines
        self.suspendsWhenOutOfLines = suspendsWhenOutOfLines
    }

    var sentLines: [String] {
        writes
    }

    var connectedServer: MailServerSettings? {
        server
    }

    var upgradedServers: [MailServerSettings] {
        tlsUpgrades
    }

    var disconnectCount: Int {
        disconnects
    }

    func connect(to server: MailServerSettings) async throws {
        self.server = server
    }

    func readLine() async throws -> String {
        if lines.isEmpty, suspendsWhenOutOfLines {
            return try await withCheckedThrowingContinuation { continuation in
                blockedRead = continuation
            }
        }
        guard !lines.isEmpty else {
            throw SMTPClientError.transport("No scripted SMTP response available.")
        }
        return lines.removeFirst()
    }

    func writeLine(_ line: String) async throws {
        writes.append(line)
    }

    func writeData(_ data: Data) async throws {
        guard let payload = String(
            data: data.count >= 2 ? Data(data.dropLast(2)) : data,
            encoding: .utf8
        ) else {
            throw SMTPClientError.transport("scripted transport received non-UTF-8 data")
        }
        writes.append(payload)
    }

    func upgradeToTLS(server: MailServerSettings) async throws {
        tlsUpgrades.append(server)
    }

    func disconnect() async {
        disconnects += 1
        blockedRead?.resume(throwing: SMTPClientError.transport("SMTP transport disconnected."))
        blockedRead = nil
    }
}
