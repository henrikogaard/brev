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

// MARK: - Message security state (ADR-0021)

/// The cryptographic security state of a rendered message body.
///
/// Produced by a `CryptoBodyProcessing` implementation and passed
/// through `BodyRenderer` to the reading pane. Views branch on this
/// without knowing which library produced it.
///
/// In v1 all messages return `.none`. The `BrevCrypto` package
/// (v2) provides implementations that return other states.
public enum MessageSecurityState: Sendable, Hashable {
    /// Message is not signed or encrypted (default).
    case none
    /// Message is encrypted but has not been decrypted (no local key).
    case encrypted
    /// Message was decrypted successfully; signature state is nested.
    case decrypted(signatureState: MessageSignatureState)
    /// Decryption failed; the rendered body may contain a placeholder.
    case decryptionFailed(reason: String)
    /// Message body is signed but not encrypted.
    case signed(state: MessageSignatureState)

    /// True when the body was decrypted or is unencrypted and verified.
    public var isSecure: Bool {
        switch self {
        case .decrypted(.verified): return true
        case .signed(.verified): return true
        default: return false
        }
    }

    /// True when the user should be warned about a problem.
    public var hasWarning: Bool {
        switch self {
        case .encrypted, .decryptionFailed: return true
        case .decrypted(.failed), .decrypted(.unverified): return true
        case .signed(.failed), .signed(.unverified): return true
        default: return false
        }
    }

    /// Short human-readable summary for badge or toolbar.
    public var summary: String {
        switch self {
        case .none: return ""
        case .encrypted: return "Encrypted — no local key"
        case .decrypted(.unsigned): return "Decrypted"
        case .decrypted(.verified(let signer)): return "Decrypted · Verified: \(signer)"
        case .decrypted(.unverified(let reason)): return "Decrypted · Unverified: \(reason)"
        case .decrypted(.failed(let reason)): return "Decrypted · Signature error: \(reason)"
        case .decryptionFailed(let reason): return "Decryption failed: \(reason)"
        case .signed(.unsigned): return ""
        case .signed(.verified(let signer)): return "Verified: \(signer)"
        case .signed(.unverified(let reason)): return "Unverified: \(reason)"
        case .signed(.failed(let reason)): return "Signature error: \(reason)"
        }
    }
}

/// The verification state of a digital signature on a message.
public enum MessageSignatureState: Sendable, Hashable {
    /// No signature present.
    case unsigned
    /// Signature verified against a trusted key or certificate.
    /// `signer` is a display name or email address.
    case verified(signer: String)
    /// Signature present but not fully trusted.
    case unverified(reason: String)
    /// Signature invalid or key not found.
    case failed(reason: String)
}

// MARK: - Crypto processing protocol

/// Pluggable interface for S/MIME body processing.
///
/// Implementations live in `packages/BrevCrypto/` (v2). The default
/// no-op pass-through is used in v1 so the rest of the pipeline
/// compiles and tests correctly without any crypto library.
///
/// Conforming types must be `Sendable` because `BodyRenderer` is
/// async and may be called from multiple actors.
public protocol CryptoBodyProcessing: Sendable {
    /// Process a message body, returning the (possibly decrypted)
    /// body and the security state.
    ///
    /// Implementations must not throw — they return `.decryptionFailed`
    /// instead so callers always receive a renderable body.
    func process(body: MessageBody) async -> (body: MessageBody, securityState: MessageSecurityState)
}
