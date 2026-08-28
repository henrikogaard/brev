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

// MARK: - In-memory token store for tests

actor InMemoryTokenStore: TokenStore {
    private var tokens: [String: Token] = [:]

    func token(for accountID: String) -> Token? {
        tokens[accountID]
    }

    func setToken(_ token: Token, for accountID: String) {
        tokens[accountID] = token
    }

    func clearToken(for accountID: String) {
        tokens.removeValue(forKey: accountID)
    }
}

// MARK: - Mock URLSession / protocol

/// Captures outbound requests and returns scripted responses.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeResponse(statusCode: Int, body: String) -> (HTTPURLResponse, Data) {
    let url = URL(string: "https://oauth2.googleapis.com/token")!
    let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    return (response, Data(body.utf8))
}

/// Reads a request's POST body. URLSession converts `httpBody` to an
/// `httpBodyStream` by the time `URLProtocol` sees the request, so handle both.
private func requestBodyString(_ request: URLRequest) -> String {
    if let data = request.httpBody {
        return String(decoding: data, as: UTF8.self)
    }
    guard let stream = request.httpBodyStream else { return "" }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bufferSize)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return String(decoding: data, as: UTF8.self)
}

private final class CapturedBody: @unchecked Sendable {
    var value = ""
}

private enum RefreshProbeError: Error, Equatable {
    case firstAttempt
}

