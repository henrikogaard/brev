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

/// Syncs contacts for a Google contacts source via the People API
/// `people.connections.list` feed (ADR-0072).
///
/// Google syncs contacts account-wide, not per group: one paged feed
/// returns every connection, and `memberships` carries the contact
/// groups each person belongs to. Initial syncs request a sync token;
/// incremental passes send only that token. Deleted contacts arrive in
/// the feed flagged `metadata.deleted` and become tombstones. An
/// expired token surfaces as `PIMContactSyncError.cursorExpired` so the
/// service restarts a full generation (sync rule 2).
///
/// Person payloads are kept verbatim in `PIMContact.rawPayload` (R4).
public struct GooglePeopleContactSync: Sendable {
    /// HTTP seam shared with the other PIM adapters.
    private let transport: any PIMDAVTransport
    /// Bound on pagination loops so a misbehaving provider cannot spin
    /// the sync forever.
    private static let maxPages = 40

    private static let connectionsURL = URL(
        string: "https://people.googleapis.com/v1/people/me/connections"
    )!
    /// Fields the shared contact model reads. Photos ship URL references
    /// only — image bytes are never fetched during sync.
    private static let personFields =
        "names,nicknames,emailAddresses,phoneNumbers,organizations,"
            + "addresses,biographies,photos,memberships,metadata,"
            + "birthdays,events,urls"

    public init(transport: any PIMDAVTransport = URLSessionPIMDAVTransport()) {
        self.transport = transport
    }

    /// Syncs the account-wide connections feed. `cursorToken` selects
    /// incremental mode; nil runs a full listing that requests a fresh
    /// sync token on the last page.
    public func syncContacts(
        source: PIMSource,
        cursorToken: String?,
        accessToken: String
    ) async throws -> PIMContactSyncResult {
        var result = PIMContactSyncResult(
            isFullSnapshot: cursorToken == nil
        )
        var pageToken: String?
        for _ in 0 ..< Self.maxPages {
            let url = try requestURL(
                cursorToken: cursorToken,
                pageToken: pageToken
            )
            let (data, response) = try await send(
                url,
                accessToken: accessToken
            )
            switch response.statusCode {
            case 200:
                let page = try parsePage(data)
                for person in page.people {
                    mapPerson(person, source: source, into: &result)
                }
                if let next = page.nextPageToken, !next.isEmpty {
                    pageToken = next
                    continue
                }
                result.nextCursorToken = page.nextSyncToken ?? cursorToken
                return result
            case 401, 403:
                throw PIMContactSyncError.authenticationRequired
            case 410:
                throw PIMContactSyncError.cursorExpired
            case 400:
                // People answers an expired sync token with a 400 whose
                // body names the sync token — treat it as recoverable.
                if let body = String(data: data, encoding: .utf8),
                   body.localizedCaseInsensitiveContains("sync") {
                    throw PIMContactSyncError.cursorExpired
                }
                throw PIMContactSyncError.invalidResponse
            default:
                throw PIMContactSyncError.invalidResponse
            }
        }
        throw PIMContactSyncError.invalidResponse
    }

    // MARK: - Request

