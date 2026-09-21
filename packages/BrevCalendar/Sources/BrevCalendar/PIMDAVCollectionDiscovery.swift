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

/// Discovers the collections a connected DAV source exposes (ADR-0072).
///
/// The walk mirrors RFC 4791/6352: PROPFIND the principal for the
/// kind's home-set, then Depth:1 the home set for collections. Sources
/// whose validation never reported a principal fall back to probing the
/// endpoint for both values. Redirects get the connect client's policy —
/// one same-origin HTTPS hop, credentials never cross origins — and
/// failures reuse the PIMDAVConnectError taxonomy so settings surfaces
/// already know how to present them.
public struct PIMDAVCollectionDiscovery: Sendable {
    private let transport: any PIMDAVTransport
    private static let maxRedirectHops = 1

    public init(transport: any PIMDAVTransport = URLSessionPIMDAVTransport()) {
        self.transport = transport
    }

    /// Lists every collection the source's home set advertises for its
    /// kind. Read permission, color and sync-token support are captured
    /// when the server reports them; absent privilege information leaves
    /// the collection marked writable so the UI does not hide actions the
    /// server may still allow — conditional writes re-check later.
    public func discoverCollections(
        for source: PIMSource,
        credential: CalDAVCredential
    ) async throws -> [PIMDiscoveredCollection] {
        guard let endpoint = source.endpointURL else {
            throw PIMDAVConnectError.invalidEndpoint
        }
        guard let homeSet = try await resolveHomeSet(
            for: source,
            endpoint: endpoint,
            credential: credential
        ) else {
            throw PIMDAVConnectError.unsupportedServer
        }
        return try await listCollections(
            in: homeSet,
            kind: source.kind,
            credential: credential
        )
    }

    // MARK: - Home set

    private func resolveHomeSet(
        for source: PIMSource,
        endpoint: URL,
        credential: CalDAVCredential
    ) async throws -> URL? {
        if let principal = source.principalURL {
            try PIMDAVClient.requireHTTPS(principal)
            if let homeSet = try await propfindHomeSet(
                at: principal,
                kind: source.kind,
                includePrincipal: false,
                credential: credential
            ).homeSet {
                return homeSet
            }
        }
        // No principal (or the principal did not answer): probe the
        // endpoint for both values. Some servers expose the home set on
        // the endpoint itself.
        let probe = try await propfindHomeSet(
            at: endpoint,
            kind: source.kind,
            includePrincipal: true,
            credential: credential
        )
        if let homeSet = probe.homeSet { return homeSet }
        if let principal = probe.principal, principal != endpoint {
            try PIMDAVClient.requireHTTPS(principal)
            return try await propfindHomeSet(
                at: principal,
                kind: source.kind,
                includePrincipal: false,
                credential: credential
            ).homeSet
        }
        return nil
    }

    private struct HomeSetProbe {
        let homeSet: URL?
        let principal: URL?
    }

    private func propfindHomeSet(
        at url: URL,
        kind: PIMSourceKind,
        includePrincipal: Bool,
        credential: CalDAVCredential
    ) async throws -> HomeSetProbe {
        let (data, _) = try await send(
            Self.homeSetPropfind(url, includePrincipal: includePrincipal),
            credential: credential
        )
        let parsed = PIMDAVHomeSetParser.parse(data, relativeTo: url)
        // Tasks live in the calendar home set: a .tasks source lists
        // VTODO-capable CalDAV collections (#12).
        let href = kind == .contacts
            ? parsed.addressbookHomeSet
            : parsed.calendarHomeSet
        let homeSet = href.flatMap {
            URL(string: $0, relativeTo: url)?.absoluteURL
        }
        if let homeSet { try PIMDAVClient.requireHTTPS(homeSet) }
        return HomeSetProbe(homeSet: homeSet, principal: parsed.principal)
    }

    // MARK: - Collection listing

