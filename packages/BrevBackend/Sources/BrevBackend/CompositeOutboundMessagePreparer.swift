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

/// Combines `OutboundMessagePreparing` engines and uses the first that can
/// satisfy the request. If an engine lacks
/// the key material for this sender/recipients (`OutboundMessageSecurityError`)
/// or isn't available on this platform (`OutboundCryptoEngineUnavailableError`),
/// the next engine is tried. When none can satisfy it, the send fails closed —
/// a real cryptographic failure from a chosen engine propagates immediately and
/// is never swallowed (ADR-0021 #4).
public struct CompositeOutboundMessagePreparer: OutboundMessagePreparing {
    private let preparers: [any OutboundMessagePreparing]

    public init(_ preparers: [any OutboundMessagePreparing]) {
        self.preparers = preparers
    }

    public func prepare(
        mimeData: Data,
        request: OutboundMessageSecurityRequest
    ) async throws -> Data {
        guard request.mode != .none else { return mimeData }

        var lastError: any Error = OutboundCryptoEngineUnavailableError(mode: request.mode)
        for preparer in preparers {
            do {
                return try await preparer.prepare(mimeData: mimeData, request: request)
            } catch let error as OutboundMessageSecurityError {
                lastError = error // this engine has no key material — try the next
            } catch let error as OutboundCryptoEngineUnavailableError {
                lastError = error // this engine is unavailable here — try the next
            }
            // Any other error is a genuine failure from the chosen engine and
            // propagates out (never a silent plaintext fallback).
        }
        throw lastError
    }
}
