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

/// Concrete crypto pipeline adapter used by `BodyRenderer`.
///
/// This processor detects S/MIME envelope and signature parts without exposing
/// Security framework types outside `BrevCrypto`.
///
/// A deterministic `[[BREV_CRYPTO:...]]` fixture-directive path exists so tests
/// can prove end-to-end security-state mapping without network dependencies.
/// It is **disabled by default** and only enabled via the explicit test-only
/// initializer: a message body must never be able to dictate its own security
/// state, or a sender could forge a "verified"/"decrypted" badge on live mail.
public struct BrevCryptoProcessor: CryptoBodyProcessing {
    private let fixtureDirectivesEnabled: Bool

    /// Production initializer. Body-embedded `[[BREV_CRYPTO:...]]` directives are
    /// ignored — security state is derived only from real armor/MIME structure.
    public init() {
        fixtureDirectivesEnabled = false
    }

    /// Test-only initializer that honors `[[BREV_CRYPTO:...]]` fixture directives
    /// for deterministic security-state mapping tests. MUST NOT be used in
    /// production: an attacker-controlled body could otherwise forge its own
    /// verified/decrypted security state.
    public init(fixtureDirectivesEnabledForTesting: Bool) {
        fixtureDirectivesEnabled = fixtureDirectivesEnabledForTesting
    }

    public func process(
        body: MessageBody
    ) async -> (body: MessageBody, securityState: MessageSecurityState) {
        let payload = (body.html ?? "") + "\n" + (body.plainText ?? "")

        // Fixture directives are a test-only affordance and are never honored in
        // production (`init()` leaves them disabled). Gating this here ensures a
        // hostile message body can never spoof a trusted security state.
        if fixtureDirectivesEnabled, let directive = FixtureDirective.parse(in: payload) {
            return apply(directive: directive, to: body)
        }

        if hasEncryptedEnvelope(body: body) {
            return (body: body, securityState: .encrypted)
        }
        if hasSignedEnvelope(body: body) {
            return (body: body, securityState: .signed(state: .unverified(reason: "Signature present")))
        }
        return (body: body, securityState: .none)
    }

    private func apply(
        directive: FixtureDirective,
        to body: MessageBody
    ) -> (body: MessageBody, securityState: MessageSecurityState) {
        let renderedBody = {
            if let base64 = directive.plaintextBase64,
               let decoded = Data(base64Encoded: base64),
               let plaintext = String(data: decoded, encoding: .utf8) {
                return MessageBody(
                    messageID: body.messageID,
                    html: body.html,
                    plainText: plaintext,
                    attachments: body.attachments,
                    listUnsubscribe: body.listUnsubscribe
                )
            }
            return body
        }()

        switch directive.state {
        case .none:
            return (body: renderedBody, securityState: .none)
        case .encrypted:
            return (body: renderedBody, securityState: .encrypted)
        case .decryptionFailed:
            return (
                body: renderedBody,
                securityState: .decryptionFailed(reason: directive.reason ?? "Unable to decrypt")
            )
        case .decrypted:
            return (
                body: renderedBody,
                securityState: .decrypted(signatureState: signatureState(for: directive))
            )
        case .signed:
            return (
                body: renderedBody,
                securityState: .signed(state: signatureState(for: directive))
            )
        }
    }

    private func signatureState(for directive: FixtureDirective) -> MessageSignatureState {
        switch directive.signature {
        case .none:
            return .unsigned
        case .verified:
            return .verified(signer: directive.signer ?? "Unknown signer")
        case .unverified:
            return .unverified(reason: directive.reason ?? "Signature is not trusted")
        case .failed:
            return .failed(reason: directive.reason ?? "Signature verification failed")
        }
    }

    /// Returns `true` when an S/MIME encrypted attachment MIME type is present.
    private func hasEncryptedEnvelope(body: MessageBody) -> Bool {
        let attachmentEncrypted = body.attachments.contains {
            let mime = $0.mimeType.lowercased()
            return mime == "application/pkcs7-mime"
                || mime == "application/x-pkcs7-mime"
        }
        return attachmentEncrypted
    }

    /// Returns `true` when an S/MIME signature is present as a structured MIME
    /// part.
    ///
    /// Detection is by a parsed `application/(x-)pkcs7-signature` part only. A
    /// previous fallback that searched
    /// the body *text* for "Content-Type: multipart/signed" was removed: it
    /// false-positived on any message that merely quoted that string (e.g. a
    /// forwarded MIME discussion), showing a bogus "signature present" badge.
    /// Real signed messages always surface the signature as a non-text part,
    /// which the MIME parser exposes as an attachment.
    private func hasSignedEnvelope(body: MessageBody) -> Bool {
        body.attachments.contains {
            let mime = $0.mimeType.lowercased()
            return mime == "application/pkcs7-signature"
                || mime == "application/x-pkcs7-signature"
        }
    }
}

private struct FixtureDirective: Equatable {
    enum State: String {
        case none
        case encrypted
        case decrypted
        case decryptionFailed = "decryption_failed"
        case signed
    }

    enum Signature: String {
        case none
        case verified
        case unverified
        case failed
    }

    let state: State
    let signature: Signature
    let signer: String?
    let reason: String?
    let plaintextBase64: String?

    static func parse(in payload: String) -> FixtureDirective? {
        guard let start = payload.range(of: "[[BREV_CRYPTO:"),
              let end = payload[start.upperBound...].range(of: "]]")
        else {
            return nil
        }

        let content = String(payload[start.upperBound ..< end.lowerBound])
        let components = content.split(separator: ";", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var fields: [String: String] = [:]
        for component in components {
            let parts = component.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                fields[parts[0].lowercased()] = parts[1]
            }
        }

        let state = State(rawValue: fields["state"]?.lowercased() ?? "none") ?? .none
        let signature = Signature(rawValue: fields["signature"]?.lowercased() ?? "none") ?? .none
        return FixtureDirective(
            state: state,
            signature: signature,
            signer: fields["signer"],
            reason: fields["reason"],
            plaintextBase64: fields["plaintext_base64"]
        )
    }
}