    private func listCollections(
        in homeSet: URL,
        kind: PIMSourceKind,
        credential: CalDAVCredential
    ) async throws -> [PIMDiscoveredCollection] {
        let (data, _) = try await send(
            Self.collectionPropfind(homeSet),
            credential: credential
        )
        let responses = PIMDAVCollectionListParser.parse(data)
        // Tasks share the calendar resourcetype; the component set
        // decides which collections can hold VTODOs (#12).
        let kindMarker = kind == .contacts ? "addressbook" : "calendar"
        let homeSetPath = Self.normalizedPath(homeSet)
        var collections: [PIMDiscoveredCollection] = []
        for response in responses {
            guard response.resourceTypes.contains("collection"),
                  response.resourceTypes.contains(kindMarker),
                  let href = response.href,
                  let collectionURL = URL(
                      string: href,
                      relativeTo: homeSet
                  )?.absoluteURL
            else { continue }
            // The home set itself can answer with a collection
            // resourcetype; it is a container, not a browsable collection.
            if Self.normalizedPath(collectionURL) == homeSetPath { continue }
            // VTODO support must be advertised, not assumed (#12): a
            // calendar without a component set, or one that omits VTODO,
            // never surfaces as a task list.
            if kind == .tasks,
               !response.supportedComponents.contains("vtodo") {
                continue
            }
            collections.append(
                PIMDiscoveredCollection(
                    providerKey: collectionURL.absoluteString,
                    displayName: response.displayName
                        ?? collectionURL.lastPathComponent.nilIfEmpty
                        ?? collectionURL.absoluteString,
                    colorHex: response.color,
                    isReadOnly: response.isReadOnly,
                    isPrimary: false,
                    supportsSyncToken: response.supportsSyncToken,
                    providerVersion: response.ctag ?? response.etag,
                    initiallyHidden: false
                )
            )
        }
        return collections
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
            } catch let error as PIMDAVConnectError {
                throw error
            } catch let error as URLError {
                throw PIMDAVClient.mapTransportError(error)
            } catch {
                throw PIMDAVConnectError.transportFailed
            }
            switch response.statusCode {
            case 207:
                return (data, response)
            case 300 ..< 400:
                guard attempt < Self.maxRedirectHops,
                      let location = response
                      .value(forHTTPHeaderField: "Location"),
                      let next = URL(
                          string: location,
                          relativeTo: current.url
                      )?.absoluteURL
                else {
                    throw PIMDAVConnectError.discoveryFailed
                }
                try PIMDAVClient.requireHTTPS(next)
                guard let currentURL = current.url,
                      PIMDAVClient.isSameOrigin(currentURL, next)
                else {
                    throw PIMDAVConnectError.crossOriginRedirect
                }
                current.url = next
            case 401, 403:
                throw PIMDAVConnectError.authenticationRequired
            case 404, 405, 501:
                throw PIMDAVConnectError.unsupportedServer
            default:
                throw PIMDAVConnectError.discoveryFailed
            }
        }
        throw PIMDAVConnectError.discoveryFailed
    }

    private static func homeSetPropfind(
        _ url: URL,
        includePrincipal: Bool
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue(
            "application/xml; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        let principalProp = includePrincipal
            ? "<d:current-user-principal/>"
            : ""
        request.httpBody = Data(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <d:propfind xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav" xmlns:card="urn:ietf:params:xml:ns:carddav">
              <d:prop>
                \(principalProp)
                <cal:calendar-home-set/>
                <card:addressbook-home-set/>
              </d:prop>
            </d:propfind>
            """.utf8
        )
        return request
    }

    private static func collectionPropfind(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue(
            "application/xml; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Data(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <d:propfind xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav" xmlns:card="urn:ietf:params:xml:ns:carddav" xmlns:cs="http://calendarserver.org/ns/" xmlns:ical="http://apple.com/ns/ical/">
              <d:prop>
                <d:resourcetype/>
                <d:displayname/>
                <d:sync-token/>
                <d:getetag/>
                <d:supported-report-set/>
                <d:current-user-privilege-set/>
                <cal:supported-calendar-component-set/>
                <cs:getctag/>
                <ical:calendar-color/>
                <card:addressbook-color/>
              </d:prop>
            </d:propfind>
            """.utf8
        )
        return request
    }

    /// Compares hrefs by scheme/host/path so a trailing-slash difference
    /// cannot make the home set look like its own child.
    private static func normalizedPath(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        var normalized = components?.string ?? url.absoluteString
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized.lowercased()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Home-set parsing

/// Extracts home-set and principal hrefs from a PROPFIND multistatus
/// body. Matches on local element names so namespace prefixes and
/// propstat layout do not matter.
enum PIMDAVHomeSetParser {
    struct Result: Sendable {
        var principal: URL?
        var calendarHomeSet: String?
        var addressbookHomeSet: String?
    }

    static func parse(_ data: Data, relativeTo base: URL) -> Result {
        let delegate = Delegate(base: base)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.parse()
        return delegate.result
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        private(set) var result = Result()
        private let base: URL
        /// The href-bearing property currently open, if any.
        private var target: Target?
        private var buffer = ""

        private enum Target {
            case principal, calendarHomeSet, addressbookHomeSet
        }

        init(base: URL) { self.base = base }

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
            case "current-user-principal": target = .principal
            case "calendar-home-set": target = .calendarHomeSet
            case "addressbook-home-set": target = .addressbookHomeSet
            case "href" where target != nil:
                buffer = ""
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if target != nil { buffer += string }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let local = Self.localName(elementName)
            if local == "href", let target {
                let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    switch target {
                    case .principal:
                        if result.principal == nil {
                            result.principal = URL(
                                string: value,
                                relativeTo: base
                            )?.absoluteURL
                        }
                    case .calendarHomeSet:
                        result.calendarHomeSet = result.calendarHomeSet ?? value
                    case .addressbookHomeSet:
                        result.addressbookHomeSet = result.addressbookHomeSet ?? value
                    }
                }
                return
            }
            switch local {
            case "current-user-principal", "calendar-home-set", "addressbook-home-set":
                target = nil
            default:
                break
            }
        }
    }
}

