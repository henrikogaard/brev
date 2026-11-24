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

import CryptoKit
import Foundation

/// Transport mode for opt-in, zero-Brev-proxy closed-app push delivery (#11).
public enum PushRelayMode: String, Codable, CaseIterable, Equatable, Hashable, Sendable, Identifiable {
    /// Closed-app push wakes are disabled (zero network calls).
    case disabled
    /// User-hosted HTTPS push relay (e.g. self-hosted IMAP-IDLE-to-APNs or webhook-to-APNs bridge).
    case userHostedRelay
    /// Standards-compliant JMAP WebPush (`PushSubscription/set`, RFC 8620 §7.2 + RFC 8291).
    case jmapWebPush

    /// Stable identifier for SwiftUI pickers.
    public var id: String { rawValue }
}

/// Validation errors for user-configured push relay and JMAP WebPush endpoints.
public enum PushRelayEndpointValidationError: Error, LocalizedError, Equatable, Sendable {
    case empty
    case malformedURL
    case httpsRequired
    case embeddedCredentialsForbidden
    case missingHost

    public var errorDescription: String? {
        switch self {
        case .empty:
            String(localized: "Enter an HTTPS push relay URL.", bundle: .module)
        case .malformedURL:
            String(localized: "The push relay URL is not a valid URL.", bundle: .module)
        case .httpsRequired:
            String(localized: "Push relay URLs must use https://.", bundle: .module)
        case .embeddedCredentialsForbidden:
            String(
                localized: "Do not embed credentials in the push relay URL. Use the Bearer token field instead.",
                bundle: .module
            )
        case .missingHost:
            String(localized: "The push relay URL must include a host name.", bundle: .module)
        }
    }
}

/// Validates user-configured push relay URLs strictly over HTTPS without embedded credentials.
public enum PushRelayEndpointValidator {
    /// Validates and normalizes a push relay or JMAP WebPush endpoint URL string.
    ///
    /// Rejects blank strings, non-`https` schemes (including `http://`), embedded
    /// username/password components, and missing hosts.
    public static func validate(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PushRelayEndpointValidationError.empty
        }
        guard !trimmed.contains(where: \.isWhitespace),
              let components = URLComponents(string: trimmed)
        else {
            throw PushRelayEndpointValidationError.malformedURL
        }
        guard components.scheme?.lowercased() == "https" else {
            throw PushRelayEndpointValidationError.httpsRequired
        }
        if components.user != nil || components.password != nil {
            throw PushRelayEndpointValidationError.embeddedCredentialsForbidden
        }
        guard let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty
        else {
            throw PushRelayEndpointValidationError.missingHost
        }
        guard let url = components.url else {
            throw PushRelayEndpointValidationError.malformedURL
        }
        return url
    }
}

/// URL-safe Base64 encoding without padding (RFC 4648 §5), used by RFC 8291 / RFC 8620 §7.2.
public enum PushRelayBase64URL {
    /// Encodes `data` into unpadded Base64URL text.
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decodes unpadded or padded Base64URL text into bytes.
    public static func decode(_ encoded: String) -> Data? {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder == 2 {
            base64.append("==")
        } else if remainder == 3 {
            base64.append("=")
        } else if remainder == 1 {
            return nil
        }
        return Data(base64Encoded: base64)
    }
}

/// Public-only RFC 8291 WebPush encryption parameters (`p256dh` + `auth`) sent
/// when registering a device with a self-hosted relay or JMAP server.
public struct PushRelayPublicKeys: Codable, Equatable, Hashable, Sendable {
    /// Base64URL-encoded uncompressed 65-byte ANSI X9.63 P-256 public key (`0x04 || X || Y`).
    public let p256dh: String
    /// Base64URL-encoded 16-byte WebPush authentication secret.
    public let auth: String

    /// Creates public WebPush encryption parameters.
    public init(p256dh: String, auth: String) {
        self.p256dh = p256dh
        self.auth = auth
    }
}

