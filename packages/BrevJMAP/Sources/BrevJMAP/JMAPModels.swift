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

import BrevBackend
import Foundation

/// Standard JMAP capability URIs defined by RFC 8620 and RFC 8621.
public enum JMAPCapability {
    /// Core JMAP capability (`urn:ietf:params:jmap:core`).
    public static let core = "urn:ietf:params:jmap:core"
    /// JMAP Mail capability (`urn:ietf:params:jmap:mail`).
    public static let mail = "urn:ietf:params:jmap:mail"
    /// JMAP Mail Submission capability (`urn:ietf:params:jmap:submission`).
    public static let submission = "urn:ietf:params:jmap:submission"
    /// JMAP Vacation Response capability (`urn:ietf:params:jmap:vacationresponse`).
    public static let vacationResponse = "urn:ietf:params:jmap:vacationresponse"
    /// JMAP Sieve capability (`urn:ietf:params:jmap:sieve`).
    public static let sieve = "urn:ietf:params:jmap:sieve"
}

/// Built-in JMAP provider presets offered during account setup.
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

/// Non-secret metadata persisted for a configured JMAP account.
///
/// Bearer / API tokens are never stored here; they live exclusively in
/// `TokenStore` (Keychain).
public struct JMAPAccountConfiguration: Codable, Equatable, Hashable, Sendable {
    /// Stable Brev account identifier (`jmap:<normalized-email>`).
    public let accountID: String
    /// Account email address.
    public let emailAddress: String
    /// User-visible account display name.
    public let displayName: String
    /// Validated strict HTTPS JMAP session discovery URL.
    public let sessionURL: URL
    /// Discovered JMAP primary mail account identifier, if known.
    public let jmapAccountID: String?
    /// Discovered JMAP session username, if known.
    public let username: String?

