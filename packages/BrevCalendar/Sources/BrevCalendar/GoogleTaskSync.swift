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

/// Syncs tasks for one Google tasklist (ADR-0072 sync rule 3, #12).
///
/// The Tasks API has no sync token: incremental passes send
/// `updatedMin` (the stored cursor) with `showDeleted` so completed
/// and deleted entries still surface as tombstones, and the cursor is
/// the pass start time. A full pass lists every task including hidden
/// ones (`showHidden`) so the cache is complete; hidden/completed
/// states are presentation concerns, not sync filters.
public struct GoogleTaskSync: Sendable {
    private let transport: any PIMDAVTransport
    /// Bound on pagination loops so a misbehaving provider cannot spin
    /// the pass forever.
    private static let maxPages = 20

    public init(transport: any PIMDAVTransport = URLSessionPIMDAVTransport()) {
        self.transport = transport
    }

    /// Syncs one tasklist. `cursorToken` is the RFC 3339 timestamp of
    /// the last completed pass; nil means a full listing.
    public func syncCollection(
        _ collection: PIMCollection,
        source: PIMSource,
        cursorToken: String?,
        accessToken: String,
        passStartedAt: Date = Date()
    ) async throws -> PIMTaskSyncResult {
        var tasks: [PIMTask] = []
        var removed: [String] = []
        var pageToken: String?
        for _ in 0 ..< Self.maxPages {
            let url = try Self.tasksURL(
                collection: collection,
                cursorToken: cursorToken,
                pageToken: pageToken
            )
            let (data, response) = try await transport.send(
                Self.request(url, accessToken: accessToken)
            )
            switch response.statusCode {
            case 200:
                break
            case 401, 403:
                throw PIMTaskSyncError.authenticationRequired
            case 404:
                throw PIMTaskSyncError.invalidResponse
            case 410:
                throw PIMTaskSyncError.cursorExpired
            default:
                throw PIMTaskSyncError.invalidResponse
            }
            let page = try Self.decodePage(data)
            for item in page.items ?? [] {
                if item.deleted == true {
                    if let id = item.id { removed.append(id) }
                    continue
                }
                guard let task = Self.mapTask(
                    item,
                    collection: collection,
                    source: source
                ) else { continue }
                tasks.append(task)
            }
            guard let next = page.nextPageToken, !next.isEmpty else {
                return PIMTaskSyncResult(
                    tasks: tasks,
                    removedItemKeys: removed,
                    // The pass start is the next updatedMin floor —
                    // anything mutated during the pass re-syncs.
                    nextCursorToken: Self.rfc3339(passStartedAt),
                    isFullSnapshot: cursorToken == nil
                )
            }
            pageToken = next
        }
        throw PIMTaskSyncError.invalidResponse
    }

    // MARK: - Mapping

    private static func mapTask(
        _ item: TaskItem,
        collection: PIMCollection,
        source: PIMSource
    ) -> PIMTask? {
        guard let id = item.id, !id.isEmpty else { return nil }
        return PIMTask(
            id: PIMTask.makeID(
                collectionID: collection.id,
                providerItemKey: id
            ),
            sourceID: source.id,
            collectionID: collection.id,
            providerItemKey: id,
            providerVersion: item.etag,
            uid: id,
            title: item.title,
            notes: item.notes,
            due: parseRFC3339(item.due),
            completedAt: parseRFC3339(item.completed),
            status: PIMTaskStatus(rawValue: item.status),
            position: item.position,
            parentKey: item.parent,
            links: (item.links ?? []).compactMap(\.link),
            rawPayload: rawPayload(for: item),
            providerUpdatedAt: parseRFC3339(item.updated)
        )
    }

    /// Keeps the provider's original JSON for round-trip fidelity (R4).
    private static func rawPayload(for item: TaskItem) -> String? {
        guard let data = try? JSONEncoder().encode(item),
              let raw = String(data: data, encoding: .utf8)
        else { return nil }
        return raw
    }

    // MARK: - Wire types

    struct TasksPage: Decodable {
        var items: [TaskItem]?
        var nextPageToken: String?
    }

    struct TaskItem: Codable {
        var id: String?
        var etag: String?
        var title: String?
        var notes: String?
        var status: String?
        var due: String?
        var updated: String?
        var completed: String?
        var deleted: Bool?
        var hidden: Bool?
        var parent: String?
        var position: String?
        var links: [Link]?

        struct Link: Codable {
            var type: String?
            var description: String?
            var link: String?
        }
    }

    private static func decodePage(_ data: Data) throws -> TasksPage {
        guard let page = try? JSONDecoder().decode(TasksPage.self, from: data)
        else {
            throw PIMTaskSyncError.invalidResponse
        }
        return page
    }

    // MARK: - Requests

    private static func tasksURL(
        collection: PIMCollection,
        cursorToken: String?,
        pageToken: String?
    ) throws -> URL {
        guard let encoded = collection.providerKey.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ), var components = URLComponents(
            string:
            "https://tasks.googleapis.com/tasks/v1/lists/\(encoded)/tasks"
        ) else {
            throw PIMTaskSyncError.invalidResponse
        }
        var query = [
            URLQueryItem(name: "maxResults", value: "100"),
            URLQueryItem(name: "showDeleted", value: "true"),
            URLQueryItem(name: "showHidden", value: "true"),
        ]
        if let cursorToken {
            query.append(URLQueryItem(name: "updatedMin", value: cursorToken))
        }
        if let pageToken {
            query.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = query
        guard let url = components.url else {
            throw PIMTaskSyncError.invalidResponse
        }
        return url
    }

    private static func request(
        _ url: URL,
        accessToken: String
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    // MARK: - Dates

    /// RFC 3339 with optional fractional seconds; Google due values are
    /// date-only ("2026-09-22T00:00:00.000Z").
    private static func parseRFC3339(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }

    private static func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
