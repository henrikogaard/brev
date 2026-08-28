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
import BrevCrypto
import Foundation

/// The output of the body rendering pipeline. Views consume this
/// rather than raw `MessageBody`.
///
/// The crypto seam lets S/MIME processing evolve without restructuring views
/// (ADR-0028 invariant 3).
public struct RenderedBody: Sendable {
    /// HTML content ready for display, or `nil` if unavailable.
    public let html: String?
    /// Plaintext content, or `nil` if unavailable.
    public let plainText: String?
    /// Attachments after any decryption unwrapping.
    public let attachments: [Attachment]
    /// Message signing/decryption status for trust UI.
    public let securityState: MessageSecurityState

    public init(
        html: String?,
        plainText: String?,
        attachments: [Attachment],
        securityState: MessageSecurityState = .none
    ) {
        self.html = html
        self.plainText = plainText
        self.attachments = attachments
        self.securityState = securityState
    }
}

/// Actor that transforms a `MessageBody` into a `RenderedBody`.
///
/// v1 implementation is identity — the body passes through unchanged.
/// The pipeline inserts S/MIME processing before producing `RenderedBody`.
/// The actor boundary ensures decryption work runs
/// off the main thread.
public actor BodyRenderer {
    private let cryptoProcessor: any CryptoBodyProcessing

    public init(cryptoProcessor: any CryptoBodyProcessing = BrevCryptoProcessor()) {
        self.cryptoProcessor = cryptoProcessor
    }

    /// Render a message body through the pipeline.
    ///
    /// v1: identity transform. v2: decrypt → sanitize → produce
    /// `RenderedBody`.
    public func render(_ body: MessageBody) async -> RenderedBody {
        let interval = MailUIPerformanceDiagnostics.beginInterval("Body Render")
        defer { MailUIPerformanceDiagnostics.endInterval(interval) }
        let processed = await cryptoProcessor.process(body: body)
        let rendered = RenderedBody(
            html: processed.body.html,
            plainText: processed.body.plainText,
            attachments: processed.body.attachments,
            securityState: processed.securityState
        )
        MailUIPerformanceDiagnostics.logBodyRenderFinished(
            hasHTML: rendered.html != nil,
            hasPlainText: rendered.plainText != nil,
            attachmentCount: rendered.attachments.count,
            durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
        )
        return rendered
    }
}
