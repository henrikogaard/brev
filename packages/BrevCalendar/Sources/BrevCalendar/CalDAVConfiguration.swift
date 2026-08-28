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

// MARK: - CalDAV configuration

/// Connection parameters for a CalDAV server.
///
/// Authentication is always OAuth2/Bearer for providers that expose DAV
/// services with XOAUTH2. Username/password and app-password are not
/// supported in this path — privacy-first design, no plaintext credentials
/// (see ADR-0028).
public struct CalDAVConfiguration: Sendable, Hashable, Codable {
    /// Authentication method for the CalDAV connection.
    public enum AuthMode: String, Sendable, Hashable, Codable {
        /// OAuth2 Bearer token (preferred).
        case oauth2
        /// HTTP Basic — only permitted for localhost dev servers.
        case httpBasicLocalOnly
    }

    /// Base URL for the CalDAV principal.
    public var principalURL: URL
    public var authMode: AuthMode
    /// Account email, used to derive paths and for display.
    public var email: String

    public init(principalURL: URL, authMode: AuthMode = .oauth2, email: String) {
        self.principalURL = principalURL
        self.authMode = authMode
        self.email = email
    }
}

// MARK: - CardDAV configuration

/// Connection parameters for a CardDAV contacts server.
public struct CardDAVConfiguration: Sendable, Hashable, Codable {
    public enum AuthMode: String, Sendable, Hashable, Codable {
        case oauth2
        case httpBasicLocalOnly
    }

    public var principalURL: URL
    public var authMode: AuthMode
    public var email: String

    public init(principalURL: URL, authMode: AuthMode = .oauth2, email: String) {
        self.principalURL = principalURL
        self.authMode = authMode
        self.email = email
    }
}

// MARK: - Discovery

public enum CalDAVDiscoveryMethod: String, Sendable, Hashable, Codable {
    case wellKnown = "well-known"
    case srv
    case manual
}

/// Discovers CalDAV and CardDAV server endpoints for a mail domain.
///
/// Uses the well-known URI scheme (RFC 6764) as the primary path.
/// Full SRV probing requires network access and is deferred to a live
/// implementation that injects `URLSession`.
public struct CalDAVDiscovery: Sendable {
    public typealias DiscoveryMethod = CalDAVDiscoveryMethod

    private static func isValidDomain(_ domain: String) -> Bool {
        guard !domain.isEmpty, domain.utf8.count <= 253 else { return false }

        var labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        if labels.last?.isEmpty == true {
            labels.removeLast()
        }
        guard !labels.isEmpty else { return false }

        return labels.allSatisfy { label in
            guard !label.isEmpty, label.utf8.count <= 63,
                  let first = label.first, let last = label.last,
                  first.isLetter || first.isNumber,
                  last.isLetter || last.isNumber
            else {
                return false
            }
            return label.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "-"
            }
        }
    }

    private static func endpointURL(for domain: String, path: String) -> URL? {
        guard isValidDomain(domain) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = domain
        components.path = path
        return components.url
    }

    /// The result of a CalDAV/CardDAV discovery attempt.
    public struct Result: Sendable {
        public let caldav: CalDAVConfiguration?
        public let carddav: CardDAVConfiguration?
        public let discoveryMethod: DiscoveryMethod
    }

    /// Synchronously returns the discovery result for a mail domain.
    ///
    /// Uses provider-neutral well-known URL construction for valid domains.
    public static func discover(for emailAddress: String) -> Result {
        guard let atIndex = emailAddress.firstIndex(of: "@") else {
            return Result(caldav: nil, carddav: nil, discoveryMethod: .manual)
        }
        let domain = String(emailAddress[emailAddress.index(after: atIndex)...]).lowercased()
        guard isValidDomain(domain) else {
            return Result(caldav: nil, carddav: nil, discoveryMethod: .manual)
        }

        // Well-known URL construction (RFC 6764).
        guard
            let caldavURL = endpointURL(for: domain, path: "/.well-known/caldav"),
            let carddavURL = endpointURL(for: domain, path: "/.well-known/carddav")
        else {
            return Result(caldav: nil, carddav: nil, discoveryMethod: .manual)
        }
        return Result(
            caldav: CalDAVConfiguration(principalURL: caldavURL, email: emailAddress),
            carddav: CardDAVConfiguration(principalURL: carddavURL, email: emailAddress),
            discoveryMethod: .wellKnown
        )
    }

    /// Constructs well-known CalDAV probe URLs for a domain.
    ///
    /// Returns the set of URLs that should be probed in order of
    /// preference. The caller is responsible for making the HTTP
    /// requests and following redirects.
    public static func probeURLs(for domain: String) -> [URL] {
        let d = domain.lowercased()
        guard isValidDomain(d) else { return [] }
        return [
            endpointURL(for: d, path: "/.well-known/caldav"),
            endpointURL(for: "caldav.\(d)", path: "/.well-known/caldav"),
            endpointURL(for: d, path: "/caldav/")
        ].compactMap { $0 }
    }
}

// MARK: - CalDAV capabilities

/// Features advertised by a CalDAV server after successful discovery.
///
/// Populated from a `PROPFIND` or `OPTIONS` response. In v1 we stub
/// this as a model only — live probing is a v2 implementation task.
public struct CalDAVCapabilities: Sendable, Hashable {
    /// Server supports CalDAV scheduling (RFC 6638).
    public var scheduling: Bool
    /// Server supports free-busy queries (RFC 4791 §7.10).
    public var freeBusy: Bool
    /// Server supports sharing calendars with other principals.
    public var sharing: Bool
    /// Server supports CalDAV managed attachments (RFC 8607).
    public var managedAttachments: Bool

    public static let none = CalDAVCapabilities(
        scheduling: false,
        freeBusy: false,
        sharing: false,
        managedAttachments: false
    )

    public init(
        scheduling: Bool = false,
        freeBusy: Bool = false,
        sharing: Bool = false,
        managedAttachments: Bool = false
    ) {
        self.scheduling = scheduling
        self.freeBusy = freeBusy
        self.sharing = sharing
        self.managedAttachments = managedAttachments
    }
}
