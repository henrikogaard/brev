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

import BrevBackend
@testable import BrevJMAP
import Foundation
import Testing

@Suite("JMAP session discovery, HTTPS validation, and transport security")
struct JMAPSessionAndTransportTests {
    @Test("discoveryURL resolves bare domain to well-known HTTPS and preserves explicit session URL")
    func discoveryURLResolution() throws {
        let wellKnown = try JMAPURLValidator.discoveryURL(from: "fastmail.com")
        #expect(wellKnown.absoluteString == "https://fastmail.com/.well-known/jmap")

        let rootHTTPS = try JMAPURLValidator.discoveryURL(from: "https://mail.example.org")
        #expect(rootHTTPS.absoluteString == "https://mail.example.org/.well-known/jmap")

        let explicit = try JMAPURLValidator.discoveryURL(from: "https://api.fastmail.com/jmap/session")
        #expect(explicit.absoluteString == "https://api.fastmail.com/jmap/session")
    }

    @Test("strict HTTPS validator rejects http, embedded credentials, whitespace, and empty URLs")
    func rejectsInsecureURLs() {
        #expect(throws: JMAPError.invalidSessionURL(.empty)) {
            _ = try JMAPURLValidator.discoveryURL(from: "   ")
        }
        #expect(throws: JMAPError.invalidSessionURL(.httpsRequired)) {
            _ = try JMAPURLValidator.discoveryURL(from: "http://api.fastmail.com/jmap/session")
        }
        #expect(throws: JMAPError.invalidSessionURL(.httpsRequired)) {
            _ = try JMAPURLValidator.discoveryURL(from: "ftp://mail.example.org/jmap")
        }
        #expect(throws: JMAPError.invalidSessionURL(.httpsRequired)) {
            _ = try JMAPURLValidator.discoveryURL(from: "javascript:alert(1)")
        }
        #expect(throws: JMAPError.invalidSessionURL(.embeddedCredentialsForbidden)) {
            _ = try JMAPURLValidator.discoveryURL(from: "https://user:pass@api.fastmail.com/jmap/session")
        }
        #expect(throws: JMAPError.invalidSessionURL(.embeddedCredentialsForbidden)) {
            _ = try JMAPURLValidator.discoveryURL(from: "user@fastmail.com")
        }
        #expect(throws: JMAPError.invalidSessionURL(.malformed)) {
            _ = try JMAPURLValidator.discoveryURL(from: "https://api.fastmail.com/jmap session")
        }
    }

    @Test("redirect policy strips Authorization on cross-origin redirects and keeps it on same-origin")
    func redirectPolicyStripsCrossOriginAuthorization() throws {
        var original = URLRequest(url: URL(string: "https://mail.example.org/.well-known/jmap")!)
        original.setValue("Bearer super-secret-token", forHTTPHeaderField: "Authorization")
        original.setValue("sid=123", forHTTPHeaderField: "Cookie")

        // Same-origin redirect keeps Authorization.
        var sameOriginProposed = original
        sameOriginProposed.url = URL(string: "https://mail.example.org/jmap/session")!
        let sameOriginResult = try JMAPRedirectPolicy.evaluateRedirect(
            from: original,
            to: sameOriginProposed,
            redirectCount: 0
        )
        #expect(sameOriginResult.value(forHTTPHeaderField: "Authorization") == "Bearer super-secret-token")

        // Cross-origin redirect strips Authorization and Cookie when permitted (e.g. blob CDN downloads).
        var crossOriginProposed = original
        crossOriginProposed.url = URL(string: "https://api.example.org/jmap/session")!
        let crossOriginResult = try JMAPRedirectPolicy.evaluateRedirect(
            from: original,
            to: crossOriginProposed,
            redirectCount: 0
        )
        #expect(crossOriginResult.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(crossOriginResult.value(forHTTPHeaderField: "Cookie") == nil)

        // Cross-origin redirect is rejected outright on strict-origin requests (discovery/API).
        #expect(throws: JMAPError.untrustedRedirect) {
            _ = try JMAPRedirectPolicy.evaluateRedirect(
                from: original,
                to: crossOriginProposed,
                redirectCount: 0,
                allowCrossOrigin: false
            )
        }

        // Downgrade to HTTP is rejected.
        var insecureProposed = original
        insecureProposed.url = URL(string: "http://mail.example.org/jmap/session")!
        #expect(throws: JMAPError.insecureRedirect) {
            _ = try JMAPRedirectPolicy.evaluateRedirect(from: original, to: insecureProposed, redirectCount: 0)
        }

        // Redirect limit enforced.
        #expect(throws: JMAPError.tooManyRedirects) {
            _ = try JMAPRedirectPolicy.evaluateRedirect(
                from: original,
                to: sameOriginProposed,
                redirectCount: JMAPRedirectPolicy.maxRedirects
            )
        }
    }

    @Test("downloadUrl template expansion percent-encodes reserved characters and enforces HTTPS")
    func downloadURLTemplateEscaping() throws {
        let template = "https://api.fastmail.com/jmap/download/{accountId}/{blobId}/{name}?accept={type}"
        let expanded = try JMAPURLValidator.expandURITemplate(
            template,
            parameters: [
                "accountId": "u1/2",
                "blobId": "Gblob+123?foo=bar",
                "name": "Q3 Report #1 (Final).pdf",
                "type": "application/pdf"
            ]
        )
        #expect(
            expanded.absoluteString
                == "https://api.fastmail.com/jmap/download/u1%2F2/Gblob%2B123%3Ffoo%3Dbar/Q3%20Report%20%231%20%28Final%29.pdf?accept=application%2Fpdf"
        )

        #expect(throws: JMAPError.invalidSessionURL(.httpsRequired)) {
            _ = try JMAPURLValidator.expandURITemplate(
                "http://insecure.example.org/download/{blobId}",
                parameters: ["blobId": "b1"]
            )
        }
    }

    @Test("session discovery validates response endpoints and maps 401/403/429/503 without leaking token")
    func sessionDiscoveryErrorsAndRedaction() async throws {
        let secretToken = "fmu1-secret-bearer-token-987654"

        let transport401 = MockJMAPHTTPTransport { req in
            #expect(req.headers["Authorization"] == "Bearer \(secretToken)")
            return JMAPHTTPResponse(statusCode: 401, body: Data(), finalURL: req.url)
        }
        let client401 = JMAPSessionClient(transport: transport401)
        do {
            _ = try await client401.discoverSession(
                from: "https://api.fastmail.com/jmap/session",
                bearerToken: secretToken
            )
            Issue.record("Expected 401 authenticationRequired")
        } catch let error as JMAPError {
            #expect(error == .authenticationRequired)
            #expect(!error.localizedDescription.contains(secretToken))
        }

        let transport429 = MockJMAPHTTPTransport { req in
            JMAPHTTPResponse(
                statusCode: 429,
                headers: ["Retry-After": "42"],
                body: Data(),
                finalURL: req.url
            )
        }
        do {
            _ = try await JMAPSessionClient(transport: transport429).discoverSession(
                from: "https://api.fastmail.com/jmap/session",
                bearerToken: secretToken
            )
            Issue.record("Expected 429 rateLimited")
        } catch let error as JMAPError {
            #expect(error == .rateLimited(retryAfter: 42))
            #expect(!error.localizedDescription.contains(secretToken))
        }

        let transport503 = MockJMAPHTTPTransport { req in
            JMAPHTTPResponse(statusCode: 503, body: Data(), finalURL: req.url)
        }
        await #expect(throws: JMAPError.serverError(statusCode: 503)) {
            _ = try await JMAPSessionClient(transport: transport503).discoverSession(
                from: "https://api.fastmail.com/jmap/session",
                bearerToken: secretToken
            )
        }

        let redacted = JMAPSecretRedactor.redact("Failed with \(secretToken) on server", secrets: [secretToken])
        #expect(redacted == "Failed with [REDACTED] on server")
        #expect(!redacted.contains(secretToken))
    }

    @Test("session discovery rejects cross-origin redirect destinations so bearer tokens are never forwarded to spoofed APIs")
    func sessionDiscoveryRejectsCrossOriginRedirect() async throws {
        let spoofedSessionJSON = Data("""
        {
          "capabilities": {
            "urn:ietf:params:jmap:core": {},
            "urn:ietf:params:jmap:mail": {}
          },
          "accounts": {
            "u-evil": { "name": "evil", "isPersonal": true, "isReadOnly": false, "accountCapabilities": { "urn:ietf:params:jmap:mail": {} } }
          },
          "primaryAccounts": { "urn:ietf:params:jmap:mail": "u-evil" },
          "username": "victim@example.org",
          "apiUrl": "https://attacker.example.net/jmap/api/",
          "downloadUrl": "https://attacker.example.net/jmap/download/{accountId}/{blobId}/{name}?accept={type}",
          "uploadUrl": "https://attacker.example.net/jmap/upload/{accountId}/",
          "state": "evil-1"
        }
        """.utf8)

        let transport = MockJMAPHTTPTransport { request in
            #expect(request.allowCrossOriginRedirects == false)
            // Simulate a cross-origin redirect landing on an untrusted host returning 200 OK.
            return JMAPHTTPResponse(
                statusCode: 200,
                body: spoofedSessionJSON,
                finalURL: URL(string: "https://attacker.example.net/jmap/session")!
            )
        }
        let client = JMAPSessionClient(transport: transport)
        await #expect(throws: JMAPError.untrustedRedirect) {
            _ = try await client.discoverSession(
                from: "https://mail.example.org/.well-known/jmap",
                bearerToken: "secret-bearer-token"
            )
        }
    }

    @Test("EventSource parser handles comments, multi-line data, event names, and IDs")
    func eventSourceParserFrames() {
        var parser = JMAPEventSourceParser()
        #expect(parser.feedLine(": keepalive ping") == nil)
        #expect(parser.feedLine("event: state") == nil)
        #expect(parser.feedLine("id: 42") == nil)
        #expect(parser.feedLine("data: {\"changed\":") == nil)
        #expect(parser.feedLine("data: {\"u1\":{\"Email\":\"s2\"}}}") == nil)
        let event = parser.feedLine("")
        #expect(event?.event == "state")
        #expect(event?.id == "42")
        #expect(event?.data == "{\"changed\":\n{\"u1\":{\"Email\":\"s2\"}}}")
    }

    @Test("zero network by default: constructing JMAPBackend and JMAPAccountConnector sends no requests")
    func zeroNetworkByDefault() async {
        let counter = RequestCounter()
        let transport = MockJMAPHTTPTransport { req in
            await counter.increment()
            return JMAPHTTPResponse(statusCode: 200, body: Data(), finalURL: req.url)
        }
        let account = BrevAccount(
            id: BrevAccount.jmapAccountID(forEmailAddress: "user@example.org"),
            displayName: "User",
            emailAddress: "user@example.org",
            backendIdentifier: BrevAccount.jmapBackendIdentifier,
            backendDisplayName: BrevAccount.jmapBackendDisplayName
        )
        let backend = JMAPBackend(
            account: account,
            sessionURL: URL(string: "https://api.fastmail.com/jmap/session")!,
            tokenProvider: StaticJMAPAccessTokenProvider(token: "tok"),
            transport: transport
        )
        _ = JMAPAccountConnector(
            configurationStore: InMemoryJMAPAccountConfigurationStore(),
            tokenStore: TestJMAPTokenStore(),
            transport: transport
        )
        #expect(backend.capabilities.isEmpty)
        #expect(await counter.count == 0)
    }
}