    private func requestURL(
        cursorToken: String?,
        pageToken: String?
    ) throws -> URL {
        var components = URLComponents(
            url: Self.connectionsURL,
            resolvingAgainstBaseURL: false
        )
        var query = [
            URLQueryItem(name: "personFields", value: Self.personFields),
            URLQueryItem(name: "pageSize", value: "1000")
        ]
        if let cursorToken {
            query.append(URLQueryItem(name: "syncToken", value: cursorToken))
        } else {
            query.append(
                URLQueryItem(name: "requestSyncToken", value: "true")
            )
        }
        if let pageToken {
            query.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components?.queryItems = query
        guard let url = components?.url else {
            throw PIMContactSyncError.invalidResponse
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
        } catch let error as PIMContactSyncError {
            throw error
        } catch {
            throw PIMContactSyncError.transportFailed
        }
    }

    // MARK: - Page parsing

    private struct Page {
        let people: [[String: Any]]
        let nextPageToken: String?
        let nextSyncToken: String?
    }

    private func parsePage(_ data: Data) throws -> Page {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let page = object as? [String: Any]
        else {
            throw PIMContactSyncError.invalidResponse
        }
        return Page(
            people: page["connections"] as? [[String: Any]] ?? [],
            nextPageToken: page["nextPageToken"] as? String,
            nextSyncToken: page["nextSyncToken"] as? String
        )
    }

    // MARK: - Person mapping

    /// Maps one People person resource into the shared model. Deleted
    /// entries carry only identity — they become tombstones.
    private func mapPerson(
        _ person: [String: Any],
        source: PIMSource,
        into result: inout PIMContactSyncResult
    ) {
        guard let resourceName = person["resourceName"] as? String,
              !resourceName.isEmpty
        else { return }

        let metadata = person["metadata"] as? [String: Any]
        if metadata?["deleted"] as? Bool == true {
            result.removedItemKeys.append(resourceName)
            return
        }

        let names = person["names"] as? [[String: Any]] ?? []
        let primaryName = names.first {
            ($0["metadata"] as? [String: Any])?["primary"] as? Bool == true
        } ?? names.first

        let displayName = (primaryName?["displayName"] as? String)
            ?? Self.bestNameFallback(person)
        guard let displayName, !displayName.isEmpty else { return }

        result.contacts.append(
            PIMContact(
                id: PIMContact.makeID(
                    sourceID: source.id,
                    providerItemKey: resourceName
                ),
                sourceID: source.id,
                collectionID: nil,
                providerItemKey: resourceName,
                providerVersion: person["etag"] as? String,
                uid: resourceName,
                displayName: displayName,
                givenName: primaryName?["givenName"] as? String,
                familyName: primaryName?["familyName"] as? String,
                nickname: (person["nicknames"] as? [[String: Any]])?
                    .compactMap { $0["value"] as? String }
                    .first,
                organization: Self.primaryOrganization(person)?.name,
                jobTitle: Self.primaryOrganization(person)?.title,
                note: (person["biographies"] as? [[String: Any]])?
                    .compactMap { $0["value"] as? String }
                    .first,
                emails: Self.mapFields(
                    person["emailAddresses"] as? [[String: Any]]
                ),
                phones: Self.mapFields(
                    person["phoneNumbers"] as? [[String: Any]]
                ),
                addresses: Self.mapAddresses(
                    person["addresses"] as? [[String: Any]]
                ),
                dates: Self.mapDates(person),
                urls: Self.mapFields(
                    person["urls"] as? [[String: Any]]
                ),
                photoURL: Self.mapPhoto(person),
                groupKeys: Self.mapGroupKeys(person),
                rawPayload: Self.rawPayload(for: person),
                providerUpdatedAt: Self.mapUpdateTime(metadata)
            )
        )
    }

    /// A displayName can be absent on contacts that only carry an email —
    /// fall back to the first email so the record stays browsable.
    private static func bestNameFallback(_ person: [String: Any]) -> String? {
        (person["emailAddresses"] as? [[String: Any]])?
            .compactMap { $0["value"] as? String }
            .first
    }

    private static func primaryOrganization(
        _ person: [String: Any]
    ) -> (name: String?, title: String?)? {
        let organizations = person["organizations"] as? [[String: Any]] ?? []
        let primary = organizations.first {
            ($0["metadata"] as? [String: Any])?["primary"] as? Bool == true
        } ?? organizations.first
        guard let primary else { return nil }
        return (
            name: primary["name"] as? String,
            title: primary["title"] as? String
        )
    }

    private static func mapFields(
        _ entries: [[String: Any]]?
    ) -> [PIMContactField] {
        (entries ?? []).compactMap { entry in
            guard let value = entry["value"] as? String, !value.isEmpty
            else { return nil }
            return PIMContactField(
                label: (entry["formattedType"] as? String)?
                    .lowercased(),
                value: value
            )
        }
    }

    private static func mapAddresses(
        _ entries: [[String: Any]]?
    ) -> [PIMContactAddress] {
        (entries ?? []).map { entry in
            PIMContactAddress(
                label: (entry["formattedType"] as? String)?.lowercased(),
                street: entry["streetAddress"] as? String,
                city: entry["city"] as? String,
                region: entry["region"] as? String,
                postalCode: entry["postalCode"] as? String,
                country: entry["country"] as? String
            )
        }
        .filter { !$0.isEmpty }
    }

    /// Birthdays plus events map onto the shared labeled-date list —
    /// a Person's `birthdays` entries carry label \"birthday\", events
    /// carry their type (custom types come back through customType).
    private static func mapDates(
        _ person: [String: Any]
    ) -> [PIMContactDate] {
        var dates: [PIMContactDate] = []
        let birthdays = person["birthdays"] as? [[String: Any]] ?? []
        for entry in birthdays {
            if let date = mapDateEntry(entry, label: "birthday") {
                dates.append(date)
            }
        }
        let events = person["events"] as? [[String: Any]] ?? []
        for entry in events {
            let type = (entry["type"] as? String)?.lowercased()
            let label = type == "custom"
                ? (entry["customType"] as? String)?.lowercased()
                : type
            if let date = mapDateEntry(entry, label: label ?? "other") {
                dates.append(date)
            }
        }
        return dates
    }

    /// One google.type.Date entry — year-less dates omit year.
    private static func mapDateEntry(
        _ entry: [String: Any],
        label: String
    ) -> PIMContactDate? {
        guard let date = entry["date"] as? [String: Any],
              let month = date["month"] as? Int,
              let day = date["day"] as? Int
        else { return nil }
        let year = (date["year"] as? Int).flatMap { $0 > 0 ? $0 : nil }
        return PIMContactDate(
            label: label,
            year: year,
            month: month,
            day: day
        )
    }

    /// Only HTTPS photo URLs are stored; Google's default silhouette
    /// (which carries no real image) is dropped.
    private static func mapPhoto(_ person: [String: Any]) -> String? {
        let photos = person["photos"] as? [[String: Any]] ?? []
        for photo in photos {
            if (photo["default"] as? Bool) == true { continue }
            guard let url = photo["url"] as? String,
                  url.lowercased().hasPrefix("https://")
            else { continue }
            return url
        }
        return nil
    }

    private static func mapGroupKeys(_ person: [String: Any]) -> [String] {
        (person["memberships"] as? [[String: Any]] ?? [])
            .compactMap {
                ($0["contactGroupMembership"] as? [String: Any])?[
                    "contactGroupResourceName"
                ] as? String
            }
    }

    private static func mapUpdateTime(
        _ metadata: [String: Any]?
    ) -> Date? {
        let sources = metadata?["sources"] as? [[String: Any]] ?? []
        for source in sources {
            if let raw = source["updateTime"] as? String,
               let date = Self.rfc3339.date(from: raw)
               ?? Self.rfc3339Fractional.date(from: raw) {
                return date
            }
        }
        return nil
    }

    /// The verbatim person JSON — provider fields the shared model does
    /// not read still survive refresh and later edits (ADR-0072 R4).
    private static func rawPayload(for person: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(person),
              let data = try? JSONSerialization.data(
                  withJSONObject: person,
                  options: [.sortedKeys]
              )
        else { return nil }
        return String(data: data, encoding: .utf8)
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
}
