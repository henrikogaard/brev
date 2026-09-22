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

/// Syncs events for one CalDAV collection (ADR-0072 sync rule 3).
///
/// Collections that advertise sync-token support use the RFC 6578
/// `sync-collection` REPORT — an empty token returns the complete
/// state, a stored token returns only changes plus removed hrefs.
/// Servers without it fall back to a bounded `calendar-query` listing:
/// hrefs and ETags diff against the cached versions, changed items are
/// fetched by `calendar-multiget`, and hrefs missing from a complete
/// listing are treated as deletions.
///
/// Raw calendar-data is kept verbatim in `PIMEvent.rawPayload` (R4).
public struct PIMDAVEventSync: Sendable {
    private let transport: any PIMDAVTransport
    private static let maxRedirectHops = 2

    public init(transport: any PIMDAVTransport = URLSessionPIMDAVTransport()) {
        self.transport = transport
    }

    /// Syncs one collection. `cursorToken` is the stored sync-token;
    /// `cachedVersions` maps provider item key → ETag for the cached
    /// set so the fallback path can diff without refetching unchanged
    /// items.
    public func syncCollection(
        _ collection: PIMCollection,
        source: PIMSource,
        cursorToken: String?,
        cachedVersions: [String: String],
        windowStart: Date,
        windowEnd: Date,
        credential: CalDAVCredential
    ) async throws -> PIMEventSyncResult {
        guard let collectionURL = URL(string: collection.providerKey) else {
            throw PIMEventSyncError.invalidResponse
        }
        if collection.supportsSyncToken {
            do {
                return try await syncCollectionReport(
                    collection: collection,
                    collectionURL: collectionURL,
                    source: source,
                    cursorToken: cursorToken,
                    credential: credential
                )
            } catch PIMEventSyncError.unsupportedServer {
                // Advertised but not implemented — degrade to the
                // bounded listing path rather than failing the source.
            }
        }
        return try await calendarQuerySync(
            collection: collection,
            collectionURL: collectionURL,
            source: source,
            cachedVersions: cachedVersions,
            windowStart: windowStart,
            windowEnd: windowEnd,
            credential: credential
        )
    }

    // MARK: - RFC 6578 sync-collection

    private func syncCollectionReport(
        collection: PIMCollection,
        collectionURL: URL,
        source: PIMSource,
        cursorToken: String?,
        credential: CalDAVCredential
    ) async throws -> PIMEventSyncResult {
        let (data, response) = try await send(
            Self.syncCollectionRequest(
                collectionURL,
                cursorToken: cursorToken
            ),
            credential: credential
        )
        switch response.statusCode {
        case 207:
            break
        case 401, 403:
            // RFC 6578 answers an invalid token with 403 + a
            // DAV:valid-sync-token error body; a bare 403/401 is auth.
            if let body = String(data: data, encoding: .utf8),
               body.contains("valid-sync-token") {
                throw PIMEventSyncError.cursorExpired
            }
            if response.statusCode == 401 {
                throw PIMEventSyncError.authenticationRequired
            }
            throw PIMEventSyncError.authenticationRequired
        case 404, 405, 501:
            throw PIMEventSyncError.unsupportedServer
        case 412:
            throw PIMEventSyncError.cursorExpired
        default:
            throw PIMEventSyncError.invalidResponse
        }

        let report = PIMDAVSyncReportParser.parse(
            data,
            relativeTo: collectionURL
        )
        var result = PIMEventSyncResult(
            removedItemKeys: report.removedHrefs,
            nextCursorToken: report.syncToken ?? cursorToken,
            isFullSnapshot: cursorToken == nil
        )

        var needsFetch: [String] = []
        for member in report.members {
            guard let href = member.href else { continue }
            if let calendarData = member.calendarData {
                result.events.append(
                    contentsOf: mapCalendarData(
                        calendarData,
                        href: href,
                        etag: member.etag,
                        collection: collection,
                        source: source
                    )
                )
            } else {
                // The server omitted data for a changed member — fetch
                // it explicitly rather than dropping the update.
                needsFetch.append(href)
            }
        }
        if !needsFetch.isEmpty {
            let fetched = try await multiget(
                hrefs: needsFetch,
                collectionURL: collectionURL,
                collection: collection,
                source: source,
                credential: credential
            )
            result.events.append(contentsOf: fetched)
        }
        return result
    }

    // MARK: - calendar-query fallback