    /// Creates non-secret JMAP account configuration metadata.
    public init(
        accountID: String,
        emailAddress: String,
        displayName: String,
        sessionURL: URL,
        jmapAccountID: String? = nil,
        username: String? = nil
    ) {
        self.accountID = accountID
        self.emailAddress = emailAddress
        self.displayName = displayName
        self.sessionURL = sessionURL
        self.jmapAccountID = jmapAccountID
        self.username = username
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

/// Redacts sensitive bearer tokens from untrusted error or server strings before display or storage.
public enum JMAPSecretRedactor {
    /// Replaces every non-empty secret value found in `text` with `[REDACTED]`.
    public static func redact(_ text: String, secrets: [String]) -> String {
        var result = text
        for secret in secrets {
            let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            result = result.replacingOccurrences(of: trimmed, with: "[REDACTED]")
        }
        return result
    }
}

/// Typed errors raised by JMAP discovery, HTTP transport, protocol methods, and provisioning.
public enum JMAPError: Error, LocalizedError, Sendable, Equatable {
    /// Session or endpoint URL failed strict HTTPS / host / credential validation.
    case invalidSessionURL(JMAPURLValidationReason)
    /// Server attempted to redirect a JMAP request to an insecure non-HTTPS or credential-bearing URL.
    case insecureRedirect
    /// Too many HTTP redirects occurred while contacting the JMAP server.
    case tooManyRedirects
    /// Authentication failed (HTTP 401 or missing/revoked bearer token).
    case authenticationRequired
    /// Server rejected the request due to insufficient permissions (HTTP 403).
    case forbidden
    /// Server rate-limited the client (HTTP 429).
    case rateLimited(retryAfter: TimeInterval?)
    /// Server returned an HTTP 5xx error.
    case serverError(statusCode: Int)
    /// Server returned an unexpected HTTP status code.
    case httpError(statusCode: Int)
    /// Underlying network transport failure.
    case networkFailure
    /// Server returned malformed or unreadable JMAP JSON.
    case invalidResponse
    /// Session resource did not advertise a primary JMAP mail account.
    case missingPrimaryMailAccount
    /// JMAP method invocation returned an RFC 8620 `error` response.
    case methodError(type: String, description: String?)
    /// Server returned `cannotCalculateChanges`, requiring a full state refresh.
    case cannotCalculateChanges
    /// Referenced mailbox, message, or blob could not be found.
    case notFound(id: String)
    /// Attachment or blob exceeded the server's advertised `maxSizeUpload`.
    case uploadTooLarge(limit: Int)
    /// Server reported no usable sending identity (`Identity/get`).
    case missingIdentity
    /// Account has no mailbox suitable for storing drafts.
    case missingDraftsMailbox
    /// Account has no mailbox suitable for storing sent messages.
    case missingSentMailbox
    /// Expanded `downloadUrl` template was invalid or non-HTTPS.
    case invalidDownloadURL
    /// Expanded `uploadUrl` template was invalid or non-HTTPS.
    case invalidUploadURL
    /// Saved JMAP account configuration was invalid or missing.
    case invalidConfiguration
    /// No bearer token is stored in Keychain for this account.
    case missingToken

    /// Localized user-facing error message with zero secret material.
    public var errorDescription: String? {
        switch self {
        case .invalidSessionURL(.empty):
            String(localized: "Enter a JMAP server URL or domain.", bundle: .module)
        case .invalidSessionURL(.malformed):
            String(localized: "The JMAP server URL is not valid.", bundle: .module)
        case .invalidSessionURL(.httpsRequired):
            String(localized: "JMAP server URLs must use https://.", bundle: .module)
        case .invalidSessionURL(.embeddedCredentialsForbidden):
            String(
                localized: "Do not include credentials in the JMAP server URL. Use the API token field instead.",
                bundle: .module
            )
        case .invalidSessionURL(.missingHost):
            String(localized: "The JMAP server URL must include a host name.", bundle: .module)
        case .insecureRedirect:
            String(localized: "The JMAP server redirected to an insecure address.", bundle: .module)
        case .tooManyRedirects:
            String(localized: "The JMAP server redirected too many times.", bundle: .module)
        case .authenticationRequired:
            String(localized: "JMAP sign-in failed or the API token was rejected.", bundle: .module)
        case .forbidden:
            String(localized: "The JMAP server denied access to this mailbox.", bundle: .module)
        case .rateLimited(let retryAfter):
            if let retryAfter {
                String(
                    localized: "The JMAP server rate-limited requests. Try again in \(Int(retryAfter.rounded())) seconds.",
                    bundle: .module
                )
            } else {
                String(localized: "The JMAP server rate-limited requests. Try again later.", bundle: .module)
            }
        case .serverError(let statusCode):
            String(localized: "The JMAP server is temporarily unavailable (HTTP \(statusCode)).", bundle: .module)
        case .httpError(let statusCode):
            String(localized: "The JMAP server rejected the request (HTTP \(statusCode)).", bundle: .module)
        case .networkFailure:
            String(localized: "Brev could not reach the JMAP server.", bundle: .module)
        case .invalidResponse:
            String(localized: "The JMAP server returned a response Brev could not read.", bundle: .module)
        case .missingPrimaryMailAccount:
            String(localized: "The JMAP server did not advertise a primary mail account.", bundle: .module)
        case .methodError(let type, _):
            String(localized: "The JMAP server reported an error (\(type)).", bundle: .module)
        case .cannotCalculateChanges:
            String(localized: "The JMAP mailbox needs a full refresh.", bundle: .module)
        case .notFound:
            String(localized: "The requested JMAP item could not be found.", bundle: .module)
        case .uploadTooLarge(let limit):
            String(localized: "The attachment exceeds the JMAP server upload limit (\(limit) bytes).", bundle: .module)
        case .missingIdentity:
            String(localized: "No sending identity is available on this JMAP account.", bundle: .module)
        case .missingDraftsMailbox:
            String(localized: "Could not find a Drafts folder on this JMAP account.", bundle: .module)
        case .missingSentMailbox:
            String(localized: "Could not find a Sent folder on this JMAP account.", bundle: .module)
        case .invalidDownloadURL:
            String(localized: "The JMAP server advertised an invalid download address.", bundle: .module)
        case .invalidUploadURL:
            String(localized: "The JMAP server advertised an invalid upload address.", bundle: .module)
        case .invalidConfiguration:
            String(localized: "Saved JMAP account settings are incomplete or invalid.", bundle: .module)
        case .missingToken:
            String(localized: "JMAP API token is unavailable in Keychain.", bundle: .module)
        }
    }

    /// Converts a JMAP error into the provider-neutral `MailBackendError` contract.
    public func asMailBackendError() -> MailBackendError {
        switch self {
        case .authenticationRequired, .missingToken:
            .authenticationRequired
        case .forbidden:
            .permissionDenied(message: localizedDescription)
        case .rateLimited(let retryAfter):
            .rateLimited(retryAfter: retryAfter)
        case .notFound(let id):
            .notFound(id: id)
        case .networkFailure, .serverError:
            .network(underlying: localizedDescription)
        case .uploadTooLarge:
            .quotaExceeded
        default:
            .backendSpecific(message: localizedDescription)
        }
    }
}

// MARK: - Dynamic JSON Value

/// Type-safe, `Sendable` JSON value used in JMAP method arguments, capabilities, and `#resultRef` patches.
public enum JMAPJSONValue: Codable, Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JMAPJSONValue])
    case object([String: JMAPJSONValue])

    /// Decodes any JSON primitive, array, or object.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JMAPJSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JMAPJSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    /// Encodes the wrapped JSON value.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    /// Extracts an underlying string if this value is `.string`.
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Extracts an underlying integer if this value is `.int`.
    public var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    /// Extracts an underlying dictionary if this value is `.object`.
    public var objectValue: [String: JMAPJSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Encodes a strongly typed `Encodable` value into a `JMAPJSONValue`.
    public static func from<T: Encodable>(_ value: T) throws -> JMAPJSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JMAPJSONValue.self, from: data)
    }

    /// Decodes this JSON value into a strongly typed `Decodable` model.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(type, from: data)
    }
}

// MARK: - RFC 8620 Session & Transport Envelopes

/// Account metadata advertised inside a JMAP Session resource (RFC 8620 §2).
public struct JMAPAccountInfo: Codable, Equatable, Sendable {
    /// Human-readable account name.
    public let name: String
    /// Whether this account belongs to the authenticated user personally.
    public let isPersonal: Bool
    /// Whether this account is read-only.
    public let isReadOnly: Bool
    /// Per-account capability payloads keyed by capability URI.
    public let accountCapabilities: [String: JMAPJSONValue]

    /// Creates a JMAP account descriptor.
    public init(
        name: String,
        isPersonal: Bool = true,
        isReadOnly: Bool = false,
        accountCapabilities: [String: JMAPJSONValue] = [:]
    ) {
        self.name = name
        self.isPersonal = isPersonal
        self.isReadOnly = isReadOnly
        self.accountCapabilities = accountCapabilities
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case isPersonal
        case isReadOnly
        case accountCapabilities
    }

    /// Decodes a JMAP account descriptor with safe defaults for omitted optional flags.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        isPersonal = try container.decodeIfPresent(Bool.self, forKey: .isPersonal) ?? true
        isReadOnly = try container.decodeIfPresent(Bool.self, forKey: .isReadOnly) ?? false
        accountCapabilities = try container.decodeIfPresent([String: JMAPJSONValue].self, forKey: .accountCapabilities) ?? [:]
    }
}

