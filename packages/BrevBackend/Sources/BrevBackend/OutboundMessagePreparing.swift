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

// MARK: - Outbound message preparation (ADR-0021)

/// Transforms a plaintext RFC 5322/MIME message into its signed and/or
/// encrypted form before submission (ADR-0021 decision #6).
///
/// The backend calls this once and uses the returned bytes for BOTH the SMTP
/// `DATA` and the IMAP Sent-copy `APPEND`, so the delivered message and the
/// saved copy never disagree about their security state (decision #7).
///
/// The concrete implementation lives in `BrevCrypto`, uses Apple Security for
/// S/MIME per RFC 5751, and owns all key-material access. It MUST fail closed —
/// throw rather than return
/// plaintext — whenever the requested security cannot be satisfied
/// (decision #4). The view layer never sees this protocol; it is injected into
/// the backend by the app target.
public protocol OutboundMessagePreparing: Sendable {
    /// Returns the prepared (signed/encrypted) MIME bytes for `mimeData`.
    ///
    /// - Parameters:
    ///   - mimeData: The plaintext MIME message the backend serialized.
    ///   - request: Sender, recipients, and the requested `mode`.
    /// - Throws: if the requested signing/encryption cannot be produced.
    ///   Never returns plaintext for a `.sign`/`.encrypt`/`.signAndEncrypt`
    ///   request.
    func prepare(
        mimeData: Data,
        request: OutboundMessageSecurityRequest
    ) async throws -> Data
}

/// Thrown when a draft requests signing/encryption but no crypto engine is
/// wired into the backend. Fail-closed: the send is blocked and surfaced to the
/// user — never silently downgraded to plaintext.
public struct OutboundCryptoEngineUnavailableError: Error, Sendable, Hashable, LocalizedError {
    public let mode: OutboundMessageSecurityMode

    public init(mode: OutboundMessageSecurityMode) {
        self.mode = mode
    }

    public var errorDescription: String? {
        String(
            localized: "This build can't sign or encrypt mail yet, so the message was not sent. Turn off message security to send it, or wait for an update that adds encryption.",
            bundle: .module
        )
    }
}
