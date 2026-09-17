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

/// One exclusively claimed delivery with frozen content and a durable attempt identity.
public struct GmailScheduledSendAttempt: Sendable {
    /// Immutable submitted draft.
    public let draft: Draft
    /// Frozen UTF-8 MIME with original attachment content.
    public let rawMIME: Data
    /// Compare-and-update token, preventing stale acknowledgements from altering a newer attempt.
    public let attemptID: String
    /// Claimed attempt number for bounded retry backoff.
    public let attemptCount: Int
}

/// Durable scheduling intent and compare-and-update delivery state, independent of autosave.
public protocol GmailScheduledSendStore: Sendable {
    /// Returns metadata only, scoped to the owning account.
    func scheduledSends(accountID: String) async throws -> [PendingScheduledSend]
    /// Atomically persists explicit scheduling intent and complete submitted MIME.
    func enqueueScheduledSend(_ draft: Draft, rawMIME: Data, accountID: String) async throws
    /// Reads the submitted draft, independent of autosave.
    func scheduledDraft(accountID: String, draftID: String) async throws -> Draft?
    /// Exclusively claims an eligible row before making a provider request.
    func claimScheduledSend(accountID: String, draftID: String, now: Date, ownerID: String) async throws
        -> GmailScheduledSendAttempt?
    /// Finishes a matching claim and returns whether unchanged provider-draft content may be deleted.
    func completeScheduledSend(accountID: String, draftID: String, attemptID: String) async throws -> Bool
    /// Records a failure; nil retryAt holds the message for explicit review.
    func failScheduledSend(accountID: String, draftID: String, attemptID: String, message: String,
                           retryAt: Date?) async throws
    /// Holds interrupted requests for review rather than expiring them into duplicate sends.
    /// The nonblocking owner lookup runs inside the database write transaction and must not call this store.
    func recoverInterruptedScheduledSends(accountID: String, activeOwnerIDs: @Sendable () -> Set<String>) async throws
    /// Removes intent while retaining the latest editable draft; rejects active delivery.
    func cancelScheduledSend(accountID: String, draftID: String) async throws -> Draft
    /// Changes the date; allowReview is true only after explicit uncertain-delivery review.
    func rescheduleSend(accountID: String, draftID: String, date: Date, allowReview: Bool) async throws
}

/// Errors that leave submitted scheduling intent intact for review.
public enum GmailScheduledSendError: Error, LocalizedError {
    case invalidSchedule, inFlight, notFound

    public var errorDescription: String? {
        switch self {
        case .invalidSchedule: String(localized: "Choose a valid send date and complete message content.", bundle: .module)
        case .inFlight: String(localized: "This scheduled message is being delivered or needs review in Outbox.", bundle: .module)
        case .notFound: String(localized: "This scheduled message is no longer in Outbox.", bundle: .module)
        }
    }
}

/// Concurrent refresh/poller requests join the same delivery pass.
actor GmailScheduledDeliveryDriver {
    private var task: Task<Void, Never>?
    private var taskID: UUID?

    func run(_ operation: @escaping @Sendable () async -> Void) async {
        if let task { await task.value; return }
        let id = UUID()
        let work = Task { await operation() }
        taskID = id
        task = work
        await work.value
        if taskID == id { task = nil; taskID = nil }
    }

    func cancel() { task?.cancel() }
}

enum GmailScheduledRetryPolicy {
    static func retryDate(for error: Error, attempt: Int, now: Date) -> Date? {
        guard attempt < 10, let error = error as? GmailAPIError else { return nil }
        let providerDelay: TimeInterval?
        switch error {
        case .missingAccessToken, .reauthenticationRequired: providerDelay = nil
        case .quotaExceeded(_, let delay), .retryable(429, let delay): providerDelay = delay
        default: return nil // No proof of non-delivery: never retry a timeout/5xx/unknown outcome automatically.
        }
        let backoff = min(3600, 60 * pow(2, Double(min(max(0, attempt - 1), 6))))
        let delay = providerDelay.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 0
        return now.addingTimeInterval(max(backoff, delay))
    }
}

/// Weak process-local ownership distinguishes a live sibling backend from an interrupted process.
final class GmailScheduledSession: Sendable {
    let id = UUID().uuidString
}

final class GmailScheduledSessionRegistry: @unchecked Sendable {
    static let shared = GmailScheduledSessionRegistry()
    private final class WeakSession {
        weak var value: GmailScheduledSession?
        init(_ value: GmailScheduledSession) { self.value = value }
    }

    private let lock = NSLock()
    private var accounts: [String: [String: WeakSession]] = [:]

    func register(accountID: String) -> GmailScheduledSession {
        lock.withLock {
            let session = GmailScheduledSession()
            accounts[accountID, default: [:]][session.id] = WeakSession(session)
            return session
        }
    }

    func retire(_ session: GmailScheduledSession, accountID: String) {
        lock.withLock {
            accounts[accountID]?[session.id] = nil
            if accounts[accountID]?.isEmpty == true { accounts[accountID] = nil }
        }
    }

    func activeIDs(accountID: String) -> Set<String> {
        lock.withLock {
            let live = (accounts[accountID] ?? [:]).filter { $0.value.value != nil }
            accounts[accountID] = live.isEmpty ? nil : live
            return Set(live.keys)
        }
    }
}

enum GmailScheduledMIME {
    static func source(_ data: Data, sentAt: Date) throws -> String {
        guard let source = String(data: data, encoding: .utf8), let separator = source.range(of: "\r\n\r\n") else {
            throw GmailScheduledSendError.invalidSchedule
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss '+0000'"
        var headers = source[..<separator.lowerBound].components(separatedBy: "\r\n")
        let dateHeader = "Date: " + formatter.string(from: sentAt)
        if let index = headers.firstIndex(where: { $0.lowercased().hasPrefix("date:") }) { headers[index] = dateHeader }
        else { headers.append(dateHeader) }
        return headers.joined(separator: "\r\n") + "\r\n\r\n" + source[separator.upperBound...]
    }
}
