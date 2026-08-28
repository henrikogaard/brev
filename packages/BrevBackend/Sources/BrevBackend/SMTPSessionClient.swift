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

public protocol SMTPSessionTransport: Sendable {
    func connect(to server: MailServerSettings) async throws
    func upgradeToTLS(server: MailServerSettings) async throws
    func readLine() async throws -> String
    func writeLine(_ line: String) async throws
    /// Writes an SMTP DATA payload without converting arbitrary message bytes
    /// through `String`, which would replace invalid UTF-8 octets.
    func writeData(_ data: Data) async throws
    func disconnect() async
}

public extension SMTPSessionTransport {
    func writeData(_ data: Data) async throws {
        let messageData = data.count >= 2 ? Data(data.dropLast(2)) : data
        guard let line = String(data: messageData, encoding: .utf8) else {
            throw SMTPClientError.transport("SMTP transport cannot write non-UTF-8 DATA bytes.")
        }
        try await writeLine(line)
    }

    func upgradeToTLS(server: MailServerSettings) async throws {
        _ = server
        throw SMTPClientError.unsupportedTLSMode(.startTLS)
    }
}

public struct SMTPMessageSubmission: Sendable, Hashable {
    public let messageData: Data
    public let senderEmail: String
    public let recipientEmails: [String]

    public init(
        messageData: Data,
        senderEmail: String,
        recipientEmails: [String]
    ) {
        self.messageData = messageData
        self.senderEmail = senderEmail
        self.recipientEmails = recipientEmails
    }
}

public enum SMTPClientError: Error, Equatable, LocalizedError, Sendable {
    case invalidServerKind(MailServerProtocolKind)
    case unsupportedTLSMode(MailServerTLSMode)
    case unsupportedAuthentication(MailServerAuthentication)
    case authenticationUnavailable(String)
    case connectionRejected(String)
    case authenticationFailed(String)
    case commandFailed(command: String, response: String)
    case malformedResponse(String)
    case transport(String)
    /// The DATA payload was submitted, but the server's final acceptance
    /// response was not received. Retrying automatically could deliver a
    /// duplicate message, so callers must leave the draft for an explicit
    /// user decision.
    case deliveryOutcomeUnknown(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .invalidServerKind:
            String(localized: "SMTP client received non-SMTP server settings.", bundle: .module)
        case .unsupportedTLSMode(let mode):
            String(localized: "SMTP transport does not support \(mode.rawValue) yet.", bundle: .module)
        case .unsupportedAuthentication(let authentication):
            String(localized: "SMTP client does not support \(authentication.rawValue) authentication yet.", bundle: .module)
        case .authenticationUnavailable(let mechanism):
            String(localized: "SMTP server did not advertise \(mechanism) authentication.", bundle: .module)
        case .connectionRejected(let response):
            String(localized: "SMTP server rejected the connection: \(response)", bundle: .module)
        case .authenticationFailed:
            String(localized: "SMTP authentication failed.", bundle: .module)
        case .commandFailed(let command, let response):
            String(localized: "SMTP command \(command) failed: \(response)", bundle: .module)
        case .malformedResponse(let response):
            String(localized: "SMTP server returned an unreadable response: \(response)", bundle: .module)
        case .transport(let message):
            String(localized: "SMTP transport failed: \(message)", bundle: .module)
        case .deliveryOutcomeUnknown(let underlying):
            String(
                localized: "The message may have been delivered, but SMTP confirmation was unavailable (\(underlying)). Check Sent before trying again.",
                bundle: .module
            )
        }
    }
}

public struct SMTPSessionClient: Sendable {
    private struct Envelope: Sendable {
        let senderEmail: String
        let recipientEmails: [String]
    }

    private let transport: any SMTPSessionTransport
    private let ehloHostname: String
    private let responseTimeoutNanoseconds: UInt64?

    public init(
        transport: any SMTPSessionTransport,
        ehloHostname: String = "brev.local",
        responseTimeoutNanoseconds: UInt64? = 60_000_000_000
    ) {
        self.transport = transport
        self.ehloHostname = ehloHostname
        self.responseTimeoutNanoseconds = responseTimeoutNanoseconds
    }