    /// Bounded listing for collections without sync-token support.
    /// Diffs the href→ETag listing against cached versions, fetches only
    /// changed items, and treats hrefs missing from the complete listing
    /// as deletions (ADR-0072 sync rule 3).
    private func calendarQuerySync(
        collection: PIMCollection,
        collectionURL: URL,
        source: PIMSource,
        cachedVersions: [String: String],
        windowStart: Date,
        windowEnd: Date,
        credential: CalDAVCredential
    ) async throws -> PIMEventSyncResult {
        let (data, response) = try await send(
            Self.calendarQueryRequest(
                collectionURL,
                windowStart: windowStart,
                windowEnd: windowEnd
            ),
            credential: credential
        )
        switch response.statusCode {
        case 207:
            break
        case 401, 403:
            throw PIMEventSyncError.authenticationRequired
        case 404, 405, 501:
            throw PIMEventSyncError.unsupportedServer
        default:
            throw PIMEventSyncError.invalidResponse
        }

        let report = PIMDAVSyncReportParser.parse(
            data,
            relativeTo: collectionURL
        )
        var listed: [String: String] = [:]
        for member in report.members {
            guard let href = member.href else { continue }
            listed[href] = member.etag ?? ""
        }

        var kept: [String] = []
        var fetch: [String] = []
        for (href, etag) in listed {
            if let cached = cachedVersions[href], cached == etag, !etag.isEmpty {
                kept.append(href)
            } else {
                fetch.append(href)
            }
        }
        let removed = cachedVersions.keys.filter { listed[$0] == nil }

        var events: [PIMEvent] = []
        if !fetch.isEmpty {
            events = try await multiget(
                hrefs: fetch,
                collectionURL: collectionURL,
                collection: collection,
                source: source,
                credential: credential
            )
        }
        return PIMEventSyncResult(
            events: events,
            removedItemKeys: removed,
            keptItemKeys: kept,
            nextCursorToken: nil,
            isFullSnapshot: true
        )
    }

    // MARK: - calendar-multiget

    private func multiget(
        hrefs: [String],
        collectionURL: URL,
        collection: PIMCollection,
        source: PIMSource,
        credential: CalDAVCredential
    ) async throws -> [PIMEvent] {
        var events: [PIMEvent] = []
        // Bound each request so a large delta does not produce an
        // unbounded body.
        for chunk in hrefs.chunked(into: 50) {
            let (data, response) = try await send(
                Self.multigetRequest(collectionURL, hrefs: chunk),
                credential: credential
            )
            switch response.statusCode {
            case 207:
                let report = PIMDAVSyncReportParser.parse(
                    data,
                    relativeTo: collectionURL
                )
                for member in report.members {
                    guard let href = member.href,
                          let calendarData = member.calendarData
                    else { continue }
                    events.append(
                        contentsOf: mapCalendarData(
                            calendarData,
                            href: href,
                            etag: member.etag,
                            collection: collection,
                            source: source
                        )
                    )
                }
            case 401, 403:
                throw PIMEventSyncError.authenticationRequired
            default:
                throw PIMEventSyncError.invalidResponse
            }
        }
        return events
    }

    // MARK: - Mapping

    /// Parses one calendar-data payload into one record per VEVENT —
    /// master plus recurrence exceptions share the item key (R7).
    private func mapCalendarData(
        _ calendarData: String,
        href: String,
        etag: String?,
        collection: PIMCollection,
        source: PIMSource
    ) -> [PIMEvent] {
        ICSParser.parseEvents(from: calendarData).map { parsed in
            PIMEvent(
                id: PIMEvent.makeID(
                    collectionID: collection.id,
                    providerItemKey: href,
                    recurrenceID: parsed.recurrenceID
                ),
                sourceID: source.id,
                collectionID: collection.id,
                providerItemKey: href,
                providerVersion: etag,
                uid: parsed.uid,
                summary: parsed.summary,
                eventDescription: parsed.description,
                location: parsed.location,
                start: parsed.start,
                end: parsed.end,
                isAllDay: parsed.isAllDay,
                timeZoneIdentifier: parsed.timeZoneIdentifier,
                status: PIMEventStatus(rawValue: parsed.status),
                organizer: parsed.organizer.map(Self.mapPerson),
                attendees: parsed.attendees.map(Self.mapPerson),
                reminders: parsed.reminderMinutes.map {
                    PIMEventReminder(minutesBefore: $0, method: .alert)
                },
                conferenceURL: parsed.conferenceURL,
                conference: Self.mapConference(parsed),
                attachments: parsed.attachments.map {
                    PIMEventAttachment(
                        url: $0.url,
                        title: $0.title,
                        mimeType: $0.mimeType
                    )
                },
                recurrenceRule: parsed.recurrenceRule,
                recurrenceID: parsed.recurrenceID,
                rawPayload: calendarData,
                providerUpdatedAt: parsed.lastModified
            )
        }
    }

