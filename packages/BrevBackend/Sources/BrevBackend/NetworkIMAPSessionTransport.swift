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

// MARK: - NetworkIMAPSessionTransport

/// IMAP session transport backed by a `MailSocketConnection`.
///
/// Selects `NWConnectionSocketTransport` (Network.framework) for implicit TLS
/// and `URLSessionStreamSocketTransport` for STARTTLS. The socket is created
/// lazily during `connect(to:)` so the transport can be instantiated without
/// upfront configuration, as required by `IMAPSessionTransport`.
public final class NetworkIMAPSessionTransport: IMAPSessionTransport, @unchecked Sendable {
    private let state: NetworkIMAPTransportState

    public init() {
        state = NetworkIMAPTransportState()
    }

    /// Creates a transport backed by a pre-built socket. Used in tests to
    /// inject a scripted socket without making a real network connection.
    ///
    /// Callers must not call `connect(to:)` after using this init — the socket
    /// is already set. Call `readLine()` / `writeLine(_:)` directly.
    public init(configuration: IMAPConfiguration, socket: any MailSocketConnection) {
        state = NetworkIMAPTransportState(preConnectedSocket: socket)
    }

    // MARK: - IMAPSessionTransport

    public func connect(to server: MailServerSettings) async throws {
        guard server.kind == .imap else {
            throw IMAPClientError.invalidServerKind(server.kind)
        }
        let socket = MailSocketConnectionFactory.make(
            host: server.host,
            port: server.port,
            tlsMode: server.tlsMode == .implicit ? .implicit : .starttls
        )
        do {
            try await socket.connect()
            await state.setSocket(socket)
            // Read and discard the server greeting — IMAPSessionClient handles it.
        } catch {
            await socket.close()
            throw IMAPClientError.transport(error.localizedDescription)
        }
    }

    public func upgradeToTLS(server: MailServerSettings) async throws {
        let socket = try await state.requireSocket()
        guard let starttls = socket as? URLSessionStreamSocketTransport else {
            throw IMAPClientError.unsupportedTLSMode(.startTLS)
        }
        do {
            try await starttls.upgradeToTLS()
            await state.resetBuffer()
        } catch {
            throw IMAPClientError.transport(error.localizedDescription)
        }
    }

    public func readLine() async throws -> String {
        let (socket, generation) = try await state.socketSnapshot()
        return try await state.readLine(socket: socket, generation: generation)
    }

    public func readData(maxLength: Int) async throws -> Data {
        let (socket, generation) = try await state.socketSnapshot()
        return try await state.readData(maxLength: maxLength, socket: socket, generation: generation)
    }

    public func writeLine(_ line: String) async throws {
        let socket = try await state.requireSocket()
        do {
            try await socket.write(Data((line + "\r\n").utf8))
        } catch {
            throw IMAPClientError.transport(error.localizedDescription)
        }
    }

    public func writeData(_ data: Data) async throws {
        let socket = try await state.requireSocket()
        do {
            try await socket.write(data)
        } catch {
            throw IMAPClientError.transport(error.localizedDescription)
        }
    }

    public func disconnect() async {
        await state.disconnect()
    }
}

// MARK: - Transport state actor

private actor NetworkIMAPTransportState {
    private var socket: (any MailSocketConnection)?
    private var lineBuffer = IMAPLineBuffer()
    private var generation = 0

    init(preConnectedSocket: (any MailSocketConnection)? = nil) {
        socket = preConnectedSocket
    }

    func setSocket(_ socket: any MailSocketConnection) {
        self.socket = socket
        generation &+= 1
        lineBuffer = IMAPLineBuffer()
    }

    func requireSocket() throws -> any MailSocketConnection {
        guard let socket else {
            throw IMAPClientError.transport("IMAP transport not connected.")
        }
        return socket
    }

    func socketSnapshot() throws -> (socket: any MailSocketConnection, generation: Int) {
        guard let socket else {
            throw IMAPClientError.transport("IMAP transport not connected.")
        }
        return (socket, generation)
    }

    func resetBuffer() {
        lineBuffer = IMAPLineBuffer()
    }

    func readLine(socket: any MailSocketConnection, generation: Int) async throws -> String {
        while true {
            if let line = lineBuffer.takeLine() {
                return line
            }
            guard lineBuffer.pendingByteCount <= MailTransportLimits.maxLineByteCount else {
                throw IMAPClientError.transport("IMAP response line exceeded the maximum length.")
            }
            do {
                let chunk = try await socket.read(maxLength: 4096)
                guard self.generation == generation, self.socket != nil else {
                    throw IMAPClientError.transport("IMAP transport session changed while reading.")
                }
                guard !chunk.isEmpty else {
                    throw IMAPClientError.transport("IMAP connection closed by server.")
                }
                lineBuffer.append(chunk)
            } catch let error as IMAPClientError {
                throw error
            } catch {
                throw IMAPClientError.transport(error.localizedDescription)
            }
        }
    }

    func readData(
        maxLength: Int,
        socket: any MailSocketConnection,
        generation: Int
    ) async throws -> Data {
        guard maxLength > 0 else { return Data() }
        if let data = lineBuffer.takeData(maxLength: maxLength) {
            return Data(data)
        }

        do {
            let data = try await socket.read(maxLength: maxLength)
            guard self.generation == generation, self.socket != nil else {
                throw IMAPClientError.transport("IMAP transport session changed while reading.")
            }
            return data
        } catch let error as IMAPClientError {
            throw error
        } catch {
            throw IMAPClientError.transport(error.localizedDescription)
        }
    }

    func disconnect() async {
        let s = socket
        socket = nil
        generation &+= 1
        lineBuffer = IMAPLineBuffer()
        // Await the close before returning. A timed-out session read may still
        // be suspended in the socket implementation; scheduling close in a
        // detached task lets that orphan reader outlive the next session and
        // makes teardown/reconnect ordering nondeterministic.
        await s?.close()
    }
}
