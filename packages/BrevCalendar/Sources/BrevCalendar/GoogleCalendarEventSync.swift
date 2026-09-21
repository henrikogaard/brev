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
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Syncs events for one Google calendar collection (ADR-0072).
///
/// Initial sync runs a bounded `events.list` window with
/// `singleEvents=false` so recurrence masters and their exceptions
/// arrive as stored; incremental sync sends only the sync token — Google
/// rejects token requests that also carry time bounds or expansion
/// parameters. A 410 answer surfaces as `PIMEventSyncError.cursorExpired`
/// so the service can restart a full generation (sync rule 2).
///
/// Item payloads are kept verbatim in `PIMEvent.rawPayload` (R4): the
/// mapper reads fields out of the raw JSON object rather than decoding
/// into a lossy Codable shape.
public struct GoogleCalendarEventSync: Sendable {
    /// HTTP seam shared with the other PIM adapters.
    private let transport: any PIMDAVTransport
    /// Bound on pagination loops so a misbehaving provider cannot spin
    /// the sync forever.
    private static let maxPages = 40
    private static let eventsBaseURL =
        "https://www.googleapis.com/calendar/v3/calendars"

    public init(transport: any PIMDAVTransport = URLSessionPIMDAVTransport()) {
        self.transport = transport
    }

    /// Syncs one collection. `cursorToken` selects incremental mode;
    /// nil runs a windowed full listing.
    public func syncCollection(
        _ collection: PIMCollection,
        source: PIMSource,
        cursorToken: String?,
        windowStart: Date,
        windowEnd: Date,
        accessToken: String
    ) async throws -> PIMEventSyncResult {
        var result = PIMEventSyncResult(
            isFullSnapshot: cursorToken == nil
        )
        var pageToken: String?
        for _ in 0 ..< Self.maxPages {
            let url = try requestURL(
                collection: collection,
                cursorToken: cursorToken,
                pageToken: pageToken,
                windowStart: windowStart,
                windowEnd: windowEnd
            )
            let (data, response) = try await send(url, accessToken: accessToken)
            switch response.statusCode {
            case 200:
                let page = try parsePage(data)
                for item in page.items {
                    mapItem(
                        item,
                        collection: collection,
                        source: source,
                        into: &result
                    )
                }
                if let next = page.nextPageToken, !next.isEmpty {
                    pageToken = next
                    continue
                }
                result.nextCursorToken = page.nextSyncToken ?? cursorToken
                return result
            case 401, 403:
                throw PIMEventSyncError.authenticationRequired
            case 410:
                throw PIMEventSyncError.cursorExpired
            default:
                throw PIMEventSyncError.invalidResponse
            }
        }
        throw PIMEventSyncError.invalidResponse
    }

    // MARK: - Request

    private func requestURL(
        collection: PIMCollection,
        cursorToken: String?,
        pageToken: String?,
        windowStart: Date,
        windowEnd: Date
    ) throws -> URL {
        guard let encodedID = collection.providerKey.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) else {
            throw PIMEventSyncError.invalidResponse
        }
        var components = URLComponents(
            string: "\(Self.eventsBaseURL)/\(encodedID)/events"
        )
        var query = [
            URLQueryItem(name: "maxResults", value: "250")
        ]
        if let cursorToken {
            // Incremental: Google rejects time bounds, expansion and
            // filter parameters alongside syncToken — send only the token.
            query.append(URLQueryItem(name: "syncToken", value: cursorToken))
        } else {
            query.append(contentsOf: [
                URLQueryItem(name: "singleEvents", value: "false"),
                URLQueryItem(name: "showDeleted", value: "true"),
                URLQueryItem(
                    name: "timeMin",
                    value: Self.rfc3339.string(from: windowStart)
                ),
                URLQueryItem(
                    name: "timeMax",
                    value: Self.rfc3339.string(from: windowEnd)
                )
            ])
        }
        if let pageToken {
            query.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components?.queryItems = query
        guard let url = components?.url else {
            throw PIMEventSyncError.invalidResponse
        }
        return url
    }

