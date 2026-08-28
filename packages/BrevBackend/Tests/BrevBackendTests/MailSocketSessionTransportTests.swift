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

// MARK: - MailSocketConnectionFactory selection

@Suite("MailSocketConnectionFactory")
struct MailSocketConnectionFactoryTests {
    @Test("implicit TLS mode produces NWConnectionSocketTransport")
    func implicitTLSProducesNWConnectionTransport() {
        let transport = MailSocketConnectionFactory.make(
            host: "imap.example.com",
            port: 993,
            tlsMode: .implicit
        )
        #expect(transport is NWConnectionSocketTransport)
    }

    @Test("starttls mode produces URLSessionStreamSocketTransport")
    func startTLSProducesSecureTransportTransport() {
        let transport = MailSocketConnectionFactory.make(
            host: "imap.example.com",
            port: 143,
            tlsMode: .starttls
        )
        #expect(transport is URLSessionStreamSocketTransport)
    }

    @Test("factory constructs NWConnectionSocketTransport for SMTP implicit port")
    func implicitSMTPTransport() {
        let transport = MailSocketConnectionFactory.make(
            host: "smtp.gmail.com",
            port: 465,
            tlsMode: .implicit
        )
        #expect(transport is NWConnectionSocketTransport)
    }
}

// MARK: - NWConnectionSocketTransport construction

@Suite("NWConnectionSocketTransport")
struct NWConnectionSocketTransportTests {
    @Test("constructs without crashing for a typical IMAP endpoint")
    func constructsForIMAPEndpoint() {
        // Just verify the object can be created without fatal errors.
        // Network operations are not exercised in unit tests (no live server).
        _ = NWConnectionSocketTransport(host: "imap.example.com", port: 993)
    }

    @Test("constructs without crashing for a typical SMTP endpoint")
    func constructsForSMTPEndpoint() {
        _ = NWConnectionSocketTransport(host: "smtp.example.com", port: 465)
    }

    @Test("conforms to MailSocketConnection protocol")
    func conformsToMailSocketConnection() {
        let _: any MailSocketConnection = NWConnectionSocketTransport(
            host: "imap.example.com",
            port: 993
        )
    }
}

// MARK: - URLSessionStreamSocketTransport construction

@Suite("URLSessionStreamSocketTransport")
struct URLSessionStreamSocketTransportTests {
    @Test("constructs without crashing for a STARTTLS IMAP endpoint")
    func constructsForStartTLSEndpoint() {
        _ = URLSessionStreamSocketTransport(host: "imap.example.com", port: 143)
    }

    @Test("conforms to MailSocketConnection protocol")
    func conformsToMailSocketConnection() {
        let _: any MailSocketConnection = URLSessionStreamSocketTransport(
            host: "imap.example.com",
            port: 143
        )
    }
}

// MARK: - MailSocketContinuationGate

@Suite("MailSocketContinuationGate")
struct MailSocketContinuationGateTests {
    @Test("ignores duplicate resumes from stream callbacks")
    func ignoresDuplicateResumes() async throws {
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let gate = MailSocketContinuationGate<String>(continuation)

            #expect(gate.resume(returning: "first"))
            #expect(!gate.resume(throwing: MailSocketError.readFailed("late cancellation")))
        }

        #expect(result == "first")
    }
}

// MARK: - NetworkIMAPSessionTransport with scripted socket

@Suite("NetworkIMAPSessionTransport")
struct NetworkIMAPSessionTransportTests {
    @Test("constructs with no-arg init")
    func constructsWithNoArgInit() {
        _ = NetworkIMAPSessionTransport()
    }

    @Test("constructs with injected scripted socket")
    func constructsWithScriptedSocket() {
        let config = IMAPConfiguration(host: "imap.gmail.com")
        let scripted = ScriptedSocket(lines: [
            "* OK Gimap ready",
            "A0001 OK Begin TLS"
        ])
        _ = NetworkIMAPSessionTransport(configuration: config, socket: scripted)
    }

