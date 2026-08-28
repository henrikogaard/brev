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

#if os(macOS)
@Suite("Google OAuth loopback receiver")
struct GoogleOAuthLoopbackReceiverTests {
    @Test("captures the callback on an ephemeral 127.0.0.1 port")
    @MainActor
    func capturesCallbackOnLoopback() async throws {
        let receiver = GoogleOAuthLoopbackReceiver()
        let redirectURI = try await receiver.start()
        defer { receiver.cancel() }

        let callbackTask = Task { @MainActor in
            try await receiver.waitForCallback()
        }
        let callbackURL = try #require(
            URL(string: "\(redirectURI)?code=authorization-code&state=expected-state")
        )
        let (_, response) = try await URLSession.shared.data(from: callbackURL)
        let receivedURL = try await callbackTask.value

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(receivedURL.scheme == "http")
        #expect(receivedURL.host == "127.0.0.1")
        #expect(receivedURL.path == "/oauth2redirect")
        let items = URLComponents(url: receivedURL, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first(where: { $0.name == "code" })?.value == "authorization-code")
        #expect(items?.first(where: { $0.name == "state" })?.value == "expected-state")
    }

    @Test("rejects non-callback requests without consuming the listener")
    @MainActor
    func rejectsInvalidRequestsAndRemainsReady() async throws {
        let receiver = GoogleOAuthLoopbackReceiver()
        let redirectURI = try await receiver.start()
        defer { receiver.cancel() }

        let wrongPathURL = try #require(URL(string: redirectURI)?.deletingLastPathComponent().appendingPathComponent("wrong"))
        let (_, wrongPathResponse) = try await URLSession.shared.data(from: wrongPathURL)
        #expect((wrongPathResponse as? HTTPURLResponse)?.statusCode == 404)

        var postRequest = try URLRequest(url: #require(URL(string: redirectURI)))
        postRequest.httpMethod = "POST"
        let (_, postResponse) = try await URLSession.shared.data(for: postRequest)
        #expect((postResponse as? HTTPURLResponse)?.statusCode == 405)

        let callbackTask = Task { @MainActor in try await receiver.waitForCallback() }
        let callbackURL = try #require(URL(string: "\(redirectURI)?code=code&state=state"))
        let (_, callbackResponse) = try await URLSession.shared.data(from: callbackURL)
        #expect((callbackResponse as? HTTPURLResponse)?.statusCode == 200)
        #expect(try await callbackTask.value == callbackURL)
    }

    @Test("rejects a second start")
    @MainActor
    func rejectsSecondStart() async throws {
        let receiver = GoogleOAuthLoopbackReceiver()
        _ = try await receiver.start()
        defer { receiver.cancel() }

        await #expect(throws: GoogleOAuthLoopbackReceiverError.alreadyStarted) {
            try await receiver.start()
        }
    }

    @Test("cancellation releases a pending callback waiter")
    @MainActor
    func cancellationReleasesPendingWaiter() async throws {
        let receiver = GoogleOAuthLoopbackReceiver()
        _ = try await receiver.start()
        let callbackTask = Task { @MainActor in try await receiver.waitForCallback() }
        await Task.yield()

        receiver.cancel()

        await #expect(throws: GoogleOAuthLoopbackReceiverError.cancelled) {
            try await callbackTask.value
        }
    }

    @Test("cancellation before waiting is retained")
    @MainActor
    func cancellationBeforeWaitingIsRetained() async throws {
        let receiver = GoogleOAuthLoopbackReceiver()
        _ = try await receiver.start()
        receiver.cancel()
        try await Task.sleep(for: .milliseconds(50))
        let startedAt = Date()
        let fallbackCancellation = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            receiver.cancel()
        }
        defer { fallbackCancellation.cancel() }

        await #expect(throws: GoogleOAuthLoopbackReceiverError.cancelled) {
            try await receiver.waitForCallback()
        }
        #expect(Date().timeIntervalSince(startedAt) < 0.1)
    }

    @Test("only the first concurrent callback is accepted")
    @MainActor
    func onlyFirstConcurrentCallbackIsAccepted() async throws {
        let receiver = GoogleOAuthLoopbackReceiver()
        let redirectURI = try await receiver.start()
        defer { receiver.cancel() }
        let callbackTask = Task { @MainActor in try await receiver.waitForCallback() }
        let firstURL = try #require(URL(string: "\(redirectURI)?code=first&state=state"))
        let secondURL = try #require(URL(string: "\(redirectURI)?code=second&state=state"))

        async let firstStatus = responseStatus(for: firstURL)
        async let secondStatus = responseStatus(for: secondURL)
        let statuses = await [firstStatus, secondStatus]
        let receivedURL = try await callbackTask.value

        #expect(statuses.compactMap(\.self).filter { $0 == 200 }.count == 1)
        let code = URLComponents(url: receivedURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        #expect(code == "first" || code == "second")
    }

    private func responseStatus(for url: URL) async -> Int? {
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }
}
#endif
