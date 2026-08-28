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

// MARK: - CardDAVContactRecord

/// A single contact fetched from a CardDAV addressbook collection.
public struct CardDAVContactRecord: Sendable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    public let emails: [String]
    public let organization: String?

    public init(id: String, displayName: String, emails: [String], organization: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.emails = emails
        self.organization = organization
    }
}

// MARK: - Sync errors

/// Errors that can occur during a CardDAV REPORT sync.
public enum CardDAVSyncError: Error, Sendable {
    case insecureBasicAuth
    case authenticationFailed
    case unexpectedStatus(Int)
    case transport(String)
}

// MARK: - ContactsSyncCoordinator

/// Actor that fetches contacts from a CardDAV addressbook collection via an
/// `addressbook-query` REPORT and caches them in memory for compose autocomplete.
///
/// Sync is triggered explicitly; the actor never makes background network calls
/// on its own schedule. The caller is responsible for determining when to refresh.
public actor ContactsSyncCoordinator {
    private var contacts: [CardDAVContactRecord] = []
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - Search

    /// Returns contacts whose display name or any email address contains `query`
    /// (case-insensitive prefix or substring match), up to `limit` results.
    public func contacts(matching query: String, limit: Int = 8) -> [CardDAVContactRecord] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let q = query.lowercased()
        return contacts
            .filter { record in
                record.displayName.lowercased().contains(q)
                    || record.emails.contains { $0.lowercased().contains(q) }
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Sync

    /// Issues an `addressbook-query` REPORT against the principal URL, parses the
    /// vCard responses, and replaces the in-memory contact list.
    ///
    /// Follows RFC 6352 §8.6. Returns the count of imported contacts on success.
    @discardableResult
    public func sync(
        configuration: CardDAVConfiguration,
        credential: CalDAVCredential
    ) async throws -> Int {
        if case .basic = credential {
            let host = configuration.principalURL.host?.lowercased() ?? ""
            guard host == "localhost" || host == "127.0.0.1" || host == "::1" else {
                throw CardDAVSyncError.insecureBasicAuth
            }
        }

        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <C:addressbook-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
          <D:prop>
            <C:address-data/>
          </D:prop>
        </C:addressbook-query>
        """

        var request = URLRequest(
            url: configuration.principalURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.httpMethod = "REPORT"
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue(credential.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.httpBody = Data(body.utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw CardDAVSyncError.transport(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        switch status {
        case 200, 207:
            break
        case 401, 403:
            throw CardDAVSyncError.authenticationFailed
        default:
            throw CardDAVSyncError.unexpectedStatus(status)
        }

        let parsed = VCardXMLParser.parse(data)
        contacts = parsed
        return parsed.count
    }
}

// MARK: - vCard XML parser

/// Minimal parser for the multistatus REPORT response. Extracts `address-data`
/// vCard payloads and pulls out FN, EMAIL, and ORG fields.
enum VCardXMLParser {
    static func parse(_ data: Data) -> [CardDAVContactRecord] {
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        // Extract each <C:address-data> block (may be namespaced differently in responses).
        let blocks = extractAddressDataBlocks(from: xmlString)
        return blocks.compactMap { parseVCard($0) }
    }

    private static func extractAddressDataBlocks(from xml: String) -> [String] {
        var results: [String] = []
        let patterns = ["address-data", "card:address-data", "C:address-data"]
        for tag in patterns {
            let open = "<\(tag)"
            let close = "</\(tag)>"
            var searchRange = xml.startIndex ..< xml.endIndex
            while let start = xml.range(of: open, range: searchRange) {
                guard let tagEnd = xml.range(of: ">", range: start.upperBound ..< xml.endIndex) else { break }
                guard let end = xml.range(of: close, range: tagEnd.upperBound ..< xml.endIndex) else { break }
                let content = String(xml[tagEnd.upperBound ..< end.lowerBound])
                if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    results.append(content)
                }
                searchRange = end.upperBound ..< xml.endIndex
            }
            if !results.isEmpty { break }
        }
        return results
    }

    /// Parses a single vCard 3.0/4.0 text blob and extracts a `CardDAVContactRecord`.
    static func parseVCard(_ vcard: String) -> CardDAVContactRecord? {
        var fn: String?
        var emails: [String] = []
        var org: String?
        var uid: String?

        for rawLine in vcard.components(separatedBy: .newlines) {
            let line = rawLine
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "=\r", with: "")
                .replacingOccurrences(of: "=\n", with: "")

            let upper = line.uppercased()
            if upper.hasPrefix("UID:") {
                uid = String(line.dropFirst(4))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if upper.hasPrefix("FN:") || upper.hasPrefix("FN;") {
                fn = unescapeVCardValue(String(line.dropFirst(3)))
            } else if upper.hasPrefix("EMAIL") {
                if let colon = line.firstIndex(of: ":") {
                    let email = String(line[line.index(after: colon)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !email.isEmpty, email.contains("@") {
                        emails.append(email.lowercased())
                    }
                }
            } else if upper.hasPrefix("ORG:") || upper.hasPrefix("ORG;") {
                if let colon = line.firstIndex(of: ":") {
                    let raw = String(line[line.index(after: colon)...])
                    // ORG can have semi-colon separated division names; take first component.
                    org = unescapeVCardValue(raw.components(separatedBy: ";").first ?? raw)
                }
            }
        }

        guard let displayName = fn, !displayName.isEmpty, !emails.isEmpty else { return nil }
        return CardDAVContactRecord(
            id: uid ?? "\(displayName)-\(emails.first ?? UUID().uuidString)",
            displayName: displayName,
            emails: emails,
            organization: org?.isEmpty == false ? org : nil
        )
    }

    static func unescapeVCardValue(_ raw: String) -> String {
        // Single left-to-right pass (RFC 6350 §3.4). Sequential string
        // replacements with "\\" unescaped last are wrong: e.g. "\\n" (escaped
        // backslash + literal n) would have its "\n" matched across the escaped
        // backslash and become backslash + newline instead of backslash + "n".
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ""
        result.reserveCapacity(trimmed.count)
        var iterator = trimmed.makeIterator()
        while let character = iterator.next() {
            guard character == "\\", let escaped = iterator.next() else {
                result.append(character)
                continue
            }
            switch escaped {
            case "n", "N": result.append("\n")
            case ",": result.append(",")
            case ";": result.append(";")
            case "\\": result.append("\\")
            default:
                // Unknown escape: keep both characters verbatim.
                result.append("\\")
                result.append(escaped)
            }
        }
        return result
    }
}