    @Test("writeLine sends CRLF-terminated bytes to injected socket")
    @available(macOS 14, iOS 17, *)
    func writeLineSendsCRLF() async throws {
        let config = IMAPConfiguration(host: "imap.example.com", port: 993, tlsMode: .implicit)
        let scripted = ScriptedSocket(lines: ["* OK Ready"])
        let transport = NetworkIMAPSessionTransport(configuration: config, socket: scripted)
        try await transport.writeLine("A0001 NOOP")
        let sent = scripted.sentLines
        #expect(sent.contains("A0001 NOOP\r\n"))
    }

    @Test("readData consumes literal bytes already buffered by readLine")
    func readDataConsumesBufferedLiteralBytes() async throws {
        let literal = "Project update"
        let chunk = Data(
            #"* 9 FETCH (UID 56 FLAGS () ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" {\#(literal.utf8.count)}"#
                .utf8
        )
            + Data("\r\n\(literal)))\r\nA0001 OK FETCH completed\r\n".utf8)
        let config = IMAPConfiguration(host: "imap.example.com", port: 993, tlsMode: .implicit)
        let scripted = ScriptedSocket(chunks: [chunk])
        let transport = NetworkIMAPSessionTransport(configuration: config, socket: scripted)

        let line = try await transport.readLine()
        let data = try await transport.readData(maxLength: literal.utf8.count)
        let suffix = try await transport.readLine()
        let completion = try await transport.readLine()

        #expect(line.hasSuffix("{\(literal.utf8.count)}"))
        #expect(String(data: data, encoding: .utf8) == literal)
        #expect(suffix == "))")
        #expect(completion == "A0001 OK FETCH completed")
    }

    @Test("readLine separates LF-terminated responses after buffered literals")
    func readLineSeparatesLFTerminatedResponsesAfterBufferedLiterals() async throws {
        let literal = "Project update"
        let chunk = Data(
            #"* 9 FETCH (UID 55 FLAGS () ENVELOPE ("Sat, 06 Jun 2026 12:00:00 +0000" {\#(literal.utf8.count)}"#
                .utf8
        )
            + Data("\n\(literal)))\n* 10 FETCH (UID 56 FLAGS () ENVELOPE NIL)\nA0001 OK FETCH completed\n".utf8)
        let config = IMAPConfiguration(host: "imap.example.com", port: 993, tlsMode: .implicit)
        let scripted = ScriptedSocket(chunks: [chunk])
        let transport = NetworkIMAPSessionTransport(configuration: config, socket: scripted)

        _ = try await transport.readLine()
        _ = try await transport.readData(maxLength: literal.utf8.count)
        let suffix = try await transport.readLine()
        let nextFetch = try await transport.readLine()
        let completion = try await transport.readLine()

        #expect(suffix == "))")
        #expect(nextFetch == "* 10 FETCH (UID 56 FLAGS () ENVELOPE NIL)")
        #expect(completion == "A0001 OK FETCH completed")
    }

    @Test("discard a read result that arrives after transport teardown")
    func discardsReadResultAfterTransportTeardown() async throws {
        let config = IMAPConfiguration(host: "imap.example.com", port: 993, tlsMode: .implicit)
        let socket = DelayedSocket()
        let transport = NetworkIMAPSessionTransport(configuration: config, socket: socket)
        let readTask = Task { try await transport.readLine() }

        await socket.waitUntilReadStarted()
        await transport.disconnect()
        await socket.release(Data("stale response\r\n".utf8))

        await #expect(throws: IMAPClientError.transport("IMAP transport session changed while reading.")) {
            _ = try await readTask.value
        }
    }
}

// MARK: - NetworkSMTPSessionTransport with scripted socket

@Suite("NetworkSMTPSessionTransport")
struct NetworkSMTPSessionTransportTests {
    @Test("constructs with no-arg init")
    func constructsWithNoArgInit() {
        _ = NetworkSMTPSessionTransport()
    }

    @Test("constructs with injected scripted socket")
    func constructsWithScriptedSocket() {
        let config = SMTPConfiguration(host: "smtp.gmail.com", port: 465)
        let scripted = ScriptedSocket(lines: [
            "220 smtp.gmail.com ESMTP ready",
            "250 Hello"
        ])
        _ = NetworkSMTPSessionTransport(configuration: config, socket: scripted)
    }