    public func loginAndSubmitMessage(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        submission: SMTPMessageSubmission
    ) async throws {
        try validateOutgoingServer(configuration)
        try Self.validatePlainCredential(credential)
        let envelope = try Self.validatedEnvelope(submission)

        do {
            try await connectAndAuthenticate(
                configuration: configuration,
                credential: credential
            )
            try await submitEnvelopeAndData(submission, envelope: envelope)
            try await quit()
            await transport.disconnect()
        } catch {
            if !Self.isResponseTimeout(error) {
                await transport.disconnect()
            }
            throw error
        }
    }

    public func loginAndValidateCredentials(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential
    ) async throws {
        try validateOutgoingServer(configuration)
        try Self.validatePlainCredential(credential)

        do {
            try await connectAndAuthenticate(
                configuration: configuration,
                credential: credential
            )
            try await quit()
            await transport.disconnect()
        } catch {
            if !Self.isResponseTimeout(error) {
                await transport.disconnect()
            }
            throw error
        }
    }

    private func validateOutgoingServer(
        _ configuration: IMAPAccountConfiguration
    ) throws {
        guard configuration.outgoing.kind == .smtp else {
            throw SMTPClientError.invalidServerKind(configuration.outgoing.kind)
        }
        guard [.implicit, .startTLS].contains(configuration.outgoing.tlsMode) else {
            throw SMTPClientError.unsupportedTLSMode(configuration.outgoing.tlsMode)
        }
        guard [.password, .appPassword, .xoauth2]
            .contains(configuration.outgoing.authentication)
        else {
            throw SMTPClientError.unsupportedAuthentication(configuration.outgoing.authentication)
        }
    }

    private static func validatedEnvelope(
        _ submission: SMTPMessageSubmission
    ) throws -> Envelope {
        let senderEmail = submission.senderEmail
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let recipientEmails = submission.recipientEmails.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !senderEmail.isEmpty,
              !recipientEmails.isEmpty,
              recipientEmails.allSatisfy({ !$0.isEmpty })
        else {
            throw SMTPClientError.malformedResponse("SMTP submission requires sender and recipients.")
        }

        let addresses = [senderEmail] + recipientEmails
        guard addresses.allSatisfy({ $0.rangeOfCharacter(from: .newlines) == nil }) else {
            throw SMTPClientError.malformedResponse(
                "SMTP envelope addresses cannot contain line breaks."
            )
        }

        return Envelope(senderEmail: senderEmail, recipientEmails: recipientEmails)
    }

    private static func validatePlainCredential(
        _ credential: MailAccountCredential
    ) throws {
        guard !containsNUL(credential.outgoingUsername),
              !containsNUL(credential.secret)
        else {
            throw SMTPClientError.malformedResponse(
                "SMTP credentials cannot contain NUL characters."
            )
        }
    }

    private static func containsNUL(_ value: String) -> Bool {
        value.unicodeScalars.contains { $0.value == 0 }
    }

    private func connectAndAuthenticate(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential
    ) async throws {
        try await transport.connect(to: configuration.outgoing)
        _ = try await readReply(expectedCodes: ["220"], commandName: "CONNECT")
        var authenticationEHLOReply = try await sendEHLO()
        if configuration.outgoing.tlsMode == .startTLS {
            try await startTLS(
                server: configuration.outgoing,
                ehloReply: authenticationEHLOReply
            )
            authenticationEHLOReply = try await sendEHLO()
        }
        try await authenticate(credential, ehloReply: authenticationEHLOReply)
    }

    private func sendEHLO() async throws -> [String] {
        try await writeCommand("EHLO \(ehloHostname)")
        return try await readReply(expectedCodes: ["250"], commandName: "EHLO")
    }

    private func startTLS(
        server: MailServerSettings,
        ehloReply: [String]
    ) async throws {
        guard Self.replyAdvertisesSTARTTLS(ehloReply) else {
            throw SMTPClientError.unsupportedTLSMode(.startTLS)
        }
        try await writeCommand("STARTTLS")
        _ = try await readReply(expectedCodes: ["220"], commandName: "STARTTLS")
        try await transport.upgradeToTLS(server: server)
    }

