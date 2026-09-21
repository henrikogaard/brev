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

/// Discovery failures that are not DAV errors. Each maps to the same
/// user remedy the source setup taxonomy already presents.
public enum PIMCollectionDiscoveryError: Error, Sendable, Hashable, LocalizedError {
    /// The access token was rejected or lacks the feature's scope; the
    /// source needs reauthorization.
    case authenticationRequired
    /// Connectivity or an unspecified transport failure.
    case transportFailed
    /// The provider answered with a status or body Brev cannot use.
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return String(
                localized: "Google rejected the account's authorization. Reconnect the source to grant access again.",
                bundle: .module
            )
        case .transportFailed:
            return String(
                localized: "Google could not be reached. Check the connection and try again.",
                bundle: .module
            )
        case .invalidResponse:
            return String(
                localized: "Google returned an unexpected response. Try refreshing again.",
                bundle: .module
            )
        }
    }
}

/// Discovers the collections a Google PIM source exposes (ADR-0072).
///
/// Calendar sources read the Calendar API calendar list; contacts
/// sources read People API contact groups. Both paginate with page
/// tokens and ride the linked mail account's OAuth grant — the access
/// token is resolved by the caller so this adapter never touches the
/// token store.
public struct GooglePIMCollectionDiscovery: Sendable {
    /// HTTP seam shared with the DAV adapters: a bare request/response
    /// exchange with no redirect following.
    private let transport: any PIMDAVTransport
    /// Bound on pagination loops so a misbehaving provider cannot spin
    /// the refresh forever.
    private static let maxPages = 20

    private static let calendarListURL = URL(
        string: "https://www.googleapis.com/calendar/v3/users/me/calendarList"
    )!
    private static let contactGroupsURL = URL(
        string: "https://people.googleapis.com/v1/contactGroups"
    )!

    public init(transport: any PIMDAVTransport = URLSessionPIMDAVTransport()) {
        self.transport = transport
    }

    /// Lists every collection the source kind exposes on the account.
    public func discoverCollections(
        kind: PIMSourceKind,
        accessToken: String
    ) async throws -> [PIMDiscoveredCollection] {
        switch kind {
        case .calendar:
            return try await discoverCalendars(accessToken: accessToken)
        case .contacts:
            return try await discoverContactGroups(accessToken: accessToken)
        }
    }

    // MARK: - Calendar list

    private func discoverCalendars(
        accessToken: String
    ) async throws -> [PIMDiscoveredCollection] {
        var collections: [PIMDiscoveredCollection] = []
        var pageToken: String?
        for _ in 0 ..< Self.maxPages {
            var components = URLComponents(
                url: Self.calendarListURL,
                resolvingAgainstBaseURL: false
            )
            var query = [
                URLQueryItem(name: "maxResults", value: "250"),
                // Hidden calendars are discovered so the user can
                // un-hide them in Settings.
                URLQueryItem(name: "showHidden", value: "true")
            ]
            if let pageToken {
                query.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components?.queryItems = query
            guard let url = components?.url else {
                throw PIMCollectionDiscoveryError.invalidResponse
            }
            let data = try await get(url, accessToken: accessToken)
            let page = try decode(CalendarListPage.self, from: data)
            for item in page.items ?? [] {
                // Deleted entries can appear in the list response; they
                // are not browsable collections.
                if item.deleted == true { continue }
                guard let id = item.id, !id.isEmpty else { continue }
                collections.append(
                    PIMDiscoveredCollection(
                        providerKey: id,
                        displayName: item.summaryOverride
                            ?? item.summary
                            ?? id,
                        colorHex: item.backgroundColor,
                        isReadOnly: Self.isReadOnly(accessRole: item.accessRole),
                        isPrimary: item.primary == true,
                        supportsSyncToken: true,
                        providerVersion: item.etag,
                        initiallyHidden: item.hidden == true
                            || item.selected == false
                    )
                )
            }
            guard let next = page.nextPageToken, !next.isEmpty else {
                return collections
            }
            pageToken = next
        }
        return collections
    }

    private static func isReadOnly(accessRole: String?) -> Bool {
        switch accessRole {
        case "owner", "writer":
            return false
        default:
            // reader, freeBusyReader, and unknown roles cannot write.
            return true
        }
    }

    // MARK: - Contact groups

    private func discoverContactGroups(
        accessToken: String
    ) async throws -> [PIMDiscoveredCollection] {
        var collections: [PIMDiscoveredCollection] = []
        var pageToken: String?
        for _ in 0 ..< Self.maxPages {
            var components = URLComponents(
                url: Self.contactGroupsURL,
                resolvingAgainstBaseURL: false
            )
            var query = [URLQueryItem(name: "pageSize", value: "200")]
            if let pageToken {
                query.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components?.queryItems = query
            guard let url = components?.url else {
                throw PIMCollectionDiscoveryError.invalidResponse
            }
            let data = try await get(url, accessToken: accessToken)
            let page = try decode(ContactGroupsPage.self, from: data)
            for item in page.contactGroups ?? [] {
                guard let resourceName = item.resourceName,
                      !resourceName.isEmpty
                else { continue }
                let isSystem = item.groupType == "SYSTEM_CONTACT_GROUP"
                collections.append(
                    PIMDiscoveredCollection(
                        providerKey: resourceName,
                        displayName: item.formattedName
                            ?? item.name
                            ?? resourceName,
                        colorHex: nil,
                        // System groups are readable but their membership
                        // is managed by Google, not edited directly.
                        isReadOnly: isSystem,
                        isPrimary: resourceName == "contactGroups/myContacts",
                        // People sync tokens cover connections, not
                        // individual groups.
                        supportsSyncToken: false,
                        providerVersion: item.etag,
                        initiallyHidden: false
                    )
                )
            }
            guard let next = page.nextPageToken, !next.isEmpty else {
                return collections
            }
            pageToken = next
        }
        return collections
    }

    // MARK: - Transport

    private func get(_ url: URL, accessToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw PIMCollectionDiscoveryError.transportFailed
        }
        switch response.statusCode {
        case 200 ..< 300:
            return data
        case 401, 403:
            throw PIMCollectionDiscoveryError.authenticationRequired
        default:
            throw PIMCollectionDiscoveryError.invalidResponse
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw PIMCollectionDiscoveryError.invalidResponse
        }
    }

    // MARK: - Response models

    private struct CalendarListPage: Decodable {
        let items: [CalendarListItem]?
        let nextPageToken: String?
    }

    private struct CalendarListItem: Decodable {
        let id: String?
        let summary: String?
        let summaryOverride: String?
        let backgroundColor: String?
        let accessRole: String?
        let primary: Bool?
        let hidden: Bool?
        let selected: Bool?
        let deleted: Bool?
        let etag: String?
    }

    private struct ContactGroupsPage: Decodable {
        let contactGroups: [ContactGroupItem]?
        let nextPageToken: String?
    }

    private struct ContactGroupItem: Decodable {
        let resourceName: String?
        let name: String?
        let formattedName: String?
        let groupType: String?
        let etag: String?
    }
}
