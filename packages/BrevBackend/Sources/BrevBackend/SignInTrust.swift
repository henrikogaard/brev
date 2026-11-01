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

/// Reason a sign-in trust assessment could not be produced (ADR-0088).
/// Every failure is closed: an unrecognized or unverifiable shape must
/// never be upgraded to a pass.
public enum SignInTrustFailure: String, Sendable, Equatable {
    /// The message did not arrive through a fresh provider delta.
    case notFreshDelivery
    /// The message is not located in the trusted inbox position.
    case wrongFolder
    /// The message's provider receive time is older than the trust window.
    case stale
    /// No top-level trusted authentication header was found.
    case noTrustedHeader
    /// Another authentication header also claims the trusted authserv-id.
    case conflictingTrustedHeaders
    /// The trusted header carries no `dmarc=` result.
    case missingDMARC
    /// The trusted header carries more than one `dmarc=` result.
    case duplicateDMARC
    /// The `dmarc=` result is not `pass`.
    case dmarcNotPass
    /// The DMARC-aligned domain does not match the single `From` address.
    case fromMismatch
    /// The message does not have exactly one `From` header with one address.
    case malformedFrom
    /// The trusted authentication header cannot be parsed.
    case malformedHeader
    /// The account's provider does not support trusted sign-in assessment.
    case unsupportedAccount
}

/// Outcome of a trusted sign-in assessment (ADR-0088). Only the aligned
/// From domain crosses the backend seam; raw header values never do.
public enum SignInTrustAssessment: Sendable, Equatable {
    /// The message passed the scoped trust rule; `fromDomain` is the
    /// DMARC-aligned sender domain, lowercased.
    case pass(fromDomain: String)
    /// The message could not be assessed and must not be trusted.
    case unavailable(SignInTrustFailure)
}

/// Assesses whether a message is a trusted fresh sign-in delivery
/// (ADR-0088). Implemented by provider backends that can prove the
/// transport provenance of a message; reachable from tests only until the
/// ADR-0088 E1-E5 evidence is recorded and the capability is enabled.
public protocol SignInTrustAssessing: Sendable {
    /// Returns the trust assessment for one cached provider message.
    /// - Parameter messageID: the backend's stable message identifier.
    func signInTrustAssessment(for messageID: String) async -> SignInTrustAssessment
}