/// Device-local RFC 8291 P-256 ECDH private key and 16-byte authentication secret.
///
/// Stored strictly in the system Keychain (`ThisDeviceOnly`) and never written to
/// `UserDefaults`, logs, or network requests. Only `publicKeys()` is transmitted.
public struct PushRelayEncryptionKeyMaterial: Codable, Equatable, Sendable, CustomStringConvertible {
    /// Raw 32-byte scalar representation of the P-256 private key.
    public let privateKeyRawRepresentation: Data
    /// 16-byte random authentication secret for RFC 8291.
    public let authSecret: Data

    /// Creates key material from persisted raw bytes.
    public init(privateKeyRawRepresentation: Data, authSecret: Data) {
        self.privateKeyRawRepresentation = privateKeyRawRepresentation
        self.authSecret = authSecret
    }

    /// Generates a fresh RFC 8291 P-256 key pair and 16-byte auth secret using `CryptoKit`.
    public static func generate() -> PushRelayEncryptionKeyMaterial {
        let key = P256.KeyAgreement.PrivateKey()
        let authKey = SymmetricKey(size: .bits128)
        let authBytes = authKey.withUnsafeBytes { Data($0) }
        return PushRelayEncryptionKeyMaterial(
            privateKeyRawRepresentation: key.rawRepresentation,
            authSecret: authBytes
        )
    }

    /// Reconstructs the `P256.KeyAgreement.PrivateKey` from stored raw bytes.
    public func privateKey() throws -> P256.KeyAgreement.PrivateKey {
        try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKeyRawRepresentation)
    }

    /// Derives the public-only RFC 8291 `p256dh` and `auth` parameters safe to send to a push server.
    public func publicKeys() throws -> PushRelayPublicKeys {
        let key = try privateKey()
        return PushRelayPublicKeys(
            p256dh: PushRelayBase64URL.encode(key.publicKey.x963Representation),
            auth: PushRelayBase64URL.encode(authSecret)
        )
    }

    /// Redacted description so secret bytes never appear in diagnostics or logs.
    public var description: String {
        "PushRelayEncryptionKeyMaterial(redacted)"
    }
}

/// Registration payload sent to a user-hosted HTTPS push relay or JMAP endpoint.
///
/// Strictly limited to opaque device/account identifiers and optional RFC 8291
/// public keys — never carries mail passwords, OAuth tokens, private keys, or message bodies.
public struct PushRelayRegistrationRequest: Codable, Equatable, Sendable {
    /// Selected push relay transport mode.
    public let mode: PushRelayMode
    /// Opaque per-device client identifier generated locally.
    public let deviceClientID: String
    /// APNs device token or WebPush delivery endpoint URL.
    public let devicePushToken: String
    /// Sorted, deduplicated opaque Brev account identifiers opted into wakes.
    public let accountIDs: [String]
    /// Optional RFC 8291 public encryption keys (`p256dh` and `auth`).
    public let keys: PushRelayPublicKeys?
    /// Platform label (`ios` or `macos`).
    public let platform: String

