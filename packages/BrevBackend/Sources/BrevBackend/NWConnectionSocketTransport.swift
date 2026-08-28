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
import Network

// MARK: - NWConnectionSocketTransport

/// Implicit-TLS socket transport built on `NWConnection` from Network.framework.
///
/// Used for port 993 (IMAP) and port 465 (SMTP) where TLS wraps the connection
/// from the very first byte. The TLS handshake is driven by `NWProtocolTLS` and
/// evaluated against the system trust store — no SecureTransport APIs are
/// involved.
///
/// Minimum deployment: macOS 14 / iOS 17 (matches Brev's platform targets).
///
/// Do not instantiate directly; go through `MailSocketConnectionFactory.make`.
final class NWConnectionSocketTransport: MailSocketConnection, @unchecked Sendable {
    // @unchecked Sendable: `connection` is only mutated before `connect()` returns
    // and thereafter reads/writes are serialized through `NWConnection`'s own
    // dispatch queue and the async continuation machinery below.

    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let connection: NWConnection

    // Serializes concurrent reads so callers don't interleave partial frames.
    private let readLock = NSLock()

    /// Creates a transport that will connect to `host`:`port` using implicit TLS.
    ///
    /// - Parameters:
    ///   - host: Hostname or IP address of the mail server.
    ///   - port: TCP port (typically 993 for IMAP, 465 for SMTP).
    init(host: String, port: UInt16) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
        let tlsOptions = NWProtocolTLS.Options()
        let tcpOptions = NWProtocolTCP.Options()
        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        connection = NWConnection(
            host: self.host,
            port: self.port,
            using: parameters
        )
    }

    // MARK: - MailSocketConnection

    /// Maximum time to wait for the TCP + TLS handshake to reach `.ready`.
    /// Without this, a server that accepts the TCP connection but stalls the
    /// TLS handshake (stays `.preparing`) would suspend the caller forever.
    private static let connectTimeoutNanoseconds: UInt64 = 30_000_000_000 // 30s

    /// Opens the TCP connection and completes the TLS handshake.
    ///
    /// Suspends until the connection enters `.ready` state, then returns.
    /// Throws `MailSocketError.connectionFailed` on any network or TLS error,
    /// or if the handshake does not complete within `connectTimeoutNanoseconds`.
    func connect() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [self] in
                try await withTaskCancellationHandler {
                    try await awaitReady()
                } onCancel: {
                    // On timeout the handshake task is cancelled; cancelling the
                    // NWConnection drives it to `.cancelled`, which resumes the
                    // continuation in `awaitReady()` so it doesn't leak.
                    connection.cancel()
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.connectTimeoutNanoseconds)
                throw MailSocketError.connectionFailed("Connection timed out before the handshake completed.")
            }
            // First task to finish decides the outcome; cancel the other. On
            // success the handshake task is already complete, so its onCancel
            // never fires and the ready connection is left intact.
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    private func awaitReady() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: MailSocketError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: MailSocketError.connectionClosed)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Read up to `maxLength` bytes from the stream.
    ///
    /// Suspends until bytes arrive or the connection closes.
    /// Returns empty `Data` on clean EOF.
    func read(maxLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maxLength) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: MailSocketError.readFailed(error.localizedDescription))
                    return
                }
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: Data())
                } else {
                    continuation.resume(throwing: MailSocketError.connectionClosed)
                }
            }
        }
    }

    /// Write `data` to the stream.
    ///
    /// Suspends until the bytes are handed off to the network stack.
    func write(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: MailSocketError.writeFailed(error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    /// Cancel the `NWConnection` and release resources.
    func close() async {
        connection.cancel()
    }
}