/// Typed JMAP Session resource returned by RFC 8620 §2 discovery.
public struct JMAPSession: Codable, Equatable, Sendable {
    /// Server-level capabilities keyed by URI.
    public let capabilities: [String: JMAPJSONValue]
    /// Accounts accessible to the authenticated user.
    public let accounts: [String: JMAPAccountInfo]
    /// Primary account identifier per capability URI.
    public let primaryAccounts: [String: String]
    /// Authenticated username associated with the session.
    public let username: String
    /// HTTPS endpoint for batched JMAP API requests.
    public let apiUrl: URL
    /// RFC 6570 URI template for blob downloads (`{accountId}`, `{blobId}`, `{name}`, `{type}`).
    public let downloadUrl: String
    /// RFC 6570 URI template for blob uploads (`{accountId}`).
    public let uploadUrl: String
    /// Optional RFC 6570 URI template for RFC 8620 §7.3 Server-Sent Events (`EventSource`).
    public let eventSourceUrl: String?
    /// Opaque session state string.
    public let state: String

    /// Creates a JMAP session value.
    public init(
        capabilities: [String: JMAPJSONValue] = [:],
        accounts: [String: JMAPAccountInfo] = [:],
        primaryAccounts: [String: String] = [:],
        username: String,
        apiUrl: URL,
        downloadUrl: String,
        uploadUrl: String,
        eventSourceUrl: String? = nil,
        state: String
    ) {
        self.capabilities = capabilities
        self.accounts = accounts
        self.primaryAccounts = primaryAccounts
        self.username = username
        self.apiUrl = apiUrl
        self.downloadUrl = downloadUrl
        self.uploadUrl = uploadUrl
        self.eventSourceUrl = eventSourceUrl
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case capabilities
        case accounts
        case primaryAccounts
        case username
        case apiUrl
        case downloadUrl
        case uploadUrl
        case eventSourceUrl
        case state
    }

    /// Decodes a JMAP Session resource from JSON.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        capabilities = try container.decodeIfPresent([String: JMAPJSONValue].self, forKey: .capabilities) ?? [:]
        accounts = try container.decodeIfPresent([String: JMAPAccountInfo].self, forKey: .accounts) ?? [:]
        primaryAccounts = try container.decodeIfPresent([String: String].self, forKey: .primaryAccounts) ?? [:]
        username = try container.decode(String.self, forKey: .username)
        let apiURLString = try container.decode(String.self, forKey: .apiUrl)
        guard let parsedAPIURL = URL(string: apiURLString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .apiUrl,
                in: container,
                debugDescription: "Invalid apiUrl"
            )
        }
        apiUrl = parsedAPIURL
        downloadUrl = try container.decode(String.self, forKey: .downloadUrl)
        uploadUrl = try container.decode(String.self, forKey: .uploadUrl)
        eventSourceUrl = try container.decodeIfPresent(String.self, forKey: .eventSourceUrl)
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
    }

    /// Primary account ID for `urn:ietf:params:jmap:mail`, falling back to the first personal mail account if omitted.
    public var primaryMailAccountID: String? {
        if let primary = primaryAccounts[JMAPCapability.mail], !primary.isEmpty {
            return primary
        }
        if let mailAccount = accounts.first(where: { $0.value.accountCapabilities[JMAPCapability.mail] != nil }) {
            return mailAccount.key
        }
        return accounts.keys.sorted().first
    }

    /// Whether the session advertises `urn:ietf:params:jmap:mail`.
    public var supportsMail: Bool {
        capabilities[JMAPCapability.mail] != nil || primaryAccounts[JMAPCapability.mail] != nil
    }

    /// Whether the session advertises `urn:ietf:params:jmap:submission`.
    public var supportsSubmission: Bool {
        capabilities[JMAPCapability.submission] != nil || primaryAccounts[JMAPCapability.submission] != nil
    }

    /// Maximum single-blob upload size in bytes advertised in core capabilities, if present.
    public var maxSizeUpload: Int? {
        capabilities[JMAPCapability.core]?.objectValue?["maxSizeUpload"]?.intValue
    }

    /// Maximum method calls per request advertised in core capabilities, if present.
    public var maxCallsInRequest: Int? {
        capabilities[JMAPCapability.core]?.objectValue?["maxCallsInRequest"]?.intValue
    }

    /// Maximum objects per `*/get` call advertised in core capabilities, if present.
    public var maxObjectsInGet: Int? {
        capabilities[JMAPCapability.core]?.objectValue?["maxObjectsInGet"]?.intValue
    }
}

/// RFC 8620 §3.7 back-reference (`#property`) linking one batched method call's argument to an earlier call's result.
public struct JMAPResultReference: Codable, Equatable, Sendable {
    /// The `callID` of the earlier method invocation in the same batch.
    public let resultOf: String
    /// The method name of the earlier invocation (e.g. `"Email/query"`).
    public let name: String
    /// JSON Pointer path into the earlier invocation's response arguments (e.g. `"/ids"`).
    public let path: String

    /// Creates a JMAP result reference.
    public init(resultOf: String, name: String, path: String) {
        self.resultOf = resultOf
        self.name = name
        self.path = path
    }

    /// Converts this reference into a `JMAPJSONValue` object suitable for a `#`-prefixed argument.
    public var jsonValue: JMAPJSONValue {
        .object([
            "resultOf": .string(resultOf),
            "name": .string(name),
            "path": .string(path)
        ])
    }
}

