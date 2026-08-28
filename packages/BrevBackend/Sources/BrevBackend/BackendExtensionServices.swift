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

/// Marker for optional provider services that sit beside core mail.
///
/// Views should ask for these only after checking a matching capability
/// or `BackendFeature` support state.
public protocol BackendExtensionService: Sendable {}

public protocol AutoReplyManaging: BackendExtensionService {
    func vacationResponderSettings(
        for sourceID: MailSourceID
    ) async throws -> [VacationResponderSettings]

    func saveVacationResponder(
        _ draft: VacationResponderDraft,
        sourceID: MailSourceID
    ) async throws -> VacationResponderSettings

    func deleteVacationResponder(id: String, sourceID: MailSourceID) async throws
    func resetVacationResponderCounter(id: String, sourceID: MailSourceID) async throws
}

public protocol ServerRuleManaging: BackendExtensionService {
    func serverRules(for sourceID: MailSourceID) async throws -> [ServerRule]
    func saveServerRule(_ rule: ServerRule, sourceID: MailSourceID) async throws -> ServerRule
    func deleteServerRule(id: String, sourceID: MailSourceID) async throws
    func reorderServerRules(ids: [String], sourceID: MailSourceID) async throws
}

/// Syncs Brev's local rules to a Brev-owned server-side Sieve script.
///
/// This is intentionally narrower than `ServerRuleManaging`: ManageSieve does
/// not imply Brev can safely list, edit, or reorder arbitrary server scripts.
/// Callers invoke this only after a user action and a matching `.manageSieve`
/// capability, per ADR-0032.
public protocol ManageSieveRuleSyncing: BackendExtensionService {
    func syncLocalRulesToServer(
        _ rules: [ServerRule],
        sourceID: MailSourceID,
        scriptName: String
    ) async throws -> SieveScriptPlan
}

public extension ManageSieveRuleSyncing {
    func syncLocalRulesToServer(
        _ rules: [ServerRule],
        sourceID: MailSourceID
    ) async throws -> SieveScriptPlan {
        try await syncLocalRulesToServer(
            rules,
            sourceID: sourceID,
            scriptName: "brev-rules"
        )
    }
}

public struct ContactLookupQuery: Sendable, Hashable, Codable {
    public let text: String
    public let sourceID: MailSourceID
    public let limit: Int

    public init(text: String, sourceID: MailSourceID, limit: Int = 8) {
        self.text = text
        self.sourceID = sourceID
        self.limit = limit
    }
}

public struct ContactLookupResult: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let displayName: String?
    public let email: String
    public let sourceID: MailSourceID

    public init(
        id: String,
        displayName: String? = nil,
        email: String,
        sourceID: MailSourceID
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.sourceID = sourceID
    }
}

public protocol ContactLookupProviding: BackendExtensionService {
    func contacts(matching query: ContactLookupQuery) async throws -> [ContactLookupResult]
}

public protocol CachedMessageHeaderProviding: BackendExtensionService {
    func cachedMessageHeader(
        messageID: MessageHeader.ID,
        folderID: Folder.ID
    ) async -> MessageHeader?
}

/// Adds or removes provider labels on messages. Offered only by backends that
/// advertise `BackendCapabilities.labels` (Gmail `X-GM-LABELS` over IMAP);
/// views resolve it through `MailBackend.extensionService(_:)` and never
/// branch on the backend type (ADR-0028 invariant 2).
public protocol MessageLabelManaging: BackendExtensionService {
    /// Applies (`isEnabled == true`) or removes `labels` on `messageIDs`.
    /// `MessageHeader.labels` on cached headers is updated in place.
    func setLabels(
        _ labels: [String],
        isEnabled: Bool,
        for messageIDs: [MessageHeader.ID],
        sourceID: MailSourceID?
    ) async throws
}

public struct MailImportSummary: Sendable, Hashable, Codable {
    public let importedCount: Int
    public let errors: [String]

    public init(importedCount: Int, errors: [String] = []) {
        self.importedCount = importedCount
        self.errors = errors
    }
}

public protocol MailImporting: BackendExtensionService {
    func importMessages(_ messages: [ImportedMessage], into folder: Folder) async throws -> MailImportSummary
}

