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

// MARK: - MailSocketConnection protocol

/// Low-level byte-stream abstraction used by IMAP and SMTP session transports.
///
/// Concrete implementations (`NWConnectionSocketTransport` for implicit TLS,
/// `URLSessionStreamSocketTransport` for STARTTLS) hide the TLS stack from
/// the session layer. The session transport chooses the implementation via
/// `MailSocketConnectionFactory.make(host:port:tlsMode:)`.
///
/// All reads and writes are async/await. Implementations must serialize
/// concurrent calls internally.
public protocol MailSocketConnection: AnyObject, Sendable {
    /// Opens the connection, including the TLS handshake.
    ///
    /// Throws `MailSocketError.connectionFailed` if the host is unreachable
    /// or the TLS handshake fails.
    func connect() async throws

    /// Read up to `maxLength` bytes from the stream.
    ///
    /// Returns an empty `Data` when the server signals EOF.
    ///
    /// - Parameter maxLength: Maximum number of bytes to return in one call.
    func read(maxLength: Int) async throws -> Data

    /// Write `data` to the stream.
    ///
    /// - Parameter data: Bytes to send; must be non-empty.
    func write(_ data: Data) async throws

    /// Close the connection. Idempotent.
    func close() async
}

// MARK: - MailSocketError

/// Errors a `MailSocketConnection` may throw.
public enum MailSocketError: Error, Sendable, Equatable {
    /// TCP or TLS connection setup failed.
    case connectionFailed(String)
    /// A read from the stream failed.
    case readFailed(String)
    /// A write to the stream failed.
    case writeFailed(String)
    /// Connection was closed unexpectedly by the remote end.
    case connectionClosed
}

extension MailSocketError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            String(localized: "Connection failed: \(reason)", bundle: .module)
        case .readFailed(let reason):
            String(localized: "Read failed: \(reason)", bundle: .module)
        case .writeFailed(let reason):
            String(localized: "Write failed: \(reason)", bundle: .module)
        case .connectionClosed:
            String(localized: "Connection closed by server.", bundle: .module)
        }
    }
}

// MARK: - Factory

/// Selects the appropriate `MailSocketConnection` implementation for the
/// requested TLS mode.
///
/// - `.implicit` → `NWConnectionSocketTransport` (Network.framework `NWConnection`
///   with `NWProtocolTLS`). Preferred for port 993 / 465.
/// - `.starttls` → `URLSessionStreamSocketTransport` (`URLSessionStreamTask`
///   in-place TLS upgrade). Used for IMAP 143 / SMTP 587 STARTTLS endpoints.
public enum MailSocketConnectionFactory {
    /// Creates a new, unconnected socket transport for the given endpoint.
    ///
    /// Call `connect()` on the returned object to open the socket and complete
    /// the TLS handshake before issuing any reads or writes.
    ///
    /// - Parameters:
    ///   - host: DNS hostname or IP address of the mail server.
    ///   - port: TCP port number.
    ///   - tlsMode: Whether to use implicit TLS (`NWConnection`) or STARTTLS
    ///     upgrade (`URLSessionStreamTask.startSecureConnection()`).
    public static func make(
        host: String,
        port: UInt16,
        tlsMode: TLSMode
    ) -> any MailSocketConnection {
        switch tlsMode {
        case .implicit:
            return NWConnectionSocketTransport(host: host, port: port)
        case .starttls:
            return URLSessionStreamSocketTransport(host: host, port: port)
        }
    }

    /// TLS connection mode.
    public enum TLSMode: String, Sendable, Equatable {
        /// Implicit TLS from the first byte (e.g. port 993 IMAP, 465 SMTP).
        case implicit
        /// Plain connection upgraded to TLS via STARTTLS (e.g. port 143 IMAP,
        /// 587 SMTP).
        case starttls
    }
}