/// Single JMAP method invocation encoded as the RFC 8620 §3.2 3-tuple `[name, arguments, callId]`.
public struct JMAPInvocation: Codable, Equatable, Sendable {
    /// JMAP method name (e.g. `"Email/query"`, `"Email/get"`, or `"error"`).
    public let name: String
    /// JSON object carrying method arguments or response fields.
    public let arguments: [String: JMAPJSONValue]
    /// Client-assigned correlation identifier matched between request and response.
    public let callID: String

    /// Creates a JMAP method invocation.
    public init(name: String, arguments: [String: JMAPJSONValue], callID: String) {
        self.name = name
        self.arguments = arguments
        self.callID = callID
    }

    /// Decodes a 3-element JSON array `[name, arguments, callId]`.
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        name = try container.decode(String.self)
        arguments = try container.decode([String: JMAPJSONValue].self)
        callID = try container.decode(String.self)
    }

    /// Encodes a 3-element JSON array `[name, arguments, callId]`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(name)
        try container.encode(arguments)
        try container.encode(callID)
    }

    /// Decodes `arguments` into a typed response struct.
    public func decodeArguments<T: Decodable>(_ type: T.Type) throws -> T {
        try JMAPJSONValue.object(arguments).decode(type)
    }
}

/// RFC 8620 §3.3 JMAP API request envelope.
public struct JMAPRequest: Codable, Equatable, Sendable {
    /// Capability URIs used by the method calls in this batch.
    public let using: [String]
    /// Ordered list of JMAP method invocations.
    public let methodCalls: [JMAPInvocation]
    /// Optional client-to-server creation ID map.
    public let createdIds: [String: String]?

    /// Creates a batched JMAP API request.
    public init(
        using: [String],
        methodCalls: [JMAPInvocation],
        createdIds: [String: String]? = nil
    ) {
        self.using = using
        self.methodCalls = methodCalls
        self.createdIds = createdIds
    }
}

/// RFC 8620 §3.4 JMAP API response envelope.
public struct JMAPResponse: Codable, Equatable, Sendable {
    /// Ordered list of method response tuples.
    public let methodResponses: [JMAPInvocation]
    /// Current session state token reported by the server.
    public let sessionState: String
    /// Optional map of client creation IDs to server-assigned IDs.
    public let createdIds: [String: String]?

    /// Creates a JMAP API response.
    public init(
        methodResponses: [JMAPInvocation],
        sessionState: String,
        createdIds: [String: String]? = nil
    ) {
        self.methodResponses = methodResponses
        self.sessionState = sessionState
        self.createdIds = createdIds
    }

    /// Returns the first method response matching `callID`, throwing a typed `JMAPError` if it is an `"error"` tuple.
    public func response(forCallID callID: String) throws -> JMAPInvocation {
        guard let invocation = methodResponses.first(where: { $0.callID == callID }) else {
            throw JMAPError.invalidResponse
        }
        if invocation.name == "error" {
            let type = invocation.arguments["type"]?.stringValue ?? "unknown"
            let description = invocation.arguments["description"]?.stringValue
            if type == "cannotCalculateChanges" {
                throw JMAPError.cannotCalculateChanges
            }
            throw JMAPError.methodError(type: type, description: description)
        }
        return invocation
    }
}

// MARK: - RFC 8621 Mail Objects

/// RFC 8621 §2 `Mailbox` object.
public struct JMAPMailbox: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let parentId: String?
    public let role: String?
    public let sortOrder: Int
    public let totalEmails: Int
    public let unreadEmails: Int
    public let totalThreads: Int
    public let unreadThreads: Int
    public let isSubscribed: Bool

    /// Creates a JMAP mailbox DTO.
    public init(
        id: String,
        name: String,
        parentId: String? = nil,
        role: String? = nil,
        sortOrder: Int = 0,
        totalEmails: Int = 0,
        unreadEmails: Int = 0,
        totalThreads: Int = 0,
        unreadThreads: Int = 0,
        isSubscribed: Bool = true
    ) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.role = role
        self.sortOrder = sortOrder
        self.totalEmails = totalEmails
        self.unreadEmails = unreadEmails
        self.totalThreads = totalThreads
        self.unreadThreads = unreadThreads
        self.isSubscribed = isSubscribed
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, parentId, role, sortOrder, totalEmails, unreadEmails, totalThreads, unreadThreads, isSubscribed
    }

    /// Decodes a JMAP mailbox with safe defaults for omitted count fields.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        totalEmails = try container.decodeIfPresent(Int.self, forKey: .totalEmails) ?? 0
        unreadEmails = try container.decodeIfPresent(Int.self, forKey: .unreadEmails) ?? 0
        totalThreads = try container.decodeIfPresent(Int.self, forKey: .totalThreads) ?? 0
        unreadThreads = try container.decodeIfPresent(Int.self, forKey: .unreadThreads) ?? 0
        isSubscribed = try container.decodeIfPresent(Bool.self, forKey: .isSubscribed) ?? true
    }

    /// Maps RFC 8621 §2 mailbox role strings onto Brev's `FolderRole`.
    public var folderRole: FolderRole {
        switch role?.lowercased() {
        case "inbox":
            .inbox
        case "sent":
            .sent
        case "drafts":
            .drafts
        case "trash":
            .trash
        case "junk", "spam":
            .spam
        case "archive":
            .archive
        case "important", "flagged":
            .starred
        case "all":
            .allMail
        case "snoozed":
            .snoozed
        case "scheduled":
            .scheduled
        default:
            .custom
        }
    }

    /// Converts this JMAP mailbox into a provider-neutral `Folder`.
    public func toFolder() -> Folder {
        Folder(
            id: id,
            name: name,
            role: folderRole,
            parentID: parentId,
            unreadCount: unreadEmails,
            totalCount: totalEmails
        )
    }
}

