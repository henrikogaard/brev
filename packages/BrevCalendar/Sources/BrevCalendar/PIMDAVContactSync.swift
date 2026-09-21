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

/// Syncs contacts for one CardDAV address book collection (ADR-0072
/// sync rule 3).
///
/// Collections that advertise sync-token support use the RFC 6578
/// `sync-collection` REPORT requesting `address-data` inline;
/// servers without it fall back to an `addressbook-query` href+ETag
/// listing diffed against the cached versions, with changed items
/// fetched by `addressbook-multiget`. Hrefs missing from a complete
/// listing are treated as deletions.
///
/// Raw vCard payloads are kept verbatim in `PIMContact.rawPayload` (R4).
public struct PIMDAVContactSync: Sendable {
    private let transport: any PIMDAVTransport
    private static let maxRedirectHops = 2

    public init(transport: any PIMDAVTransport = URLSessionPIMDAVTransport()) {
        self.transport = transport
    }

    /// Syncs one address book collection. `cursorToken` is the stored
    /// sync-token; `cachedVersions` maps provider item key → ETag for
    /// the fallback diff.
    public func syncCollection(
        _ collection: PIMCollection,
        source: PIMSource,
        cursorToken: String?,
        cachedVersions: [String: String],
        credential: CalDAVCredential
    ) async throws -> PIMContactSyncResult {
        guard let collectionURL = URL(string: collection.providerKey) else {
            throw PIMContactSyncError.invalidResponse
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
            } catch PIMContactSyncError.unsupportedServer {
                // Advertised but not implemented — degrade to the
                // listing path rather than failing the source.
            }
        }
        return try await addressbookQuerySync(
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
    ) async throws -> PIMContactSyncResult {
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
            // DAV:valid-sync-token error body.
            if let body = String(data: data, encoding: .utf8),
               body.contains("valid-sync-token") {
                throw PIMContactSyncError.cursorExpired
            }
            throw PIMContactSyncError.authenticationRequired
        case 404, 405, 501:
            throw PIMContactSyncError.unsupportedServer
        case 412:
            throw PIMContactSyncError.cursorExpired
        default:
            throw PIMContactSyncError.invalidResponse
        }

        let report = PIMDAVAddressReportParser.parse(
            data,
            relativeTo: collectionURL
        )
        var result = PIMContactSyncResult(
            removedItemKeys: report.removedHrefs,
            nextCursorToken: report.syncToken ?? cursorToken,
            isFullSnapshot: cursorToken == nil
        )

        var needsFetch: [String] = []
        for member in report.members {
            guard let href = member.href else { continue }
            if let addressData = member.addressData {
                if let contact = mapAddressData(
                    addressData,
                    href: href,
                    etag: member.etag,
                    collection: collection,
                    source: source
                ) {
                    result.contacts.append(contact)
                }
            } else {
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
            result.contacts.append(contentsOf: fetched)
        }
        return result
    }

    // MARK: - addressbook-query fallback

