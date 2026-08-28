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

@Suite("ProviderHostedAIBackend")
struct ProviderHostedAIBackendTests {
    @Test("requests use the current mailbox for every AI invocation")
    func requestsUseCurrentMailboxForEveryInvocation() async throws {
        let recorder = RequestRecorder()
        let session = URLSession(configuration: Self.urlSessionConfiguration(recorder: recorder))
        let mailboxState = MailboxProviderState(mailboxUUID: "mailbox-a")
        let backend = ProviderHostedAIBackend(
            baseURL: URL(string: "https://mail.example.test")!,
            mailboxUUIDProvider: {
                await mailboxState.mailboxUUID
            },
            tokenProvider: {
                "fresh-token"
            },
            urlSession: session
        )

        _ = try await backend.shortcut(.shorten, on: "First draft")
        await mailboxState.setMailboxUUID("mailbox-b")
        _ = try await backend.shortcut(.expand, on: "Second draft")

        #expect(recorder.paths == [
            "/api/mail/mailbox-a/ai",
            "/api/mail/mailbox-b/ai"
        ])
        #expect(recorder.authorizationHeaders == [
            "Bearer fresh-token",
            "Bearer fresh-token"
        ])
    }

    private static func urlSessionConfiguration(recorder: RequestRecorder) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        ProviderHostedAIBackendURLProtocol.recorder = recorder
        configuration.protocolClasses = [ProviderHostedAIBackendURLProtocol.self]
        return configuration
    }
}

private actor MailboxProviderState {
    private var value: String

    init(mailboxUUID: String) {
        value = mailboxUUID
    }

    var mailboxUUID: String {
        value
    }

    func setMailboxUUID(_ mailboxUUID: String) {
        value = mailboxUUID
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    var paths: [String] {
        lock.withLock {
            requests.map { $0.url?.path ?? "" }
        }
    }

    var authorizationHeaders: [String?] {
        lock.withLock {
            requests.map { $0.value(forHTTPHeaderField: "Authorization") }
        }
    }

    func record(_ request: URLRequest) {
        lock.withLock {
            requests.append(request)
        }
    }
}

private final class ProviderHostedAIBackendURLProtocol: URLProtocol {
    static var recorder: RequestRecorder?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.recorder?.record(request)
        let data = Data(#"{"data":{"content":"Updated draft"}}"#.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
