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

@testable import BrevAI
import Foundation
import Testing

// MARK: - Captured request value

private struct CapturedAIRequest: Sendable {
    let url: URL?
    let method: String?
    let headers: [String: String]
    let bodyData: Data

    func header(_ name: String) -> String? { headers[name] }

    func jsonBody() -> [String: Any]? {
        guard !bodyData.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
    }
}

// MARK: - URLProtocol stub

/// Thread-safe stub URLProtocol for intercepting URLSession requests
/// without hitting any real network endpoint.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var stubbedError: Error?
    nonisolated(unsafe) static var captured: [CapturedAIRequest] = []

    static func reset(responseData: Data = Data(), statusCode: Int = 200, error: Error? = nil) {
        Self.responseData = responseData
        Self.statusCode = statusCode
        stubbedError = error
        captured = []
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Read body — URLSession places it in httpBodyStream, not httpBody.
        let bodyData: Data
        if let data = request.httpBody, !data.isEmpty {
            bodyData = data
        } else if let stream = request.httpBodyStream {
            var buf = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            stream.open()
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                guard n > 0 else { break }
                buf.append(contentsOf: buffer.prefix(n))
            }
            stream.close()
            bodyData = buf
        } else {
            bodyData = Data()
        }

        let headers = (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) {
            $0[$1.key] = $1.value
        }
        Self.captured.append(
            CapturedAIRequest(
                url: request.url,
                method: request.httpMethod,
                headers: headers,
                bodyData: bodyData
            )
        )

        if let error = Self.stubbedError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeBackend(apiKey: String = "sk-test-key") -> OpenAICompatibleBackend {
    OpenAICompatibleBackend(
        providerName: "Test Provider",
        baseURL: URL(string: "https://api.test.example/v1")!,
        apiKey: apiKey,
        modelID: "test-model",
        urlSession: makeSession()
    )
}

private let successJSON = Data("""
{"choices":[{"message":{"role":"assistant","content":"Hello from AI"}}]}
""".utf8)

// MARK: - Tests

@Suite("OpenAICompatibleBackend — network request/response", .serialized)
struct OpenAICompatibleBackendNetworkTests {
    // MARK: - Successful path

    @Test("successful response decodes into AIResponse")
    func successDecodes() async throws {
        StubURLProtocol.reset(responseData: successJSON, statusCode: 200)
        let response = try await makeBackend().shortcut(.improveWriting, on: "Draft")
        #expect(response.text == "Hello from AI")
    }