    @Test("writeLine sends CRLF-terminated bytes to injected socket")
    @available(macOS 14, iOS 17, *)
    func writeLineSendsCRLF() async throws {
        let config = SMTPConfiguration(host: "smtp.example.com", port: 465, tlsMode: .implicit)
        let scripted = ScriptedSocket(lines: ["220 smtp.example.com ready"])
        let transport = NetworkSMTPSessionTransport(configuration: config, socket: scripted)
        try await transport.writeLine("EHLO localhost")
        let sent = scripted.sentLines
        #expect(sent.contains("EHLO localhost\r\n"))
    }
}

// MARK: - MailSocketError

@Suite("MailSocketError")
struct MailSocketErrorTests {
    @Test("connectionFailed carries reason in localizedDescription")
    func connectionFailedDescription() {
        let error = MailSocketError.connectionFailed("TLS handshake timed out")
        #expect(error.localizedDescription.contains("TLS handshake timed out"))
    }

    @Test("connectionClosed has readable description")
    func connectionClosedDescription() {
        let error = MailSocketError.connectionClosed
        #expect(!error.localizedDescription.isEmpty)
    }

    @Test("readFailed carries reason")
    func readFailedDescription() {
        let error = MailSocketError.readFailed("errno 32")
        #expect(error.localizedDescription.contains("errno 32"))
    }

    @Test("writeFailed carries reason")
    func writeFailedDescription() {
        let error = MailSocketError.writeFailed("send failed")
        #expect(error.localizedDescription.contains("send failed"))
    }

    @Test("MailSocketError values are Equatable")
    func equatable() {
        #expect(MailSocketError.connectionClosed == MailSocketError.connectionClosed)
        #expect(MailSocketError.connectionFailed("x") == MailSocketError.connectionFailed("x"))
        #expect(MailSocketError.connectionFailed("x") != MailSocketError.connectionFailed("y"))
    }
}

// MARK: - ScriptedSocket (test double)

/// A scripted `MailSocketConnection` that returns pre-canned lines and
/// records everything written to it.
///
/// Lines are returned one at a time, suffixed with `\r\n`.
/// `connect()` and `close()` are no-ops.
final class ScriptedSocket: MailSocketConnection, @unchecked Sendable {
    private var lines: [String]
    private var chunks: [Data]
    private(set) var sentLines: [String] = []
    private let lock = NSLock()

    init(lines: [String]) {
        self.lines = lines
        chunks = []
    }

    init(chunks: [Data]) {
        lines = []
        self.chunks = chunks
    }

    func connect() async throws { /* no-op */ }

    func read(maxLength: Int) async throws -> Data {
        lock.withLock {
            if !chunks.isEmpty {
                let chunk = chunks.removeFirst()
                guard chunk.count > maxLength else { return chunk }

                chunks.insert(chunk.dropFirst(maxLength), at: 0)
                return chunk.prefix(maxLength)
            }

            guard !lines.isEmpty else { return Data() }
            let line = lines.removeFirst() + "\r\n"
            return Data(line.utf8)
        }
    }

    func write(_ data: Data) async throws {
        lock.withLock {
            if let text = String(data: data, encoding: .utf8) {
                sentLines.append(text)
            }
        }
    }

    func close() async { /* no-op */ }
}

private actor DelayedSocketState {
    var readContinuation: CheckedContinuation<Data, Error>?
    var readStarted = false
}

private final class DelayedSocket: MailSocketConnection, @unchecked Sendable {
    private let state = DelayedSocketState()

    func connect() async throws {}

    func read(maxLength: Int) async throws -> Data {
        _ = maxLength
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await state.setReadContinuation(continuation)
            }
        }
    }

    func write(_ data: Data) async throws { _ = data }
    func close() async {}

    func waitUntilReadStarted() async {
        while await !(state.readStarted) {
            await Task.yield()
        }
    }

    func release(_ data: Data) async {
        guard let continuation = await state.takeReadContinuation() else { return }
        continuation.resume(returning: data)
    }
}

private extension DelayedSocketState {
    func setReadContinuation(_ continuation: CheckedContinuation<Data, Error>) {
        readContinuation = continuation
        readStarted = true
    }

    func takeReadContinuation() -> CheckedContinuation<Data, Error>? {
        defer { readContinuation = nil }
        return readContinuation
    }
}