private actor RefreshProbe {
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var startCount = 0
    private var shouldFail = true
    private var isReleased = false

    func refresh(returning token: Token) async throws -> Token {
        startCount += 1
        resumeStartWaiters()
        if !isReleased {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
        return token
    }

    func failFirstThenReturn(_ token: Token) async throws -> Token {
        startCount += 1
        resumeStartWaiters()
        guard shouldFail else { return token }
        shouldFail = false
        throw RefreshProbeError.firstAttempt
    }

    func waitUntilStarted(count: Int) async {
        guard startCount < count else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((count, continuation))
        }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func resumeStartWaiters() {
        let ready = startWaiters.filter { $0.count <= startCount }
        startWaiters.removeAll { $0.count <= startCount }
        ready.forEach { $0.continuation.resume() }
    }
}

// MARK: - Tests

@Suite("OAuthTokenRefresher", .serialized)
struct OAuthTokenRefresherTests {
    @Test("coalesces concurrent refreshes per account")
    func coalescesConcurrentRefreshesPerAccount() async throws {
        let coordinator = OAuthRefreshCoordinator()
        let probe = RefreshProbe()
        let expected = Token(accessToken: "fresh", refreshToken: "rotated", expiresAt: .distantFuture)

        let first = Task {
            try await coordinator.run(for: "account-a") {
                try await probe.refresh(returning: expected)
            }
        }
        await probe.waitUntilStarted(count: 1)

        let second = Task {
            try await coordinator.run(for: "account-a") {
                try await probe.refresh(returning: expected)
            }
        }
        await Task.yield()

        #expect(await probe.startCount == 1)
        await probe.release()
        #expect(try await first.value == expected)
        #expect(try await second.value == expected)
        #expect(await probe.startCount == 1)
    }

    @Test("allows refreshes for different accounts to proceed independently")
    func allowsDifferentAccountsToProceedIndependently() async throws {
        let coordinator = OAuthRefreshCoordinator()
        let probe = RefreshProbe()
        let expected = Token(accessToken: "fresh", refreshToken: "rotated", expiresAt: .distantFuture)

        let first = Task {
            try await coordinator.run(for: "account-a") {
                try await probe.refresh(returning: expected)
            }
        }
        let second = Task {
            try await coordinator.run(for: "account-b") {
                try await probe.refresh(returning: expected)
            }
        }

        await probe.waitUntilStarted(count: 2)
        #expect(await probe.startCount == 2)
        await probe.release()
        #expect(try await first.value == expected)
        #expect(try await second.value == expected)
    }

    @Test("clears a failed refresh so the next attempt can retry")
    func clearsFailedRefreshForRetry() async throws {
        let coordinator = OAuthRefreshCoordinator()
        let probe = RefreshProbe()
        let expected = Token(accessToken: "fresh", refreshToken: "rotated", expiresAt: .distantFuture)

        let failed = Task {
            try await coordinator.run(for: "account-a") {
                try await probe.failFirstThenReturn(expected)
            }
        }
        await #expect(throws: RefreshProbeError.firstAttempt) {
            try await failed.value
        }

        let retried = try await coordinator.run(for: "account-a") {
            try await probe.failFirstThenReturn(expected)
        }
        #expect(retried == expected)
        #expect(await probe.startCount == 2)
    }

    @Test("parses a successful refresh response correctly")
    func parsesSuccessResponse() async throws {
        let store = InMemoryTokenStore()
        let refreshTokenExpiresAt = Date(timeIntervalSince1970: 123_456)
        let existingToken = Token(
            accessToken: "old-access",
            refreshToken: "refresh-token-123",
            expiresAt: Date(),
            refreshTokenExpiresAt: refreshTokenExpiresAt,
            oauthMetadata: OAuthTokenMetadata(
                providerMode: .gmailAPI,
                googleSubject: "stable-subject",
                hostedDomain: "ogard.no",
                grantedScopes: ["openid", "email"]
            )
        )
        await store.setToken(existingToken, for: "account-1")

        MockURLProtocol.handler = { _ in
            makeResponse(statusCode: 200, body: """
                {
                    "access_token": "new-access-token",
                    "expires_in": 3600,
                    "token_type": "Bearer"
                }
            """)
        }

        let refresher = OAuthTokenRefresher(
            clientID: "test-client-id",
            clientSecret: "test-client-secret",
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
            urlSession: makeMockSession(),
            tokenStore: store
        )

        let token = try await refresher.refresh(for: "account-1")

        #expect(token.accessToken == "new-access-token")
        // Refresh token should be preserved from the stored token.
        #expect(token.refreshToken == "refresh-token-123")
        // Expiry should be roughly 3600 seconds from now.
        #expect(token.expiresAt.timeIntervalSinceNow > 3500)
        #expect(token.expiresAt.timeIntervalSinceNow < 3700)
        #expect(token.refreshTokenExpiresAt == refreshTokenExpiresAt)
        #expect(token.oauthMetadata == existingToken.oauthMetadata)
    }

    @Test("native refresh omits an empty client secret")
    func nativeRefreshOmitsEmptyClientSecret() async throws {
        let store = InMemoryTokenStore()
        await store.setToken(
            Token(accessToken: "old", refreshToken: "refresh", expiresAt: Date()),
            for: "account-native"
        )
        let captured = CapturedBody()
        MockURLProtocol.handler = { request in
            captured.value = requestBodyString(request)
            return makeResponse(statusCode: 200, body: #"{"access_token":"new","expires_in":3600}"#)
        }

        let refresher = OAuthTokenRefresher(
            clientID: "native-client",
            clientSecret: "",
            urlSession: makeMockSession(),
            tokenStore: store
        )
        _ = try await refresher.refresh(for: "account-native")

        #expect(!captured.value.contains("client_secret"))
    }

    @Test("preserves original refresh token when server omits it")
    func preservesRefreshTokenWhenOmitted() async throws {
        let store = InMemoryTokenStore()
        let existingToken = Token(
            accessToken: "old-access",
            refreshToken: "original-refresh-token",
            expiresAt: Date()
        )
        await store.setToken(existingToken, for: "account-a")

        MockURLProtocol.handler = { _ in
            makeResponse(statusCode: 200, body: """
                { "access_token": "new-access", "expires_in": 3600 }
            """)
        }

        let refresher = OAuthTokenRefresher(
            clientID: "cid",
            clientSecret: "csec",
            urlSession: makeMockSession(),
            tokenStore: store
        )

        let token = try await refresher.refresh(for: "account-a")
        #expect(token.refreshToken == "original-refresh-token")
    }

    @Test("updates stored token after successful refresh")
    func updatesStoredToken() async throws {
        let store = InMemoryTokenStore()
        let existing = Token(
            accessToken: "old",
            refreshToken: "refresh-xyz",
            expiresAt: Date()
        )
        await store.setToken(existing, for: "acc")

        MockURLProtocol.handler = { _ in
            makeResponse(statusCode: 200, body: """
                { "access_token": "brand-new", "refresh_token": "rotated-refresh", "expires_in": 3600 }
            """)
        }

        let refresher = OAuthTokenRefresher(
            clientID: "c",
            clientSecret: "s",
            urlSession: makeMockSession(),
            tokenStore: store
        )

        _ = try await refresher.refresh(for: "acc")
        let stored = await store.token(for: "acc")
        #expect(stored?.accessToken == "brand-new")
        #expect(stored?.refreshToken == "rotated-refresh")
    }

    @Test("throws refreshFailed when server returns non-200")
    func throwsOnNon200Response() async throws {
        let store = InMemoryTokenStore()
        await store.setToken(
            Token(accessToken: "a", refreshToken: "r", expiresAt: Date()),
            for: "acc"
        )

        MockURLProtocol.handler = { _ in
            makeResponse(statusCode: 401, body: #"{"error":"invalid_grant"}"#)
        }

        let refresher = OAuthTokenRefresher(
            clientID: "c",
            clientSecret: "s",
            urlSession: makeMockSession(),
            tokenStore: store
        )

        await #expect(throws: OAuthRefreshError.reauthenticationRequired) {
            try await refresher.refresh(for: "acc")
        }
    }

    @Test("permanent refresh failures are marked as requiring sign-in")
    func permanentRefreshFailureRequiresSignIn() {
        #expect(OAuthRefreshError.reauthenticationRequired.isPermanent)
        #expect(OAuthRefreshError.missingRefreshToken.isPermanent)
        #expect(!OAuthRefreshError.refreshFailed(statusCode: 503, bodyByteCount: 0).isPermanent)
    }

    @Test("non-200 refresh failures retain only safe response metadata")
    func non200RefreshFailureRedactsBody() async throws {
        let store = InMemoryTokenStore()
        await store.setToken(
            Token(accessToken: "a", refreshToken: "r", expiresAt: Date()),
            for: "acc"
        )
        let secret = "secret-token-fragment-xyz"
        let body = #"{"error":"temporarily_unavailable","access_token":"\#(secret)"}"#
        MockURLProtocol.handler = { _ in
            makeResponse(statusCode: 401, body: body)
        }

        let refresher = OAuthTokenRefresher(
            clientID: "c",
            clientSecret: "s",
            urlSession: makeMockSession(),
            tokenStore: store
        )

        do {
            try await refresher.refresh(for: "acc")
            Issue.record("Expected refresh to fail")
        } catch let error as OAuthRefreshError {
            let description = error.errorDescription ?? ""
            let value = String(describing: error)
            #expect(description.contains("401"))
            #expect(!description.contains(secret))
            #expect(!value.contains(secret))
        }
    }

    @Test("malformed refresh responses keep response bodies out of the error")
    func malformedResponseRedactsBody() async throws {
        let store = InMemoryTokenStore()
        await store.setToken(
            Token(accessToken: "a", refreshToken: "r", expiresAt: Date()),
            for: "acc"
        )
        let body = #"not-json secret-token-fragment-xyz"#
        MockURLProtocol.handler = { _ in
            makeResponse(statusCode: 200, body: body)
        }

        let refresher = OAuthTokenRefresher(
            clientID: "c",
            clientSecret: "s",
            urlSession: makeMockSession(),
            tokenStore: store
        )

        await #expect(throws: OAuthRefreshError.malformedResponse(reason: "could not decode JSON")) {
            try await refresher.refresh(for: "acc")
        }
    }

    @Test("throws missingRefreshToken when no token is stored for the account")
    func throwsWhenNoStoredToken() async throws {
        let store = InMemoryTokenStore()
        let refresher = OAuthTokenRefresher(
            clientID: "c",
            clientSecret: "s",
            urlSession: makeMockSession(),
            tokenStore: store
        )

        await #expect(throws: OAuthRefreshError.missingRefreshToken) {
            try await refresher.refresh(for: "no-such-account")
        }
    }

    @Test("raw refresh token overload stores token when accountID is provided")
    func rawRefreshStoresToAccountID() async throws {
        let store = InMemoryTokenStore()

        MockURLProtocol.handler = { _ in
            makeResponse(statusCode: 200, body: """
                { "access_token": "direct-new", "expires_in": 3600 }
            """)
        }

        let refresher = OAuthTokenRefresher(
            clientID: "c",
            clientSecret: "s",
            urlSession: makeMockSession(),
            tokenStore: store
        )

        let token = try await refresher.refresh(
            refreshToken: "raw-refresh-token",
            storeTo: "new-account"
        )

        #expect(token.accessToken == "direct-new")
        let stored = await store.token(for: "new-account")
        #expect(stored?.accessToken == "direct-new")
    }

    @Test("raw refresh token overload throws missingRefreshToken when token is empty")
    func rawRefreshThrowsOnEmptyToken() async throws {
        let store = InMemoryTokenStore()
        let refresher = OAuthTokenRefresher(
            clientID: "c",
            clientSecret: "s",
            urlSession: makeMockSession(),
            tokenStore: store
        )

        await #expect(throws: OAuthRefreshError.missingRefreshToken) {
            try await refresher.refresh(refreshToken: "", storeTo: nil)
        }
    }

    // Regression: a refresh token containing + and / (the standard-base64
    // alphabet Microsoft uses) must be percent-encoded in the form body. The
    // old URLComponents encoder left + literal, which the server decodes as a
    // space → invalid_grant → forced re-sign-in on every refresh.
    @Test("refresh form body percent-encodes a + and / bearing refresh token")
    func refreshFormBodyEncodesSpecialCharsToken() async throws {
        let store = InMemoryTokenStore()
        await store.setToken(
            Token(accessToken: "old", refreshToken: "M.C5+a/bQ8==", expiresAt: Date()),
            for: "acc"
        )

        let captured = CapturedBody()
        MockURLProtocol.handler = { request in
            captured.value = requestBodyString(request)
            return makeResponse(statusCode: 200, body: """
                {"access_token": "new", "expires_in": 3600, "token_type": "Bearer"}
            """)
        }

        let refresher = OAuthTokenRefresher(
            clientID: "id",
            clientSecret: "secret",
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
            urlSession: makeMockSession(),
            tokenStore: store
        )
        _ = try await refresher.refresh(for: "acc")

        #expect(captured.value.contains("refresh_token=M.C5%2Ba%2FbQ8%3D%3D"))
        // The corrupting literal + / must not appear in the form body.
        #expect(!captured.value.contains("M.C5+a/bQ8"))
    }
}
