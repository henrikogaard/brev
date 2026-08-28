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

// MARK: - NetworkSMTPSessionTransport

/// SMTP submission transport backed by a `MailSocketConnection`.
///
/// Selects `NWConnectionSocketTransport` (Network.framework) for implicit TLS
/// and `URLSessionStreamSocketTransport` for STARTTLS. The socket is created
/// lazily during `connect(to:)` so the transport can be instantiated without
/// upfront configuration, as required by `SMTPSessionTransport`.
public final class NetworkSMTPSessionTransport: SMTPSessionTransport, @unchecked Sendable {
    private let state: NetworkSMTPTransportState

    public init() {
        state = NetworkSMTPTransportState()
    }

    /// Creates a transport backed by a pre-built socket. Used in tests to
    /// inject a scripted socket without making a real network connection.
    public init(configuration: SMTPConfiguration, socket: any MailSocketConnection) {
        state = NetworkSMTPTransportState(preConnectedSocket: socket)
    }

    // MARK: - SMTPSessionTransport

    public func connect(to server: MailServerSettings) async throws {
        let socket = MailSocketConnectionFactory.make(
            host: server.host,
            port: server.port,
            tlsMode: server.tlsMode == .implicit ? .implicit : .starttls
        )
        do {
            try await socket.connect()
            await state.setSocket(socket)
        } catch {
            await socket.close()
            throw SMTPClientError.transport(error.localizedDescription)
        }
    }

    public func upgradeToTLS(server: MailServerSettings) async throws {
        let socket = try await state.requireSocket()
        guard let starttls = socket as? URLSessionStreamSocketTransport else {
            throw SMTPClientError.unsupportedTLSMode(.startTLS)
        }
        do {
            try await starttls.upgradeToTLS()
            await state.resetBuffer()
        } catch {
            throw SMTPClientError.transport(error.localizedDescription)
        }
    }

    public func readLine() async throws -> String {
        let socket = try await state.requireSocket()
        return try await state.readLine(socket: socket)
    }

    public func writeLine(_ line: String) async throws {
        let socket = try await state.requireSocket()
        do {
            try await socket.write(Data((line + "\r\n").utf8))
        } catch {
            throw SMTPClientError.transport(error.localizedDescription)
        }
    }

    public func writeData(_ data: Data) async throws {
        let socket = try await state.requireSocket()
        do {
            try await socket.write(data)
        } catch {
            throw SMTPClientError.transport(error.localizedDescription)
        }
    }

    public func disconnect() async {
        await state.disconnect()
    }
}

// MARK: - Transport state actor

private actor NetworkSMTPTransportState {
    private var socket: (any MailSocketConnection)?
    private var lineBuffer = Data()

    init(preConnectedSocket: (any MailSocketConnection)? = nil) {
        socket = preConnectedSocket
    }

    func setSocket(_ socket: any MailSocketConnection) {
        self.socket = socket
    }

    func requireSocket() throws -> any MailSocketConnection {
        guard let socket else {
            throw SMTPClientError.transport("SMTP transport not connected.")
        }
        return socket
    }

    func resetBuffer() {
        lineBuffer = Data()
    }

    func readLine(socket: any MailSocketConnection) async throws -> String {
        while true {
            if let crlfRange = lineBuffer.firstRange(of: Data([0x0D, 0x0A])) {
                let line = String(data: lineBuffer[..<crlfRange.lowerBound], encoding: .utf8) ?? ""
                lineBuffer.removeSubrange(..<crlfRange.upperBound)
                return line
            }
            // Mirror the IMAP/ManageSieve guard: a server that streams data
            // without ever sending CRLF would otherwise grow lineBuffer without
            // bound (OOM). Bulk payloads do not arrive this way in SMTP.
            guard lineBuffer.count <= MailTransportLimits.maxLineByteCount else {
                throw SMTPClientError.transport("SMTP response line exceeded the maximum length.")
            }
            do {
                let chunk = try await socket.read(maxLength: 4096)
                guard !chunk.isEmpty else {
                    throw SMTPClientError.transport("SMTP connection closed by server.")
                }
                lineBuffer.append(chunk)
            } catch let error as SMTPClientError {
                throw error
            } catch {
                throw SMTPClientError.transport(error.localizedDescription)
            }
        }
    }

    func disconnect() async {
        let s = socket
        socket = nil
        lineBuffer = Data()
        // Await the close before returning. A timed-out session read may still
        // be suspended in the socket implementation; scheduling close in a
        // detached task lets that orphan reader outlive the next session and
        // makes teardown/reconnect ordering nondeterministic.
        await s?.close()
    }
}