    private static func mapPerson(
        _ person: ICSParser.ParsedPerson
    ) -> PIMEventPerson {
        PIMEventPerson(
            name: person.name,
            email: person.email,
            rsvp: PIMEventPerson.RSVP(rawValue: person.participation)
        )
    }

    /// The CONFERENCE property as a shared record (#13): the LABEL
    /// parameter becomes the name, X-GOOGLE-CONFERENCE marks the link
    /// as Meet, and unknown providers stay readable as .other.
    private static func mapConference(
        _ parsed: ICSParser.ParsedEvent
    ) -> PIMConference? {
        guard let url = parsed.conferenceURL, !url.isEmpty else {
            return nil
        }
        let isMeet = parsed.conferenceIsGoogleMeet
            || url.localizedCaseInsensitiveContains("meet.google.com")
        return PIMConference(
            kind: isMeet ? .meet : .other,
            providerKey: isMeet ? "hangoutsMeet" : nil,
            name: parsed.conferenceLabel
                ?? (isMeet ? "Google Meet" : nil),
            joinURL: url
        )
    }

    // MARK: - Requests

    private func send(
        _ request: URLRequest,
        credential: CalDAVCredential
    ) async throws -> (Data, HTTPURLResponse) {
        var current = request
        current.setValue(
            PIMDAVClient.authorizationHeader(for: credential),
            forHTTPHeaderField: "Authorization"
        )
        for attempt in 0 ... Self.maxRedirectHops {
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(current)
            } catch let error as PIMEventSyncError {
                throw error
            } catch let error as URLError {
                throw PIMDAVClient.mapTransportError(error).asSyncError
            } catch {
                throw PIMEventSyncError.transportFailed
            }
            if (300 ..< 400).contains(response.statusCode),
               attempt < Self.maxRedirectHops,
               let location = response.value(forHTTPHeaderField: "Location"),
               let next = URL(string: location, relativeTo: current.url) {
                try PIMDAVClient.requireHTTPS(next)
                guard PIMDAVClient.isSameOrigin(current.url!, next) else {
                    throw PIMEventSyncError.invalidResponse
                }
                var redirected = URLRequest(url: next)
                redirected.httpMethod = current.httpMethod
                redirected.httpBody = current.httpBody
                for (field, value) in current.allHTTPHeaderFields ?? [:] {
                    redirected.setValue(value, forHTTPHeaderField: field)
                }
                current = redirected
                continue
            }
            return (data, response)
        }
        throw PIMEventSyncError.invalidResponse
    }

    private static func syncCollectionRequest(
        _ url: URL,
        cursorToken: String?
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "REPORT"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue(
            "application/xml; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Data(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <d:sync-collection xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
              <d:sync-token>\(cursorToken ?? "")</d:sync-token>
              <d:sync-level>1</d:sync-level>
              <d:prop>
                <d:getetag/>
                <c:calendar-data/>
              </d:prop>
            </d:sync-collection>
            """.utf8
        )
        return request
    }

    private static func calendarQueryRequest(
        _ url: URL,
        windowStart: Date,
        windowEnd: Date
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "REPORT"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue(
            "application/xml; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Data(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
              <d:prop>
                <d:getetag/>
              </d:prop>
              <c:filter>
                <c:comp-filter name="VCALENDAR">
                  <c:comp-filter name="VEVENT">
                    <c:time-range start="\(icalTimestamp(windowStart))" end="\(icalTimestamp(windowEnd))"/>
                  </c:comp-filter>
                </c:comp-filter>
              </c:filter>
            </c:calendar-query>
            """.utf8
        )
        return request
    }

    private static func multigetRequest(
        _ url: URL,
        hrefs: [String]
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "REPORT"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue(
            "application/xml; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        let hrefElements = hrefs
            .map { "  <d:href>\($0)</d:href>" }
            .joined(separator: "\n")
        request.httpBody = Data(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <c:calendar-multiget xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
              <d:prop>
                <d:getetag/>
                <c:calendar-data/>
              </d:prop>
            \(hrefElements)
            </c:calendar-multiget>
            """.utf8
        )
        return request
    }

    private static func icalTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}

private extension PIMDAVConnectError {
    /// Projects setup errors onto the sync taxonomy.
    var asSyncError: PIMEventSyncError {
        switch self {
        case .authenticationRequired:
            return .authenticationRequired
        case .transportFailed, .tlsValidationFailed,
             .httpsRequired, .crossOriginRedirect:
            return .transportFailed
        case .unsupportedServer:
            return .unsupportedServer
        case .invalidEndpoint, .discoveryFailed:
            return .invalidResponse
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Sync report parsing

/// One member row from a sync-collection, calendar-query or
/// calendar-multiget multistatus response.
struct PIMDAVSyncMember: Sendable, Hashable {
    /// Absolute href of the member resource.
    var href: String?
    /// getetag value when the propstat succeeded.
    var etag: String?
    /// calendar-data payload when the response carried it inline.
    var calendarData: String?
}

/// Extracts member rows, removed hrefs and the next sync-token from a
/// REPORT multistatus body. Local-name matching keeps the parser immune
/// to namespace prefix choices.
enum PIMDAVSyncReportParser {
    static func parse(
        _ data: Data,
        relativeTo base: URL
    ) -> (members: [PIMDAVSyncMember], removedHrefs: [String], syncToken: String?) {
        let delegate = ReportDelegate(base: base)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.parse()
        return (delegate.members, delegate.removedHrefs, delegate.syncToken)
    }

    private final class ReportDelegate: NSObject, XMLParserDelegate {
        private let base: URL
        private(set) var members: [PIMDAVSyncMember] = []
        private(set) var removedHrefs: [String] = []
        private(set) var syncToken: String?

        private var current: PIMDAVSyncMember?
        private var responseStatus = ""
        private var capturing: Capture?
        private var buffer = ""
        /// Depth inside <response> so the top-level sync-token element
        /// (a sibling of the responses) is not mistaken for a member.
        private var responseDepth = 0
        /// Inside <propstat> a 404 status means that property block
        /// failed — the member itself is still listed. Only a
        /// response-level 404 marks a removal.
        private var inPropstat = false

        init(base: URL) { self.base = base }

        private enum Capture {
            case href, etag, calendarData, status, syncToken
        }

        private static func localName(_ elementName: String) -> String {
            elementName.components(separatedBy: ":").last ?? elementName
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            switch Self.localName(elementName) {
            case "response":
                responseDepth += 1
                current = PIMDAVSyncMember()
                responseStatus = ""
            case "propstat":
                inPropstat = true
            case "href" where responseDepth > 0:
                capturing = .href
                buffer = ""
            case "getetag" where inPropstat:
                capturing = .etag
                buffer = ""
            case "calendar-data" where inPropstat:
                capturing = .calendarData
                buffer = ""
            case "status":
                capturing = .status
                buffer = ""
            case "sync-token" where responseDepth == 0:
                capturing = .syncToken
                buffer = ""
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if capturing != nil { buffer += string }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let local = Self.localName(elementName)
            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            switch local {
            case "response":
                responseDepth = max(0, responseDepth - 1)
                if let member = current {
                    if responseStatus.contains("404") {
                        if let href = member.href {
                            removedHrefs.append(href)
                        }
                    } else {
                        members.append(member)
                    }
                }
                current = nil
            case "propstat":
                inPropstat = false
            case "href" where capturing == .href:
                // The first href in a response is the member's own;
                // hrefs nested in prop values must not overwrite it.
                if current?.href == nil {
                    current?.href = URL(
                        string: text,
                        relativeTo: base
                    )?.absoluteURL.absoluteString ?? text
                }
                capturing = nil
            case "getetag" where capturing == .etag:
                current?.etag = text.isEmpty ? nil : text
                capturing = nil
            case "calendar-data" where capturing == .calendarData:
                current?.calendarData = buffer
                capturing = nil
            case "status" where capturing == .status:
                if !inPropstat, responseDepth > 0 {
                    responseStatus = text
                }
                capturing = nil
            case "sync-token" where capturing == .syncToken:
                if !text.isEmpty { syncToken = text }
                capturing = nil
            default:
                break
            }
        }
    }
}