// MARK: - Collection list parsing

/// Parses the Depth:1 home-set listing into per-response property bags.
/// Only propstats whose status reads 200 contribute props; hrefs are
/// captured at response level so prop values never leak into the href.
enum PIMDAVCollectionListParser {
    struct Response: Sendable {
        var href: String?
        var displayName: String?
        var resourceTypes: Set<String> = []
        var privileges: Set<String> = []
        var reports: Set<String> = []
        var ctag: String?
        var syncToken: String?
        var etag: String?
        var color: String?
        /// CalDAV supported-calendar-component-set values, lowercased
        /// (e.g. "vevent", "vtodo"). Empty when the server did not
        /// advertise one — callers treat that as "not proven".
        var supportedComponents: Set<String> = []

        /// Read-only is only asserted when the server reported a
        /// privilege set without any write privilege; absent privilege
        /// information leaves the collection marked writable.
        var isReadOnly: Bool {
            guard !privileges.isEmpty else { return false }
            return !privileges.contains("all")
                && !privileges.contains("write")
                && !privileges.contains("write-content")
        }

        var supportsSyncToken: Bool {
            syncToken != nil || reports.contains("sync-collection")
        }
    }

    static func parse(_ data: Data) -> [Response] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.parse()
        return delegate.responses
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        private(set) var responses: [Response] = []

        private var current: Response?
        /// Scratch bag for the open propstat; merged only when the
        /// propstat status is 200.
        private var scratch = Response()
        private var inPropstat = false
        private var propstatOK = false
        private var inResourceType = false
        private var inPrivilege = false
        private var inReport = false
        private var inSupportedComponents = false
        private var textTarget: TextTarget?
        private var buffer = ""