// MARK: - Test Support

actor RequestCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

final class MockJMAPHTTPTransport: JMAPHTTPTransport, @unchecked Sendable {
    private let handler: @Sendable (JMAPHTTPRequest) async throws -> JMAPHTTPResponse
    private let sseHandler: @Sendable (JMAPHTTPRequest) -> AsyncThrowingStream<JMAPEventSourceEvent, Error>

    init(
        handler: @escaping @Sendable (JMAPHTTPRequest) async throws -> JMAPHTTPResponse,
        sseHandler: (@Sendable (JMAPHTTPRequest) -> AsyncThrowingStream<JMAPEventSourceEvent, Error>)? = nil
    ) {
        self.handler = handler
        self.sseHandler = sseHandler ?? { _ in AsyncThrowingStream { $0.finish() } }
    }

    func send(_ request: JMAPHTTPRequest) async throws -> JMAPHTTPResponse {
        try await handler(request)
    }

    func streamEvents(_ request: JMAPHTTPRequest) -> AsyncThrowingStream<JMAPEventSourceEvent, Error> {
        sseHandler(request)
    }
}

actor TestJMAPTokenStore: TokenStore {
    private var tokens: [String: Token] = [:]

    func token(for accountID: String) -> Token? {
        tokens[accountID]
    }

    func setToken(_ token: Token, for accountID: String) throws {
        tokens[accountID] = token
    }

    func clearToken(for accountID: String) {
        tokens[accountID] = nil
    }
}
