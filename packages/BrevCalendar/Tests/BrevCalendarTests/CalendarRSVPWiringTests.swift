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

/// Tests that directly verify the three requirements called out in the
/// "Wire `IMIPReplyComposer` → `CalDAVEventWriter`" task:
///
/// 1. `InviteAcceptanceCoordinator` produces an `ACCEPTED` iMIP reply for an
///    accepted event.
/// 2. CalDAV write failure does not propagate as an error from the coordinator.
/// 3. `IMIPReplyComposer` sets `PARTSTAT=ACCEPTED/DECLINED/TENTATIVE`
///    correctly in the generated ICS.
@testable import BrevCalendar
import Foundation
import Testing

// MARK: - Stub URLProtocol

private final class RSVPStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var statusCode = 201

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func rsvpSession(statusCode: Int) -> URLSession {
    RSVPStubURLProtocol.statusCode = statusCode
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [RSVPStubURLProtocol.self]
    return URLSession(configuration: config)
}

// MARK: - Shared fixtures

private let sampleEvent = ICSParser.ParsedEvent(
    uid: "rsvp-wire-test@example.com",
    summary: "Wiring review",
    description: nil,
    location: nil,
    start: Date(timeIntervalSince1970: 1_800_000_000),
    end: Date(timeIntervalSince1970: 1_800_003_600),
    isAllDay: false,
    organizer: ICSParser.ParsedPerson(name: "Organizer", email: "org@example.com"),
    attendees: [ICSParser.ParsedPerson(name: "Attendee", email: "me@example.com")]
)

private let sampleAttendee = ICSParser.ParsedPerson(name: "Attendee", email: "me@example.com")

private let sampleICS = """
BEGIN:VCALENDAR\r
VERSION:2.0\r
BEGIN:VEVENT\r
UID:rsvp-wire-test@example.com\r
SUMMARY:Wiring review\r
END:VEVENT\r
END:VCALENDAR\r

"""

private let writeTarget = CalDAVWriteTarget(
    collectionURL: URL(string: "https://dav.example.com/calendars/personal/")!
)

// MARK: - Test suite

@Suite("CalendarRSVPWiring", .serialized)
struct CalendarRSVPWiringTests {
    // MARK: Requirement 1: coordinator produces ACCEPTED iMIP reply

    @Test("coordinator produces METHOD:REPLY with ACCEPTED status for an accepted event")
    func coordinatorProducesAcceptedIMIPReply() async throws {
        let outcome = try await InviteAcceptanceCoordinator().handle(
            event: sampleEvent,
            attendee: sampleAttendee,
            status: .accepted,
            originalICS: sampleICS,
            writer: nil // No CalDAV needed to verify the iMIP path
        )

        #expect(outcome.reply.subject.hasPrefix("Accepted:"))
        #expect(outcome.reply.ics.contains("METHOD:REPLY"))
        #expect(outcome.reply.ics.contains("PARTSTAT=ACCEPTED"))
        #expect(outcome.reply.ics.contains("UID:rsvp-wire-test@example.com"))
        #expect(outcome.reply.plainTextBody.contains("accepted"))
    }

    @Test("coordinator produces METHOD:REPLY with ACCEPTED status and writes to CalDAV when writer is configured")
    func coordinatorAcceptsAndWritesToCalDAV() async throws {
        let writer = CalDAVEventWriter(
            target: writeTarget,
            credential: .bearer(token: "tok"),
            urlSession: rsvpSession(statusCode: 201)
        )
        let outcome = try await InviteAcceptanceCoordinator().handle(
            event: sampleEvent,
            attendee: sampleAttendee,
            status: .accepted,
            originalICS: sampleICS,
            writer: writer
        )

        // iMIP reply always present
        #expect(outcome.reply.subject.hasPrefix("Accepted:"))
        #expect(outcome.reply.ics.contains("PARTSTAT=ACCEPTED"))

        // CalDAV write happened
        if case .written(let result) = outcome.calendarWrite {
            #expect(result.outcome == .created)
        } else {
            Issue.record("Expected .written, got \(outcome.calendarWrite)")
        }
    }

    // MARK: Requirement 2: CalDAV write failure does not propagate