    private func authenticate(
        _ credential: MailAccountCredential,
        ehloReply: [String]
    ) async throws {
        switch credential.authentication {
        case .xoauth2:
            guard Self.replyAdvertisesAUTHXOAuth2(ehloReply) else {
                throw SMTPClientError.authenticationUnavailable("AUTH XOAUTH2")
            }
            let sasl = XOAuth2SASLEncoder.encode(
                email: credential.outgoingUsername,
                accessToken: credential.secret
            )
            try await writeCommand("AUTH XOAUTH2 \(sasl)")
            let firstReply = try await readReply(
                expectedCodes: ["235", "334"],
                commandName: "AUTH XOAUTH2"
            )
            if firstReply.first?.hasPrefix("334") == true {
                // Error challenge — respond with empty string; the connection will
                // be torn down immediately after this throws.
                try? await writeCommand("")
                throw SMTPClientError.authenticationFailed(
                    firstReply.first ?? "AUTH XOAUTH2 rejected"
                )
            }
        case .password, .appPassword, .encryptedPassword, .none:
            guard Self.replyAdvertisesAUTHPlain(ehloReply) else {
                throw SMTPClientError.authenticationUnavailable("AUTH PLAIN")
            }
            let token = authPlainToken(
                username: credential.outgoingUsername,
                secret: credential.secret
            )
            try await writeCommand("AUTH PLAIN \(token)")
            _ = try await readReply(expectedCodes: ["235"], commandName: "AUTH PLAIN")
        }
    }

    private static func replyAdvertisesAUTHXOAuth2(_ lines: [String]) -> Bool {
        lines.contains { line in
            guard line.count >= 4 else { return false }
            let extensionText = line.dropFirst(4)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            if extensionText.hasPrefix("AUTH=") {
                return extensionText.dropFirst(5)
                    .split(whereSeparator: \.isWhitespace)
                    .contains("XOAUTH2")
            }
            let tokens = extensionText.split(whereSeparator: \.isWhitespace)
            guard tokens.first == "AUTH" else { return false }
            return tokens.dropFirst().contains("XOAUTH2")
        }
    }

    private func submitEnvelopeAndData(
        _ submission: SMTPMessageSubmission,
        envelope: Envelope
    ) async throws {
        try await writeCommand("MAIL FROM:<\(envelope.senderEmail)>")
        _ = try await readReply(expectedCodes: ["250"], commandName: "MAIL FROM")

        for recipient in envelope.recipientEmails {
            try await writeCommand("RCPT TO:<\(recipient)>")
            _ = try await readReply(expectedCodes: ["250"], commandName: "RCPT TO")
        }

        try await writeCommand("DATA")
        _ = try await readReply(expectedCodes: ["354"], commandName: "DATA")
        try await transport.writeData(Self.smtpDataPayload(from: submission.messageData))
        do {
            _ = try await readReply(expectedCodes: ["250"], commandName: "DATA")
        } catch {
            // Once the DATA terminator has been written, a lost response is
            // ambiguous: the server may already have accepted the message.
            // Never turn that state into an automatic retry.
            if case SMTPClientError.commandFailed = error {
                // A concrete SMTP rejection is an explicit negative outcome,
                // not an unknown delivery state.
                throw error
            }
            throw SMTPClientError.deliveryOutcomeUnknown(
                underlying: Self.deliveryOutcomeUnderlyingDescription(error)
            )
        }
    }

    private func quit() async throws {
        try await writeCommand("QUIT")
        _ = try await readReply(expectedCodes: ["221"], commandName: "QUIT")
    }

    private func writeCommand(_ command: String) async throws {
        try await transport.writeLine(command)
    }

    private func readReply(
        expectedCodes: Set<String>,
        commandName: String
    ) async throws -> [String] {
        let firstLine = try await readLine(commandName: commandName)
        guard firstLine.count >= 4 else {
            throw SMTPClientError.malformedResponse(firstLine)
        }
        let code = String(firstLine.prefix(3))
        guard code.allSatisfy(\.isNumber) else {
            throw SMTPClientError.malformedResponse(firstLine)
        }

        var lines = [firstLine]
        var byteCount = firstLine.utf8.count
        guard byteCount <= MailTransportLimits.maxSMTPReplyByteCount else {
            throw SMTPClientError.malformedResponse(
                "SMTP response exceeded the maximum aggregate size."
            )
        }
        if firstLine[firstLine.index(firstLine.startIndex, offsetBy: 3)] == "-" {
            while true {
                guard lines.count < MailTransportLimits.maxSMTPReplyLineCount else {
                    throw SMTPClientError.malformedResponse(
                        "SMTP response exceeded the maximum line count."
                    )
                }
                let line = try await readLine(commandName: commandName)
                guard line.hasPrefix(code) else {
                    throw SMTPClientError.malformedResponse(line)
                }
                guard line.count >= 4 else {
                    throw SMTPClientError.malformedResponse(line)
                }
                let lineByteCount = line.utf8.count
                guard lineByteCount <= MailTransportLimits.maxSMTPReplyByteCount - byteCount else {
                    throw SMTPClientError.malformedResponse(
                        "SMTP response exceeded the maximum aggregate size."
                    )
                }
                byteCount += lineByteCount
                lines.append(line)
                if line[line.index(line.startIndex, offsetBy: 3)] == " " {
                    break
                }
            }
        }

        guard expectedCodes.contains(code) else {
            if commandName == "CONNECT" {
                throw SMTPClientError.connectionRejected(firstLine)
            }
            if commandName.hasPrefix("AUTH ") {
                throw SMTPClientError.authenticationFailed(firstLine)
            }
            throw SMTPClientError.commandFailed(
                command: commandName,
                response: lines.joined(separator: "\n")
            )
        }
        return lines
    }

