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

// MARK: - Transport

/// Minimal HTTP seam for DAV setup requests so tests can script responses
/// without a live server.
public protocol PIMDAVTransport: Sendable {
    /// Sends the request and returns the raw response. Redirects are NOT
    /// followed: the client evaluates each hop itself so credentials are
    /// never forwarded across origins by transport policy.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSession-backed transport that refuses to auto-follow redirects.
///
/// The session delegate declines every redirect, so responses arrive as the
/// raw 3xx and the client decides whether the next hop stays in origin.
public struct URLSessionPIMDAVTransport: PIMDAVTransport {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        self.session = session ?? Self.makeSession()
    }

    private static func makeSession() -> URLSession {
        URLSession(
            configuration: .ephemeral,
            delegate: RedirectBlocker(),
            delegateQueue: nil
        )
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PIMDAVConnectError.transportFailed
        }
        return (data, http)
    }

    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}

// MARK: - Endpoint and result models

/// How the DAV endpoint is reached (ADR-0072 source setup).
public enum PIMDAVEndpoint: Sendable, Hashable {
    /// User-entered server URL, validated directly.
    case manual(URL)
    /// RFC 6764 well-known discovery against the address domain.
    case discover(emailAddress: String)
}

/// What a successful validation learned about the endpoint.
public struct PIMDAVValidation: Sendable, Hashable {
    /// The URL the credential was actually validated against.
    public let endpointURL: URL
    /// The authenticated principal reported by the server, when it answered
    /// current-user-principal.
    public let principalURL: URL?
    /// How the endpoint was reached.
    public let discoveryMethod: CalDAVDiscoveryMethod

    public init(
        endpointURL: URL,
        principalURL: URL?,
        discoveryMethod: CalDAVDiscoveryMethod
    ) {
        self.endpointURL = endpointURL
        self.principalURL = principalURL
        self.discoveryMethod = discoveryMethod
    }
}

// MARK: - Errors

/// Actionable setup failures. Each case maps to a distinct user remedy —
/// fix the address, enter a manual endpoint, re-enter credentials, or pick
/// a different server — rather than a generic failure.
public enum PIMDAVConnectError: Error, Sendable, Hashable, LocalizedError {
    /// The address or URL cannot produce a usable endpoint.
    case invalidEndpoint
    /// Endpoint or a discovered redirect is not HTTPS.
    case httpsRequired
    /// The server redirected authentication to a different host; the user
    /// must enter that endpoint manually.
    case crossOriginRedirect
    /// Credentials were rejected (401/403 or a transport auth challenge).
    case authenticationRequired
    /// Discovery did not find a DAV service at the domain.
    case discoveryFailed
    /// The endpoint answered but does not speak DAV.
    case unsupportedServer
    /// TLS validation failed; never fall back to insecure transport.
    case tlsValidationFailed
    /// Connectivity or an unspecified transport failure.
    case transportFailed

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return String(
                localized: "Enter a valid email address or server URL.",
                bundle: .module
            )
        case .httpsRequired:
            return String(
                localized: "This server requires a secure HTTPS connection.",
                bundle: .module
            )
        case .crossOriginRedirect:
            return String(
                localized: "The server redirects to a different host. Enter that server address manually.",
                bundle: .module
            )
        case .authenticationRequired:
            return String(
                localized: "The server rejected these credentials. Check the username and password or token.",
                bundle: .module
            )
        case .discoveryFailed:
            return String(
                localized: "No calendar or contacts service was found at this address. Enter the server URL manually.",
                bundle: .module
            )
        case .unsupportedServer:
            return String(
                localized: "This server does not support CalDAV or CardDAV.",
                bundle: .module
            )
        case .tlsValidationFailed:
            return String(
                localized: "The server's certificate could not be verified. The connection was not made.",
                bundle: .module
            )
        case .transportFailed:
            return String(
                localized: "The server could not be reached. Check the connection and try again.",
                bundle: .module
            )
        }
    }
}

// MARK: - Client