/// RFC 8621 §4.1.2.3 `EmailAddress` object.
public struct JMAPEmailAddress: Codable, Equatable, Sendable {
    public let name: String?
    public let email: String

    /// Creates a JMAP email address.
    public init(name: String? = nil, email: String) {
        self.name = name
        self.email = email
    }

    /// Converts to Brev's `Correspondent`.
    public func toCorrespondent() -> Correspondent {
        Correspondent(name: name, email: email)
    }

    /// Converts from Brev's `Correspondent`.
    public static func from(_ correspondent: Correspondent) -> JMAPEmailAddress {
        JMAPEmailAddress(name: correspondent.name, email: correspondent.email)
    }
}

/// RFC 8621 §4.1.2.2 `EmailHeader` object.
public struct JMAPEmailHeader: Codable, Equatable, Sendable {
    public let name: String
    public let value: String

    /// Creates a raw header pair.
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// RFC 8621 §4.1.4 `EmailBodyPart` object.
public struct JMAPEmailBodyPart: Codable, Equatable, Sendable {
    public let partId: String?
    public let blobId: String?
    public let size: Int
    public let name: String?
    public let type: String
    public let charset: String?
    public let disposition: String?
    public let cid: String?
    public let subParts: [JMAPEmailBodyPart]?

    /// Creates a JMAP MIME body part descriptor.
    public init(
        partId: String? = nil,
        blobId: String? = nil,
        size: Int = 0,
        name: String? = nil,
        type: String = "application/octet-stream",
        charset: String? = nil,
        disposition: String? = nil,
        cid: String? = nil,
        subParts: [JMAPEmailBodyPart]? = nil
    ) {
        self.partId = partId
        self.blobId = blobId
        self.size = size
        self.name = name
        self.type = type
        self.charset = charset
        self.disposition = disposition
        self.cid = cid
        self.subParts = subParts
    }

    private enum CodingKeys: String, CodingKey {
        case partId, blobId, size, name, type, charset, disposition, cid, subParts
    }

    /// Decodes a body part with safe defaults.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        partId = try container.decodeIfPresent(String.self, forKey: .partId)
        blobId = try container.decodeIfPresent(String.self, forKey: .blobId)
        size = try container.decodeIfPresent(Int.self, forKey: .size) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "application/octet-stream"
        charset = try container.decodeIfPresent(String.self, forKey: .charset)
        disposition = try container.decodeIfPresent(String.self, forKey: .disposition)
        cid = try container.decodeIfPresent(String.self, forKey: .cid)
        subParts = try container.decodeIfPresent([JMAPEmailBodyPart].self, forKey: .subParts)
    }
}

/// RFC 8621 §4.1.4 `EmailBodyValue` object.
public struct JMAPEmailBodyValue: Codable, Equatable, Sendable {
    public let value: String
    public let isEncodingProblem: Bool
    public let isTruncated: Bool

    /// Creates a JMAP body value payload.
    public init(value: String, isEncodingProblem: Bool = false, isTruncated: Bool = false) {
        self.value = value
        self.isEncodingProblem = isEncodingProblem
        self.isTruncated = isTruncated
    }

    private enum CodingKeys: String, CodingKey {
        case value, isEncodingProblem, isTruncated
    }

    /// Decodes a body value with defaults for optional flags.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        isEncodingProblem = try container.decodeIfPresent(Bool.self, forKey: .isEncodingProblem) ?? false
        isTruncated = try container.decodeIfPresent(Bool.self, forKey: .isTruncated) ?? false
    }
}

/// RFC 8621 §4.1 `Email` object covering both listing metadata and full body fetches.
public struct JMAPEmail: Codable, Equatable, Sendable {
    public let id: String
    public let blobId: String?
    public let threadId: String?
    public let mailboxIds: [String: Bool]
    public let keywords: [String: Bool]
    public let size: Int
    public let receivedAt: String?
    public let sentAt: String?
    public let messageId: [String]?
    public let inReplyTo: [String]?
    public let references: [String]?
    public let from: [JMAPEmailAddress]?
    public let to: [JMAPEmailAddress]?
    public let cc: [JMAPEmailAddress]?
    public let bcc: [JMAPEmailAddress]?
    public let replyTo: [JMAPEmailAddress]?
    public let subject: String?
    public let hasAttachment: Bool
    public let preview: String?
    public let bodyStructure: JMAPEmailBodyPart?
    public let bodyValues: [String: JMAPEmailBodyValue]?
    public let textBody: [JMAPEmailBodyPart]?
    public let htmlBody: [JMAPEmailBodyPart]?
    public let attachments: [JMAPEmailBodyPart]?
    public let headers: [JMAPEmailHeader]?

    /// Creates a JMAP email DTO.
    public init(
        id: String,
        blobId: String? = nil,
        threadId: String? = nil,
        mailboxIds: [String: Bool] = [:],
        keywords: [String: Bool] = [:],
        size: Int = 0,
        receivedAt: String? = nil,
        sentAt: String? = nil,
        messageId: [String]? = nil,
        inReplyTo: [String]? = nil,
        references: [String]? = nil,
        from: [JMAPEmailAddress]? = nil,
        to: [JMAPEmailAddress]? = nil,
        cc: [JMAPEmailAddress]? = nil,
        bcc: [JMAPEmailAddress]? = nil,
        replyTo: [JMAPEmailAddress]? = nil,
        subject: String? = nil,
        hasAttachment: Bool = false,
        preview: String? = nil,
        bodyStructure: JMAPEmailBodyPart? = nil,
        bodyValues: [String: JMAPEmailBodyValue]? = nil,
        textBody: [JMAPEmailBodyPart]? = nil,
        htmlBody: [JMAPEmailBodyPart]? = nil,
        attachments: [JMAPEmailBodyPart]? = nil,
        headers: [JMAPEmailHeader]? = nil
    ) {
        self.id = id
        self.blobId = blobId
        self.threadId = threadId
        self.mailboxIds = mailboxIds
        self.keywords = keywords
        self.size = size
        self.receivedAt = receivedAt
        self.sentAt = sentAt
        self.messageId = messageId
        self.inReplyTo = inReplyTo
        self.references = references
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.replyTo = replyTo
        self.subject = subject
        self.hasAttachment = hasAttachment
        self.preview = preview
        self.bodyStructure = bodyStructure
        self.bodyValues = bodyValues
        self.textBody = textBody
        self.htmlBody = htmlBody
        self.attachments = attachments
        self.headers = headers
    }

