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

private final class CoordStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var statusCode = 201
    nonisolated(unsafe) static var requestCount = 0

    static func reset(statusCode: Int = 201) {
        Self.statusCode = statusCode
        requestCount = 0
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestCount += 1
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1", headerFields: [:]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func coordSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CoordStubURLProtocol.self]
    return URLSession(configuration: config)
}

private let event = ICSParser.ParsedEvent(
    uid: "evt-9@example.com", summary: "Planning", description: nil, location: nil,
    start: Date(timeIntervalSince1970: 1_700_000_000),
    end: Date(timeIntervalSince1970: 1_700_003_600),
    isAllDay: false, organizer: nil, attendees: []
)
private let me = ICSParser.ParsedPerson(name: "Me", email: "me@example.com")
private let ics = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:evt-9@example.com\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

@Suite("InviteAcceptanceCoordinator", .serialized)
struct InviteAcceptanceCoordinatorTests {
    @Test("no writer: iMIP reply still produced, calendar write skipped")
    func fallbackWithoutWriter() async throws {
        CoordStubURLProtocol.reset()
        let outcome = try await InviteAcceptanceCoordinator().handle(
            event: event, attendee: me, status: .accepted, originalICS: ics, writer: nil
        )
        #expect(outcome.reply.subject.contains("Accepted"))
        if case .skipped = outcome.calendarWrite {} else {
            Issue.record("Expected skipped, got \(outcome.calendarWrite)")
        }
        #expect(CoordStubURLProtocol.requestCount == 0)
    }

    @Test("with writer + accept: iMIP reply plus calendar write")
    func acceptWritesToCalendar() async throws {
        CoordStubURLProtocol.reset(statusCode: 201)
        let writer = CalDAVEventWriter(
            target: CalDAVWriteTarget(collectionURL: URL(string: "https://dav.example.com/cal/")!),
            credential: .bearer(token: "t"),
            urlSession: coordSession()
        )
        let outcome = try await InviteAcceptanceCoordinator().handle(
            event: event, attendee: me, status: .accepted, originalICS: ics, writer: writer
        )
        if case .written(let result) = outcome.calendarWrite {
            #expect(result.outcome == .created)
        } else {
            Issue.record("Expected written, got \(outcome.calendarWrite)")
        }
        #expect(CoordStubURLProtocol.requestCount == 1)
    }

    @Test("decline never writes to calendar even when configured")
    func declineSkipsCalendar() async throws {
        CoordStubURLProtocol.reset(statusCode: 201)
        let writer = CalDAVEventWriter(
            target: CalDAVWriteTarget(collectionURL: URL(string: "https://dav.example.com/cal/")!),
            credential: .bearer(token: "t"),
            urlSession: coordSession()
        )
        let outcome = try await InviteAcceptanceCoordinator().handle(
            event: event, attendee: me, status: .declined, originalICS: ics, writer: writer
        )
        #expect(outcome.reply.subject.contains("Declined"))
        if case .skipped = outcome.calendarWrite {} else {
            Issue.record("Expected skipped on decline")
        }
        #expect(CoordStubURLProtocol.requestCount == 0)
    }

    @Test("calendar write failure does not block the iMIP reply")
    func writeFailureStillReplies() async throws {
        CoordStubURLProtocol.reset(statusCode: 500)
        let writer = CalDAVEventWriter(
            target: CalDAVWriteTarget(collectionURL: URL(string: "https://dav.example.com/cal/")!),
            credential: .bearer(token: "t"),
            urlSession: coordSession()
        )
        let outcome = try await InviteAcceptanceCoordinator().handle(
            event: event, attendee: me, status: .accepted, originalICS: ics, writer: writer
        )
        #expect(outcome.reply.subject.contains("Accepted"))
        if case .failed(let error) = outcome.calendarWrite {
            #expect(error == .unexpectedStatus(500))
        } else {
            Issue.record("Expected failed, got \(outcome.calendarWrite)")
        }
    }
}