    @Test("shortcut request body includes model ID and two messages")
    func shortcutRequestBodyIsCorrect() async throws {
        StubURLProtocol.reset(responseData: successJSON, statusCode: 200)
        _ = try await makeBackend().shortcut(.shorten, on: "Long text")

        let req = try #require(StubURLProtocol.captured.last)
        let body = try #require(req.jsonBody())
        #expect((body["model"] as? String) == "test-model")
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] == "system")
        #expect(messages[1]["role"] == "user")
        #expect(messages[1]["content"]?.contains("Long text") == true)
        #expect(messages[1]["content"]?.contains("<<<UNTRUSTED_EMAIL_CONTENT>>>") == true)
    }

    @Test("request URL ends with chat/completions")
    func requestURLIsCorrect() async throws {
        StubURLProtocol.reset(responseData: successJSON, statusCode: 200)
        _ = try await makeBackend().shortcut(.formal, on: "text")
        let req = try #require(StubURLProtocol.captured.last)
        #expect(req.url?.lastPathComponent == "completions")
    }

    @Test("Authorization header carries Bearer token")
    func authorizationHeaderIsPresent() async throws {
        StubURLProtocol.reset(responseData: successJSON, statusCode: 200)
        _ = try await makeBackend(apiKey: "sk-secret").shortcut(.translate, on: "text")
        let req = try #require(StubURLProtocol.captured.last)
        #expect(req.header("Authorization") == "Bearer sk-secret")
    }

    @Test("Ollama backend sends no Authorization header when apiKey is nil")
    func ollamaNoAuthHeader() async throws {
        StubURLProtocol.reset(responseData: successJSON, statusCode: 200)
        let backend = OpenAICompatibleBackend(
            providerName: "Ollama",
            baseURL: URL(string: "http://localhost:11434/v1")!,
            apiKey: nil,
            modelID: "llama3",
            urlSession: makeSession()
        )
        _ = try await backend.shortcut(.improveWriting, on: "text")
        let req = try #require(StubURLProtocol.captured.last)
        #expect(req.header("Authorization") == nil)
    }

    // MARK: - Error mapping

    @Test("401 maps to serverError with API key redacted")
    func unauthorizedRedactsKey() async throws {
        StubURLProtocol.reset(
            responseData: Data(#"{"error":{"message":"Invalid key sk-secret-key-value"}}"#.utf8),
            statusCode: 401
        )
        let backend = makeBackend(apiKey: "sk-secret-key-value")
        do {
            _ = try await backend.shortcut(.translate, on: "text")
            Issue.record("Expected error")
        } catch AIBackendError.serverError(_, let message) {
            #expect(!message.contains("sk-secret-key-value"),
                    "API key must be redacted from error message")
        }
    }

    @Test("403 maps to serverError")
    func forbiddenMapsToServerError() async throws {
        StubURLProtocol.reset(responseData: Data("Forbidden".utf8), statusCode: 403)
        await #expect(throws: AIBackendError.self) {
            _ = try await makeBackend().shortcut(.expand, on: "text")
        }
    }

    @Test("429 maps to rateLimited error")
    func tooManyRequestsMapsToRateLimited() async throws {
        StubURLProtocol.reset(responseData: Data("Rate limited".utf8), statusCode: 429)
        do {
            _ = try await makeBackend().shortcut(.formal, on: "text")
            Issue.record("Expected rateLimited")
        } catch AIBackendError.rateLimited {
            // expected
        } catch {
            Issue.record("Expected .rateLimited, got: \(error)")
        }
    }

    @Test("5xx maps to serverError")
    func serverErrorMapsToServerError() async throws {
        StubURLProtocol.reset(responseData: Data("Internal Error".utf8), statusCode: 500)
        await #expect(throws: AIBackendError.self) {
            _ = try await makeBackend().shortcut(.casual, on: "text")
        }
    }

    @Test("malformed JSON maps to AIBackendError — no crash")
    func malformedJSONMapsToError() async throws {
        StubURLProtocol.reset(responseData: Data("not json!!".utf8), statusCode: 200)
        await #expect(throws: AIBackendError.self) {
            _ = try await makeBackend().shortcut(.friendly, on: "text")
        }
    }

    @Test("network transport error maps to networkError")
    func transportErrorMapsToNetworkError() async throws {
        StubURLProtocol.reset(error: URLError(.notConnectedToInternet))
        do {
            _ = try await makeBackend().shortcut(.improveWriting, on: "text")
            Issue.record("Expected networkError")
        } catch AIBackendError.networkError {
            // expected
        } catch {
            Issue.record("Expected .networkError, got: \(error)")
        }
    }

    @Test("API key is redacted from transport error message when echoed")
    func apiKeyRedactedFromTransportError() async throws {
        struct LeakError: Error, LocalizedError {
            let key: String
            var errorDescription: String? { "Connection failed with token \(key)" }
        }
        let key = "sk-leaked-value"
        StubURLProtocol.reset(error: LeakError(key: key))
        let backend = makeBackend(apiKey: key)
        do {
            _ = try await backend.shortcut(.fixSpelling, on: "text")
            Issue.record("Expected networkError")
        } catch AIBackendError.networkError(let msg) {
            #expect(!msg.contains(key), "Key must not appear in error: \(msg)")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("generateReply includes instruction as system message")
    func generateReplyIncludesInstruction() async throws {
        StubURLProtocol.reset(responseData: successJSON, statusCode: 200)
        let messages = [AIMessage(role: .user, content: "Please respond")]
        _ = try await makeBackend().generateReply(to: messages, instruction: "Be concise")
        let req = try #require(StubURLProtocol.captured.last)
        let body = try #require(req.jsonBody())
        let msgs = try #require(body["messages"] as? [[String: String]])
        // Safety instruction → requested instruction → wrapped user message.
        #expect(msgs[0]["role"] == "system")
        #expect(msgs[0]["content"] == AISafetyPolicy.untrustedMailSystemInstruction)
        #expect(msgs[1]["content"] == "Be concise")
        #expect(msgs[2]["content"]?.contains("Please respond") == true)
    }
}