    private enum CodingKeys: String, CodingKey {
        case id, blobId, threadId, mailboxIds, keywords, size, receivedAt, sentAt
        case messageId, inReplyTo, references, from, to, cc, bcc, replyTo
        case subject, hasAttachment, preview, bodyStructure, bodyValues
        case textBody, htmlBody, attachments, headers
    }

    /// Decodes a JMAP email with safe defaults for omitted fields.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        blobId = try container.decodeIfPresent(String.self, forKey: .blobId)
        threadId = try container.decodeIfPresent(String.self, forKey: .threadId)
        mailboxIds = try container.decodeIfPresent([String: Bool].self, forKey: .mailboxIds) ?? [:]
        keywords = try container.decodeIfPresent([String: Bool].self, forKey: .keywords) ?? [:]
        size = try container.decodeIfPresent(Int.self, forKey: .size) ?? 0
        receivedAt = try container.decodeIfPresent(String.self, forKey: .receivedAt)
        sentAt = try container.decodeIfPresent(String.self, forKey: .sentAt)
        messageId = try container.decodeIfPresent([String].self, forKey: .messageId)
        inReplyTo = try container.decodeIfPresent([String].self, forKey: .inReplyTo)
        references = try container.decodeIfPresent([String].self, forKey: .references)
        from = try container.decodeIfPresent([JMAPEmailAddress].self, forKey: .from)
        to = try container.decodeIfPresent([JMAPEmailAddress].self, forKey: .to)
        cc = try container.decodeIfPresent([JMAPEmailAddress].self, forKey: .cc)
        bcc = try container.decodeIfPresent([JMAPEmailAddress].self, forKey: .bcc)
        replyTo = try container.decodeIfPresent([JMAPEmailAddress].self, forKey: .replyTo)
        subject = try container.decodeIfPresent(String.self, forKey: .subject)
        hasAttachment = try container.decodeIfPresent(Bool.self, forKey: .hasAttachment) ?? false
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
        bodyStructure = try container.decodeIfPresent(JMAPEmailBodyPart.self, forKey: .bodyStructure)
        bodyValues = try container.decodeIfPresent([String: JMAPEmailBodyValue].self, forKey: .bodyValues)
        textBody = try container.decodeIfPresent([JMAPEmailBodyPart].self, forKey: .textBody)
        htmlBody = try container.decodeIfPresent([JMAPEmailBodyPart].self, forKey: .htmlBody)
        attachments = try container.decodeIfPresent([JMAPEmailBodyPart].self, forKey: .attachments)
        headers = try container.decodeIfPresent([JMAPEmailHeader].self, forKey: .headers)
    }

    /// Converts this JMAP email into Brev's `MessageHeader` for `folderID`.
    public func toMessageHeader(folderID: String) -> MessageHeader {
        let activeKeywords = keywords.compactMap { $0.value ? $0.key : nil }
        let keywordSet = Set(activeKeywords)
        let receivedDate = receivedAt.flatMap(JMAPDateCoding.parse)
        let sentDate = sentAt.flatMap(JMAPDateCoding.parse)
        let displayDate = sentDate ?? receivedDate ?? Date(timeIntervalSince1970: 0)
        let sender = from?.first?.toCorrespondent() ?? Correspondent(name: nil, email: "")
        let isFlagged = keywordSet.contains("$flagged")
        let flagColor = isFlagged ? AppleFlagKeyword.flagColor(from: activeKeywords) : nil

        return MessageHeader(
            id: id,
            threadID: threadId ?? id,
            folderID: folderID,
            from: sender,
            replyTo: (replyTo ?? []).map { $0.toCorrespondent() },
            to: (to ?? []).map { $0.toCorrespondent() },
            cc: (cc ?? []).map { $0.toCorrespondent() },
            bcc: (bcc ?? []).map { $0.toCorrespondent() },
            subject: subject ?? "",
            snippet: preview ?? "",
            date: displayDate,
            internalDate: receivedDate,
            isRead: keywordSet.contains("$seen"),
            isFlagged: isFlagged,
            isAnswered: keywordSet.contains("$answered"),
            isForwarded: keywordSet.contains("$forwarded"),
            hasAttachments: hasAttachment,
            flagColor: flagColor,
            messageID: messageId?.first,
            inReplyTo: inReplyTo?.first,
            references: references
        )
    }

    /// Converts this JMAP email (fetched with body values and headers) into Brev's `MessageBody`.
    public func toMessageBody() -> MessageBody {
        let values = bodyValues ?? [:]
        let textParts = (textBody ?? []).compactMap { part -> String? in
            guard let partId = part.partId, let text = values[partId]?.value, !text.isEmpty else { return nil }
            return text
        }
        let htmlParts = (htmlBody ?? []).compactMap { part -> String? in
            guard let partId = part.partId, let html = values[partId]?.value, !html.isEmpty else { return nil }
            return html
        }

        let plainText = textParts.isEmpty ? nil : textParts.joined(separator: "\n\n")
        let html = htmlParts.isEmpty ? nil : htmlParts.joined(separator: "\n")

        var mappedAttachments: [Attachment] = []
        var seenAttachmentKeys: Set<String> = []
        let bodyPartSources = (attachments ?? []) + Self.inlineParts(from: bodyStructure)
        for part in bodyPartSources {
            guard let blobId = part.blobId, !blobId.isEmpty else { continue }
            let cleanCID = part.cid?.trimmingCharacters(in: CharacterSet(charactersIn: "<> \t\r\n"))
            let isInline = (part.disposition?.lowercased() == "inline") || (cleanCID?.isEmpty == false)
            let partKey = "\(blobId)|\(part.partId ?? "")|\(cleanCID ?? "")"
            guard seenAttachmentKeys.insert(partKey).inserted else { continue }
            let fallbackName = part.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (fallbackName?.isEmpty == false) ? fallbackName! : "attachment"
            mappedAttachments.append(
                Attachment(
                    id: part.partId ?? blobId,
                    name: displayName,
                    mimeType: part.type,
                    sizeBytes: part.size,
                    isInline: isInline,
                    contentID: cleanCID?.isEmpty == false ? cleanCID : nil,
                    resource: blobId
                )
            )
        }

        let headerLookup: (String) -> String? = { target in
            headers?.first(where: { $0.name.caseInsensitiveCompare(target) == .orderedSame })?.value
        }
        let parsedUnsubscribe = ListUnsubscribeOptions.parse(
            listUnsubscribe: headerLookup("List-Unsubscribe"),
            listUnsubscribePost: headerLookup("List-Unsubscribe-Post")
        )
        let listUnsubscribe: ListUnsubscribeOptions? = parsedUnsubscribe.methods.isEmpty ? nil : parsedUnsubscribe
        let isBulk = ListUnsubscribeOptions.isBulkPrecedence(
            precedence: headerLookup("Precedence"),
            autoSubmitted: headerLookup("Auto-Submitted")
        )
        let readReceiptTarget = headerLookup("Disposition-Notification-To")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let readReceiptRequest = readReceiptTarget.flatMap { $0.isEmpty ? nil : ReadReceiptRequest(notificationTo: $0) }
        let authResults = headerLookup("Authentication-Results")

        return MessageBody(
            messageID: id,
            html: html,
            plainText: plainText,
            attachments: mappedAttachments,
            listUnsubscribe: listUnsubscribe,
            isBulkPrecedence: isBulk,
            readReceiptRequest: readReceiptRequest,
            authenticationResults: authResults
        )
    }

    private static func inlineParts(from root: JMAPEmailBodyPart?) -> [JMAPEmailBodyPart] {
        guard let root else { return [] }
        var collected: [JMAPEmailBodyPart] = []
        if let cid = root.cid, !cid.isEmpty, root.blobId != nil {
            collected.append(root)
        }
        for child in root.subParts ?? [] {
            collected.append(contentsOf: inlineParts(from: child))
        }
        return collected
    }
}