    private func send(
        _ url: URL,
        accessToken: String
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            return try await transport.send(request)
        } catch let error as PIMEventSyncError {
            throw error
        } catch {
            throw PIMEventSyncError.transportFailed
        }
    }

    // MARK: - Page parsing

    private struct Page {
        let items: [[String: Any]]
        let nextPageToken: String?
        let nextSyncToken: String?
    }

    private func parsePage(_ data: Data) throws -> Page {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let page = object as? [String: Any]
        else {
            throw PIMEventSyncError.invalidResponse
        }
        return Page(
            items: page["items"] as? [[String: Any]] ?? [],
            nextPageToken: page["nextPageToken"] as? String,
            nextSyncToken: page["nextSyncToken"] as? String
        )
    }

    // MARK: - Item mapping

    /// Maps one Google event resource into the shared model. Cancelled
    /// entries carry only an ID — they become tombstones.
    private func mapItem(
        _ item: [String: Any],
        collection: PIMCollection,
        source: PIMSource,
        into result: inout PIMEventSyncResult
    ) {
        guard let itemID = item["id"] as? String, !itemID.isEmpty else {
            return
        }
        if (item["status"] as? String)?.lowercased() == "cancelled" {
            result.removedItemKeys.append(itemID)
            return
        }

        let start = item["start"] as? [String: Any]
        let end = item["end"] as? [String: Any]
        let isAllDay = start?["date"] != nil
        let timeZoneIdentifier = start?["timeZone"] as? String

        let recurrenceID = Self.parseGoogleDateTime(
            (item["originalStartTime"] as? [String: Any])?["dateTime"]
                as? String
        )

        let conference = GoogleConferenceMapping.conference(from: item)
        result.events.append(
            PIMEvent(
                id: PIMEvent.makeID(
                    collectionID: collection.id,
                    providerItemKey: itemID,
                    recurrenceID: recurrenceID
                ),
                sourceID: source.id,
                collectionID: collection.id,
                providerItemKey: itemID,
                providerVersion: item["etag"] as? String,
                uid: item["iCalUID"] as? String,
                summary: item["summary"] as? String,
                eventDescription: item["description"] as? String,
                location: item["location"] as? String,
                start: Self.parseGoogleStartEnd(start),
                end: Self.parseGoogleStartEnd(end),
                isAllDay: isAllDay,
                timeZoneIdentifier: timeZoneIdentifier,
                status: PIMEventStatus(
                    rawValue: item["status"] as? String
                ),
                organizer: Self.mapPerson(
                    item["organizer"] as? [String: Any]
                ),
                attendees: (item["attendees"] as? [[String: Any]] ?? [])
                    .compactMap(Self.mapPerson),
                reminders: Self.mapReminders(
                    item["reminders"] as? [String: Any]
                ),
                conferenceURL: conference?.joinURL,
                conference: conference,
                recurrenceRule: Self.mapRecurrence(
                    item["recurrence"] as? [String]
                ),
                recurrenceID: recurrenceID,
                rawPayload: Self.rawPayload(for: item),
                providerUpdatedAt: Self.parseGoogleDateTime(
                    item["updated"] as? String
                )
            )
        )
    }

    private static func mapPerson(
        _ dict: [String: Any]?
    ) -> PIMEventPerson? {
        guard let dict,
              let email = dict["email"] as? String, !email.isEmpty
        else { return nil }
        return PIMEventPerson(
            name: dict["displayName"] as? String,
            email: email,
            rsvp: PIMEventPerson.RSVP(
                rawValue: dict["responseStatus"] as? String
            )
        )
    }

    private static func mapReminders(
        _ dict: [String: Any]?
    ) -> [PIMEventReminder] {
        guard let dict else { return [] }
        let overrides = dict["overrides"] as? [[String: Any]] ?? []
        if !overrides.isEmpty {
            return overrides.map { override in
                PIMEventReminder(
                    minutesBefore: override["minutes"] as? Int,
                    method: PIMEventReminder.Method(
                        rawValue: override["method"] as? String
                    )
                )
            }
        }
        if dict["useDefault"] as? Bool == true {
            return [PIMEventReminder(minutesBefore: nil, method: .alert)]
        }
        return []
    }

    private static func mapRecurrence(
        _ entries: [String]?
    ) -> ICSParser.RecurrenceRule? {
        for entry in entries ?? [] {
            // Entries look like "RRULE:FREQ=WEEKLY;BYDAY=MO".
            guard let colon = entry.firstIndex(of: ":") else { continue }
            let name = entry[..<colon].uppercased()
            guard name == "RRULE" else { continue }
            if let rule = ICSParser.parseRecurrenceRule(
                String(entry[entry.index(after: colon)...])
            ) {
                return rule
            }
        }
        return nil
    }

    /// The verbatim item JSON — provider fields the shared model does
    /// not read still survive refresh and later edits (ADR-0072 R4).
    private static func rawPayload(for item: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(item),
              let data = try? JSONSerialization.data(
                  withJSONObject: item,
                  options: [.sortedKeys]
              )
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Dates

    /// Parses an RFC 3339 timestamp with or without fractional seconds.
    static func parseGoogleDateTime(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let date = Self.rfc3339.date(from: raw) { return date }
        return Self.rfc3339Fractional.date(from: raw)
    }

    /// start/end values carry either `dateTime` or a date-only `date`.
    static func parseGoogleStartEnd(_ dict: [String: Any]?) -> Date? {
        guard let dict else { return nil }
        if let dateTime = dict["dateTime"] as? String {
            return parseGoogleDateTime(dateTime)
        }
        if let date = dict["date"] as? String {
            return Self.dateOnly.date(from: date)
        }
        return nil
    }

    private static let rfc3339: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let rfc3339Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime, .withFractionalSeconds
        ]
        return formatter
    }()

    private static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