/// Validates DAV endpoints for source setup (ADR-0072).
///
/// Two entry points mirror the issue's setup contract: standards discovery
/// via RFC 6764 well-known URIs, and manual endpoints where needed. Every
/// hop is checked for HTTPS, redirects are followed explicitly so a
/// credential-bearing request never crosses origins, and TLS or
/// authentication failures surface as actionable errors.
public struct PIMDAVClient: Sendable {
    private let transport: any PIMDAVTransport
    /// Maximum redirect hops accepted during well-known discovery.
    private static let maxDiscoveryHops = 3

    public init(transport: any PIMDAVTransport = URLSessionPIMDAVTransport()) {
        self.transport = transport
    }

    /// Validates credentials against the endpoint and returns what the
    /// server reported. Throws PIMDAVConnectError on failure; never stores
    /// the credential — that is the coordinator's job after success.
    public func validate(
        endpoint: PIMDAVEndpoint,
        kind: PIMSourceKind,
        credential: CalDAVCredential
    ) async throws -> PIMDAVValidation {
        let resolution = try await resolve(endpoint: endpoint, kind: kind)
        let principal = try await fetchPrincipal(
            at: resolution.url,
            credential: credential
        )
        return PIMDAVValidation(
            endpointURL: resolution.url,
            principalURL: principal,
            discoveryMethod: resolution.method
        )
    }

    // MARK: - Resolution

    private struct ResolvedEndpoint {
        let url: URL
        let method: CalDAVDiscoveryMethod
    }

    private func resolve(
        endpoint: PIMDAVEndpoint,
        kind: PIMSourceKind
    ) async throws -> ResolvedEndpoint {
        switch endpoint {
        case .manual(let url):
            try Self.requireHTTPS(url)
            return ResolvedEndpoint(url: url, method: .manual)

        case .discover(let emailAddress):
            guard let wellKnown = Self.wellKnownURL(
                for: emailAddress,
                kind: kind
            ) else {
                throw PIMDAVConnectError.invalidEndpoint
            }
            var current = wellKnown
            for _ in 0 ..< Self.maxDiscoveryHops {
                let (_, response) = try await send(Self.get(current), authorize: nil)
                if (300 ..< 400).contains(response.statusCode),
                   let location = response.value(forHTTPHeaderField: "Location"),
                   let next = URL(string: location, relativeTo: current)?.absoluteURL {
                    // Every discovered hop must stay on HTTPS before the
                    // credential-bearing PROPFIND is aimed at it.
                    try Self.requireHTTPS(next)
                    current = next
                    continue
                }
                // A definitive answer — even an auth challenge — means the
                // endpoint exists; PROPFIND performs the authenticated check.
                if (200 ..< 300).contains(response.statusCode)
                    || response.statusCode == 401
                    || response.statusCode == 403 {
                    return ResolvedEndpoint(url: current, method: .wellKnown)
                }
                throw PIMDAVConnectError.discoveryFailed
            }
            throw PIMDAVConnectError.discoveryFailed
        }
    }

    // MARK: - PROPFIND

