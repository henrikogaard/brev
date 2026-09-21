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

/// Syncs tasks for one VTODO-capable CalDAV collection (ADR-0072 sync
/// rule 3, #12).
///
/// Same mechanics as event sync: `sync-collection` when the server
/// advertises it, otherwise a bounded `calendar-query` listing whose
/// href→ETag map diffs against cached versions. The query filters on
/// VTODO without a time range — undated tasks must sync too.
///
/// Raw calendar-data is kept verbatim in `PIMTask.rawPayload` (R4).
public struct PIMDAVTaskSync: Sendable {
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
        credential: CalDAVCredential
    ) async throws -> PIMTaskSyncResult {
        guard let collectionURL = URL(string: collection.providerKey) else {
            throw PIMTaskSyncError.invalidResponse
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
            } catch PIMTaskSyncError.unsupportedServer {
                // Advertised but not implemented — degrade to the
                // bounded listing path rather than failing the source.
            }
        }
        return try await taskQuerySync(
            collection: collection,
            collectionURL: collectionURL,
            source: source,
            cachedVersions: cachedVersions,
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
    ) async throws -> PIMTaskSyncResult {
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
                throw PIMTaskSyncError.cursorExpired
            }
            throw PIMTaskSyncError.authenticationRequired
        case 404, 405, 501:
            throw PIMTaskSyncError.unsupportedServer
        case 412:
            throw PIMTaskSyncError.cursorExpired
        default:
            throw PIMTaskSyncError.invalidResponse
        }

        let report = PIMDAVSyncReportParser.parse(
            data,
            relativeTo: collectionURL
        )
        var result = PIMTaskSyncResult(
            removedItemKeys: report.removedHrefs,
            nextCursorToken: report.syncToken ?? cursorToken,
            isFullSnapshot: cursorToken == nil
        )

        var needsFetch: [String] = []
        for member in report.members {
            guard let href = member.href else { continue }
            if let calendarData = member.calendarData {
                result.tasks.append(
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
            result.tasks.append(contentsOf: fetched)
        }
        return result
    }

    // MARK: - calendar-query fallback

    /// Bounded listing for collections without sync-token support.
    /// Diffs the href→ETag listing against cached versions, fetches only
    /// changed items, and treats hrefs missing from the complete listing
    /// as deletions (ADR-0072 sync rule 3).
    private func taskQuerySync(
        collection: PIMCollection,
        collectionURL: URL,
        source: PIMSource,
        cachedVersions: [String: String],
        credential: CalDAVCredential
    ) async throws -> PIMTaskSyncResult {
        let (data, response) = try await send(
            Self.taskQueryRequest(collectionURL),
            credential: credential
        )
        switch response.statusCode {
        case 207:
            break
        case 401, 403:
            throw PIMTaskSyncError.authenticationRequired
        case 404, 405, 501:
            throw PIMTaskSyncError.unsupportedServer
        default:
            throw PIMTaskSyncError.invalidResponse
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

        var tasks: [PIMTask] = []
        if !fetch.isEmpty {
            tasks = try await multiget(
                hrefs: fetch,
                collectionURL: collectionURL,
                collection: collection,
                source: source,
                credential: credential
            )
        }
        return PIMTaskSyncResult(
            tasks: tasks,
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
    ) async throws -> [PIMTask] {
        var tasks: [PIMTask] = []
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
                    tasks.append(
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
                throw PIMTaskSyncError.authenticationRequired
            default:
                throw PIMTaskSyncError.invalidResponse
            }
        }
        return tasks
    }

    // MARK: - Mapping

    /// Parses one calendar-data payload into one record per VTODO.
    /// A DAV task resource holds exactly one VTODO; extra components
    /// still map so nothing is silently dropped.
    private func mapCalendarData(
        _ calendarData: String,
        href: String,
        etag: String?,
        collection: PIMCollection,
        source: PIMSource
    ) -> [PIMTask] {
        ICSParser.parseTasks(from: calendarData).map { parsed in
            PIMTask(
                id: PIMTask.makeID(
                    collectionID: collection.id,
                    providerItemKey: href
                ),
                sourceID: source.id,
                collectionID: collection.id,
                providerItemKey: href,
                providerVersion: etag,
                uid: parsed.uid,
                title: parsed.summary,
                notes: parsed.description,
                due: parsed.due,
                completedAt: parsed.completed,
                status: PIMTaskStatus(rawValue: parsed.status),
                position: parsed.sortOrder,
                parentKey: parsed.parentUID,
                links: parsed.links,
                rawPayload: calendarData,
                providerUpdatedAt: parsed.lastModified
            )
        }
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
            } catch let error as PIMTaskSyncError {
                throw error
            } catch let error as URLError {
                throw PIMDAVClient.mapTransportError(error).asSyncError
            } catch {
                throw PIMTaskSyncError.transportFailed
            }
            if (300 ..< 400).contains(response.statusCode),
               attempt < Self.maxRedirectHops,
               let location = response.value(forHTTPHeaderField: "Location"),
               let next = URL(string: location, relativeTo: current.url) {
                try PIMDAVClient.requireHTTPS(next)
                guard PIMDAVClient.isSameOrigin(current.url!, next) else {
                    throw PIMTaskSyncError.invalidResponse
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
        throw PIMTaskSyncError.invalidResponse
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

    /// VTODO listing without a time range — tasks need not carry dates.
    private static func taskQueryRequest(_ url: URL) -> URLRequest {
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
                  <c:comp-filter name="VTODO"/>
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
}

private extension PIMDAVConnectError {
    /// Projects setup errors onto the sync taxonomy.
    var asSyncError: PIMTaskSyncError {
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
