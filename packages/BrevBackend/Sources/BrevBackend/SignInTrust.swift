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
    /// Neither an aligned `dkim=pass` nor an aligned `spf=pass` result was present in the top-most header.
    case missingAlignedMechanism
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

    /// Re-assesses a message whose fresh delivery was already verified by Brev before a process
    /// restart, preserving Inbox, freshness window, and authentication alignment checks while
    /// avoiding treating arbitrary reconnect backfill as fresh.
    func signInTrustAssessmentForDeliveredNotification(for messageID: String) async -> SignInTrustAssessment
}

public extension SignInTrustAssessing {
    func signInTrustAssessmentForDeliveredNotification(for messageID: String) async -> SignInTrustAssessment {
        await signInTrustAssessment(for: messageID)
    }
}

/// Bounded in-memory registry of freshly delivered message IDs observed during
/// the active remote session. Entries expire after 10 minutes and never persist.
final class SignInFreshDeliveryRegistry: @unchecked Sendable {
    private struct Entry {
        let id: String
        let observedAt: Date
        let messageDate: Date?
    }

    private let now: @Sendable () -> Date
    private let lifetime: TimeInterval
    private let capacity: Int
    private let lock = NSLock()
    private var entries: [Entry] = []

    init(
        now: @escaping @Sendable () -> Date = { Date() },
        lifetime: TimeInterval = 600,
        capacity: Int = 200
    ) {
        self.now = now
        self.lifetime = lifetime
        self.capacity = capacity
    }

    /// Records freshly delivered message IDs with their optional message dates.
    func record(_ idsWithDates: [(id: String, messageDate: Date?)]) {
        guard !idsWithDates.isEmpty else { return }
        lock.withLock {
            let observedAt = now()
            pruneExpired(at: observedAt)
            for item in idsWithDates.sorted(by: { $0.id < $1.id })
                where !entries.contains(where: { $0.id == item.id }) {
                entries.append(Entry(id: item.id, observedAt: observedAt, messageDate: item.messageDate))
            }
            while entries.count > capacity {
                entries.removeFirst()
            }
        }
    }

    /// Returns whether `id` is an unexpired fresh delivery in this session.
    func contains(_ id: String) -> Bool {
        lock.withLock {
            pruneExpired(at: now())
            return entries.contains { $0.id == id }
        }
    }

    /// Returns the recorded message date for an unexpired fresh delivery, if any.
    func messageDate(for id: String) -> Date? {
        lock.withLock {
            pruneExpired(at: now())
            return entries.first { $0.id == id }?.messageDate
        }
    }

    /// Clears all fresh-delivery provenance when a connection ends.
    func removeAll() {
        lock.withLock { entries.removeAll() }
    }

    private func pruneExpired(at instant: Date) {
        entries.removeAll { instant.timeIntervalSince($0.observedAt) >= lifetime }
    }
}