    private func readLine(commandName: String) async throws -> String {
        try await withResponseTimeout(commandName: commandName) {
            try await transport.readLine()
        }
    }

    private func withResponseTimeout<T: Sendable>(
        commandName: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        guard let responseTimeoutNanoseconds else {
            return try await operation()
        }

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    try await operation()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: responseTimeoutNanoseconds)
                    throw SMTPClientError.transport(
                        "Timed out waiting for SMTP \(commandName) response."
                    )
                }

                do {
                    guard let result = try await group.next() else {
                        throw SMTPClientError.transport(
                            "Timed out waiting for SMTP \(commandName) response."
                        )
                    }
                    group.cancelAll()
                    return result
                } catch {
                    // Cancelling a Swift task does not necessarily interrupt a
                    // socket read. Close the transport before leaving the task
                    // group so an orphan reader cannot consume later protocol
                    // bytes and leave this session stuck during teardown.
                    if Self.isResponseTimeout(error) {
                        await transport.disconnect()
                    }
                    group.cancelAll()
                    throw error
                }
            }
        } onCancel: {
            Task { await transport.disconnect() }
        }
    }

    private static func isResponseTimeout(_ error: Error) -> Bool {
        switch error {
        case SMTPClientError.transport(let message):
            return message.hasPrefix("Timed out waiting for SMTP")
        case SMTPClientError.deliveryOutcomeUnknown(let underlying):
            return underlying.hasPrefix("SMTP transport failed: Timed out waiting for SMTP")
                || underlying.hasPrefix("Timed out waiting for SMTP")
        default:
            return false
        }
    }

    private static func deliveryOutcomeUnderlyingDescription(_ error: Error) -> String {
        guard let smtpError = error as? SMTPClientError else {
            return error.localizedDescription
        }
        if case .transport(let message) = smtpError {
            return message
        }
        return smtpError.localizedDescription
    }

    private static func replyAdvertisesSTARTTLS(_ lines: [String]) -> Bool {
        lines.contains { line in
            guard line.count >= 4 else { return false }
            let extensionText = line.dropFirst(4)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            return extensionText == "STARTTLS"
                || extensionText.hasPrefix("STARTTLS ")
        }
    }

    private static func replyAdvertisesAUTHPlain(_ lines: [String]) -> Bool {
        lines.contains { line in
            guard line.count >= 4 else { return false }
            let extensionText = line.dropFirst(4)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()

            if extensionText.hasPrefix("AUTH=") {
                return extensionText.dropFirst(5)
                    .split(whereSeparator: \.isWhitespace)
                    .contains("PLAIN")
            }

            let tokens = extensionText.split(whereSeparator: \.isWhitespace)
            guard tokens.first == "AUTH" else { return false }
            return tokens.dropFirst().contains("PLAIN")
        }
    }

    private func authPlainToken(username: String, secret: String) -> String {
        Data("\u{0}\(username)\u{0}\(secret)".utf8).base64EncodedString()
    }

    private static func smtpDataPayload(from data: Data) -> Data {
        let normalized = MIMEWireEncoding.crlfNormalizedMessageData(data)
        var output = Data()
        output.reserveCapacity(normalized.count + 8)
        var atLineStart = true
        for byte in normalized {
            if atLineStart, byte == 0x2E {
                output.append(0x2E)
            }
            output.append(byte)
            atLineStart = byte == 0x0A
        }
        if output.count < 2 || Array(output.suffix(2)) != [0x0D, 0x0A] {
            output.append(contentsOf: [0x0D, 0x0A])
        }
        output.append(contentsOf: [0x2E, 0x0D, 0x0A])
        return output
    }
}
