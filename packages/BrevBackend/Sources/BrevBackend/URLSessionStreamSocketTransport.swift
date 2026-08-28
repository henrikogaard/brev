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

// STARTTLS transport built on URLSessionStreamTask.
//
// URLSessionStreamTask supports in-place TLS upgrade via
// `startSecureConnection()`. This transport intentionally avoids the retired
// SecureTransport (SSLCreateContext / SSLHandshake) APIs.
//
// The session layer issues the plaintext STARTTLS command over the plain TCP
// stream, waits for the server acknowledgement, then calls `upgradeToTLS()`.
// `upgradeToTLS()` calls `task.startSecureConnection()`, which performs the
// TLS handshake on the existing byte stream without tearing down the TCP
// connection — exactly what STARTTLS requires.

import Foundation

// MARK: - URLSessionStreamSocketTransport

/// STARTTLS-capable socket transport using `URLSessionStreamTask`.
///
/// `URLSessionStreamTask.startSecureConnection()` performs an in-place
/// TLS upgrade on the existing TCP connection, satisfying the STARTTLS
/// protocol requirement.
///
/// Prefer `NWConnectionSocketTransport` for implicit-TLS connections
/// (port 993 IMAP / 465 SMTP). This transport is for STARTTLS ports only
/// (port 143 IMAP / 587 SMTP).
///
/// Do not instantiate directly; go through `MailSocketConnectionFactory.make`.
final class URLSessionStreamSocketTransport: MailSocketConnection, @unchecked Sendable {
    // @unchecked Sendable: `task` is set once in `connect()` and thereafter
    // only read. URLSession and URLSessionStreamTask are thread-safe by
    // contract.

    private let host: String
    private let port: UInt16

    private let session: URLSession
    private var task: URLSessionStreamTask?

    /// Read timeout passed to URLSessionStreamTask. Long enough to survive
    /// slow servers; callers should apply their own higher-level timeouts.
    private let readTimeout: TimeInterval = 30
    /// Write timeout passed to URLSessionStreamTask.
    private let writeTimeout: TimeInterval = 30

    /// Creates a transport for a STARTTLS-capable mail server.
    ///
    /// - Parameters:
    ///   - host: Hostname or IP address of the mail server.
    ///   - port: TCP port (typically 143 IMAP, 587 SMTP).
    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
        session = URLSession(configuration: .ephemeral)
    }

    // MARK: - MailSocketConnection

    /// Opens a plain TCP connection. No TLS is established at this point.
    ///
    /// The caller must issue the STARTTLS command at the application-protocol
    /// layer (IMAP: `STARTTLS\r\n`, SMTP: `STARTTLS\r\n`), read the server
    /// acknowledgement, and then call `upgradeToTLS()`.
    ///
    /// `URLSessionStreamTask` does not surface a "connected" event; TCP errors
    /// appear on the first subsequent read or write.
    func connect() async throws {
        let streamTask = session.streamTask(withHostName: host, port: Int(port))
        task = streamTask
        streamTask.resume()
    }

    /// Read up to `maxLength` bytes from the stream.
    ///
    /// After `upgradeToTLS()` has been called the data is decrypted by the
    /// TLS layer transparently; the caller sees the same API either way.
    func read(maxLength: Int) async throws -> Data {
        guard let task else {
            throw MailSocketError.connectionFailed("read called before connect()")
        }
        return try await withCheckedThrowingContinuation { continuation in
            let gate = MailSocketContinuationGate<Data>(continuation)
            task.readData(
                ofMinLength: 1,
                maxLength: maxLength,
                timeout: readTimeout
            ) { data, atEOF, error in
                if let error {
                    gate.resume(throwing: MailSocketError.readFailed(error.localizedDescription))
                    return
                }
                if let data, !data.isEmpty {
                    gate.resume(returning: data)
                } else if atEOF {
                    gate.resume(returning: Data())
                } else {
                    gate.resume(throwing: MailSocketError.connectionClosed)
                }
            }
        }
    }

    /// Write `data` to the stream.
    ///
    /// Suspends until the bytes are accepted by the stream task.
    func write(_ data: Data) async throws {
        guard let task else {
            throw MailSocketError.connectionFailed("write called before connect()")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = MailSocketContinuationGate<Void>(continuation)
            task.write(data, timeout: writeTimeout) { error in
                if let error {
                    gate.resume(throwing: MailSocketError.writeFailed(error.localizedDescription))
                } else {
                    gate.resume(returning: ())
                }
            }
        }
    }

    /// Close the stream. Idempotent.
    func close() async {
        task?.closeRead()
        task?.closeWrite()
        task?.cancel()
        task = nil
    }

    // MARK: - TLS upgrade

    /// Upgrade the existing plain-TCP connection to TLS in-place.
    ///
    /// Call this after the server has acknowledged the STARTTLS command.
    /// The session transport is responsible for issuing the STARTTLS command
    /// and consuming the server acknowledgement before calling this method.
    ///
    /// `URLSessionStreamTask.startSecureConnection()` performs the TLS
    /// handshake on the existing byte stream. Subsequent reads and writes
    /// go through the TLS layer automatically.
    ///
    /// `startSecureConnection()` does not await the handshake — it merely
    /// enqueues it — so certificate failures would otherwise only surface on a
    /// later read of application data. To fail fast on an untrusted or
    /// mismatched certificate, this method forces the handshake to complete by
    /// issuing a minimal read immediately after enqueuing the upgrade. Any TLS
    /// negotiation error is raised here, before LOGIN credentials are sent.
    ///
    /// The probe read uses `ofMinLength: 0` so it returns as soon as the
    /// handshake settles without consuming any post-STARTTLS server bytes: the
    /// next protocol-level `readLine()` still sees the server's response intact.
    ///
    /// Throws `MailSocketError.connectionFailed` if called before `connect()`.
    func upgradeToTLS() async throws {
        guard let task else {
            throw MailSocketError.connectionFailed("upgradeToTLS called before connect()")
        }
        task.startSecureConnection()
        try await forceHandshakeCompletion(task: task)
    }

    /// Drives the enqueued TLS handshake to completion so certificate errors
    /// surface synchronously rather than on a later application read.
    ///
    /// Reads with `ofMinLength: 0`, which completes once the handshake settles
    /// without waiting for (or consuming) any application data; the IMAP/SMTP
    /// session layer then reads the post-STARTTLS server response normally.
    private func forceHandshakeCompletion(task: URLSessionStreamTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = MailSocketContinuationGate<Void>(continuation)
            task.readData(
                ofMinLength: 0,
                maxLength: 0,
                timeout: readTimeout
            ) { _, _, error in
                if let error {
                    gate.resume(
                        throwing: MailSocketError.connectionFailed(
                            "TLS handshake failed: \(error.localizedDescription)"
                        )
                    )
                } else {
                    gate.resume(returning: ())
                }
            }
        }
    }
}
