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

@Suite("Gmail API write client")
struct GmailAPIWriteClientTests {
    @Test("modifies labels and sends base64url MIME")
    func modifiesAndSends() async throws {
        let executor = WriteRecordingExecutor(body: #"{"id":"m1","threadId":"t1","labelIds":["STARRED"]}"#)
        let client = Self.client(executor: executor)

        _ = try await client.modifyMessageLabels(id: "m1", addLabelIDs: ["STARRED"], removeLabelIDs: ["INBOX"])
        _ = try await client.sendMessage(rawMIME: "Subject: Test\r\n\r\nHello")

        let requests = await executor.requests()
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].url?.path == "/gmail/v1/users/me/messages/m1/modify")
        #expect(String(decoding: requests[0].httpBody ?? Data(), as: UTF8.self).contains("addLabelIds"))
        #expect(requests[1].url?.path == "/gmail/v1/users/me/messages/send")
        let sendBody = try #require(requests[1].httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: sendBody) as? [String: Any])
        let raw = try #require(json["raw"] as? String)
        #expect(Self.decodeBase64URL(raw) == "Subject: Test\r\n\r\nHello")
    }

    @Test("batch and label writes validate Gmail limits")
    func validatesLimits() async throws {
        let client = Self.client(executor: WriteRecordingExecutor(body: "{}"))
        await #expect(throws: GmailAPIError.invalidRequest) {
            try await client.batchModifyMessageLabels(
                messageIDs: Array(repeating: "m", count: 1001),
                addLabelIDs: [],
                removeLabelIDs: []
            )
        }
        await #expect(throws: GmailAPIError.invalidRequest) {
            try await client.modifyMessageLabels(
                id: "m",
                addLabelIDs: Array(repeating: "l", count: 101),
                removeLabelIDs: []
            )
        }
        await #expect(throws: GmailAPIError.invalidRequest) {
            try await client.deleteLabel(id: "")
        }
    }

    @Test("lists send-as signature and default metadata")
    func listsSendAs() async throws {
        let executor =
            WriteRecordingExecutor(
                body: #"{"sendAs":[{"sendAsEmail":"alias@example.com","signature":"<p>Cheers</p>","isDefault":true,"isPrimary":false}]}"#
            )
        let client = Self.client(executor: executor)

        let sendAs = try await client.listSendAs()

        #expect(sendAs.first?.signature == "<p>Cheers</p>")
        #expect(sendAs.first?.isDefault == true)
        #expect(sendAs.first?.isPrimary == false)
        #expect(await (executor.requests()).first?.url?.path == "/gmail/v1/users/me/settings/sendAs")
    }

    @Test("writes threads, label lifecycle, drafts, and supports empty delete responses")
    func writesAllResourceFamilies() async throws {
        let threadBody = #"{"id":"t1","messages":[]}"#
        let threadExecutor = WriteRecordingExecutor(body: threadBody)
        let threadClient = Self.client(executor: threadExecutor)
        _ = try await threadClient.modifyThreadLabels(id: "t1", addLabelIDs: ["STARRED"], removeLabelIDs: [])
        _ = try await threadClient.trashThread(id: "t1")
        _ = try await threadClient.untrashThread(id: "t1")
        try await threadClient.deleteThread(id: "t1")
        let threadPaths = await threadExecutor.requests().compactMap { $0.url?.path }
        #expect(threadPaths == [
            "/gmail/v1/users/me/threads/t1/modify",
            "/gmail/v1/users/me/threads/t1/trash",
            "/gmail/v1/users/me/threads/t1/untrash",
            "/gmail/v1/users/me/threads/t1"
        ])

        let labelExecutor = WriteRecordingExecutor(body: #"{"id":"label-1","name":"Work","type":"user"}"#)
        let labelClient = Self.client(executor: labelExecutor)
        _ = try await labelClient.createLabel(GmailLabelWrite(name: "Work"))
        _ = try await labelClient.patchLabel(
            id: "label-1",
            with: GmailLabelWrite(color: GmailLabelColor(backgroundColor: "#ffffff"))
        )
        try await labelClient.deleteLabel(id: "label-1")
        let labelRequests = await labelExecutor.requests()
        #expect(labelRequests[0].httpMethod == "POST")
        #expect(labelRequests[1].httpMethod == "PATCH")
        #expect(labelRequests[2].httpMethod == "DELETE")

        let draftExecutor = WriteRecordingExecutor(body: #"{"id":"d1","message":{"id":"m1"}}"#)
        let draftClient = Self.client(executor: draftExecutor)
        _ = try await draftClient.createDraft(rawMIME: "Subject: Draft\r\n\r\nBody")
        _ = try await draftClient.updateDraft(id: "d1", rawMIME: "Subject: Updated\r\n\r\nBody")
        try await draftClient.deleteDraft(id: "d1")
        let draftRequests = await draftExecutor.requests()
        #expect(draftRequests[0].url?.path == "/gmail/v1/users/me/drafts")
        #expect(draftRequests[1].url?.path == "/gmail/v1/users/me/drafts/d1")
        #expect(draftRequests[1].httpMethod == "PUT")
        #expect(draftRequests[2].httpMethod == "DELETE")

        let emptyExecutor = WriteRecordingExecutor(statusCode: 204, body: "")
        try await Self.client(executor: emptyExecutor).deleteMessage(id: "m1")
    }

    @Test("maps a lost send response to an ambiguous outcome without exposing body")
    func ambiguousSend() async {
        let executor = WriteThrowingExecutor(error: GmailAPIRequestFailurePhase.postDispatch)
        let client = Self.client(executor: executor)

        do {
            _ = try await client.sendMessage(rawMIME: "Subject: Secret\r\n\r\nPrivate")
            Issue.record("Expected ambiguous send outcome")
        } catch let error as GmailAPIError {
            #expect(error.isAmbiguousSend)
            #expect(error.localizedDescription.contains("Secret") == false)
            #expect(String(describing: error).contains("Private") == false)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("keeps authentication and policy errors typed for writes")
    func typedWriteErrors() async {
        for statusCode in [401, 403, 429] {
            let executor = WriteRecordingExecutor(statusCode: statusCode, body: "{}")
            let client = Self.client(executor: executor)
            do {
                try await client.deleteMessage(id: "m1")
                Issue.record("Expected HTTP \(statusCode) error")
            } catch let error as GmailAPIError {
                if statusCode == 401 { #expect(error.requiresReauthentication) }
                if statusCode == 429 { #expect(error.isRetryable) }
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    private static func client(executor: any GmailAPIHTTPExecutor) -> GmailAPIClient {
        GmailAPIClient(
            transport: GmailAPITransport(
                accessTokenProvider: WriteTokenProvider(),
                httpExecutor: executor
            )
        )
    }

    private static func decodeBase64URL(_ value: String) -> String? {
        let padded = value + String(repeating: "=", count: (4 - value.count % 4) % 4)
        let normalized = padded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: normalized) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

private struct WriteTokenProvider: GmailAccessTokenProvider {
    func accessToken() async throws -> String { "token" }
}

private actor WriteRecordingExecutor: GmailAPIHTTPExecutor {
    private var recorded: [URLRequest] = []
    private let statusCode: Int
    private let responseBody: Data

    init(statusCode: Int = 200, body: String) {
        self.statusCode = statusCode
        responseBody = Data(body.utf8)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        recorded.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (responseBody, response)
    }

    func requests() -> [URLRequest] { recorded }
}

private struct WriteThrowingExecutor: GmailAPIHTTPExecutor {
    let error: Error

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw error
    }
}
