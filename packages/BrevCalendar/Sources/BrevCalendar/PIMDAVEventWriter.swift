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

/// CalDAV write path for PIM events (ADR-0072 #7).
///
/// PUT creates or replaces a calendar object resource at
/// `{collection}/{uid}.ics`; DELETE removes it. Updates and deletes
/// carry the cached ETag as an `If-Match` precondition so a stale edit
/// never silently overwrites a newer remote change — a 412 surfaces as
/// `conflict` and the caller reloads first.
///
/// Distinct from `CalDAVEventWriter`: that type serves the invite
/// acceptance flow's single configured target; this one writes any
/// `PIMCollection`'s URL with per-source credentials.
public struct PIMDAVEventWriter: Sendable {
    /// Errors surfaced by the DAV write path.
    public enum WriteError: Error, Sendable, Hashable, LocalizedError {
        /// The credential was rejected (401/403).
        case authenticationRequired
        /// The precondition failed — the remote changed first (412) or
        /// the create target already exists.
        case conflict
        /// The server answered with a status Brev cannot use.
        case invalidResponse
        /// Connectivity or an unspecified transport failure.
        case transportFailed
        /// The collection's provider key is not a usable URL.
        case invalidCollection

        public var errorDescription: String? {
            switch self {
            case .authenticationRequired:
                String(
                    localized:
                    "The server rejected the stored credential. Reconnect the source in Settings.",
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
                    "The server returned a response Brev could not use.",
                    bundle: .module
                )
            case .transportFailed:
                String(
                    localized:
                    "The server could not be reached. Check the connection and try again.",
                    bundle: .module
                )
            case .invalidCollection:
                String(
                    localized:
                    "This calendar has no writable address.",
                    bundle: .module
                )
            }
        }
    }

    /// Outcome of a successful PUT — the server ETag when returned.
    public struct WriteResult: Sendable, Hashable {
        public let etag: String?
        public let resourceURL: URL

        public init(etag: String?, resourceURL: URL) {
            self.etag = etag
            self.resourceURL = resourceURL
        }
    }

    /// The transport seam — tests inject a stubbed sender.
    public typealias Transport =
        @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

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

    /// Conditional create: `If-None-Match: *` fails with `conflict`
    /// when the UID's resource already exists.
    public func create(
        _ event: PIMEvent,
        ics: String,
        in collection: PIMCollection,
        credential: CalDAVCredential
    ) async throws -> WriteResult {
        try await put(
            event,
            ics: ics,
            in: collection,
            credential: credential,
            precondition: .createOnly
        )
    }

    /// Conditional replace: `If-Match: <etag>` when the cached record
    /// carries one, else an unconditional replace.
    public func update(
        _ event: PIMEvent,
        ics: String,
        in collection: PIMCollection,
        credential: CalDAVCredential
    ) async throws -> WriteResult {
        try await put(
            event,
            ics: ics,
            in: collection,
            credential: credential,
            precondition: event.providerVersion.map(Precondition.match)
                ?? .unconditional
        )
    }

    /// Deletes the event's resource. `If-Match` rides along when the
    /// cache has an ETag; a missing resource (404) counts as deleted —
    /// the desired end state already holds.
    public func delete(
        _ event: PIMEvent,
        in collection: PIMCollection,
        credential: CalDAVCredential
    ) async throws {
        let resourceURL = try Self.resourceURL(
            forUID: event.uid ?? event.providerItemKey,
            collection: collection
        )
        var request = URLRequest(url: resourceURL)
        request.httpMethod = "DELETE"
        request.setValue(
            credential.authorizationHeaderValue,
            forHTTPHeaderField: "Authorization"
        )
        if let etag = event.providerVersion {
            request.setValue(etag, forHTTPHeaderField: "If-Match")
        }
        let (_, response) = try await send(request)
        try requireSuccess(response, allowed: [200, 204, 404])
    }

    // MARK: - PUT

    private enum Precondition {
        case createOnly
        case match(String)
        case unconditional
    }

    private func put(
        _ event: PIMEvent,
        ics: String,
        in collection: PIMCollection,
        credential: CalDAVCredential,
        precondition: Precondition
    ) async throws -> WriteResult {
        let resourceURL = try Self.resourceURL(
            forUID: event.uid ?? event.providerItemKey,
            collection: collection
        )
        var request = URLRequest(
            url: resourceURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.httpMethod = "PUT"
        request.setValue(
            "text/calendar; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            credential.authorizationHeaderValue,
            forHTTPHeaderField: "Authorization"
        )
        switch precondition {
        case .createOnly:
            request.setValue("*", forHTTPHeaderField: "If-None-Match")
        case .match(let etag):
            request.setValue(etag, forHTTPHeaderField: "If-Match")
        case .unconditional:
            break
        }
        request.httpBody = Data(ics.utf8)
        let (_, response) = try await send(request)
        try requireSuccess(response, allowed: 200 ..< 300)
        return WriteResult(
            etag: response.value(forHTTPHeaderField: "ETag"),
            resourceURL: resourceURL
        )
    }

    // MARK: - Helpers

    /// The calendar object resource URL for an event UID — the
    /// collection URL plus `{sanitized-uid}.ics` (RFC 4791 §5.3.2
    /// convention, shared with CalDAVEventWriter.sanitize).
    static func resourceURL(
        forUID uid: String,
        collection: PIMCollection
    ) throws -> URL {
        guard var base = URL(string: collection.providerKey) else {
            throw WriteError.invalidCollection
        }
        if !base.absoluteString.hasSuffix("/") {
            guard let withSlash = URL(
                string: base.absoluteString + "/"
            ) else {
                throw WriteError.invalidCollection
            }
            base = withSlash
        }
        let safeName = CalDAVWriteTarget.sanitize(uid) + ".ics"
        return base.appendingPathComponent(safeName)
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
}