        private enum TextTarget {
            case href
            case status
            case displayName
            case ctag
            case syncToken
            case etag
            case color
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
            let local = Self.localName(elementName)
            // Container children first: resourcetype/privilege/report
            // element names are prop values, not elements to open.
            if inResourceType {
                scratch.resourceTypes.insert(local)
                return
            }
            if inPrivilege {
                scratch.privileges.insert(local)
                return
            }
            if inReport {
                scratch.reports.insert(local)
                return
            }
            if inSupportedComponents {
                // <comp name="VTODO"/> carries the component name as an
                // attribute, not as text.
                if local == "comp",
                   let name = attributeDict["name"], !name.isEmpty {
                    scratch.supportedComponents.insert(name.lowercased())
                }
                return
            }
            if current != nil, !inPropstat, local == "href" {
                textTarget = .href
                buffer = ""
                return
            }
            switch local {
            case "response":
                current = Response()
            case "propstat" where current != nil:
                inPropstat = true
                propstatOK = false
                scratch = Response()
            case "status" where inPropstat:
                textTarget = .status
                buffer = ""
            case "resourcetype" where inPropstat:
                inResourceType = true
            case "privilege" where inPropstat:
                inPrivilege = true
            case "report" where inPropstat:
                inReport = true
            case "supported-calendar-component-set" where inPropstat:
                inSupportedComponents = true
            case "displayname" where inPropstat:
                textTarget = .displayName
                buffer = ""
            case "getctag" where inPropstat:
                textTarget = .ctag
                buffer = ""
            case "sync-token" where inPropstat:
                textTarget = .syncToken
                buffer = ""
            case "getetag" where inPropstat:
                textTarget = .etag
                buffer = ""
            case "calendar-color" where inPropstat,
                 "addressbook-color" where inPropstat:
                textTarget = .color
                buffer = ""
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if textTarget != nil { buffer += string }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let local = Self.localName(elementName)
            let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            switch local {
            case "href" where textTarget == .href:
                if current?.href == nil, !value.isEmpty {
                    current?.href = value
                }
                textTarget = nil
            case "status" where textTarget == .status:
                propstatOK = value.contains(" 200 ")
                textTarget = nil
            case "displayname" where textTarget == .displayName:
                scratch.displayName = value.nilIfEmpty
                textTarget = nil
            case "getctag" where textTarget == .ctag:
                scratch.ctag = value.nilIfEmpty
                textTarget = nil
            case "sync-token" where textTarget == .syncToken:
                scratch.syncToken = value.nilIfEmpty
                textTarget = nil
            case "getetag" where textTarget == .etag:
                scratch.etag = value.nilIfEmpty
                textTarget = nil
            case "calendar-color" where textTarget == .color,
                 "addressbook-color" where textTarget == .color:
                scratch.color = value.nilIfEmpty
                textTarget = nil
            case "resourcetype":
                inResourceType = false
            case "privilege":
                inPrivilege = false
            case "report":
                inReport = false
            case "supported-calendar-component-set":
                inSupportedComponents = false
            case "propstat":
                if inPropstat, propstatOK, current != nil {
                    mergeScratch()
                }
                inPropstat = false
                scratch = Response()
            case "response":
                if let current { responses.append(current) }
                current = nil
            default:
                break
            }
        }

        private func mergeScratch() {
            guard var merged = current else { return }
            merged.displayName = merged.displayName ?? scratch.displayName
            merged.resourceTypes.formUnion(scratch.resourceTypes)
            merged.privileges.formUnion(scratch.privileges)
            merged.reports.formUnion(scratch.reports)
            merged.ctag = merged.ctag ?? scratch.ctag
            merged.syncToken = merged.syncToken ?? scratch.syncToken
            merged.etag = merged.etag ?? scratch.etag
            merged.color = merged.color ?? scratch.color
            merged.supportedComponents.formUnion(scratch.supportedComponents)
            current = merged
        }
    }
}
