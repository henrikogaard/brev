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

// MARK: - NetworkManageSieveSessionTransport

/// ManageSieve transport backed by a `MailSocketConnection` — the same socket
/// abstraction the IMAP/SMTP transports use, so implicit TLS and STARTTLS are
/// handled identically. Lines are CRLF-delimited (RFC 5804). The socket is
/// created lazily during `connect(to:)`.
public final class NetworkManageSieveSessionTransport: ManageSieveSessionTransport, @unchecked Sendable {
    private let state: NetworkManageSieveTransportState

    public init() {
        state = NetworkManageSieveTransportState()
    }

    /// Injects a pre-built socket for tests — no real network connection.
    public init(socket: any MailSocketConnection) {
        state = NetworkManageSieveTransportState(preConnectedSocket: socket)
    }

    public func connect(to server: MailServerSettings) async throws {
        // A socket injected for tests is already connected; don't dial a real host.
        if await state.hasSocket { return }
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
            throw ManageSieveClientError.transport(error.localizedDescription)
        }
    }

    public func upgradeToTLS(server: MailServerSettings) async throws {
        let socket = try await state.requireSocket()
        guard let starttls = socket as? URLSessionStreamSocketTransport else {
            throw ManageSieveClientError.startTLSUnavailable
        }
        do {
            try await starttls.upgradeToTLS()
            await state.resetBuffer()
        } catch {
            throw ManageSieveClientError.transport(error.localizedDescription)
        }
    }

    public func readLine() async throws -> String {
        let socket = try await state.requireSocket()
        return try await state.readLine(socket: socket)
    }

    public func writeLine(_ line: String) async throws {
        try await writeData(Data((line + "\r\n").utf8))
    }

    public func writeData(_ data: Data) async throws {
        let socket = try await state.requireSocket()
        do {
            try await socket.write(data)
        } catch {
            throw ManageSieveClientError.transport(error.localizedDescription)
        }
    }

    public func disconnect() async {
        await state.disconnect()
    }
}

// MARK: - Transport state actor

private actor NetworkManageSieveTransportState {
    private var socket: (any MailSocketConnection)?
    private var lineBuffer = Data()

    init(preConnectedSocket: (any MailSocketConnection)? = nil) {
        socket = preConnectedSocket
    }

    var hasSocket: Bool { socket != nil }

    func setSocket(_ socket: any MailSocketConnection) {
        self.socket = socket
    }

    func requireSocket() throws -> any MailSocketConnection {
        guard let socket else {
            throw ManageSieveClientError.transport("ManageSieve transport not connected.")
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
            guard lineBuffer.count <= MailTransportLimits.maxLineByteCount else {
                throw ManageSieveClientError.transport("ManageSieve response line exceeded the maximum length.")
            }
            do {
                let chunk = try await socket.read(maxLength: 4096)
                guard !chunk.isEmpty else {
                    throw ManageSieveClientError.transport("ManageSieve connection closed by server.")
                }
                lineBuffer.append(chunk)
            } catch let error as ManageSieveClientError {
                throw error
            } catch {
                throw ManageSieveClientError.transport(error.localizedDescription)
            }
        }
    }

    func disconnect() {
        let activeSocket = socket
        socket = nil
        lineBuffer = Data()
        Task { await activeSocket?.close() }
    }
}
