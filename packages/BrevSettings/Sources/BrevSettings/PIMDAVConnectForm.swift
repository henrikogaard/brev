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

import BrevCalendar
import Foundation

/// A validated DAV connect request handed to the source coordinator.
public struct PIMDAVConnectRequest: Sendable, Equatable {
    public let kind: PIMSourceKind
    public let endpoint: PIMDAVEndpoint
    public let displayName: String
    public let credential: CalDAVCredential

    public init(
        kind: PIMSourceKind,
        endpoint: PIMDAVEndpoint,
        displayName: String,
        credential: CalDAVCredential
    ) {
        self.kind = kind
        self.endpoint = endpoint
        self.displayName = displayName
        self.credential = credential
    }
}

/// Editable state for the DAV source connect sheet (ADR-0072).
///
/// Pure value: the sheet binds fields, issues reports what is missing or
/// unsafe, and a valid form compiles to a connect request. Nothing here
/// performs I/O — the coordinator validates against the server.
public struct PIMDAVConnectForm: Sendable, Equatable {
    /// Which PIM domain the source serves.
    public enum SourceKind: String, Sendable, Hashable, CaseIterable {
        case calendar
        case contacts
        case tasks

        /// The matching PIM source kind.
        public var sourceKind: PIMSourceKind {
            switch self {
            case .calendar: return .calendar
            case .contacts: return .contacts
            case .tasks: return .tasks
            }
        }
    }

    /// How the endpoint is reached.
    public enum EndpointMode: String, Sendable, Hashable, CaseIterable {
        /// RFC 6764 well-known discovery against the address domain.
        case discover
        /// User-entered server URL.
        case manual
    }

    /// How the source authenticates.
    public enum CredentialMode: String, Sendable, Hashable, CaseIterable {
        /// Username plus an app-specific password (HTTP Basic over HTTPS).
        case appPassword
        /// OAuth2 Bearer token.
        case bearerToken
    }

    /// A single validation problem with a user-facing message.
    public enum Issue: String, Sendable, Hashable {
        case invalidEmailAddress
        case invalidServerURL
        case httpsRequired
        case usernameRequired
        case passwordRequired
        case tokenRequired

        /// Localized explanation shown under the offending field group.
        public var message: String {
            switch self {
            case .invalidEmailAddress:
                return String(
                    localized: "Enter an email address so Brev can discover the server.",
                    bundle: .module
                )
            case .invalidServerURL:
                return String(
                    localized: "Enter a valid server URL.",
                    bundle: .module
                )
            case .httpsRequired:
                return String(
                    localized: "DAV sources require HTTPS. Only local development servers may use HTTP.",
                    bundle: .module
                )
            case .usernameRequired:
                return String(localized: "Enter the account username.", bundle: .module)
            case .passwordRequired:
                return String(
                    localized: "Enter an app-specific password for this source.",
                    bundle: .module
                )
            case .tokenRequired:
                return String(localized: "Enter an access token.", bundle: .module)
            }
        }
    }

    public var kind: SourceKind = .calendar
    public var endpointMode: EndpointMode = .discover
    /// Email address for discovery, or the server URL for a manual endpoint.
    public var address = ""
    public var credentialMode: CredentialMode = .appPassword
    public var username = ""
    public var password = ""
    public var bearerToken = ""
    /// Optional display name; derived from the endpoint when left empty.
    public var displayName = ""

    public init() {}

    // MARK: - Validation

    /// Every currently violated rule, in display order.
    public var issues: [Issue] {
        var found: [Issue] = []
        switch endpointMode {
        case .discover:
            if !Self.isUsableEmailAddress(trimmedAddress) {
                found.append(.invalidEmailAddress)
            }
        case .manual:
            switch manualEndpointValidity {
            case .valid:
                break
            case .invalid:
                found.append(.invalidServerURL)
            case .insecureHTTP:
                found.append(.httpsRequired)
            }
        }
        switch credentialMode {
        case .appPassword:
            if trimmedUsername.isEmpty { found.append(.usernameRequired) }
            if trimmedPassword.isEmpty { found.append(.passwordRequired) }
        case .bearerToken:
            if trimmedToken.isEmpty { found.append(.tokenRequired) }
        }
        return found
    }

    /// Whether the form can be submitted.
    public var isValid: Bool { issues.isEmpty }

    /// Compiles the request for the coordinator, or nil while invalid.
    public func makeRequest() -> PIMDAVConnectRequest? {
        guard isValid,
              let endpoint = resolvedEndpoint(),
              let credential = resolvedCredential() else {
            return nil
        }
        return PIMDAVConnectRequest(
            kind: kind.sourceKind,
            endpoint: endpoint,
            displayName: resolvedDisplayName(),
            credential: credential
        )
    }

    /// The credential described by the form, or nil while its required
    /// fields are empty. Reconnect only needs the credential half.
    public func resolvedCredential() -> CalDAVCredential? {
        switch credentialMode {
        case .appPassword:
            guard !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else { return nil }
            return .basic(username: trimmedUsername, password: trimmedPassword)
        case .bearerToken:
            guard !trimmedToken.isEmpty else { return nil }
            return .bearer(token: trimmedToken)
        }
    }

    /// The name shown in the source list: the explicit display name, else
    /// the email address or endpoint host.
    public func resolvedDisplayName() -> String {
        let explicit = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }
        switch endpointMode {
        case .discover:
            return trimmedAddress
        case .manual:
            return manualURL?.host() ?? trimmedAddress
        }
    }

    // MARK: - Endpoint resolution

    private enum ManualEndpointValidity {
        case valid
        case invalid
        case insecureHTTP
    }

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPassword: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedToken: String {
        bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var manualURL: URL? {
        let raw = trimmedAddress
        guard !raw.isEmpty else { return nil }
        if let url = URL(string: raw), url.scheme != nil, url.host() != nil {
            return url
        }
        // No scheme entered — assume HTTPS rather than failing.
        if let url = URL(string: "https://" + raw), url.host() != nil {
            return url
        }
        return nil
    }

    private var manualEndpointValidity: ManualEndpointValidity {
        guard let url = manualURL else { return .invalid }
        switch url.scheme?.lowercased() {
        case "https":
            return .valid
        case "http":
            if let host = url.host(), Self.isLoopbackHost(host) {
                return .valid
            }
            return .insecureHTTP
        default:
            return .invalid
        }
    }

    private func resolvedEndpoint() -> PIMDAVEndpoint? {
        switch endpointMode {
        case .discover:
            guard Self.isUsableEmailAddress(trimmedAddress) else { return nil }
            return .discover(emailAddress: trimmedAddress)
        case .manual:
            guard manualEndpointValidity == .valid, let url = manualURL else { return nil }
            return .manual(url)
        }
    }

    private static func isUsableEmailAddress(_ address: String) -> Bool {
        guard let atIndex = address.firstIndex(of: "@") else { return false }
        let local = address[..<atIndex]
        let domain = address[address.index(after: atIndex)...]
        return !local.isEmpty && !domain.isEmpty && !domain.contains("@")
    }

    /// Loopback allowance mirrors the DAV client: HTTP stays available for
    /// local development servers only.
    private static func isLoopbackHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        return lower == "localhost"
            || lower == "127.0.0.1"
            || lower == "::1"
            || lower.hasSuffix(".localhost")
    }
}
