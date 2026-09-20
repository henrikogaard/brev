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

@testable import BrevCalendar
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing

@Suite("PIMDAVClient")
struct PIMDAVClientTests {
    /// Returns scripted responses in order and records every request it
    /// receives so tests can assert on auth and method usage.
    private final class ScriptedTransport: PIMDAVTransport, @unchecked Sendable {
        struct Step {
            let status: Int
            let headers: [String: String]
            let body: Data
            let error: Error?

            static func response(
                _ status: Int,
                headers: [String: String] = [:],
                body: String = ""
            ) -> Step {
                Step(status: status, headers: headers, body: Data(body.utf8), error: nil)
            }

            static func failure(_ error: Error) -> Step {
                Step(status: 0, headers: [:], body: Data(), error: error)
            }
        }

        private(set) var requests: [URLRequest] = []
        private var steps: [Step]

        init(steps: [Step]) {
            self.steps = steps
        }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            requests.append(request)
            guard !steps.isEmpty else {
                throw URLError(.cannotConnectToHost)
            }
            let step = steps.removeFirst()
            if let error = step.error { throw error }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: step.status,
                httpVersion: nil,
                headerFields: step.headers
            )!
            return (step.body, response)
        }
    }

    private static let multistatus = """
    <?xml version="1.0" encoding="utf-8"?>
    <d:multistatus xmlns:d="DAV:">
      <d:response>
        <d:href>/dav/</d:href>
        <d:propstat>
          <d:prop>
            <d:current-user-principal>
              <d:href>/principals/user/henrik/</d:href>
            </d:current-user-principal>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
    </d:multistatus>
    """

    private func makeClient(_ transport: ScriptedTransport) -> PIMDAVClient {
        PIMDAVClient(transport: transport)
    }

    @Test("manual endpoint validates and returns the principal")
    func manualEndpointSuccess() async throws {
        let transport = ScriptedTransport(steps: [
            .response(207, body: Self.multistatus)
        ])
        let validation = try await makeClient(transport).validate(
            endpoint: .manual(URL(string: "https://dav.example.com/dav/")!),
            kind: .contacts,
            credential: .basic(username: "u", password: "p")
        )

        #expect(validation.endpointURL.absoluteString == "https://dav.example.com/dav/")
        #expect(validation.principalURL?.absoluteString == "https://dav.example.com/principals/user/henrik/")
        #expect(validation.discoveryMethod == .manual)

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PROPFIND")
        #expect(request.value(forHTTPHeaderField: "Depth") == "0")
        #expect(
            request.value(forHTTPHeaderField: "Authorization")
                == "Basic \(Data("u:p".utf8).base64EncodedString())"
        )
    }

    @Test("manual endpoint rejects non-HTTPS hosts")
    func manualEndpointRequiresHTTPS() async throws {
        let transport = ScriptedTransport(steps: [])
        await #expect(throws: PIMDAVConnectError.httpsRequired) {
            try await makeClient(transport).validate(
                endpoint: .manual(URL(string: "http://dav.example.com/")!),
                kind: .calendar,
                credential: .bearer(token: "t")
            )
        }
        #expect(transport.requests.isEmpty)
    }

    @Test("loopback HTTP stays allowed for dev servers")
    func loopbackAllowed() async throws {
        let transport = ScriptedTransport(steps: [
            .response(207, body: Self.multistatus)
        ])
        let validation = try await makeClient(transport).validate(
            endpoint: .manual(URL(string: "http://localhost:8080/dav/")!),
            kind: .calendar,
            credential: .basic(username: "u", password: "p")
        )
        #expect(validation.endpointURL.host() == "localhost")
    }

    @Test("rejected credentials surface authenticationRequired")
    func authenticationRequired() async throws {
        let transport = ScriptedTransport(steps: [.response(401)])
        await #expect(throws: PIMDAVConnectError.authenticationRequired) {
            try await makeClient(transport).validate(
                endpoint: .manual(URL(string: "https://dav.example.com/")!),
                kind: .calendar,
                credential: .bearer(token: "expired")
            )
        }
    }

    @Test("non-DAV answer surfaces unsupportedServer")
    func unsupportedServer() async throws {
        let transport = ScriptedTransport(steps: [.response(404)])
        await #expect(throws: PIMDAVConnectError.unsupportedServer) {
            try await makeClient(transport).validate(
                endpoint: .manual(URL(string: "https://dav.example.com/")!),
                kind: .contacts,
                credential: .bearer(token: "t")
            )
        }
    }

    @Test("TLS failures never fall back to insecure transport")
    func tlsFailure() async throws {
        let transport = ScriptedTransport(steps: [
            .failure(URLError(.serverCertificateUntrusted))
        ])
        await #expect(throws: PIMDAVConnectError.tlsValidationFailed) {
            try await makeClient(transport).validate(
                endpoint: .manual(URL(string: "https://dav.example.com/")!),
                kind: .calendar,
                credential: .bearer(token: "t")
            )
        }
    }

    @Test("well-known discovery follows HTTPS redirects then validates")
    func wellKnownDiscovery() async throws {
        let transport = ScriptedTransport(steps: [
            .response(301, headers: ["Location": "https://dav.example.com/carddav/"]),
            .response(200),
            .response(207, body: Self.multistatus)
        ])
        let validation = try await makeClient(transport).validate(
            endpoint: .discover(emailAddress: "henrik@example.com"),
            kind: .contacts,
            credential: .basic(username: "u", password: "p")
        )

        #expect(validation.endpointURL.absoluteString == "https://dav.example.com/carddav/")
        #expect(validation.discoveryMethod == .wellKnown)
        #expect(transport.requests.count == 3)

        // The unauthenticated discovery GETs carry no credential; only the
        // PROPFIND to the final endpoint is authorized.
        #expect(transport.requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(transport.requests[1].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(transport.requests[2].httpMethod == "PROPFIND")
        #expect(transport.requests[2].value(forHTTPHeaderField: "Authorization") != nil)
    }

    @Test("well-known redirect to plain HTTP is refused")
    func wellKnownInsecureRedirect() async throws {
        let transport = ScriptedTransport(steps: [
            .response(301, headers: ["Location": "http://dav.example.com/carddav/"])
        ])
        await #expect(throws: PIMDAVConnectError.httpsRequired) {
            try await makeClient(transport).validate(
                endpoint: .discover(emailAddress: "henrik@example.com"),
                kind: .contacts,
                credential: .basic(username: "u", password: "p")
            )
        }
    }

    @Test("authenticated cross-origin redirect is refused")
    func crossOriginRedirectRefused() async throws {
        let transport = ScriptedTransport(steps: [
            .response(302, headers: ["Location": "https://other.example.net/dav/"])
        ])
        await #expect(throws: PIMDAVConnectError.crossOriginRedirect) {
            try await makeClient(transport).validate(
                endpoint: .manual(URL(string: "https://dav.example.com/")!),
                kind: .calendar,
                credential: .bearer(token: "t")
            )
        }
        // The credential was never sent to the foreign host: only one
        // request went out.
        #expect(transport.requests.count == 1)
    }

    @Test("same-origin redirect is followed with the credential")
    func sameOriginRedirectFollowed() async throws {
        let transport = ScriptedTransport(steps: [
            .response(301, headers: ["Location": "https://dav.example.com/v2/dav/"]),
            .response(207, body: Self.multistatus)
        ])
        let validation = try await makeClient(transport).validate(
            endpoint: .manual(URL(string: "https://dav.example.com/dav/")!),
            kind: .calendar,
            credential: .bearer(token: "t")
        )
        #expect(validation.endpointURL.absoluteString == "https://dav.example.com/dav/")
        #expect(transport.requests.count == 2)
        #expect(
            transport.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer t"
        )
    }

    @Test("discovery without a DAV answer surfaces discoveryFailed")
    func discoveryFailed() async throws {
        let transport = ScriptedTransport(steps: [.response(404)])
        await #expect(throws: PIMDAVConnectError.discoveryFailed) {
            try await makeClient(transport).validate(
                endpoint: .discover(emailAddress: "henrik@example.com"),
                kind: .calendar,
                credential: .bearer(token: "t")
            )
        }
    }

    @Test("malformed addresses surface invalidEndpoint before any request")
    func invalidEndpoint() async throws {
        let transport = ScriptedTransport(steps: [])
        await #expect(throws: PIMDAVConnectError.invalidEndpoint) {
            try await makeClient(transport).validate(
                endpoint: .discover(emailAddress: "not-an-address"),
                kind: .calendar,
                credential: .bearer(token: "t")
            )
        }
        #expect(transport.requests.isEmpty)
    }
}
