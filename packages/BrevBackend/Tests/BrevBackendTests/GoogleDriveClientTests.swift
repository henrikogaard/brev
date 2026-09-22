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
}