    @Test("CalDAV write failure is non-fatal — iMIP reply is still returned as the result")
    func calDAVWriteFailureIsNonFatal() async throws {
        // A 500 from the server → CalDAVWriteError.unexpectedStatus(500)
        let writer = CalDAVEventWriter(
            target: writeTarget,
            credential: .bearer(token: "tok"),
            urlSession: rsvpSession(statusCode: 500)
        )

        // The call must NOT throw even though the CalDAV write fails.
        let outcome = try await InviteAcceptanceCoordinator().handle(
            event: sampleEvent,
            attendee: sampleAttendee,
            status: .accepted,
            originalICS: sampleICS,
            writer: writer
        )

        // iMIP reply is intact
        #expect(outcome.reply.ics.contains("PARTSTAT=ACCEPTED"))

        // Write failure is captured, not thrown
        if case .failed(let error) = outcome.calendarWrite {
            #expect(error == .unexpectedStatus(500))
        } else {
            Issue.record("Expected .failed, got \(outcome.calendarWrite)")
        }
    }

    @Test("CalDAV write failure for auth error is non-fatal")
    func calDAVAuthFailureIsNonFatal() async throws {
        let writer = CalDAVEventWriter(
            target: writeTarget,
            credential: .bearer(token: "bad-token"),
            urlSession: rsvpSession(statusCode: 401)
        )

        let outcome = try await InviteAcceptanceCoordinator().handle(
            event: sampleEvent,
            attendee: sampleAttendee,
            status: .accepted,
            originalICS: sampleICS,
            writer: writer
        )

        #expect(outcome.reply.ics.contains("PARTSTAT=ACCEPTED"))
        if case .failed(let error) = outcome.calendarWrite {
            #expect(error == .authenticationFailed)
        } else {
            Issue.record("Expected .failed(.authenticationFailed), got \(outcome.calendarWrite)")
        }
    }

    // MARK: Requirement 3: IMIPReplyComposer PARTSTAT values

    @Test("IMIPReplyComposer sets PARTSTAT=ACCEPTED for accepted status")
    func imipReplyComposerSetsAcceptedPartstat() throws {
        let reply = try IMIPReplyComposer.compose(
            event: sampleEvent,
            attendee: sampleAttendee,
            status: .accepted
        )

        #expect(reply.ics.contains("PARTSTAT=ACCEPTED"))
        #expect(!reply.ics.contains("PARTSTAT=DECLINED"))
        #expect(!reply.ics.contains("PARTSTAT=TENTATIVE"))
    }

    @Test("IMIPReplyComposer sets PARTSTAT=DECLINED for declined status")
    func imipReplyComposerSetsDeclinedPartstat() throws {
        let reply = try IMIPReplyComposer.compose(
            event: sampleEvent,
            attendee: sampleAttendee,
            status: .declined
        )

        #expect(reply.ics.contains("PARTSTAT=DECLINED"))
        #expect(!reply.ics.contains("PARTSTAT=ACCEPTED"))
        #expect(!reply.ics.contains("PARTSTAT=TENTATIVE"))
        #expect(reply.subject.hasPrefix("Declined:"))
    }

    @Test("IMIPReplyComposer sets PARTSTAT=TENTATIVE for tentative status")
    func imipReplyComposerSetsTentativePartstat() throws {
        let reply = try IMIPReplyComposer.compose(
            event: sampleEvent,
            attendee: sampleAttendee,
            status: .tentative
        )

        #expect(reply.ics.contains("PARTSTAT=TENTATIVE"))
        #expect(!reply.ics.contains("PARTSTAT=ACCEPTED"))
        #expect(!reply.ics.contains("PARTSTAT=DECLINED"))
        #expect(reply.subject.hasPrefix("Maybe:"))
    }

    @Test("all three PARTSTAT values produce distinct subjects and body verbs")
    func allPartstatValuesProduceDistinctSubjectsAndBodyVerbs() throws {
        let accepted = try IMIPReplyComposer.compose(
            event: sampleEvent, attendee: sampleAttendee, status: .accepted
        )
        let tentative = try IMIPReplyComposer.compose(
            event: sampleEvent, attendee: sampleAttendee, status: .tentative
        )
        let declined = try IMIPReplyComposer.compose(
            event: sampleEvent, attendee: sampleAttendee, status: .declined
        )

        // Subjects are distinct
        #expect(accepted.subject != tentative.subject)
        #expect(accepted.subject != declined.subject)
        #expect(tentative.subject != declined.subject)

        // Body verbs reflect the status
        #expect(accepted.plainTextBody.contains("accepted"))
        #expect(tentative.plainTextBody.contains("tentatively accepted"))
        #expect(declined.plainTextBody.contains("declined"))
    }
}
