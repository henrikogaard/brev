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

// MARK: - Transport

/// Byte transport for a ManageSieve session (RFC 5804). The concrete network
/// implementation lives alongside the IMAP/SMTP transports; the client logic is
/// written against this protocol so it can be exercised with a scripted mock.
public protocol ManageSieveSessionTransport: Sendable {
    func connect(to server: MailServerSettings) async throws
    func upgradeToTLS(server: MailServerSettings) async throws
    func readLine() async throws -> String
    func writeLine(_ line: String) async throws
    func writeData(_ data: Data) async throws
    func disconnect() async
}

public enum ManageSieveClientError: Error, Sendable, Equatable, LocalizedError {
    case commandRejected(command: String, message: String?)
    case authenticationFailed(message: String?)
    case startTLSUnavailable
    case unexpectedDisconnect
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .commandRejected(let command, let message):
            "ManageSieve \(command) was rejected\(message.map { ": \($0)" } ?? ".")"
        case .authenticationFailed(let message):
            "ManageSieve authentication failed\(message.map { ": \($0)" } ?? ".")"
        case .startTLSUnavailable:
            String(localized: "The ManageSieve server does not offer STARTTLS.", bundle: .module)
        case .unexpectedDisconnect:
            String(localized: "The ManageSieve server closed the connection unexpectedly.", bundle: .module)
        case .transport(let detail):
            String(localized: "ManageSieve connection error: \(detail)", bundle: .module)
        }
    }
}

// MARK: - Client

/// Uploads and activates a Brev-owned Sieve script over ManageSieve. The
/// network transport is injected; this type owns the RFC 5804 conversation.
public actor ManageSieveSessionClient {
    private let transport: any ManageSieveSessionTransport

    public init(transport: any ManageSieveSessionTransport) {
        self.transport = transport
    }

    /// Connects, authenticates, uploads `plan.script` as `plan.scriptName`, and
    /// makes it the active script. Throws (fail-closed) on any rejection.
    public func uploadAndActivate(
        plan: SieveScriptPlan,
        server: MailServerSettings,
        username: String,
        password: String
    ) async throws {
        try await transport.connect(to: server)
        defer { Task { await transport.disconnect() } }

        var capabilities = try await readCapabilities()

        // Upgrade to TLS before authenticating if the connection isn't already
        // encrypted and the server offers STARTTLS.
        if server.tlsMode == .startTLS {
            guard capabilities.supportsStartTLS else {
                throw ManageSieveClientError.startTLSUnavailable
            }
            try await sendExpectingOK("STARTTLS", as: "STARTTLS")
            try await transport.upgradeToTLS(server: server)
            // The server re-advertises capabilities after the TLS handshake.
            capabilities = try await readCapabilities()
        }

        try await authenticate(username: username, password: password)
        try await putScript(name: plan.scriptName, script: plan.script)
        try await sendExpectingOK(
            ManageSieveCommand.setActive(name: plan.scriptName), as: "SETACTIVE"
        )
        try? await transport.writeLine(ManageSieveCommand.logout())
    }

    // MARK: Steps

    /// Reads capability lines up to the terminating result line.
    private func readCapabilities() async throws -> ManageSieveCapabilities {
        var lines: [String] = []
        while true {
            let line = try await transport.readLine()
            if let response = ManageSieveResponse.parse(line) {
                guard response.status != .bye else {
                    throw ManageSieveClientError.unexpectedDisconnect
                }
                return ManageSieveCapabilities.parse(lines)
            }
            lines.append(line)
        }
    }

    private func authenticate(username: String, password: String) async throws {
        try await transport.writeLine(
            ManageSieveCommand.authenticatePlain(username: username, password: password)
        )
        let response = try await readResult()
        guard response.isOK else {
            throw ManageSieveClientError.authenticationFailed(message: response.message)
        }
    }

    private func putScript(name: String, script: String) async throws {
        // Non-synchronizing literal: send the header then the body immediately.
        try await transport.writeLine(ManageSieveCommand.putScriptHeader(name: name, script: script))
        try await transport.writeData(Data(script.utf8))
        let response = try await readResult()
        guard response.isOK else {
            throw ManageSieveClientError.commandRejected(command: "PUTSCRIPT", message: response.message)
        }
    }

    private func sendExpectingOK(_ command: String, as label: String) async throws {
        try await transport.writeLine(command)
        let response = try await readResult()
        guard response.isOK else {
            throw ManageSieveClientError.commandRejected(command: label, message: response.message)
        }
    }

    /// Reads lines until a result (`OK`/`NO`/`BYE`) is found, skipping any
    /// intermediate data. `BYE` is treated as an unexpected disconnect.
    private func readResult() async throws -> ManageSieveResponse {
        while true {
            let line = try await transport.readLine()
            guard let response = ManageSieveResponse.parse(line) else { continue }
            if response.status == .bye {
                throw ManageSieveClientError.unexpectedDisconnect
            }
            return response
        }
    }
}
