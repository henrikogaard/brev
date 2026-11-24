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

/// Lifecycle state of a registered push subscription.
public enum PushRelaySubscriptionState: String, Codable, Equatable, Hashable, Sendable {
    /// JMAP RFC 8620 §7.2.2 subscription created on the server, awaiting verification challenge update.
    case pendingVerification
    /// Subscription verified (JMAP) or active (user-hosted relay) and ready to deliver wakes.
    case active
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

    /// Returns a canonical origin string (`https://host` or `https://host:port` for non-443 ports)
    /// used to scope saved Keychain bearer tokens per relay origin.
    public static func originKey(for url: URL) -> String {
        let scheme = (url.scheme ?? "https").lowercased()
        let host = (url.host ?? "").lowercased()
        if let port = url.port, !(scheme == "https" && port == 443) {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    /// Validates `rawValue` and returns its normalized origin string.
    public static func originKey(from rawValue: String) throws -> String {
        let url = try validate(rawValue)
        return originKey(for: url)
    }

    /// Compares two validated URLs canonically (scheme, lowercased host, effective port, path, query).
    public static func representsSameDestination(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsPort = lhs.port ?? (lhs.scheme?.lowercased() == "https" ? 443 : nil)
        let rhsPort = rhs.port ?? (rhs.scheme?.lowercased() == "https" ? 443 : nil)
        let lhsPath = lhs.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let rhsPath = rhs.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && lhsPort == rhsPort
            && lhsPath == rhsPath
            && lhs.query == rhs.query
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
/// Strictly limited to opaque device/account tokens and optional RFC 8291
/// public keys — never carries email addresses, mail passwords, OAuth tokens,
/// private keys, or message bodies.
public struct PushRelayRegistrationRequest: Codable, Equatable, Sendable {
    /// Selected push relay transport mode.
    public let mode: PushRelayMode
    /// Opaque per-device client identifier generated locally.
    public let deviceClientID: String
    /// Real platform-issued APNs device push token (required for `.userHostedRelay`).
    public let devicePushToken: String
    /// Distinct HTTPS WebPush delivery receiver URL (required for `.jmapWebPush`).
    public let webPushDeliveryURL: String?
    /// Sorted, deduplicated opaque device-local account tokens opted into wakes.
    public let accountIDs: [String]
    /// Optional RFC 8291 public encryption keys (`p256dh` and `auth`).
    public let keys: PushRelayPublicKeys?
    /// Platform label (`ios` or `macos`).
    public let platform: String

    /// Creates a sanitized registration payload with deduplicated, sorted opaque account tokens.
    public init(
        mode: PushRelayMode,
        deviceClientID: String,
        devicePushToken: String = "",
        webPushDeliveryURL: String? = nil,
        accountIDs: [String],
        keys: PushRelayPublicKeys? = nil,
        platform: String = PushRelayRegistrationRequest.defaultPlatform
    ) {
        self.mode = mode
        self.deviceClientID = deviceClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.devicePushToken = devicePushToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDelivery = webPushDeliveryURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.webPushDeliveryURL = trimmedDelivery?.isEmpty == false ? trimmedDelivery : nil
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

/// Response returned after registering, refreshing, or verifying a closed-app push subscription.
public struct PushRelayRegistrationResponse: Codable, Equatable, Sendable {
    /// Server-assigned subscription identifier used for later refresh, verification, or unregistration.
    public let subscriptionID: String
    /// Optional server-assigned subscription expiration timestamp.
    public let expiresAt: Date?
    /// Optional RFC 8620 §7.2 verification code returned by a JMAP server.
    public let verificationCode: String?
    /// Subscription activation state (`.pendingVerification` for newly created JMAP subscriptions).
    public let state: PushRelaySubscriptionState

    /// Creates a registration response value.
    public init(
        subscriptionID: String,
        expiresAt: Date? = nil,
        verificationCode: String? = nil,
        state: PushRelaySubscriptionState = .active
    ) {
        self.subscriptionID = subscriptionID
        self.expiresAt = expiresAt
        self.verificationCode = verificationCode
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case subscriptionID
        case expiresAt
        case verificationCode
        case state
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subscriptionID = try container.decode(String.self, forKey: .subscriptionID)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        verificationCode = try container.decodeIfPresent(String.self, forKey: .verificationCode)
        state = try container.decodeIfPresent(PushRelaySubscriptionState.self, forKey: .state) ?? .active
    }
}

/// Payload sent when unregistering a device or removing opted-in accounts from a relay.
public struct PushRelayUnregistrationRequest: Codable, Equatable, Sendable {
    /// Opaque per-device client identifier.
    public let deviceClientID: String
    /// Last known subscription identifier, if available.
    public let subscriptionID: String?
    /// Opaque account tokens being unregistered.
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
/// plugs straight into the same Keychain key pair, verification flow, and registration seam.
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

    /// Encodes a complete RFC 8620 §7.2 `PushSubscription/set` create request body as JSON.
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
        return try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    /// Encodes an RFC 8620 §7.2.2 `PushSubscription/set` verification update request body as JSON.
    public static func encodedSetVerifyRequestData(
        subscriptionID: String,
        verificationCode: String,
        callID: String = "c0"
    ) throws -> Data {
        let payload: [String: Any] = [
            "using": usingCapabilities,
            "methodCalls": [
                [
                    "PushSubscription/set",
                    [
                        "update": [
                            subscriptionID: [
                                "verificationCode": verificationCode
                            ]
                        ]
                    ],
                    callID
                ]
            ]
        ]
        return try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    /// Encodes a complete RFC 8620 §7.2 `PushSubscription/set` destroy request body as JSON.
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
        return try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }
}

/// Kind of opaque wake or verification event delivered by a push relay or JMAP WebPush server.
public enum PushWakeEventKind: String, Codable, Equatable, Hashable, Sendable {
    /// New message arrived in the mailbox.
    case newMail = "new_mail"
    /// Mailbox state changed (flags, moves, or unread count).
    case mailboxChanged = "mailbox_changed"
    /// JMAP RFC 8620 §7.2.2 `PushVerification` challenge delivered to the WebPush URL.
    case jmapVerification = "jmap_verification"
}

/// Opaque incoming wake payload or RFC 8620 §7.2.2 JMAP verification challenge
/// decoded from an APNs silent notification or WebPush event.
///
/// Carries only an opaque account token, optional state token, or JMAP verification
/// challenge — never plaintext message bodies, subjects, or credentials.
public struct PushWakePayload: Codable, Equatable, Sendable {
    private static let maxFieldLength = 256
    private static let maxStateTokenLength = 512

    /// Opaque device-local account token to resolve and sync locally (empty for JMAP verification challenges).
    public let accountID: String
    /// Optional opaque server state token (e.g. IMAP MODSEQ / JMAP state string).
    public let stateToken: String?
    /// Coarse wake event classification.
    public let eventKind: PushWakeEventKind
    /// JMAP `pushSubscriptionId` for RFC 8620 §7.2.2 `PushVerification` challenges.
    public let pushSubscriptionID: String?
    /// JMAP `verificationCode` for RFC 8620 §7.2.2 `PushVerification` challenges.
    public let verificationCode: String?

    /// Whether this payload is an RFC 8620 §7.2.2 JMAP `PushVerification` challenge.
    public var isJMAPVerificationChallenge: Bool {
        eventKind == .jmapVerification && pushSubscriptionID != nil && verificationCode != nil
    }

    /// Creates an opaque mail wake payload directly.
    public init(
        accountID: String,
        stateToken: String? = nil,
        eventKind: PushWakeEventKind = .newMail
    ) {
        self.accountID = accountID
        self.stateToken = stateToken
        self.eventKind = eventKind
        pushSubscriptionID = nil
        verificationCode = nil
    }

    private init(
        accountID: String,
        stateToken: String?,
        eventKind: PushWakeEventKind,
        pushSubscriptionID: String?,
        verificationCode: String?
    ) {
        self.accountID = accountID
        self.stateToken = stateToken
        self.eventKind = eventKind
        self.pushSubscriptionID = pushSubscriptionID
        self.verificationCode = verificationCode
    }

    /// Creates a JMAP RFC 8620 §7.2.2 `PushVerification` challenge payload.
    public static func jmapVerification(
        pushSubscriptionId: String,
        verificationCode: String
    ) -> PushWakePayload {
        PushWakePayload(
            accountID: "",
            stateToken: nil,
            eventKind: .jmapVerification,
            pushSubscriptionID: pushSubscriptionId.trimmingCharacters(in: .whitespacesAndNewlines),
            verificationCode: verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Safely decodes and validates a wake payload or RFC 8620 §7.2.2 `PushVerification` from UTF-8 JSON bytes.
    /// Returns `nil` for malformed JSON, blank/oversized fields, or unknown event kinds.
    public init?(jsonData: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        self.init(userInfo: object)
    }

    /// Safely decodes and validates a wake payload or RFC 8620 §7.2.2 `PushVerification`
    /// from an APNs `userInfo` dictionary. Supports top-level keys or a nested `"brev"` dictionary
    /// while ignoring all unexpected keys.
    public init?(userInfo: [AnyHashable: Any]) {
        let container: [AnyHashable: Any] = if let nested = userInfo["brev"] as? [AnyHashable: Any] {
            nested
        } else {
            userInfo
        }

        // RFC 8620 §7.2.2 PushVerification challenge object.
        if (container["@type"] as? String) == "PushVerification"
            || (container["eventKind"] as? String) == PushWakeEventKind.jmapVerification.rawValue {
            guard let rawSubID = (container["pushSubscriptionId"] as? String)
                ?? (container["pushSubscriptionID"] as? String),
                let rawCode = container["verificationCode"] as? String
            else {
                return nil
            }
            let subID = rawSubID.trimmingCharacters(in: .whitespacesAndNewlines)
            let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !subID.isEmpty, subID.count <= Self.maxFieldLength,
                  !code.isEmpty, code.count <= Self.maxStateTokenLength
            else {
                return nil
            }
            self = .jmapVerification(pushSubscriptionId: subID, verificationCode: code)
            return
        }

        guard let rawAccountID = container["accountID"] as? String else {
            return nil
        }
        let eventKind: PushWakeEventKind
        if let rawKind = container["eventKind"] as? String {
            guard let parsed = PushWakeEventKind(rawValue: rawKind),
                  parsed != .jmapVerification
            else {
                return nil
            }
            eventKind = parsed
        } else {
            eventKind = .newMail
        }
        let rawStateToken = container["stateToken"] as? String
        guard let validated = Self.validatedWake(
            accountID: rawAccountID,
            stateToken: rawStateToken,
            eventKind: eventKind
        ) else {
            return nil
        }
        self = validated
    }

    private static func validatedWake(
        accountID: String,
        stateToken: String?,
        eventKind: PushWakeEventKind
    ) -> PushWakePayload? {
        let trimmedAccount = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccount.isEmpty, trimmedAccount.count <= maxFieldLength else {
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
