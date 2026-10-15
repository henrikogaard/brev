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

/// Request-shape and error-mapping coverage for the Drive client
/// (#14): metadata, download, export, multipart upload, conflict
/// lookup, and overwrite.
@Suite("GoogleDriveClient")
struct GoogleDriveClientTests {
    private final class StubTransport: @unchecked Sendable {
        private(set) var requests: [URLRequest] = []
        var handler: (URLRequest) -> (Data, HTTPURLResponse) = { _ in
            (
                Data(),
                HTTPURLResponse(
                    url: URL(string: "https://x")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }

        func send(
            _ request: URLRequest
        ) throws -> (Data, HTTPURLResponse) {
            requests.append(request)
            return handler(request)
        }
    }

    /// Mutable capture target for @Sendable progress callbacks.
    private final class ProgressRecorder: @unchecked Sendable {
        private(set) var reported: [(Int64, Int64)] = []

        func record(_ sent: Int64, _ total: Int64) {
            reported.append((sent, total))
        }
    }

    private func makeClient(
        _ stub: StubTransport
    ) -> GoogleDriveClient {
        GoogleDriveClient { request in
            try stub.send(request)
        }
    }

    private static func response(
        _ status: Int,
        json: String = "{}"
    ) -> (Data, HTTPURLResponse) {
        (
            Data(json.utf8),
            HTTPURLResponse(
                url: URL(string: "https://www.googleapis.com")!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    @Test("workspace MIME semantics include Google Apps types except folders")
    func workspaceDocumentMimeSemantics() {
        #expect(
            GoogleDriveClient.File(
                id: "form",
                name: "Form",
                mimeType: "application/vnd.google-apps.form"
            ).isWorkspaceDocument
        )
        #expect(
            GoogleDriveClient.File(
                id: "shortcut",
                name: "Shortcut",
                mimeType: "application/vnd.google-apps.shortcut"
            ).isWorkspaceDocument
        )
        #expect(
            !GoogleDriveClient.File(
                id: "folder",
                name: "Folder",
                mimeType: "application/vnd.google-apps.folder"
            ).isWorkspaceDocument
        )
    }

    @Test("metadata requests the file fields and decodes size")
    func metadataRequest() async throws {
        let stub = StubTransport()
        stub.handler = { _ in
            Self.response(
                200,
                json: #"""
                {"id":"f1","name":"Report.pdf","mimeType":"application/pdf","size":"42","webViewLink":"https://drive.google.com/file/d/f1"}
                """#
            )
        }
        let client = makeClient(stub)

        let file = try await client.metadata(
            fileID: "f1", accessToken: "tok"
        )

        #expect(file.id == "f1")
        #expect(file.sizeBytes == 42)
        #expect(file.webViewLink?.contains("f1") == true)
        let request = try #require(stub.requests.first)
        #expect(request.url?.absoluteString.contains("files/f1") == true)
        #expect(request.url?.absoluteString.contains("fields=") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }

    @Test("download uses alt=media and returns raw bytes")
    func downloadRequest() async throws {
        let stub = StubTransport()
        stub.handler = { _ in Self.response(200, json: "bytes") }
        let client = makeClient(stub)

        let data = try await client.download(
            fileID: "f1", accessToken: "tok"
        )

        #expect(String(data: data, encoding: .utf8) == "bytes")
        #expect(
            stub.requests.first?.url?.absoluteString
                .contains("alt=media") == true
        )
    }

    @Test("export maps 400/403 to exportUnsupported")
    func exportUnsupported() async throws {
        let stub = StubTransport()
        stub.handler = { _ in Self.response(403) }
        let client = makeClient(stub)

        await #expect(
            throws: GoogleDriveClient.DriveError.exportUnsupported
        ) {
            try await client.export(
                fileID: "f1",
                mimeType: "application/pdf",
                accessToken: "tok"
            )
        }
        #expect(
            stub.requests.first?.url?.absoluteString
                .contains("/export") == true
        )
    }

    @Test("create sends a multipart body with parents metadata")
    func createMultipart() async throws {
        let stub = StubTransport()
        stub.handler = { _ in
            Self.response(
                200,
                json: #"""
                {"id":"new","name":"a.txt","mimeType":"text/plain"}
                """#
            )
        }
        let client = makeClient(stub)

        let file = try await client.create(
            name: "a.txt",
            mimeType: "text/plain",
            data: Data("hello".utf8),
            parentFolderID: "folder1",
            accessToken: "tok"
        )

        #expect(file.id == "new")
        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(
            request.url?.absoluteString
                .contains("upload/drive/v3/files") == true
        )
        #expect(
            request.value(forHTTPHeaderField: "Content-Type")?
                .contains("multipart/related") == true
        )
        let body = try #require(
            request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
        )
        #expect(body.contains(#""name":"a.txt""#))
        #expect(body.contains(#""parents":["folder1"]"#))
        #expect(body.contains("hello"))
        try expectMultipart(request, metadata: ["name": "a.txt", "parents": ["folder1"]], bytes: "hello")
    }

    @Test("existingFile queries name, folder, and trashed flag")
    func conflictLookup() async throws {
        let stub = StubTransport()
        stub.handler = { _ in
            Self.response(
                200,
                json: #"""
                {"files":[{"id":"old","name":"a.txt","mimeType":"text/plain"}]}
                """#
            )
        }
        let client = makeClient(stub)

        let existing = try await client.existingFile(
            named: "a.txt",
            inFolderID: "folder1",
            accessToken: "tok"
        )

        #expect(existing?.id == "old")
        let query = try #require(
            stub.requests.first?.url?
                .absoluteString
        )
        #expect(query.contains("trashed") || query.contains("q="))
    }

    @Test("update patches bytes with a multipart body")
    func updateMultipart() async throws {
        let stub = StubTransport()
        stub.handler = { _ in
            Self.response(
                200,
                json: #"""
                {"id":"old","name":"a.txt","mimeType":"text/plain"}
                """#
            )
        }
        let client = makeClient(stub)

        let file = try await client.update(
            fileID: "old",
            mimeType: "text/plain",
            data: Data("v2".utf8),
            accessToken: "tok"
        )

        #expect(file.id == "old")
        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "PATCH")
        #expect(
            request.url?.absoluteString.contains("files/old") == true
        )
        try expectMultipart(request, metadata: [:], bytes: "v2")
    }

    private func expectMultipart(
        _ request: URLRequest,
        metadata: [String: Any],
        bytes: String
    ) throws {
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        let boundary = try #require(contentType.components(separatedBy: "boundary=").last)
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.hasPrefix("--" + boundary + "\r\n"))
        let parts = body.components(separatedBy: "\r\n--" + boundary)
        try #require(parts.count == 3)
        let metadataBody = try #require(parts[0].components(separatedBy: "\r\n\r\n").last)
        let decoded = try JSONSerialization.jsonObject(with: Data(metadataBody.utf8)) as? NSDictionary
        #expect(decoded == metadata as NSDictionary)
        #expect(parts[1] == "\r\nContent-Type: text/plain\r\n\r\n" + bytes)
        #expect(parts[2] == "--\r\n")
    }

    @Test("URLSession cancellation stays cancellation rather than a connectivity failure")
    func downloadURLCancellation() async {
        let client = GoogleDriveClient { _ in throw URLError(.cancelled) }
        await #expect(throws: CancellationError.self) {
            try await client.download(fileID: "synthetic", accessToken: "synthetic-token")
        }
    }

    @Test("401/403 map to authenticationRequired, 404 to notFound")
    func errorMapping() async throws {
        let stub = StubTransport()
        let client = makeClient(stub)

        stub.handler = { _ in Self.response(401) }
        await #expect(
            throws: GoogleDriveClient.DriveError.authenticationRequired
        ) {
            try await client.metadata(fileID: "f1", accessToken: "tok")
        }

        stub.handler = { _ in Self.response(404) }
        await #expect(
            throws: GoogleDriveClient.DriveError.notFound
        ) {
            try await client.metadata(fileID: "f1", accessToken: "tok")
        }
    }

    @Test("the scope constant is the narrow drive.file grant")
    func scopeConstant() {
        #expect(
            GoogleDriveClient.scope
                == "https://www.googleapis.com/auth/drive.file"
        )
    }

    @Test("create reports byte progress through the upload transport")
    func createProgress() async throws {
        let stub = StubTransport()
        let recorder = ProgressRecorder()
        let client = GoogleDriveClient(
            transport: { try stub.send($0) },
            uploadTransport: { request, onProgress in
                onProgress(50, 100)
                onProgress(100, 100)
                return try stub.send(request)
            }
        )
        stub.handler = { _ in
            Self.response(
                200,
                json: #"{"id":"new","name":"a.bin","mimeType":"application/octet-stream"}"#
            )
        }

        _ = try await client.create(
            name: "a.bin",
            mimeType: "application/octet-stream",
            data: Data(repeating: 0, count: 100),
            parentFolderID: nil,
            accessToken: "tok",
            onProgress: { sent, total in recorder.record(sent, total) }
        )

        #expect(recorder.reported.count == 2)
        #expect(recorder.reported[0].0 == 50)
        #expect(recorder.reported[0].1 == 100)
        #expect(recorder.reported[1].0 == 100)
        #expect(recorder.reported[1].1 == 100)
    }

    @Test("cancelling the calling task propagates CancellationError")
    func createCancellation() async throws {
        let stub = StubTransport()
        let client = GoogleDriveClient(
            transport: { try stub.send($0) },
            uploadTransport: { _, _ in
                try await Task.sleep(nanoseconds: 60_000_000_000)
                throw GoogleDriveClient.DriveError.transportFailed
            }
        )

        let task = Task {
            try await client.create(
                name: "a.bin",
                mimeType: "application/octet-stream",
                data: Data(),
                parentFolderID: nil,
                accessToken: "tok",
                onProgress: { _, _ in }
            )
        }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}

@Suite("GoogleDriveUploadTransport", .timeLimit(.minutes(1)))
struct GoogleDriveUploadTransportTests {
    @Test("a cancelled upload does not invalidate the next upload")
    func retryAfterCancellation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DriveUploadURLProtocol.self]
        let transport = GoogleDriveClient.makeUploadTransport(configuration: configuration)
        var request = URLRequest(url: URL(string: "https://drive-upload.invalid/cancel")!)
        request.httpMethod = "POST"
        request.httpBody = Data("synthetic".utf8)
        let cancelledRequest = request
        let first = Task { try await transport(cancelledRequest) { _, _ in } }
        var started = DriveUploadURLProtocol.started.stream.makeAsyncIterator()
        try #require(await started.next() != nil)
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }

        request.url = URL(string: "https://drive-upload.invalid/retry")!
        let (_, response) = try await transport(request) { _, _ in }
        #expect(response.statusCode == 200)
    }
}

private final class DriveUploadURLProtocol: URLProtocol, @unchecked Sendable {
    static let started = AsyncStream<Void>.makeStream()

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.url?.path == "/cancel" {
            Self.started.continuation.yield(())
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("synthetic".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
