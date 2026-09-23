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

/// Writes contacts to Google via the People API (ADR-0072 #9).
///
/// createContact / updateContact / deleteContact plus the contacts
/// photo endpoints — sync stays with GooglePeopleContactSync. Every
/// call needs the `contacts` scope the write-enablement flow grants; a
/// missing grant surfaces as authenticationRequired rather than a
/// silent failure. updateContact carries the cached etag in the body
/// plus an `updatePersonFields` mask listing exactly the fields Brev
/// owns, so provider fields the model does not read are preserved
/// server-side. Photo bytes never ride updatePersonFields —
/// updateContactPhoto/deleteContactPhoto handle them. Group membership
/// is written through the memberships field — the contactGroups
/// resource is untouched.
public struct GooglePeopleContactWriter: Sendable {
    /// Errors surfaced by the Google write path.
    public enum WriteError: Error, Sendable, Hashable, LocalizedError {
        /// The credential was rejected or lacks the write scope.
        case authenticationRequired
        /// The contact changed remotely since the cached copy — the
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
                    "Editing needs a fresh Google grant. Reconnect the contacts source in Settings.",
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
                    "Google Contacts returned a response Brev could not use.",
                    bundle: .module
                )
            case .transportFailed:
                String(
                    localized:
                    "Google Contacts could not be reached. Check the connection and try again.",
                    bundle: .module
                )
            }
        }
    }

    /// Outcome of a successful write — the provider's resourceName and
    /// new etag.
    public struct WriteResult: Sendable, Hashable {
        public let resourceName: String
        public let etag: String?

        public init(resourceName: String, etag: String?) {
            self.resourceName = resourceName
            self.etag = etag
        }
    }

    /// The transport seam — tests inject a stubbed sender.
    public typealias Transport =
        @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private static let baseURL = "https://people.googleapis.com/v1"

    /// Fields Brev owns on a Person — the update mask and the create
    /// body both draw from this list so a write never claims a field
    /// the model does not read.
    private static let writableFields = [
        "names", "nicknames", "emailAddresses", "phoneNumbers",
        "organizations", "addresses", "biographies", "memberships",
        "birthdays", "events", "urls",
    ]

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

    /// Creates a contact in the user's people container. Returns the
    /// provider's resourceName and etag.
    public func create(
        _ contact: PIMContact,
        accessToken: String
    ) async throws -> WriteResult {
        let url = URL(string: Self.baseURL + "/people:createContact")!
        var request = try jsonRequest(
            url: url,
            method: "POST",
            accessToken: accessToken
        )
        request.httpBody = try body(for: contact, includeEtag: false)
        let (data, response) = try await send(request)
        try requireSuccess(response, data: data, allowed: 200 ..< 300)
        return try parseResult(data)
    }

    /// Replaces the fields Brev owns on a person. The cached etag rides
    /// in the body — a stale copy answers FAILED_PRECONDITION (400) or
    /// 412, both mapped to conflict.
    public func update(
        _ contact: PIMContact,
        accessToken: String
    ) async throws -> WriteResult {
        let resourceName = contact.providerItemKey
        guard !resourceName.isEmpty,
              let encoded = resourceName.addingPercentEncoding(
                  withAllowedCharacters: .urlPathAllowed
              ),
              var components = URLComponents(
                  string: Self.baseURL + "/" + encoded + ":updateContact"
              )
        else {
            throw WriteError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(
                name: "updatePersonFields",
                value: Self.writableFields.joined(separator: ",")
            ),
        ]
        guard let url = components.url else {
            throw WriteError.invalidResponse
        }
        var request = try jsonRequest(
            url: url,
            method: "PATCH",
            accessToken: accessToken
        )
        request.httpBody = try body(for: contact, includeEtag: true)
        let (data, response) = try await send(request)
        try requireSuccess(response, data: data, allowed: 200 ..< 300)
        return try parseResult(data)
    }

    /// Deletes a person. A remote 404 counts as deleted — the desired
    /// end state already holds.
    public func delete(
        _ contact: PIMContact,
        accessToken: String
    ) async throws {
        let resourceName = contact.providerItemKey
        guard !resourceName.isEmpty,
              let encoded = resourceName.addingPercentEncoding(
                  withAllowedCharacters: .urlPathAllowed
              ),
              let url = URL(
                  string:
                  Self.baseURL + "/" + encoded + ":deleteContact"
              )
        else {
            throw WriteError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(
            "Bearer " + accessToken,
            forHTTPHeaderField: "Authorization"
        )
        let (_, response) = try await send(request)
        try requireSuccess(response, data: nil, allowed: [200, 204, 404])
    }

    /// Outcome of a photo write — the latest etag plus the photo URL
    /// Google reports (nil after a delete or when only the default
    /// placeholder remains).
    public struct PhotoWriteResult: Sendable, Hashable {
        public let etag: String?
        public let photoURL: String?

        public init(etag: String?, photoURL: String?) {
            self.etag = etag
            self.photoURL = photoURL
        }
    }

    /// Uploads contact photo bytes — never part of updatePersonFields.
    public func updatePhoto(
        _ contact: PIMContact,
        photoData: Data,
        accessToken: String
    ) async throws -> PhotoWriteResult {
        var request = try photoRequest(
            contact,
            method: "PATCH",
            action: "updateContactPhoto",
            accessToken: accessToken
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["photoBytes": photoData.base64EncodedString()]
        )
        let (data, response) = try await send(request)
        try requireSuccess(response, data: data, allowed: 200 ..< 300)
        return try parsePhotoResult(data)
    }

    /// Removes the contact photo. A remote 404 counts as done — the
    /// photo-less end state already holds.
    public func deletePhoto(
        _ contact: PIMContact,
        accessToken: String
    ) async throws -> PhotoWriteResult {
        let request = try photoRequest(
            contact,
            method: "DELETE",
            action: "deleteContactPhoto",
            accessToken: accessToken
        )
        let (data, response) = try await send(request)
        try requireSuccess(response, data: data, allowed: [200, 204, 404])
        // A 404 answers an empty body — the end state is photo-free.
        guard response.statusCode != 404, !data.isEmpty else {
            return PhotoWriteResult(etag: nil, photoURL: nil)
        }
        return try parsePhotoResult(data)
    }

    /// The shared request builder for the two contacts photo actions.
    private func photoRequest(
        _ contact: PIMContact,
        method: String,
        action: String,
        accessToken: String
    ) throws -> URLRequest {
        let resourceName = contact.providerItemKey
        guard !resourceName.isEmpty,
              let encoded = resourceName.addingPercentEncoding(
                  withAllowedCharacters: .urlPathAllowed
              ),
              let url = URL(
                  string: Self.baseURL + "/" + encoded + ":" + action
              )
        else {
            throw WriteError.invalidResponse
        }
        return try jsonRequest(
            url: url,
            method: method,
            accessToken: accessToken
        )
    }

    /// Reads the nested `person` from a photo action's response — its
    /// etag and the first non-default https photo URL.
    private func parsePhotoResult(
        _ data: Data
    ) throws -> PhotoWriteResult {
        guard let json = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any],
            let person = json["person"] as? [String: Any]
        else {
            throw WriteError.invalidResponse
        }
        return PhotoWriteResult(
            etag: person["etag"] as? String,
            photoURL: Self.photoURL(from: person)
        )
    }

    /// The first non-default https photo URL on a Person — the same
    /// filter the sync path applies.
    static func photoURL(from person: [String: Any]) -> String? {
        let photos = person["photos"] as? [[String: Any]] ?? []
        for photo in photos {
            guard photo["default"] as? Bool != true,
                  let url = photo["url"] as? String,
                  url.lowercased().hasPrefix("https://")
            else { continue }
            return url
        }
        return nil
    }

    // MARK: - Body mapping

    /// The Person resource body for a shared contact. Only the fields
    /// Brev owns are emitted; on update the updatePersonFields mask
    /// matches so untouched provider fields survive server-side.
    /// includeEtag adds the cached etag precondition (updates only).
    public func body(
        for contact: PIMContact,
        includeEtag: Bool
    ) throws -> Data {
        var dict: [String: Any] = [:]
        if includeEtag, let etag = contact.providerVersion {
            dict["etag"] = etag
        }
        // displayName is read-only on Google — when the model has no
        // split names, the display string lands in givenName so the
        // record keeps a usable identity.
        var name: [String: Any] = [:]
        if let given = contact.givenName, !given.isEmpty {
            name["givenName"] = given
        } else if contact.familyName?.isEmpty != false,
                  !contact.displayName.isEmpty {
            name["givenName"] = contact.displayName
        }
        if let family = contact.familyName, !family.isEmpty {
            name["familyName"] = family
        }
        if !name.isEmpty {
            dict["names"] = [name]
        }
        if let nickname = contact.nickname, !nickname.isEmpty {
            dict["nicknames"] = [["value": nickname]]
        }
        dict["emailAddresses"] = contact.emails.map { field in
            labeledField(value: field.value, type: field.label)
        }
        dict["phoneNumbers"] = contact.phones.map { field in
            labeledField(value: field.value, type: field.label)
        }
        if let organization = contact.organization,
           !organization.isEmpty {
            var org: [String: Any] = ["name": organization]
            if let title = contact.jobTitle, !title.isEmpty {
                org["title"] = title
            }
            dict["organizations"] = [org]
        }
        dict["addresses"] = contact.addresses
            .filter { !$0.isEmpty }
            .map { address -> [String: Any] in
                var entry: [String: Any] = [:]
                if let label = address.label, !label.isEmpty {
                    entry["type"] = label
                }
                if let street = address.street {
                    entry["streetAddress"] = street
                }
                if let city = address.city {
                    entry["city"] = city
                }
                if let region = address.region {
                    entry["region"] = region
                }
                if let postal = address.postalCode {
                    entry["postalCode"] = postal
                }
                if let country = address.country {
                    entry["country"] = country
                }
                return entry
            }
        if let note = contact.note, !note.isEmpty {
            dict["biographies"] = [[
                "value": note,
                "contentType": "TEXT_PLAIN",
            ]]
        }
        // Birthdays keep the year-less flag as an omitted year; every
        // other labeled date lands in events with a matching type.
        let birthdays = contact.dates.filter {
            let label = $0.label?.lowercased()
            return label == nil || label == "birthday"
        }
        if !birthdays.isEmpty {
            dict["birthdays"] = birthdays.map { date in
                ["date": googleDate(date)] as [String: Any]
            }
        }
        let events = contact.dates.filter {
            let label = $0.label?.lowercased()
            return label != nil && label != "birthday"
        }
        if !events.isEmpty {
            dict["events"] = events.map { date -> [String: Any] in
                var entry: [String: Any] = ["date": googleDate(date)]
                let label = date.label?.lowercased()
                if label == "anniversary" {
                    entry["type"] = "anniversary"
                } else {
                    entry["type"] = "custom"
                    entry["customType"] = date.label ?? "other"
                }
                return entry
            }
        }
        if !contact.urls.isEmpty {
            dict["urls"] = contact.urls
                .filter { !$0.value.isEmpty }
                .map { labeledField(value: $0.value, type: $0.label) }
        }
        // Memberships are written as contactGroupMembership entries.
        // The system myContacts group is implicit — sending it back
        // errors, so it is filtered out here and re-added by Google.
        dict["memberships"] = contact.groupKeys
            .filter { !$0.hasSuffix("/myContacts") }
            .map { key in
                [
                    "contactGroupMembership": [
                        "contactGroupResourceName": key,
                    ],
                ] as [String: Any]
            }
        do {
            return try JSONSerialization.data(withJSONObject: dict)
        } catch {
            throw WriteError.invalidResponse
        }
    }

    private func labeledField(
        value: String,
        type: String?
    ) -> [String: Any] {
        var entry: [String: Any] = ["value": value]
        if let type, !type.isEmpty {
            entry["type"] = type
        }
        return entry
    }

    /// google.type.Date — year omitted for year-less dates.
    private func googleDate(_ date: PIMContactDate) -> [String: Any] {
        var dict: [String: Any] = [
            "month": date.month,
            "day": date.day,
        ]
        if let year = date.year {
            dict["year"] = year
        }
        return dict
    }

    // MARK: - Helpers

    private func jsonRequest(
        url: URL,
        method: String,
        accessToken: String
    ) throws -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.httpMethod = method
        request.setValue(
            "Bearer " + accessToken,
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        return request
    }

    private func parseResult(_ data: Data) throws -> WriteResult {
        guard let json = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any],
            let resourceName = json["resourceName"] as? String
        else {
            throw WriteError.invalidResponse
        }
        return WriteResult(
            resourceName: resourceName,
            etag: json["etag"] as? String
        )
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
        data: Data?,
        allowed: some Sequence<Int> & Sendable
    ) throws {
        if allowed.contains(response.statusCode) { return }
        switch response.statusCode {
        case 401, 403:
            throw WriteError.authenticationRequired
        case 400:
            // updateContact answers etag mismatches with 400
            // FAILED_PRECONDITION; a plain bad request stays an
            // invalidResponse so a body bug never reads as a conflict.
            if let data,
               let text = String(data: data, encoding: .utf8),
               text.contains("FAILED_PRECONDITION") {
                throw WriteError.conflict
            }
            throw WriteError.invalidResponse
        case 409, 412:
            throw WriteError.conflict
        default:
            throw WriteError.invalidResponse
        }
    }
}
