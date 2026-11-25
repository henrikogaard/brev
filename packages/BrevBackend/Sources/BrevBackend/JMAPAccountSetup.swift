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

/// Built-in JMAP provider presets offered during provider-neutral account setup.
public enum JMAPServerPreset: String, CaseIterable, Identifiable, Sendable, Equatable {
    /// Fastmail's official JMAP session endpoint.
    case fastmail
    /// Any standards-compliant JMAP server (e.g. Stalwart, Cyrus, self-hosted).
    case custom

    /// Stable identifier for SwiftUI pickers.
    public var id: String { rawValue }

    /// Default HTTPS session URL for the preset, or empty for custom servers.
    public var defaultSessionURLString: String {
        switch self {
        case .fastmail:
            "https://api.fastmail.com/jmap/session"
        case .custom:
            ""
        }
    }
}

/// User-supplied credentials and server endpoint for adding or repairing a JMAP account.
public struct JMAPAccountSetupRequest: Sendable, Equatable {
    /// Account email address.
    public let emailAddress: String
    /// Optional user-visible display name (defaults to email address when blank).
    public let displayName: String
    /// HTTPS JMAP session URL or bare domain/host for `/.well-known/jmap` discovery.
    public let sessionURLString: String
    /// Bearer or API token stored strictly in Keychain (`TokenStore`).
    public let bearerToken: String

    /// Creates a JMAP account setup request.
    public init(
        emailAddress: String,
        displayName: String = "",
        sessionURLString: String,
        bearerToken: String
    ) {
        self.emailAddress = emailAddress
        self.displayName = displayName
        self.sessionURLString = sessionURLString
        self.bearerToken = bearerToken
    }
}

/// Validation failure reasons for JMAP endpoint URLs.
public enum JMAPURLValidationReason: Sendable, Equatable {
    /// The URL or host field was empty.
    case empty
    /// The value could not be parsed as a valid URL.
    case malformed
    /// A non-HTTPS scheme such as `http://` was supplied.
    case httpsRequired
    /// Embedded username or password credentials were present in the URL.
    case embeddedCredentialsForbidden
    /// The URL did not include a valid host name.
    case missingHost
}

/// Localized validation error thrown by `JMAPSetupURLValidator`.
public enum JMAPSetupURLValidationError: Error, LocalizedError, Sendable, Equatable {
    /// Endpoint failed strict HTTPS, host, or credential-free URL validation.
    case invalid(JMAPURLValidationReason)

    /// Localized user-facing validation message with zero secret material.
    public var errorDescription: String? {
        switch self {
        case .invalid(.empty):
            String(localized: "Enter a JMAP server URL or domain.", bundle: .module)
        case .invalid(.malformed):
            String(localized: "The JMAP server URL is not valid.", bundle: .module)
        case .invalid(.httpsRequired):
            String(localized: "JMAP server URLs must use https://.", bundle: .module)
        case .invalid(.embeddedCredentialsForbidden):
            String(
                localized: "Do not include credentials in the JMAP server URL. Use the API token field instead.",
                bundle: .module
            )
        case .invalid(.missingHost):
            String(localized: "The JMAP server URL must include a host name.", bundle: .module)
        }
    }
}

/// Provider-neutral strict HTTPS validator and RFC 8620 §2 well-known URL resolver for JMAP account setup.
public enum JMAPSetupURLValidator {
    /// Validates that `url` uses strict `https://`, has a non-empty host, and carries no embedded credentials.
    public static func validateHTTPSURL(_ url: URL) throws -> URL {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw JMAPSetupURLValidationError.invalid(.malformed)
        }
        guard components.scheme?.lowercased() == "https" else {
            throw JMAPSetupURLValidationError.invalid(.httpsRequired)
        }
        if components.user != nil || components.password != nil {
            throw JMAPSetupURLValidationError.invalid(.embeddedCredentialsForbidden)
        }
        guard let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty
        else {
            throw JMAPSetupURLValidationError.invalid(.missingHost)
        }
        guard let validated = components.url else {
            throw JMAPSetupURLValidationError.invalid(.malformed)
        }
        return validated
    }

    /// Resolves a user-entered JMAP session URL or bare domain/host into a strict HTTPS discovery URL.
    public static func discoveryURL(from rawInput: String) throws -> URL {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw JMAPSetupURLValidationError.invalid(.empty)
        }
        guard !trimmed.contains(where: \.isWhitespace) else {
            throw JMAPSetupURLValidationError.invalid(.malformed)
        }

        let candidateString: String
        if trimmed.contains("://") {
            candidateString = trimmed
        } else if trimmed.contains("@") {
            throw JMAPSetupURLValidationError.invalid(.embeddedCredentialsForbidden)
        } else if let colonIndex = trimmed.firstIndex(of: ":"),
                  !trimmed[..<colonIndex].contains("."),
                  Int(trimmed[trimmed.index(after: colonIndex)...].prefix(while: \.isNumber)) == nil {
            // Non-HTTPS scheme without `//`, e.g. `javascript:alert(1)` or `mailto:a@b`.
            throw JMAPSetupURLValidationError.invalid(.httpsRequired)
        } else {
            candidateString = "https://\(trimmed)"
        }

        guard var components = URLComponents(string: candidateString) else {
            throw JMAPSetupURLValidationError.invalid(.malformed)
        }
        guard components.scheme?.lowercased() == "https" else {
            throw JMAPSetupURLValidationError.invalid(.httpsRequired)
        }
        if components.user != nil || components.password != nil {
            throw JMAPSetupURLValidationError.invalid(.embeddedCredentialsForbidden)
        }
        guard let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty
        else {
            throw JMAPSetupURLValidationError.invalid(.missingHost)
        }
        if components.path.isEmpty || components.path == "/" {
            components.path = "/.well-known/jmap"
        }
        guard let url = components.url else {
            throw JMAPSetupURLValidationError.invalid(.malformed)
        }
        return try validateHTTPSURL(url)
    }
}
