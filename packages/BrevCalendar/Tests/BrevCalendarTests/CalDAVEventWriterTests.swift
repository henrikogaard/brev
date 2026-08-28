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
import Testing

// MARK: - Captured request

private struct CapturedDAVRequest: Sendable {
    let url: URL?
    let method: String?
    let headers: [String: String]
    let bodyData: Data

    func header(_ name: String) -> String? { headers[name] }
    var bodyString: String { String(decoding: bodyData, as: UTF8.self) }
}

// MARK: - URLProtocol stub

private final class DAVStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var statusCode = 201
    nonisolated(unsafe) static var responseHeaders: [String: String] = [:]
    nonisolated(unsafe) static var stubbedError: Error?
    nonisolated(unsafe) static var captured: [CapturedDAVRequest] = []

    static func reset(statusCode: Int = 201, headers: [String: String] = [:], error: Error? = nil) {
        Self.statusCode = statusCode
        responseHeaders = headers
        stubbedError = error
        captured = []
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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
        Self.captured.append(CapturedDAVRequest(
            url: request.url, method: request.httpMethod, headers: headers, bodyData: bodyData
        ))

        if let error = Self.stubbedError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: Self.responseHeaders
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [DAVStubURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeWriter(
    collection: String = "https://caldav.example.com/calendars/u/personal/",
    credential: CalDAVCredential = .bearer(token: "tok-123")
) -> CalDAVEventWriter {
    CalDAVEventWriter(
        target: CalDAVWriteTarget(collectionURL: URL(string: collection)!),
        credential: credential,
        urlSession: makeSession()
    )
}

private let sampleEvent = ICSParser.ParsedEvent(
    uid: "abc-123@example.com",
    summary: "Sprint review",
    description: nil,
    location: nil,
    start: Date(timeIntervalSince1970: 1_700_000_000),
    end: Date(timeIntervalSince1970: 1_700_003_600),
    isAllDay: false,
    organizer: nil,
    attendees: []
)

private let sampleICS = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:abc-123@example.com\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

// MARK: - Tests

@Suite("CalDAVEventWriter", .serialized)
struct CalDAVEventWriterTests {
    @Test("PUT goes to collection/UID.ics with calendar content type and auth")
    func putRequestShape() async throws {
        DAVStubURLProtocol.reset(statusCode: 201)
        _ = try await makeWriter().putEvent(sampleEvent, ics: sampleICS)

        let req = try #require(DAVStubURLProtocol.captured.last)
        #expect(req.method == "PUT")
        // '@' is not URL-path-safe in our allow-list, so it is sanitized to '-'.
        #expect(req.url?.lastPathComponent == "abc-123-example.com.ics")
        #expect(req.url?.absoluteString.hasPrefix("https://caldav.example.com/calendars/u/personal/") == true)
        #expect(req.header("Content-Type")?.contains("text/calendar") == true)
        #expect(req.header("Authorization") == "Bearer tok-123")
        #expect(req.bodyString == sampleICS)
    }

    @Test("conditional create sends If-None-Match by default")
    func conditionalCreateHeader() async throws {
        DAVStubURLProtocol.reset(statusCode: 201)
        _ = try await makeWriter().putEvent(sampleEvent, ics: sampleICS)
        let req = try #require(DAVStubURLProtocol.captured.last)
        #expect(req.header("If-None-Match") == "*")
    }

    @Test("overwrite omits If-None-Match")
    func overwriteOmitsConditional() async throws {
        DAVStubURLProtocol.reset(statusCode: 204)
        _ = try await makeWriter().putEvent(sampleEvent, ics: sampleICS, overwriteExisting: true)
        let req = try #require(DAVStubURLProtocol.captured.last)
        #expect(req.header("If-None-Match") == nil)
    }

    @Test("201 maps to created and surfaces ETag")
    func createdOutcome() async throws {
        DAVStubURLProtocol.reset(statusCode: 201, headers: ["ETag": "\"etag-1\""])
        let result = try await makeWriter().putEvent(sampleEvent, ics: sampleICS)
        #expect(result.outcome == .created)
        #expect(result.etag == "\"etag-1\"")
    }

    @Test("204 maps to updated")
    func updatedOutcome() async throws {
        DAVStubURLProtocol.reset(statusCode: 204)
        let result = try await makeWriter().putEvent(sampleEvent, ics: sampleICS, overwriteExisting: true)
        #expect(result.outcome == .updated)
    }

    @Test("412 maps to conflict")
    func conflictMapping() async throws {
        DAVStubURLProtocol.reset(statusCode: 412)
        await #expect(throws: CalDAVWriteError.conflict) {
            _ = try await makeWriter().putEvent(sampleEvent, ics: sampleICS)
        }
    }

    @Test("401 maps to authenticationFailed")
    func authFailure() async throws {
        DAVStubURLProtocol.reset(statusCode: 401)
        await #expect(throws: CalDAVWriteError.authenticationFailed) {
            _ = try await makeWriter().putEvent(sampleEvent, ics: sampleICS)
        }
    }

    @Test("5xx maps to unexpectedStatus")
    func serverError() async throws {
        DAVStubURLProtocol.reset(statusCode: 503)
        await #expect(throws: CalDAVWriteError.unexpectedStatus(503)) {
            _ = try await makeWriter().putEvent(sampleEvent, ics: sampleICS)
        }
    }

    @Test("event without UID throws missingUID before any request")
    func missingUID() async throws {
        DAVStubURLProtocol.reset(statusCode: 201)
        let noUID = ICSParser.ParsedEvent(
            uid: "  ", summary: "x", description: nil, location: nil,
            start: nil, end: nil, isAllDay: false, organizer: nil, attendees: []
        )
        await #expect(throws: CalDAVWriteError.missingUID) {
            _ = try await makeWriter().putEvent(noUID, ics: sampleICS)
        }
        #expect(DAVStubURLProtocol.captured.isEmpty)
    }

    @Test("transport failure maps to transport error")
    func transportError() async throws {
        DAVStubURLProtocol.reset(error: URLError(.notConnectedToInternet))
        await #expect(throws: CalDAVWriteError.self) {
            _ = try await makeWriter().putEvent(sampleEvent, ics: sampleICS)
        }
    }

    @Test("HTTP Basic over a public host is rejected before any request")
    func basicAuthRejectedRemotely() async throws {
        DAVStubURLProtocol.reset(statusCode: 201)
        let writer = makeWriter(
            collection: "https://caldav.example.com/calendars/u/personal/",
            credential: .basic(username: "u", password: "p")
        )
        await #expect(throws: CalDAVWriteError.insecureBasicAuth) {
            _ = try await writer.putEvent(sampleEvent, ics: sampleICS)
        }
        #expect(DAVStubURLProtocol.captured.isEmpty)
    }

    @Test("HTTP Basic on localhost is allowed")
    func basicAuthLocalhostAllowed() async throws {
        DAVStubURLProtocol.reset(statusCode: 201)
        let writer = makeWriter(
            collection: "http://localhost:8080/cal/",
            credential: .basic(username: "u", password: "p")
        )
        _ = try await writer.putEvent(sampleEvent, ics: sampleICS)
        let req = try #require(DAVStubURLProtocol.captured.last)
        // base64("u:p") == "dTpw"
        #expect(req.header("Authorization") == "Basic dTpw")
    }

    @Test("write target sanitizes path-hostile UIDs")
    func sanitizesUID() {
        let target = CalDAVWriteTarget(collectionURL: URL(string: "https://h/cal/")!)
        let url = target.resourceURL(forUID: "weird/uid with spaces")
        #expect(url.lastPathComponent.hasSuffix(".ics"))
        #expect(!url.lastPathComponent.contains(" "))
        #expect(!url.lastPathComponent.contains("/"))
    }
}