    /// Creates a sanitized registration payload with deduplicated, sorted account IDs.
    public init(
        mode: PushRelayMode,
        deviceClientID: String,
        devicePushToken: String,
        accountIDs: [String],
        keys: PushRelayPublicKeys? = nil,
        platform: String = PushRelayRegistrationRequest.defaultPlatform
    ) {
        self.mode = mode
        self.deviceClientID = deviceClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.devicePushToken = devicePushToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accountIDs = Array(
            Set(
                accountIDs
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
        self.keys = keys
        self.platform = platform
    }

    /// Current build platform identifier.
    public static var defaultPlatform: String {
        #if os(iOS)
        "ios"
        #else
        "macos"
        #endif
    }
}

/// Response returned after registering or refreshing a closed-app push subscription.
public struct PushRelayRegistrationResponse: Codable, Equatable, Sendable {
    /// Server-assigned subscription identifier used for later refresh or unregistration.
    public let subscriptionID: String
    /// Optional server-assigned subscription expiration timestamp.
    public let expiresAt: Date?
    /// Optional RFC 8620 §7.2 verification code returned by a JMAP server.
    public let verificationCode: String?

    /// Creates a registration response value.
    public init(
        subscriptionID: String,
        expiresAt: Date? = nil,
        verificationCode: String? = nil
    ) {
        self.subscriptionID = subscriptionID
        self.expiresAt = expiresAt
        self.verificationCode = verificationCode
    }
}

/// Payload sent when unregistering a device or removing opted-in accounts from a relay.
public struct PushRelayUnregistrationRequest: Codable, Equatable, Sendable {
    /// Opaque per-device client identifier.
    public let deviceClientID: String
    /// Last known subscription identifier, if available.
    public let subscriptionID: String?
    /// Account identifiers being unregistered.
    public let accountIDs: [String]

    /// Creates a sanitized unregistration payload.
    public init(
        deviceClientID: String,
        subscriptionID: String? = nil,
        accountIDs: [String]
    ) {
        self.deviceClientID = deviceClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSub = subscriptionID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.subscriptionID = trimmedSub?.isEmpty == false ? trimmedSub : nil
        self.accountIDs = Array(
            Set(
                accountIDs
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
    }
}

/// Standards-compliant JMAP RFC 8620 §7.2 `PushSubscription/set` payload builder.
///
/// Keeps the JMAP WebPush contract ready in `BrevBackend` so future `BrevJMAP`
/// plugs straight into the same Keychain key pair and registration seam.
public struct JMAPWebPushSubscriptionSpec: Equatable, Sendable {
    /// Required JMAP capabilities for mail push subscriptions.
    public static let usingCapabilities: [String] = [
        "urn:ietf:params:jmap:core",
        "urn:ietf:params:jmap:mail"
    ]

    /// JMAP `PushSubscription` create object matching RFC 8620 §7.2 field names.
    public struct CreateObject: Codable, Equatable, Sendable {
        public let deviceClientId: String
        public let url: String
        public let keys: PushRelayPublicKeys?
        public let types: [String]
        public let expires: String?

        /// Creates a JMAP `PushSubscription` creation object.
        public init(
            deviceClientId: String,
            url: String,
            keys: PushRelayPublicKeys?,
            types: [String],
            expires: String?
        ) {
            self.deviceClientId = deviceClientId
            self.url = url
            self.keys = keys
            self.types = types
            self.expires = expires
        }
    }

    /// Opaque per-device client ID sent as `deviceClientId`.
    public let deviceClientID: String
    /// Validated HTTPS WebPush delivery URL sent as `url`.
    public let url: URL
    /// Optional RFC 8291 P-256 public key and auth secret sent as `keys`.
    public let keys: PushRelayPublicKeys?
    /// JMAP state types to subscribe to (defaults to `["Email"]`).
    public let types: [String]
    /// Optional subscription expiration timestamp.
    public let expires: Date?

    /// Validates `urlString` as strict HTTPS without credentials and builds a JMAP subscription spec.
    public init(
        deviceClientID: String,
        urlString: String,
        keys: PushRelayPublicKeys? = nil,
        types: [String] = ["Email"],
        expires: Date? = nil
    ) throws {
        let validatedURL = try PushRelayEndpointValidator.validate(urlString)
        self.deviceClientID = deviceClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        url = validatedURL
        self.keys = keys
        self.types = types.isEmpty ? ["Email"] : types
        self.expires = expires
    }

    /// Builds the RFC 8620 §7.2 `PushSubscription` create object.
    public func createObject() -> CreateObject {
        let formattedExpires: String? = expires.map { date in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.string(from: date)
        }
        return CreateObject(
            deviceClientId: deviceClientID,
            url: url.absoluteString,
            keys: keys,
            types: types,
            expires: formattedExpires
        )
    }

    /// Encodes a complete RFC 8620 `PushSubscription/set` create request body as JSON.
    public func encodedSetCreateRequestData(
        clientCreationID: String = "brev-push-sub",
        callID: String = "c0"
    ) throws -> Data {
        let object = createObject()
        var subDict: [String: Any] = [
            "deviceClientId": object.deviceClientId,
            "url": object.url,
            "types": object.types
        ]
        if let keys = object.keys {
            subDict["keys"] = [
                "p256dh": keys.p256dh,
                "auth": keys.auth
            ]
        }
        if let expires = object.expires {
            subDict["expires"] = expires
        }
        let payload: [String: Any] = [
            "using": Self.usingCapabilities,
            "methodCalls": [
                [
                    "PushSubscription/set",
                    ["create": [clientCreationID: subDict]],
                    callID
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// Encodes a complete RFC 8620 `PushSubscription/set` destroy request body as JSON.
    public static func encodedSetDestroyRequestData(
        subscriptionID: String,
        callID: String = "c0"
    ) throws -> Data {
        let payload: [String: Any] = [
            "using": usingCapabilities,
            "methodCalls": [
                [
                    "PushSubscription/set",
                    ["destroy": [subscriptionID]],
                    callID
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}

/// Kind of opaque wake event delivered by a push relay or JMAP WebPush server.
public enum PushWakeEventKind: String, Codable, Equatable, Hashable, Sendable {
    /// New message arrived in the mailbox.
    case newMail = "new_mail"
    /// Mailbox state changed (flags, moves, or unread count).
    case mailboxChanged = "mailbox_changed"
}

/// Opaque incoming wake payload decoded from an APNs silent notification or WebPush event.
///
/// Carries only an account hint, optional opaque state token, and event kind —
/// never plaintext message bodies, subjects, or credentials.
public struct PushWakePayload: Codable, Equatable, Sendable {
    private static let maxAccountIDLength = 256
    private static let maxStateTokenLength = 512

    /// Opaque Brev account identifier to sync locally.
    public let accountID: String
    /// Optional opaque server state token (e.g. IMAP MODSEQ / JMAP state string).
    public let stateToken: String?
    /// Coarse wake event classification.
    public let eventKind: PushWakeEventKind

    /// Creates a wake payload directly.
    public init(
        accountID: String,
        stateToken: String? = nil,
        eventKind: PushWakeEventKind = .newMail
    ) {
        self.accountID = accountID
        self.stateToken = stateToken
        self.eventKind = eventKind
    }

    /// Safely decodes and validates a wake payload from UTF-8 JSON bytes.
    /// Returns `nil` for malformed JSON, blank/oversized fields, or unknown event kinds.
    public init?(jsonData: Data) {
        guard let decoded = try? JSONDecoder().decode(PushWakePayload.self, from: jsonData) else {
            return nil
        }
        guard let validated = Self.validated(
            accountID: decoded.accountID,
            stateToken: decoded.stateToken,
            eventKind: decoded.eventKind
        ) else {
            return nil
        }
        self = validated
    }

    /// Safely decodes and validates a wake payload from an APNs `userInfo` dictionary.
    /// Supports both top-level keys and a nested `"brev"` dictionary while ignoring all other keys.
    public init?(userInfo: [AnyHashable: Any]) {
        let container: [AnyHashable: Any] = if let nested = userInfo["brev"] as? [AnyHashable: Any] {
            nested
        } else {
            userInfo
        }
        guard let rawAccountID = container["accountID"] as? String else {
            return nil
        }
        let eventKind: PushWakeEventKind
        if let rawKind = container["eventKind"] as? String {
            guard let parsed = PushWakeEventKind(rawValue: rawKind) else {
                return nil
            }
            eventKind = parsed
        } else {
            eventKind = .newMail
        }
        let rawStateToken = container["stateToken"] as? String
        guard let validated = Self.validated(
            accountID: rawAccountID,
            stateToken: rawStateToken,
            eventKind: eventKind
        ) else {
            return nil
        }
        self = validated
    }

    private static func validated(
        accountID: String,
        stateToken: String?,
        eventKind: PushWakeEventKind
    ) -> PushWakePayload? {
        let trimmedAccount = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccount.isEmpty, trimmedAccount.count <= maxAccountIDLength else {
            return nil
        }
        let normalizedState: String?
        if let stateToken {
            let trimmedState = stateToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedState.count <= maxStateTokenLength else {
                return nil
            }
            normalizedState = trimmedState.isEmpty ? nil : trimmedState
        } else {
            normalizedState = nil
        }
        return PushWakePayload(
            accountID: trimmedAccount,
            stateToken: normalizedState,
            eventKind: eventKind
        )
    }
}
