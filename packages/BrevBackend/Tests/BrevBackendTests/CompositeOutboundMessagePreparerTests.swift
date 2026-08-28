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

private struct FailingPreparer: OutboundMessagePreparing {
    let error: any Error
    func prepare(mimeData: Data, request: OutboundMessageSecurityRequest) async throws -> Data {
        throw error
    }
}

private struct SucceedingPreparer: OutboundMessagePreparing {
    let output: Data
    let onCalled: @Sendable () -> Void
    func prepare(mimeData: Data, request: OutboundMessageSecurityRequest) async throws -> Data {
        onCalled()
        return output
    }
}

private struct OtherError: Error {}

private let req = OutboundMessageSecurityRequest(senderEmail: "a@x.com", to: ["b@x.com"], mode: .sign)
private let plaintext = Data("plain".utf8)
private let prepared = Data("PREPARED".utf8)

@Suite("CompositeOutboundMessagePreparer")
struct CompositeOutboundMessagePreparerTests {
    @Test("falls through to the next engine when the first lacks key material")
    func fallsThroughOnMissingKeys() async throws {
        let composite = CompositeOutboundMessagePreparer([
            FailingPreparer(error: OutboundMessageSecurityError.missingSigningIdentity(senderEmail: "a@x.com")),
            SucceedingPreparer(output: prepared, onCalled: {}),
        ])
        let out = try await composite.prepare(mimeData: plaintext, request: req)
        #expect(out == prepared)
    }

    @Test("falls through when the first engine is unavailable on this platform")
    func fallsThroughOnUnavailable() async throws {
        let composite = CompositeOutboundMessagePreparer([
            FailingPreparer(error: OutboundCryptoEngineUnavailableError(mode: .sign)),
            SucceedingPreparer(output: prepared, onCalled: {}),
        ])
        #expect(try await composite.prepare(mimeData: plaintext, request: req) == prepared)
    }

    @Test("fails closed when no engine can satisfy the request")
    func failsClosedWhenNoneSatisfy() async {
        let composite = CompositeOutboundMessagePreparer([
            FailingPreparer(error: OutboundMessageSecurityError.missingSigningIdentity(senderEmail: "a@x.com")),
            FailingPreparer(error: OutboundCryptoEngineUnavailableError(mode: .sign)),
        ])
        await #expect(throws: (any Error).self) {
            _ = try await composite.prepare(mimeData: plaintext, request: req)
        }
    }

    @Test("a real crypto failure propagates and is not retried on the next engine")
    func realFailurePropagates() async {
        let recorder = SecondCalledRecorder()
        let composite = CompositeOutboundMessagePreparer([
            FailingPreparer(error: OtherError()),
            SucceedingPreparer(output: prepared, onCalled: { recorder.markCalled() }),
        ])
        await #expect(throws: OtherError.self) {
            _ = try await composite.prepare(mimeData: plaintext, request: req)
        }
        #expect(!recorder.wasCalled)
    }

    @Test("mode .none passes through without invoking any engine")
    func nonePassthrough() async throws {
        let recorder = SecondCalledRecorder()
        let composite = CompositeOutboundMessagePreparer([
            SucceedingPreparer(output: prepared, onCalled: { recorder.markCalled() }),
        ])
        let none = OutboundMessageSecurityRequest(senderEmail: "a@x.com", to: ["b@x.com"], mode: .none)
        let out = try await composite.prepare(mimeData: plaintext, request: none)
        #expect(out == plaintext)
        #expect(!recorder.wasCalled)
    }
}

private final class SecondCalledRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var called = false
    func markCalled() { lock.withLock { called = true } }
    var wasCalled: Bool { lock.withLock { called } }
}
