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

@testable import BrevGmail
import Foundation
import Testing

@Suite("Gmail API transport")
struct GmailAPITransportTests {
    @Test("builds the Gmail users/me URL and encodes query values")
    func buildsURLAndEncodesQueryValues() throws {
        let request = GmailAPIRequest(
            method: .get,
            path: "/users/me/messages",
            queryItems: [
                URLQueryItem(name: "q", value: "from:alice@example.com has:attachment"),
                URLQueryItem(name: "pageToken", value: "token+/=")
            ]
        )
        let transport = GmailAPITransport(
            accessTokenProvider: StaticAccessTokenProvider(token: "secret-token"),
            httpExecutor: RecordingHTTPExecutor()
        )

        let url = try transport.url(for: request)

        #expect(url
            .absoluteString ==
            "https://gmail.googleapis.com/gmail/v1/users/me/messages?q=from:alice@example.com%20has:attachment&pageToken=token%2B%2F%3D")
    }

    @Test("adds a bearer header without placing the token in diagnostics")
    func addsBearerHeaderWithoutTokenLeak() async throws {
        let executor = RecordingHTTPExecutor(response: .json("{\"emailAddress\":\"henrik@example.com\"}"))
        let secret = "token-that-must-not-leak"
        let transport = GmailAPITransport(
            accessTokenProvider: StaticAccessTokenProvider(token: secret),
            httpExecutor: executor
        )

        _ = try await transport.send(GmailAPIRequest(method: .get, path: "/users/me/profile"), decoding: GmailProfile.self)

        let request = try #require(await executor.lastRequest())
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(secret)")
        #expect(String(describing: transport).contains(secret) == false)
    }

    @Test("classifies 401 as reauthentication and redacts the provider body")
    func classifiesUnauthorized() async {
        let body = "{\"error\":{\"code\":401,\"message\":\"Bearer token-that-must-not-leak expired\"}}"
        let transport = GmailAPITransport(
            accessTokenProvider: StaticAccessTokenProvider(token: "secret-token"),
            httpExecutor: RecordingHTTPExecutor(response: .init(statusCode: 401, body: Data(body.utf8)))
        )

        do {
            _ = try await transport.send(GmailAPIRequest(method: .get, path: "/users/me/profile"), decoding: GmailProfile.self)
            Issue.record("Expected unauthorized error")
        } catch let error as GmailAPIError {
            #expect(error.requiresReauthentication)
            #expect(error.isRetryable == false)
            #expect(String(describing: error).contains("token-that-must-not-leak") == false)
            #expect(String(describing: error).contains("Bearer") == false)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("classifies Workspace domain policy failures distinctly")
    func classifiesDomainPolicy() async {
        let body = "{\"error\":{\"code\":403,\"errors\":[{\"reason\":\"domainPolicy\"}]}}"
        let transport = GmailAPITransport(
            accessTokenProvider: StaticAccessTokenProvider(token: "secret-token"),
            httpExecutor: RecordingHTTPExecutor(response: .init(statusCode: 403, body: Data(body.utf8)))
        )

        do {
            _ = try await transport.send(GmailAPIRequest(method: .get, path: "/users/me/profile"), decoding: GmailProfile.self)
            Issue.record("Expected domain-policy error")
        } catch let error as GmailAPIError {
            #expect(error.isDomainPolicy)
            #expect(error.isRetryable == false)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("classifies safe Gmail permission reasons distinctly")
    func classifiesPermissionReasons() async {
        let cases: [(String, GmailAPIError, Bool)] = [
            ("insufficientPermissions", .insufficientPermissions, false),
            ("accessNotConfigured", .apiAccessNotConfigured, true),
            ("forbidden", .forbidden, true),
        ]
        for (reason, expected, expectedFallback) in cases {
            let body = "{\"error\":{\"code\":403,\"errors\":[{\"reason\":\"\(reason)\"}],\"message\":\"secret detail\"}}"
            let transport = GmailAPITransport(
                accessTokenProvider: StaticAccessTokenProvider(token: "secret-token"),
                httpExecutor: RecordingHTTPExecutor(response: .init(statusCode: 403, body: Data(body.utf8)))
            )

            do {
                _ = try await transport.send(
                    GmailAPIRequest(method: .get, path: "/users/me/profile"),
                    decoding: GmailProfile.self
                )
                Issue.record("Expected permission error")
            } catch let error as GmailAPIError {
                #expect(error == expected)
                #expect(error.isIMAPFallbackEligible == expectedFallback)
                #expect(!String(describing: error).contains("secret detail"))
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test("classifies rate limits and server errors as retryable")
    func classifiesRetryableErrors() async {
        for statusCode in [429, 500, 502, 503, 504] {
            let transport = GmailAPITransport(
                accessTokenProvider: StaticAccessTokenProvider(token: "secret-token"),
                httpExecutor: RecordingHTTPExecutor(response: .init(statusCode: statusCode, body: Data("{}".utf8)))
            )

            do {
                _ = try await transport.send(
                    GmailAPIRequest(method: .get, path: "/users/me/profile"),
                    decoding: GmailProfile.self
                )
                Issue.record("Expected HTTP \(statusCode) error")
            } catch let error as GmailAPIError {
                #expect(error.isRetryable)
                #expect(error.requiresReauthentication == false)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test("retries idempotent Gmail quota-shaped 403 responses")
    func retriesQuotaShapedForbiddenResponses() async throws {
        for reason in [
            "dailyLimitExceeded",
            "rateLimitExceeded",
            "userRateLimitExceeded",
            "quotaExceeded",
        ] {
            let body = "{\"error\":{\"code\":403,\"errors\":[{\"reason\":\"\(reason)\"}]}}"
            let executor = SequenceHTTPExecutor(responses: [
                .response(statusCode: 403, body: Data(body.utf8)),
                .response(statusCode: 200, body: Data("{\"emailAddress\":\"a@example.com\"}".utf8)),
            ])
            let transport = GmailAPITransport(
                accessTokenProvider: StaticAccessTokenProvider(token: "token"),
                httpExecutor: executor,
                configuration: GmailAPITransportConfiguration(
                    maxRetryAttempts: 2,
                    retryBaseDelay: 0,
                    retryMaxDelay: 0
                ),
                sleep: { _ in try Task.checkCancellation() }
            )

            let profile = try await transport.profile()

            #expect(profile.emailAddress == "a@example.com")
            #expect(await executor.requestCount == 2)
        }
    }

    @Test("retains only an allowlisted Gmail quota reason after retries exhaust")
    func retainsSafeQuotaReasonAfterRetriesExhaust() async {
        let body = """
        {"error":{"code":403,"errors":[{"reason":"rateLimitExceeded"}],"message":"secret detail"}}
        """
        let transport = GmailAPITransport(
            accessTokenProvider: StaticAccessTokenProvider(token: "secret-token"),
            httpExecutor: RecordingHTTPExecutor(response: .init(statusCode: 403, body: Data(body.utf8))),
            configuration: GmailAPITransportConfiguration(maxRetryAttempts: 1)
        )

        do {
            _ = try await transport.profile()
            Issue.record("Expected quota failure")
        } catch let error as GmailAPIError {
            #expect(error == .quotaExceeded(reason: .rateLimitExceeded, retryAfter: nil))
            #expect(error.isRetryable)
            #expect(!String(describing: error).contains("secret detail"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("rejects responses over the configured bound before decoding")
    func rejectsOversizedResponse() async {
        let transport = GmailAPITransport(
            accessTokenProvider: StaticAccessTokenProvider(token: "secret-token"),
            httpExecutor: RecordingHTTPExecutor(response: .init(statusCode: 200, body: Data(repeating: 0x7B, count: 32))),
            configuration: GmailAPITransportConfiguration(maxResponseBytes: 16)
        )

        do {
            _ = try await transport.send(GmailAPIRequest(method: .get, path: "/users/me/profile"), decoding: GmailProfile.self)
            Issue.record("Expected response-size error")
        } catch let error as GmailAPIError {
            #expect(error == .responseTooLarge(limit: 16))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("decodes a profile response")
    func decodesProfile() async throws {
        let transport = GmailAPITransport(
            accessTokenProvider: StaticAccessTokenProvider(token: "secret-token"),
            httpExecutor: RecordingHTTPExecutor(
                response: .json(
                    "{\"emailAddress\":\"henrik@example.com\",\"messagesTotal\":42,\"threadsTotal\":7,\"historyId\":\"123\"}"
                )
            )
        )

        let profile = try await transport.send(
            GmailAPIRequest(method: .get, path: "/users/me/profile"),
            decoding: GmailProfile.self
        )

        #expect(profile.emailAddress == "henrik@example.com")
        #expect(profile.messagesTotal == 42)
        #expect(profile.historyID == "123")
    }

    @Test("builds high-level list, message, and attachment requests")
    func buildsHighLevelRequests() async throws {
        let listExecutor = RecordingHTTPExecutor(response: .json("{\"messages\":[]}"))
        let listTransport = GmailAPITransport(
            accessTokenProvider: StaticAccessTokenProvider(token: "token"),
            httpExecutor: listExecutor
        )

        _ = try await listTransport.listMessages(
            labelID: "INBOX",
            query: "from:alice@example.com",
            pageToken: "next+/=",
            maxResults: 999
        )
        let listRequest = try #require(await listExecutor.lastRequest())
        #expect(listRequest.url?.absoluteString.contains("labelIds=INBOX") == true)
        #expect(listRequest.url?.absoluteString.contains("maxResults=500") == true)
        #expect(listRequest.url?.absoluteString.contains("q=from:alice@example.com") == true)

        let messageExecutor = RecordingHTTPExecutor(response: .json("{\"id\":\"m/1\"}"))
        let messageTransport = GmailAPITransport(
            accessTokenProvider: StaticAccessTokenProvider(token: "token"),
            httpExecutor: messageExecutor
        )
        _ = try await messageTransport.getMessage(messageID: "m/1", format: .full)
        let messageRequest = try #require(await messageExecutor.lastRequest())
        #expect(messageRequest.url?.absoluteString.contains("/messages/m%2F1") == true)
        #expect(messageRequest.url?.query == "format=full")

        let attachmentExecutor = RecordingHTTPExecutor(response: .json("{\"id\":\"a/1\"}"))
        let attachmentTransport = GmailAPITransport(
            accessTokenProvider: StaticAccessTokenProvider(token: "token"),
            httpExecutor: attachmentExecutor
        )
        _ = try await attachmentTransport.getAttachment(messageID: "m/1", attachmentID: "a/1")
        let attachmentRequest = try #require(await attachmentExecutor.lastRequest())
        #expect(attachmentRequest.url?.absoluteString.contains("/messages/m%2F1/attachments/a%2F1") == true)
    }

    @Test("strictly percent-encodes every path component delimiter")
    func strictlyEncodesPathComponentDelimiters() throws {
        let transport = GmailAPITransport(
            accessTokenProvider: StaticAccessTokenProvider(token: "token"),
            httpExecutor: RecordingHTTPExecutor()
        )

        let url = try transport.url(for: GmailAPIRequest(
            method: .get,
            path: "/users/me/messages/a%2Fb%3Fc%23d%25"
        ))

        #expect(url.absoluteString.contains("a%2Fb%3Fc%23d%25"))
    }

    @Test("retries idempotent transient responses with a bounded cancellable backoff")
    func retriesIdempotentTransientResponses() async throws {
        let executor = SequenceHTTPExecutor(responses: [
            .response(statusCode: 503, body: Data("{}".utf8)),
            .response(statusCode: 200, body: Data("{\"emailAddress\":\"a@example.com\"}".utf8))
        ])
        let transport = GmailAPITransport(
            accessTokenProvider: StaticAccessTokenProvider(token: "token"),
            httpExecutor: executor,
            configuration: GmailAPITransportConfiguration(
                maxRetryAttempts: 3,
                retryBaseDelay: 0,
                retryMaxDelay: 0
            ),
            sleep: { _ in try Task.checkCancellation() }
        )

        let profile = try await transport.profile()

        #expect(profile.emailAddress == "a@example.com")
        #expect(await executor.requestCount == 2)
    }

    @Test("does not retry non-idempotent sends after a transient response")
    func doesNotRetryNonIdempotentSends() async {
        let executor = SequenceHTTPExecutor(responses: [
            .response(statusCode: 503, body: Data("{}".utf8)),
            .response(statusCode: 200, body: Data("{\"id\":\"sent\"}".utf8))
        ])
        let transport = GmailAPITransport(
            accessTokenProvider: StaticAccessTokenProvider(token: "token"),
            httpExecutor: executor,
            configuration: GmailAPITransportConfiguration(maxRetryAttempts: 3, retryBaseDelay: 0, retryMaxDelay: 0)
        )

        do {
            _ = try await transport.send(
                GmailAPIRequest(method: .post, path: "/users/me/messages/send"),
                decoding: GmailMessage.self
            )
            Issue.record("Expected the transient send failure")
        } catch let error as GmailAPIError {
            #expect(error == .retryable(statusCode: 503, retryAfter: nil))
            #expect(await executor.requestCount == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("only post-dispatch evidence makes a send ambiguous")
    func classifiesSendPhaseEvidence() async {
        for phase in [GmailAPIRequestFailurePhase.preDispatch, .postDispatch] {
            let transport = GmailAPITransport(
                accessTokenProvider: StaticAccessTokenProvider(token: "token"),
                httpExecutor: ThrowingHTTPExecutor(error: phase)
            )
            do {
                _ = try await transport.send(
                    GmailAPIRequest(method: .post, path: "/users/me/messages/send"),
                    decoding: GmailMessage.self
                )
                Issue.record("Expected the send failure")
            } catch let error as GmailAPIError {
                if phase == .preDispatch {
                    #expect(error == .transportFailure)
                    #expect(error.isRetryable)
                } else {
                    #expect(error == .ambiguousSendOutcome)
                }
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test("preserves draft-write ambiguity after dispatch")
    func classifiesDraftWritePhaseEvidence() async {
        let transport = GmailAPITransport(
            accessTokenProvider: StaticAccessTokenProvider(token: "token"),
            httpExecutor: ThrowingHTTPExecutor(error: .postDispatch)
        )

        do {
            _ = try await transport.send(
                GmailAPIRequest(method: .post, path: "/users/me/drafts"),
                decoding: GmailDraft.self
            )
            Issue.record("Expected ambiguous draft write")
        } catch let error as GmailAPIError {
            #expect(error.isAmbiguousDraftWrite)
            #expect(error.isRetryable == false)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private struct StaticAccessTokenProvider: GmailAccessTokenProvider {
    let token: String

    func accessToken() async throws -> String { token }
}

private actor RecordingHTTPExecutor: GmailAPIHTTPExecutor {
    struct Response: Sendable {
        let statusCode: Int
        let body: Data

        init(statusCode: Int = 200, body: Data) {
            self.statusCode = statusCode
            self.body = body
        }

        static func json(_ string: String) -> Response {
            Response(statusCode: 200, body: Data(string.utf8))
        }
    }

    private var request: URLRequest?
    private let response: Response

    init(response: Response = .json("{}")) {
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        guard let url = request.url,
              let httpResponse = HTTPURLResponse(
                  url: url,
                  statusCode: response.statusCode,
                  httpVersion: nil,
                  headerFields: ["Content-Type": "application/json"]
              )
        else {
            throw TestSupportError.invalidRequest
        }
        return (response.body, httpResponse)
    }

    func lastRequest() -> URLRequest? { request }
}

private enum TestSupportError: Error {
    case invalidRequest
}

private actor SequenceHTTPExecutor: GmailAPIHTTPExecutor {
    struct Result: Sendable {
        let statusCode: Int
        let body: Data

        static func response(statusCode: Int, body: Data) -> Result {
            Result(statusCode: statusCode, body: body)
        }
    }

    private var responses: [Result]
    private(set) var requestCount = 0

    init(responses: [Result]) { self.responses = responses }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCount += 1
        let result = responses.isEmpty ? .response(statusCode: 500, body: Data()) : responses.removeFirst()
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: result.statusCode,
                  httpVersion: nil,
                  headerFields: nil
              ) else { throw TestSupportError.invalidRequest }
        return (result.body, response)
    }
}

private struct ThrowingHTTPExecutor: GmailAPIHTTPExecutor {
    let error: GmailAPIRequestFailurePhase

    func data(for _: URLRequest) async throws -> (Data, URLResponse) {
        throw error
    }
}
