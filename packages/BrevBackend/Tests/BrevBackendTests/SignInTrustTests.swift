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

@testable import BrevBackend
import Foundation
import Testing

/// Provider-neutral ADR-0088 assessment types and capability gating.
@Suite("Sign-in trust types")
struct SignInTrustTests {
    @Test("every failure reason is a stable raw value")
    func failureRawValues() {
        let reasons: [SignInTrustFailure] = [
            .notFreshDelivery, .wrongFolder, .stale, .noTrustedHeader,
            .conflictingTrustedHeaders, .missingDMARC, .duplicateDMARC,
            .dmarcNotPass, .fromMismatch, .malformedFrom, .malformedHeader,
            .unsupportedAccount
        ]
        #expect(Set(reasons.map(\.rawValue)).count == reasons.count)
        #expect(SignInTrustFailure(rawValue: "stale") == .stale)
    }

    @Test("the trusted-assessment flag exists but no backend advertises it yet")
    func capabilityDefinedNotAdvertised() {
        // ADR-0088 E1-E5 evidence is pending — providers must not set it.
        #expect(BackendExtendedCapabilities.trustedSignInAssessment.rawValue == 1 << 17)
        let backend = LocalMailBackend()
        #expect(!backend.extendedCapabilities.contains(.trustedSignInAssessment))
    }
}
