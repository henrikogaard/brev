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

@Suite("Gmail API client")
struct GmailAPIClientTests {
    @Test("lists labels with typed endpoint and decoding")
    func listsLabels() async throws {
        let executor = ClientRecordingExecutor(body: #"{"labels":[{"id":"INBOX","name":"Inbox","type":"system"}]}"#)
        let client = GmailAPIClient(
            transport: GmailAPITransport(
                accessTokenProvider: ClientTokenProvider(),
                httpExecutor: executor
            )
        )

        let labels = try await client.listLabels()

        #expect(labels == [GmailLabel(id: "INBOX", name: "Inbox", type: "system")])
        let request = try #require(await executor.request())
        #expect(request.url?.path == "/gmail/v1/users/me/labels")
    }

    @Test("lists messages and searches through Gmail q")
    func listsAndSearchesMessages() async throws {
        let executor = ClientRecordingExecutor(body: #"{"messages":[{"id":"m1","threadId":"t1"}],"nextPageToken":"next"}"#)
        let client = GmailAPIClient(
            transport: GmailAPITransport(
                accessTokenProvider: ClientTokenProvider(),
                httpExecutor: executor
            )
        )

        let page = try await client.listMessages(maxResults: 50, pageToken: "page", labelIDs: ["INBOX"])
        #expect(page.messages.map(\.id) == ["m1"])
        #expect(page.nextPageToken == "next")

        _ = try await client.searchMessages("from:alice@example.com has:attachment")
        let request = try #require(await executor.request())
        #expect(request.url?.query?.contains("q=from:alice@example.com%20has:attachment") == true)
    }

    @Test("clamps public message pages and preserves spam/trash inclusion")
    func clampsMessagePagesAndIncludesSpamTrash() async throws {
        let executor = ClientRecordingExecutor(body: #"{"messages":[]}"#)
        let client = GmailAPIClient(
            transport: GmailAPITransport(
                accessTokenProvider: ClientTokenProvider(),
                httpExecutor: executor
            )
        )

        _ = try await client.listMessages(maxResults: 999, includeSpamTrash: true)

        let request = try #require(await executor.request())
        #expect(request.url?.query?.contains("maxResults=500") == true)
        #expect(request.url?.query?.contains("includeSpamTrash=true") == true)
    }

    @Test("rejects dot-segment provider IDs")
    func rejectsDotSegmentIDs() async {
        let client = GmailAPIClient(
            transport: GmailAPITransport(
                accessTokenProvider: ClientTokenProvider(),
                httpExecutor: ClientRecordingExecutor(body: #"{"id":"m"}"#)
            )
        )

        do {
            _ = try await client.getMessage(id: "..")
            Issue.record("Expected dot-segment ID rejection")
        } catch let error as GmailAPIError {
            #expect(error == .invalidRequest)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("lists history with all typed filters")
    func listsHistory() async throws {
        let executor = ClientRecordingExecutor(body: #"{"history":[{"id":"10"}],"historyId":"11"}"#)
        let client = GmailAPIClient(
            transport: GmailAPITransport(
                accessTokenProvider: ClientTokenProvider(),
                httpExecutor: executor
            )
        )

        let page = try await client.listHistory(
            startHistoryID: "9",
            maxResults: 25,
            pageToken: "page",
            labelID: "INBOX",
            historyTypes: [.messageAdded, .labelRemoved]
        )
        #expect(page.historyID == "11")
        let request = try #require(await executor.request())
        let query = request.url?.query ?? ""
        #expect(query.contains("startHistoryId=9"))
        #expect(query.contains("historyTypes=messageAdded"))
        #expect(query.contains("historyTypes=labelRemoved"))
    }
}

private struct ClientTokenProvider: GmailAccessTokenProvider {
    func accessToken() async throws -> String { "token" }
}

private actor ClientRecordingExecutor: GmailAPIHTTPExecutor {
    private let responseBody: Data
    private var lastRequest: URLRequest?

    init(body: String) {
        responseBody = Data(body.utf8)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (responseBody, response)
    }

    func request() -> URLRequest? { lastRequest }
}
