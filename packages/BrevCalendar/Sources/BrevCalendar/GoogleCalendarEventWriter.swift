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

import Foundation

/// Writes events to Google Calendar via the `events` REST resource
/// (ADR-0072 #7).
///
/// Insert, patch, and delete only — sync stays with
/// `GoogleCalendarEventSync`. Every call needs the
/// `calendar.events` scope the write-enablement flow grants
/// (`GooglePIMScopes.calendarEvents`); a missing grant surfaces as
/// `authenticationRequired` rather than a silent failure. All
/// three mutations send `sendUpdates=all` so guests are
/// notified — the parameter is a no-op on events without attendees.
public struct GoogleCalendarEventWriter: Sendable {
    /// Errors surfaced by the Google write path.
    public enum WriteError: Error, Sendable, Hashable, LocalizedError {
        /// The credential was rejected or lacks the write scope.
        case authenticationRequired
        /// The event changed remotely since the cached copy — the
        /// caller reloads and re-asks rather than overwriting.
        case conflict
        /// The provider answered with a status or body Brev cannot use.
        case invalidResponse
        /// Connectivity or an unspecified transport failure.
        case transportFailed

        public var errorDescription: String? {
            switch self {
            case .authenticationRequired:
                String(
                    localized:
                    "Editing needs a fresh Google grant. Reconnect the calendar in Settings.",
                    bundle: .module
                )
            case .conflict:
                String(
                    localized:
                    "This event changed on the server. Sync, then try again.",
                    bundle: .module
                )
            case .invalidResponse:
                String(
                    localized:
                    "Google Calendar returned a response Brev could not use.",
                    bundle: .module
                )
            case .transportFailed:
                String(
                    localized:
                    "Google Calendar could not be reached. Check the connection and try again.",
                    bundle: .module
                )
            }
        }
    }

    /// Outcome of a successful write — the provider's event ID and ETag.
    public struct WriteResult: Sendable, Hashable {
        public let eventID: String
        public let etag: String?

        public init(eventID: String, etag: String?) {
            self.eventID = eventID
            self.etag = etag
        }
    }

    /// The transport seam — tests inject a stubbed sender.
    public typealias Transport =
        @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private static let baseURL =
        "https://www.googleapis.com/calendar/v3/calendars"

    private let transport: Transport

    public init(
        transport: @escaping Transport = { request in
            let (data, response) = try await URLSession.shared.data(
                for: request
            )
            guard let http = response as? HTTPURLResponse else {
                throw WriteError.invalidResponse
            }
            return (data, http)
        }
    ) {
        self.transport = transport
    }

    // MARK: - Writes

    /// Creates an event in the collection. Returns the provider's new
    /// event ID and ETag.
    public func insert(
        _ event: PIMEvent,
        into collection: PIMCollection,
        accessToken: String
    ) async throws -> WriteResult {
        let url = try eventsURL(
            collection: collection,
            notifyGuests: true
        )
        var request = try jsonRequest(url: url, method: "POST", accessToken: accessToken)
        request.httpBody = try body(for: event)
        let (data, response) = try await send(request)
        try requireSuccess(response, allowed: 200 ..< 300)
        return try parseResult(data)
    }

    /// Replaces the writable fields of an existing event. The cached
    /// `providerVersion` (Google etag) rides along as an
    /// `If-Match` precondition so a stale edit never clobbers a newer
    /// remote change — a 412 maps to `conflict`.
    public func patch(
        _ event: PIMEvent,
        in collection: PIMCollection,
        accessToken: String
    ) async throws -> WriteResult {
        let url = try eventURL(
            collection: collection,
            eventID: event.providerItemKey,
            notifyGuests: true
        )
        var request = try jsonRequest(url: url, method: "PATCH", accessToken: accessToken)
        if let etag = event.providerVersion {
            request.setValue(etag, forHTTPHeaderField: "If-Match")
        }
        request.httpBody = try body(for: event)
        let (data, response) = try await send(request)
        try requireSuccess(response, allowed: 200 ..< 300)
        return try parseResult(data)
    }

    /// Deletes an event. The cached etag rides as `If-Match` when
    /// present — a 412 means the remote changed first.
    public func delete(
        _ event: PIMEvent,
        in collection: PIMCollection,
        accessToken: String
    ) async throws {
        let url = try eventURL(
            collection: collection,
            eventID: event.providerItemKey,
            notifyGuests: true
        )
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        if let etag = event.providerVersion {
            request.setValue(etag, forHTTPHeaderField: "If-Match")
        }
        let (_, response) = try await send(request)
        try requireSuccess(response, allowed: [200, 204, 404])
    }

    // MARK: - Body mapping