    /// Full listing for collections without sync-token support. Diffs
    /// href→ETag against cached versions, fetches changed items, and
    /// treats hrefs missing from the complete listing as deletions.
    private func addressbookQuerySync(
        collection: PIMCollection,
        collectionURL: URL,
        source: PIMSource,
        cachedVersions: [String: String],
        credential: CalDAVCredential
    ) async throws -> PIMContactSyncResult {
        let (data, response) = try await send(
            Self.addressbookQueryRequest(collectionURL),
            credential: credential
        )
        switch response.statusCode {
        case 207:
            break
        case 401, 403:
            throw PIMContactSyncError.authenticationRequired
        case 404, 405, 501:
            throw PIMContactSyncError.unsupportedServer
        default:
            throw PIMContactSyncError.invalidResponse
        }

        let report = PIMDAVAddressReportParser.parse(
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

        var contacts: [PIMContact] = []
        if !fetch.isEmpty {
            contacts = try await multiget(
                hrefs: fetch,
                collectionURL: collectionURL,
                collection: collection,
                source: source,
                credential: credential
            )
        }
        return PIMContactSyncResult(
            contacts: contacts,
            removedItemKeys: removed,
            keptItemKeys: kept,
            nextCursorToken: nil,
            isFullSnapshot: true
        )
    }

    // MARK: - addressbook-multiget

    private func multiget(
        hrefs: [String],
        collectionURL: URL,
        collection: PIMCollection,
        source: PIMSource,
        credential: CalDAVCredential
    ) async throws -> [PIMContact] {
        var contacts: [PIMContact] = []
        for chunk in hrefs.chunked(into: 50) {
            let (data, response) = try await send(
                Self.multigetRequest(collectionURL, hrefs: chunk),
                credential: credential
            )
            switch response.statusCode {
            case 207:
                let report = PIMDAVAddressReportParser.parse(
                    data,
                    relativeTo: collectionURL
                )
                for member in report.members {
                    guard let href = member.href,
                          let addressData = member.addressData,
                          let contact = mapAddressData(
                              addressData,
                              href: href,
                              etag: member.etag,
                              collection: collection,
                              source: source
                          )
                    else { continue }
                    contacts.append(contact)
                }
            case 401, 403:
                throw PIMContactSyncError.authenticationRequired
            default:
                throw PIMContactSyncError.invalidResponse
            }
        }
        return contacts
    }

    // MARK: - Mapping

    /// Parses one address-data vCard payload. Malformed cards are
    /// skipped — one bad record never fails the collection.
    private func mapAddressData(
        _ addressData: String,
        href: String,
        etag: String?,
        collection: PIMCollection,
        source: PIMSource
    ) -> PIMContact? {
        guard let parsed = PIMVCardParser.parse(addressData) else {
            return nil
        }
        return PIMContact(
            id: PIMContact.makeID(
                sourceID: source.id,
                providerItemKey: href
            ),
            sourceID: source.id,
            collectionID: collection.id,
            providerItemKey: href,
            providerVersion: etag,
            uid: parsed.uid,
            displayName: parsed.displayName ?? href,
            givenName: parsed.givenName,
            familyName: parsed.familyName,
            nickname: parsed.nickname,
            organization: parsed.organization,
            jobTitle: parsed.jobTitle,
            note: parsed.note,
            emails: parsed.emails,
            phones: parsed.phones,
            addresses: parsed.addresses,
            photoURL: parsed.photoURL,
            groupKeys: parsed.groupKeys,
            rawPayload: addressData,
            providerUpdatedAt: parsed.revisedAt
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
            } catch let error as PIMContactSyncError {
                throw error
            } catch let error as URLError {
                throw PIMDAVClient.mapTransportError(error).asContactSyncError
            } catch {
                throw PIMContactSyncError.transportFailed
            }
            if (300 ..< 400).contains(response.statusCode),
               attempt < Self.maxRedirectHops,
               let location = response.value(forHTTPHeaderField: "Location"),
               let next = URL(string: location, relativeTo: current.url) {
                try PIMDAVClient.requireHTTPS(next)
                guard PIMDAVClient.isSameOrigin(current.url!, next) else {
                    throw PIMContactSyncError.invalidResponse
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
        throw PIMContactSyncError.invalidResponse
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
            <d:sync-collection xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:carddav">
              <d:sync-token>\(cursorToken ?? "")</d:sync-token>
              <d:sync-level>1</d:sync-level>
              <d:prop>
                <d:getetag/>
                <c:address-data/>
              </d:prop>
            </d:sync-collection>
            """.utf8
        )
        return request
    }

    private static func addressbookQueryRequest(_ url: URL) -> URLRequest {
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
            <c:addressbook-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:carddav">
              <d:prop>
                <d:getetag/>
              </d:prop>
            </c:addressbook-query>
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
            <c:addressbook-multiget xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:carddav">
              <d:prop>
                <d:getetag/>
                <c:address-data/>
              </d:prop>
            \(hrefElements)
            </c:addressbook-multiget>
            """.utf8
        )
        return request
    }
}

private extension PIMDAVConnectError {
    /// Projects setup errors onto the contacts-sync taxonomy.
    var asContactSyncError: PIMContactSyncError {
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

// MARK: - Address report parsing

/// One member row from a sync-collection, addressbook-query or
/// addressbook-multiget multistatus response.
struct PIMDAVAddressMember: Sendable, Hashable {
    /// Absolute href of the member resource.
    var href: String?
    /// getetag value when the propstat succeeded.
    var etag: String?
    /// address-data payload when the response carried it inline.
    var addressData: String?
}

/// Extracts member rows, removed hrefs and the next sync-token from a
/// CardDAV REPORT multistatus body. Local-name matching keeps the parser
/// immune to namespace prefix choices.
enum PIMDAVAddressReportParser {
    static func parse(
        _ data: Data,
        relativeTo base: URL
    ) -> (
        members: [PIMDAVAddressMember],
        removedHrefs: [String],
        syncToken: String?
    ) {
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
        private(set) var members: [PIMDAVAddressMember] = []
        private(set) var removedHrefs: [String] = []
        private(set) var syncToken: String?

        private var current: PIMDAVAddressMember?
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
            case href, etag, addressData, status, syncToken
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
                current = PIMDAVAddressMember()
                responseStatus = ""
            case "propstat":
                inPropstat = true
            case "href" where responseDepth > 0:
                capturing = .href
                buffer = ""
            case "getetag" where inPropstat:
                capturing = .etag
                buffer = ""
            case "address-data" where inPropstat:
                capturing = .addressData
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
            case "address-data" where capturing == .addressData:
                current?.addressData = buffer
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