/// RFC 8621 §6 `Identity` object.
public struct JMAPIdentity: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let email: String
    public let replyTo: [JMAPEmailAddress]?
    public let bcc: [JMAPEmailAddress]?
    public let textSignature: String
    public let htmlSignature: String
    public let mayDelete: Bool

    /// Creates a JMAP sending identity.
    public init(
        id: String,
        name: String = "",
        email: String,
        replyTo: [JMAPEmailAddress]? = nil,
        bcc: [JMAPEmailAddress]? = nil,
        textSignature: String = "",
        htmlSignature: String = "",
        mayDelete: Bool = true
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.replyTo = replyTo
        self.bcc = bcc
        self.textSignature = textSignature
        self.htmlSignature = htmlSignature
        self.mayDelete = mayDelete
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, email, replyTo, bcc, textSignature, htmlSignature, mayDelete
    }

    /// Decodes a JMAP identity with safe defaults.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try container.decode(String.self, forKey: .email)
        replyTo = try container.decodeIfPresent([JMAPEmailAddress].self, forKey: .replyTo)
        bcc = try container.decodeIfPresent([JMAPEmailAddress].self, forKey: .bcc)
        textSignature = try container.decodeIfPresent(String.self, forKey: .textSignature) ?? ""
        htmlSignature = try container.decodeIfPresent(String.self, forKey: .htmlSignature) ?? ""
        mayDelete = try container.decodeIfPresent(Bool.self, forKey: .mayDelete) ?? true
    }
}

// MARK: - Method Response Payloads

/// Generic `*/get` response payload (RFC 8620 §5.1).
public struct JMAPGetResponse<Object: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public let accountId: String
    public let state: String
    public let list: [Object]
    public let notFound: [String]

    /// Creates a `*/get` response payload.
    public init(accountId: String, state: String, list: [Object], notFound: [String] = []) {
        self.accountId = accountId
        self.state = state
        self.list = list
        self.notFound = notFound
    }

    private enum CodingKeys: String, CodingKey {
        case accountId, state, list, notFound
    }

    /// Decodes a `*/get` response with default empty `notFound`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try container.decode(String.self, forKey: .accountId)
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
        list = try container.decodeIfPresent([Object].self, forKey: .list) ?? []
        notFound = try container.decodeIfPresent([String].self, forKey: .notFound) ?? []
    }
}

/// Generic `*/changes` response payload (RFC 8620 §5.2).
public struct JMAPChangesResponse: Codable, Equatable, Sendable {
    public let accountId: String
    public let oldState: String
    public let newState: String
    public let hasMoreChanges: Bool
    public let created: [String]
    public let updated: [String]
    public let destroyed: [String]