    /// The Google `events` resource body for a shared event. Fields the
    /// model does not own (conferenceData, guestsCanModify, …) are left
    /// out — a PATCH only touches the keys it carries, and the cached
    /// rawPayload keeps the full provider record for the next sync.
    public func body(for event: PIMEvent) throws -> Data {
        var dict: [String: Any] = [:]
        dict["summary"] = event.summary ?? ""
        if let description = event.eventDescription {
            dict["description"] = description
        }
        if let location = event.location {
            dict["location"] = location
        }
        dict["status"] = googleStatus(event.status)
        dict["start"] = startEndDict(
            date: event.start,
            isAllDay: event.isAllDay,
            timeZoneIdentifier: event.timeZoneIdentifier
        )
        dict["end"] = startEndDict(
            date: event.end,
            isAllDay: event.isAllDay,
            timeZoneIdentifier: event.timeZoneIdentifier
        )
        if let rule = event.recurrenceRule {
            dict["recurrence"] = ["RRULE:" + recurrenceText(rule)]
        }
        if !event.attendees.isEmpty {
            dict["attendees"] = event.attendees.map { person in
                var entry: [String: Any] = ["email": person.email]
                if let name = person.name { entry["displayName"] = name }
                if let response = googleRSVP(person.rsvp) {
                    entry["responseStatus"] = response
                }
                return entry
            }
        }
        if let organizer = event.organizer {
            dict["organizer"] = [
                "email": organizer.email,
                "displayName": organizer.name ?? "",
            ]
        }
        if !event.reminders.isEmpty {
            dict["reminders"] = [
                "useDefault": false,
                "overrides": event.reminders.compactMap { reminder in
                    reminder.minutesBefore.map {
                        ["method": "popup", "minutes": $0] as [String: Any]
                    }
                },
            ]
        }
        if let uid = event.uid {
            dict["iCalUID"] = uid
        }
        do {
            return try JSONSerialization.data(withJSONObject: dict)
        } catch {
            throw WriteError.invalidResponse
        }
    }

    // MARK: - Helpers

    private func eventsURL(
        collection: PIMCollection,
        notifyGuests: Bool
    ) throws -> URL {
        guard let encoded = collection.providerKey.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ), let url = URL(
            string:
            "\(Self.baseURL)/\(encoded)/events"
                + (notifyGuests ? "?sendUpdates=all" : "")
        ) else {
            throw WriteError.invalidResponse
        }
        return url
    }

    private func eventURL(
        collection: PIMCollection,
        eventID: String,
        notifyGuests: Bool
    ) throws -> URL {
        guard let encodedCollection = collection.providerKey
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let encodedEvent = eventID.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ),
            let url = URL(
                string:
                "\(Self.baseURL)/\(encodedCollection)/events/\(encodedEvent)"
                    + (notifyGuests ? "?sendUpdates=all" : "")
            )
        else {
            throw WriteError.invalidResponse
        }
        return url
    }

    private func jsonRequest(
        url: URL,
        method: String,
        accessToken: String
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        return request
    }

    private func send(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport(request)
        } catch let error as WriteError {
            throw error
        } catch {
            throw WriteError.transportFailed
        }
    }

    private func requireSuccess(
        _ response: HTTPURLResponse,
        allowed: some Sequence<Int> & Sendable
    ) throws {
        if allowed.contains(response.statusCode) { return }
        switch response.statusCode {
        case 401, 403:
            throw WriteError.authenticationRequired
        case 409, 412:
            throw WriteError.conflict
        default:
            throw WriteError.invalidResponse
        }
    }

    private func parseResult(_ data: Data) throws -> WriteResult {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              let id = dict["id"] as? String, !id.isEmpty
        else {
            throw WriteError.invalidResponse
        }
        return WriteResult(
            eventID: id,
            etag: dict["etag"] as? String
        )
    }

    // MARK: - Field mapping

    /// Google start/end shape: all-day uses `date` (yyyy-mm-dd, the
    /// stored exclusive end), timed uses `dateTime` RFC 3339 plus the
    /// event's zone when known.
    private func startEndDict(
        date: Date?,
        isAllDay: Bool,
        timeZoneIdentifier: String?
    ) -> [String: Any] {
        guard let date else { return [:] }
        if isAllDay {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            let c = utc.dateComponents(
                [.year, .month, .day],
                from: date
            )
            return [
                "date": String(
                    format: "%04d-%02d-%02d",
                    c.year ?? 0, c.month ?? 0, c.day ?? 0
                ),
            ]
        }
        var dict: [String: Any] = [
            "dateTime": Self.rfc3339.string(from: date)
        ]
        if let timeZoneIdentifier {
            dict["timeZone"] = timeZoneIdentifier
        }
        return dict
    }

    private func googleStatus(_ status: PIMEventStatus) -> String {
        switch status {
        case .confirmed: "confirmed"
        case .tentative: "tentative"
        case .cancelled: "cancelled"
        }
    }

    private func googleRSVP(_ rsvp: PIMEventPerson.RSVP) -> String? {
        switch rsvp {
        case .accepted: "accepted"
        case .declined: "declined"
        case .tentative: "tentative"
        case .needsAction: "needsAction"
        case .delegated, .unknown: nil
        }
    }

    private func recurrenceText(
        _ rule: ICSParser.RecurrenceRule
    ) -> String {
        var parts = ["FREQ=" + rule.frequency.rawValue]
        if rule.interval > 1 {
            parts.append("INTERVAL=\(rule.interval)")
        }
        if let count = rule.count {
            parts.append("COUNT=\(count)")
        }
        if let until = rule.until {
            let formatter = Self.rfc3339
            parts.append("UNTIL=" + formatter.string(from: until)
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: ":", with: ""))
        }
        if let byDay = rule.byDay, !byDay.isEmpty {
            parts.append(
                "BYDAY=" + byDay.map(\.rawValue).joined(separator: ",")
            )
        }
        return parts.joined(separator: ";")
    }

    private static let rfc3339: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
