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

/// Writes tasks to Google Tasks via the `tasks` REST resource
/// (ADR-0072 #12).
///
/// Insert, patch, delete, and move only — sync stays with
/// `GoogleTaskSync`. Every call needs the `tasks` scope the
/// write-enablement flow grants (`GooglePIMScopes.tasks`); a missing
/// grant surfaces as `authenticationRequired` rather than a silent
/// failure. Updates and deletes carry the cached etag as an
/// `If-Match` precondition so a stale edit surfaces as `conflict`
/// instead of overwriting a newer remote change.
///
/// Google Tasks is list-scoped: `move` reorders/reparents inside one
/// list via `tasks.move`; moving to another list is a delete+insert
/// owned by the write service, not this writer.
public struct GoogleTaskWriter: Sendable {
    /// Errors surfaced by the Google write path.
    public enum WriteError: Error, Sendable, Hashable, LocalizedError {
        /// The credential was rejected or lacks the write scope.
        case authenticationRequired
        /// The task changed remotely since the cached copy — the
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
                    "Editing needs a fresh Google grant. Reconnect the task source in Settings.",
                    bundle: .module
                )
            case .conflict:
                String(
                    localized:
                    "This task changed on the server. Sync, then try again.",
                    bundle: .module
                )
            case .invalidResponse:
                String(
                    localized:
                    "Google Tasks returned a response Brev could not use.",
                    bundle: .module
                )
            case .transportFailed:
                String(
                    localized:
                    "Google Tasks could not be reached. Check the connection and try again.",
                    bundle: .module
                )
            }
        }
    }

    /// Outcome of a successful write — the provider's task ID and ETag.
    public struct WriteResult: Sendable, Hashable {
        public let taskID: String
        public let etag: String?
        /// The provider's canonical record when the response carried
        /// one — position/parent/completed fields Google assigns
        /// server-side.
        public let item: GoogleTaskSync.TaskItem?

        public init(
            taskID: String,
            etag: String?,
            item: GoogleTaskSync.TaskItem? = nil
        ) {
            self.taskID = taskID
            self.etag = etag
            self.item = item
        }
    }

    /// The transport seam — tests inject a stubbed sender.
    public typealias Transport =
        @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private static let baseURL =
        "https://tasks.googleapis.com/tasks/v1/lists"

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

    /// Creates a task in the list. Returns the provider's new task ID
    /// and ETag.
    public func insert(
        _ task: PIMTask,
        into collection: PIMCollection,
        accessToken: String
    ) async throws -> WriteResult {
        let url = try Self.tasksURL(collection: collection)
        var request = try jsonRequest(
            url: url,
            method: "POST",
            accessToken: accessToken
        )
        request.httpBody = try body(for: task)
        let (data, response) = try await send(request)
        try requireSuccess(response, allowed: 200 ..< 300)
        return try parseResult(data)
    }

    /// Replaces the writable fields of an existing task. The cached
    /// `providerVersion` (Google etag) rides as an `If-Match`
    /// precondition — a 412 maps to `conflict`. PATCH semantics keep
    /// provider-owned fields (position, parent) untouched; reordering
    /// goes through `move`.
    public func patch(
        _ task: PIMTask,
        in collection: PIMCollection,
        accessToken: String
    ) async throws -> WriteResult {
        let url = try Self.taskURL(
            collection: collection,
            taskID: task.providerItemKey
        )
        var request = try jsonRequest(
            url: url,
            method: "PATCH",
            accessToken: accessToken
        )
        if let etag = task.providerVersion {
            request.setValue(etag, forHTTPHeaderField: "If-Match")
        }
        request.httpBody = try body(for: task)
        let (data, response) = try await send(request)
        try requireSuccess(response, allowed: 200 ..< 300)
        return try parseResult(data)
    }

    /// Deletes a task. The cached etag rides as `If-Match` when
    /// present; a missing resource (404) counts as deleted — the
    /// desired end state already holds.
    public func delete(
        _ task: PIMTask,
        in collection: PIMCollection,
        accessToken: String
    ) async throws {
        let url = try Self.taskURL(
            collection: collection,
            taskID: task.providerItemKey
        )
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        if let etag = task.providerVersion {
            request.setValue(etag, forHTTPHeaderField: "If-Match")
        }
        let (_, response) = try await send(request)
        try requireSuccess(response, allowed: [200, 204, 404])
    }

    /// Reorders or reparents a task inside its list via
    /// `tasks.move` — the only Google path that mutates position.
    /// `parent`/`previous` are provider task IDs; nil leaves that
    /// axis unchanged.
    public func move(
        _ task: PIMTask,
        in collection: PIMCollection,
        parent: String?,
        previous: String?,
        accessToken: String
    ) async throws -> WriteResult {
        let url = try Self.moveURL(
            collection: collection,
            taskID: task.providerItemKey,
            parent: parent,
            previous: previous
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        let (data, response) = try await send(request)
        try requireSuccess(response, allowed: 200 ..< 300)
        return try parseResult(data)
    }

    // MARK: - Body mapping

    /// The Google `tasks` resource body for a shared task. Only the
    /// fields the model owns are sent: title, notes, status, due, and
    /// links. Position and parent are provider-owned — they mutate
    /// through `tasks.move`, never through a patch body. Fields set
    /// to JSON null (cleared values) are honored by PATCH.
    public func body(for task: PIMTask) throws -> Data {
        var dict: [String: Any] = [:]
        dict["title"] = task.title ?? ""
        dict["notes"] = task.notes ?? NSNull()
        dict["status"] = googleStatus(task.status)
        dict["due"] = task.due.map(Self.rfc3339) ?? NSNull()
        if !task.links.isEmpty {
            dict["links"] = task.links.map {
                ["type": "generic", "link": $0] as [String: Any]
            }
        }
        do {
            return try JSONSerialization.data(withJSONObject: dict)
        } catch {
            throw WriteError.invalidResponse
        }
    }

    /// Google reports only needsAction/completed — the shared model's
    /// in-process and cancelled states degrade to open rather than
    /// imitating a status the provider does not carry.
    private func googleStatus(_ status: PIMTaskStatus) -> String {
        switch status {
        case .completed: "completed"
        case .cancelled, .needsAction, .inProcess: "needsAction"
        }
    }

    // MARK: - URLs

    private static func tasksURL(
        collection: PIMCollection
    ) throws -> URL {
        guard let encoded = collection.providerKey.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ), let url = URL(
            string: "\(baseURL)/\(encoded)/tasks"
        ) else {
            throw WriteError.invalidResponse
        }
        return url
    }

    private static func taskURL(
        collection: PIMCollection,
        taskID: String
    ) throws -> URL {
        guard let encodedCollection = collection.providerKey
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let encodedTask = taskID.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ),
            let url = URL(
                string:
                "\(baseURL)/\(encodedCollection)/tasks/\(encodedTask)"
            )
        else {
            throw WriteError.invalidResponse
        }
        return url
    }

    private static func moveURL(
        collection: PIMCollection,
        taskID: String,
        parent: String?,
        previous: String?
    ) throws -> URL {
        let base = try taskURL(collection: collection, taskID: taskID)
        var components = URLComponents(
            url: base.appendingPathComponent("move"),
            resolvingAgainstBaseURL: false
        )
        var query: [URLQueryItem] = []
        if let parent {
            query.append(URLQueryItem(name: "parent", value: parent))
        }
        if let previous {
            query.append(URLQueryItem(name: "previous", value: previous))
        }
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else {
            throw WriteError.invalidResponse
        }
        return url
    }

    // MARK: - Helpers

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
        guard let item = try? JSONDecoder().decode(
            GoogleTaskSync.TaskItem.self,
            from: data
        ), let id = item.id, !id.isEmpty else {
            throw WriteError.invalidResponse
        }
        return WriteResult(taskID: id, etag: item.etag, item: item)
    }

    /// RFC 3339 with fractional seconds — the Tasks API's expected
    /// timestamp form ("2026-09-22T00:00:00.000Z").
    private static func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime, .withFractionalSeconds,
        ]
        return formatter.string(from: date)
    }
}
