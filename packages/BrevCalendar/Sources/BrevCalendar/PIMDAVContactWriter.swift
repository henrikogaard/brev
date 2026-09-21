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

/// CardDAV write path for PIM contacts (ADR-0072 #9).
///
/// PUT creates or replaces an address object resource; DELETE removes
/// it. Creates address `{collection}/{sanitized-uid}.vcf` with
/// `If-None-Match: *`; updates and deletes address the stored
/// providerItemKey href directly and ride the cached ETag as
/// `If-Match` so a stale edit never silently overwrites a newer
/// remote change — a 412 surfaces as conflict and the caller reloads
/// first. A remote 404 on delete counts as done.
public struct PIMDAVContactWriter: Sendable {
    /// Errors surfaced by the CardDAV write path.
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
        /// The collection's provider key or the record's href is not a
        /// usable URL.
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
                    "This contact changed on the server. Sync, then try again.",
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
                    "This address book has no writable address.",
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

    /// Conditional create: `If-None-Match: *` fails with conflict
    /// when the UID's resource already exists.
    public func create(
        _ contact: PIMContact,
        vcard: String,
        in collection: PIMCollection,
        credential: CalDAVCredential
    ) async throws -> WriteResult {
        let resourceURL = try Self.resourceURL(
            forUID: contact.uid ?? contact.providerItemKey,
            collection: collection
        )
        return try await put(
            vcard,
            to: resourceURL,
            credential: credential,
            precondition: .createOnly
        )
    }

    /// Conditional replace on the stored href: `If-Match: <etag>`
    /// when the cached record carries one, else unconditional.
    public func update(
        _ contact: PIMContact,
        vcard: String,
        credential: CalDAVCredential
    ) async throws -> WriteResult {
        let resourceURL = try Self.hrefURL(for: contact)
        return try await put(
            vcard,
            to: resourceURL,
            credential: credential,
            precondition: contact.providerVersion.map(Precondition.match)
                ?? .unconditional
        )
    }

    /// Deletes the contact's stored href. `If-Match` rides along
    /// when the cache has an ETag; a missing resource (404) counts as
    /// deleted — the desired end state already holds.
    public func delete(
        _ contact: PIMContact,
        credential: CalDAVCredential
    ) async throws {
        let resourceURL = try Self.hrefURL(for: contact)
        var request = URLRequest(url: resourceURL)
        request.httpMethod = "DELETE"
        request.setValue(
            credential.authorizationHeaderValue,
            forHTTPHeaderField: "Authorization"
        )
        if let etag = contact.providerVersion {
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
        _ vcard: String,
        to resourceURL: URL,
        credential: CalDAVCredential,
        precondition: Precondition
    ) async throws -> WriteResult {
        var request = URLRequest(
            url: resourceURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.httpMethod = "PUT"
        request.setValue(
            "text/vcard; charset=utf-8",
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
        request.httpBody = Data(vcard.utf8)
        let (_, response) = try await send(request)
        try requireSuccess(response, allowed: 200 ..< 300)
        return WriteResult(
            etag: response.value(forHTTPHeaderField: "ETag"),
            resourceURL: resourceURL
        )
    }

    // MARK: - Helpers

    /// The address object resource URL for a new contact UID — the
    /// collection URL plus `{sanitized-uid}.vcf` (RFC 6352 §5.1
    /// convention, shared with the event writer).
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
        let safeName = CalDAVWriteTarget.sanitize(uid) + ".vcf"
        return base.appendingPathComponent(safeName)
    }

    /// The stored provider href — authoritative for updates and
    /// deletes; servers may rename resources on write.
    static func hrefURL(for contact: PIMContact) throws -> URL {
        guard let url = URL(
            string: contact.providerItemKey
        ), url.scheme != nil else {
            throw WriteError.invalidCollection
        }
        return url
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