    /// PROPFIND current-user-principal against the endpoint. Follows a
    /// same-origin redirect once; a cross-origin redirect is surfaced so the
    /// credential is never sent to a host the user did not choose.
    private func fetchPrincipal(
        at url: URL,
        credential: CalDAVCredential
    ) async throws -> URL? {
        var current = url
        for attempt in 0 ..< 2 {
            let (data, response) = try await send(
                Self.propfind(current),
                authorize: credential
            )
            switch response.statusCode {
            case 207:
                return PIMDAVPrincipalParser.principalURL(
                    in: data,
                    relativeTo: current
                )
            case 300 ..< 400:
                guard let location = response.value(forHTTPHeaderField: "Location"),
                      let next = URL(string: location, relativeTo: current)?.absoluteURL
                else {
                    throw PIMDAVConnectError.discoveryFailed
                }
                try Self.requireHTTPS(next)
                guard Self.isSameOrigin(current, next), attempt == 0 else {
                    throw PIMDAVConnectError.crossOriginRedirect
                }
                current = next
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

    // MARK: - Requests

    private func send(
        _ request: URLRequest,
        authorize credential: CalDAVCredential?
    ) async throws -> (Data, HTTPURLResponse) {
        var request = request
        if let credential {
            request.setValue(
                Self.authorizationHeader(for: credential),
                forHTTPHeaderField: "Authorization"
            )
        }
        do {
            return try await transport.send(request)
        } catch let error as PIMDAVConnectError {
            throw error
        } catch let error as URLError {
            throw Self.mapTransportError(error)
        } catch {
            throw PIMDAVConnectError.transportFailed
        }
    }

    private static func get(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return request
    }

    private static func propfind(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue(
            "application/xml; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Data(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <d:propfind xmlns:d="DAV:">
              <d:prop><d:current-user-principal/></d:prop>
            </d:propfind>
            """.utf8
        )
        return request
    }

    /// Shared with collection discovery so both paths build credentials
    /// identically.
    static func authorizationHeader(for credential: CalDAVCredential) -> String {
        switch credential {
        case .bearer(let token):
            return "Bearer \(token)"
        case .basic(let username, let password):
            let raw = Data("\(username):\(password)".utf8)
            return "Basic \(raw.base64EncodedString())"
        }
    }

    // MARK: - URL helpers

    private static func wellKnownURL(
        for emailAddress: String,
        kind: PIMSourceKind
    ) -> URL? {
        guard let atIndex = emailAddress.firstIndex(of: "@") else { return nil }
        let domain = String(
            emailAddress[emailAddress.index(after: atIndex)...]
        ).lowercased()
        guard !domain.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = domain
        components.path = kind == .calendar
            ? "/.well-known/caldav"
            : "/.well-known/carddav"
        return components.url
    }

    /// HTTPS is mandatory for credential-bearing DAV setup. The only
    /// exception is a loopback host so local dev servers stay usable — the
    /// same allowance the CalDAV write-target path makes.
    /// Shared with collection discovery so both paths build credentials
    /// identically.
    static func requireHTTPS(_ url: URL) throws {
        if url.scheme?.lowercased() == "https" { return }
        if url.scheme?.lowercased() == "http",
           let host = url.host(),
           isLoopbackHost(host) {
            return
        }
        throw PIMDAVConnectError.httpsRequired
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        return lower == "localhost"
            || lower == "127.0.0.1"
            || lower == "::1"
            || lower.hasSuffix(".localhost")
    }

    static func isSameOrigin(_ a: URL, _ b: URL) -> Bool {
        a.scheme?.lowercased() == b.scheme?.lowercased()
            && a.host()?.lowercased() == b.host()?.lowercased()
            && a.port == b.port
    }

    static func mapTransportError(_ error: URLError) -> PIMDAVConnectError {
        switch error.code {
        case .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .secureConnectionFailed,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return .tlsValidationFailed
        case .userAuthenticationRequired:
            return .authenticationRequired
        default:
            return .transportFailed
        }
    }
}

// MARK: - Principal parsing

/// Extracts the DAV principal href from a PROPFIND multistatus body.
/// Matches on local element names so either current-user-principal or
/// principal-URL answers resolve regardless of namespace prefix.
enum PIMDAVPrincipalParser {
    static func principalURL(in data: Data, relativeTo base: URL) -> URL? {
        let delegate = PrincipalDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        guard parser.parse() else { return nil }
        guard let href = delegate.href else { return nil }
        return URL(string: href, relativeTo: base)?.absoluteURL
    }

    private final class PrincipalDelegate: NSObject, XMLParserDelegate {
        var href: String?
        /// Depth inside a principal-bearing element; hrefs elsewhere in the
        /// multistatus body (response targets, prop values) are ignored.
        private var principalDepth = 0
        private var capturing = false
        private var buffer = ""

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
            if local == "current-user-principal" || local == "principal-URL" {
                principalDepth += 1
            } else if local == "href", principalDepth > 0 {
                capturing = true
                buffer = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if capturing { buffer += string }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let local = Self.localName(elementName)
            if local == "current-user-principal" || local == "principal-URL" {
                principalDepth = max(0, principalDepth - 1)
            } else if local == "href", capturing {
                capturing = false
                if href == nil {
                    href = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }
}