public protocol SyncHealthReporting: BackendExtensionService {
    func syncHealth(for sourceID: MailSourceID) async -> AccountSyncHealth
}

public protocol SyncConflictReviewing: BackendExtensionService {
    func syncConflicts(for sourceID: MailSourceID) async throws -> [MutationConflict]
}

public protocol SyncHealthRepairing: BackendExtensionService {
    func retrySync(for sourceID: MailSourceID) async throws
    func retryConflict(id: UUID, sourceID: MailSourceID) async throws
    func rebuildSearchIndex(for sourceID: MailSourceID) async throws
    func resetLocalCacheAndIndex(for sourceID: MailSourceID) async throws
    func clearSyncConflicts(for sourceID: MailSourceID) async throws
}

public protocol MailboxBackgroundRefreshing: BackendExtensionService {
    func refreshMailbox(for sourceID: MailSourceID) async throws
}

/// Exposes the per-conflict replay conflict list and lets the user dismiss
/// individual conflicts or all at once.
///
/// Backends that track `MutationConflict` records should implement this so
/// the Settings sync-health panel can show actionable details instead of
/// only a raw count. See ADR-0022.
public protocol SyncConflictManaging: BackendExtensionService {
    /// Returns all undismissed replay conflicts for `sourceID` in
    /// descending detection order (newest first).
    func replayConflicts(for sourceID: MailSourceID) async -> [ReplayConflict]
    /// Removes the conflict with `id` from the stored list. Decrements
    /// the conflict count returned by `SyncHealthReporting.syncHealth`.
    func dismissConflict(id: UUID, sourceID: MailSourceID) async
    /// Clears all conflicts for `sourceID`. Equivalent to the existing
    /// bulk "Clear reviewed conflicts" action.
    func dismissAllConflicts(for sourceID: MailSourceID) async
}

/// Exposes the outbox queue of pending offline mutations and lets the user
/// view, retry, and discard them individually or all at once.
///
/// Backends that queue mutations while offline should implement this so the
/// sidebar outbox row and outbox sheet can show actionable pending changes.
/// See ADR-0022.
public protocol OutboxManaging: BackendExtensionService {
    /// Returns all pending mutations in insertion order.
    func pendingMutations() async -> [PendingMutation]
    /// Removes the mutation with `id` from the queue. No-op if absent.
    func discardMutation(id: UUID) async
    /// Removes all pending mutations.
    func discardAllMutations() async
}

/// A draft queued for scheduled ("send later") delivery.
public struct PendingScheduledSend: Sendable, Hashable {
    /// The staged draft that will be sent.
    public let draftID: String
    /// When the draft is due to be sent.
    public let scheduledFor: Date

    public init(draftID: String, scheduledFor: Date) {
        self.draftID = draftID
        self.scheduledFor = scheduledFor
    }
}

/// Exposes the queue of scheduled ("send later") drafts.
///
/// Scheduled delivery only runs while the app process is alive: backends
/// deliver due drafts from an in-app poller and on reconnect. The app uses
/// this service to warn before quitting with pending sends and to flush
/// overdue sends from a background-refresh window.
public protocol ScheduledSendManaging: BackendExtensionService {
    /// Returns every draft still waiting for scheduled delivery, including
    /// overdue ones that have not yet been sent.
    func pendingScheduledSends() -> [PendingScheduledSend]
    /// Delivers every scheduled draft whose due date has passed. Safe to call
    /// concurrently with the backend's own poller; retryable failures stay
    /// queued, while ambiguous SMTP deliveries become surfaced conflicts and
    /// are never retried automatically.
    func deliverDueScheduledSends() async
}

/// Exposes the minimum account information needed to configure a CardDAV contact
/// sync. Implemented by backends that carry OAuth2 credentials and have a known
/// principal email address.
public protocol CardDAVContactSyncSupporting: AnyObject, Sendable {
    /// The account email address used to derive the CardDAV principal URL.
    var emailAddressForCardDAV: String { get }
    /// The current OAuth2 bearer token, or `nil` for non-OAuth accounts.
    var bearerTokenForCardDAV: String? { get }
    /// Injects the synced contact lookup provider once CardDAV is ready.
    func setContactLookupProvider(_ provider: (any ContactLookupProviding)?)
}