    /// Creates a `*/changes` response payload.
    public init(
        accountId: String,
        oldState: String,
        newState: String,
        hasMoreChanges: Bool = false,
        created: [String] = [],
        updated: [String] = [],
        destroyed: [String] = []
    ) {
        self.accountId = accountId
        self.oldState = oldState
        self.newState = newState
        self.hasMoreChanges = hasMoreChanges
        self.created = created
        self.updated = updated
        self.destroyed = destroyed
    }

    private enum CodingKeys: String, CodingKey {
        case accountId, oldState, newState, hasMoreChanges, created, updated, destroyed
    }

    /// Decodes a `*/changes` response with safe defaults.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try container.decode(String.self, forKey: .accountId)
        oldState = try container.decodeIfPresent(String.self, forKey: .oldState) ?? ""
        newState = try container.decode(String.self, forKey: .newState)
        hasMoreChanges = try container.decodeIfPresent(Bool.self, forKey: .hasMoreChanges) ?? false
        created = try container.decodeIfPresent([String].self, forKey: .created) ?? []
        updated = try container.decodeIfPresent([String].self, forKey: .updated) ?? []
        destroyed = try container.decodeIfPresent([String].self, forKey: .destroyed) ?? []
    }
}

/// Generic `*/query` response payload (RFC 8620 §5.5).
public struct JMAPQueryResponse: Codable, Equatable, Sendable {
    public let accountId: String
    public let queryState: String
    public let canCalculateChanges: Bool
    public let position: Int
    public let ids: [String]
    public let total: Int?

    /// Creates a `*/query` response payload.
    public init(
        accountId: String,
        queryState: String = "",
        canCalculateChanges: Bool = false,
        position: Int = 0,
        ids: [String],
        total: Int? = nil
    ) {
        self.accountId = accountId
        self.queryState = queryState
        self.canCalculateChanges = canCalculateChanges
        self.position = position
        self.ids = ids
        self.total = total
    }

    private enum CodingKeys: String, CodingKey {
        case accountId, queryState, canCalculateChanges, position, ids, total
    }

    /// Decodes a `*/query` response with safe defaults.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try container.decode(String.self, forKey: .accountId)
        queryState = try container.decodeIfPresent(String.self, forKey: .queryState) ?? ""
        canCalculateChanges = try container.decodeIfPresent(Bool.self, forKey: .canCalculateChanges) ?? false
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
        ids = try container.decodeIfPresent([String].self, forKey: .ids) ?? []
        total = try container.decodeIfPresent(Int.self, forKey: .total)
    }
}

/// RFC 8620 §5.3 `SetError` item inside `notCreated`, `notUpdated`, or `notDestroyed`.
public struct JMAPSetError: Codable, Equatable, Sendable {
    public let type: String
    public let description: String?

    /// Creates a `SetError` value.
    public init(type: String, description: String? = nil) {
        self.type = type
        self.description = description
    }
}

/// Generic `*/set` response payload (RFC 8620 §5.3).
public struct JMAPSetResponse: Codable, Equatable, Sendable {
    public let accountId: String
    public let oldState: String?
    public let newState: String?
    public let created: [String: [String: JMAPJSONValue]]?
    public let updated: [String: [String: JMAPJSONValue]?]?
    public let destroyed: [String]?
    public let notCreated: [String: JMAPSetError]?
    public let notUpdated: [String: JMAPSetError]?
    public let notDestroyed: [String: JMAPSetError]?

    /// Creates a `*/set` response payload.
    public init(
        accountId: String,
        oldState: String? = nil,
        newState: String? = nil,
        created: [String: [String: JMAPJSONValue]]? = nil,
        updated: [String: [String: JMAPJSONValue]?]? = nil,
        destroyed: [String]? = nil,
        notCreated: [String: JMAPSetError]? = nil,
        notUpdated: [String: JMAPSetError]? = nil,
        notDestroyed: [String: JMAPSetError]? = nil
    ) {
        self.accountId = accountId
        self.oldState = oldState
        self.newState = newState
        self.created = created
        self.updated = updated
        self.destroyed = destroyed
        self.notCreated = notCreated
        self.notUpdated = notUpdated
        self.notDestroyed = notDestroyed
    }
}

/// RFC 8620 §6.1 blob upload response payload.
public struct JMAPBlobUploadResponse: Codable, Equatable, Sendable {
    public let accountId: String
    public let blobId: String
    public let type: String
    public let size: Int

    /// Creates a blob upload response.
    public init(accountId: String, blobId: String, type: String, size: Int) {
        self.accountId = accountId
        self.blobId = blobId
        self.type = type
        self.size = size
    }
}

/// RFC 8620 §7.1 `StateChange` object received via EventSource SSE or WebPush.
public struct JMAPStateChange: Codable, Equatable, Sendable {
    /// Map of `accountId -> (typeName -> newState)`.
    public let changed: [String: [String: String]]

    /// Creates a state-change notification payload.
    public init(changed: [String: [String: String]]) {
        self.changed = changed
    }
}

// MARK: - Date Formatting

/// ISO 8601 UTC date parser/formatter matching RFC 8620 §1.4 `UTCDate` and `Date` formats.
public enum JMAPDateCoding {
    /// Parses an RFC 3339 / ISO 8601 timestamp with or without fractional seconds.
    public static func parse(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = withFractional.date(from: string) {
            return parsed
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: string)
    }

    /// Formats a `Date` as an RFC 8620 `UTCDate` string (`YYYY-MM-DDTHH:MM:SSZ`).
    public static func formatUTC(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
