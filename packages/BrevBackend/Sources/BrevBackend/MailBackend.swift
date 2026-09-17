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

/// Provider-neutral marker for authentication/setup errors that may be
/// retried through a standards IMAP/XOAUTH2 connector when native APIs are
/// unavailable or administrator-blocked.
public protocol IMAPFallbackEligibleError: Error, Sendable {
    var isIMAPFallbackEligible: Bool { get }
}

/// Errors a `MailBackend` may throw. Backends translate provider-specific
/// failure modes onto these so the view layer doesn't grow
/// provider-specific error handling. Anything that doesn't fit becomes
/// `.backendSpecific` with an underlying error for logging.
public enum MailBackendError: Error, Sendable {
    case notConnected
    case authenticationRequired
    case notSupported(BackendCapabilities)
    case notFound(id: String)
    case permissionDenied(message: String)
    case quotaExceeded
    case rateLimited(retryAfter: TimeInterval?)
    case network(underlying: String)
    /// The credential store can't be read right now (e.g. the system Keychain
    /// is locked before first unlock at launch). Distinct from
    /// `authenticationRequired` so callers retry instead of forcing re-sign-in.
    case credentialStoreUnavailable
    case backendSpecific(message: String)
}

/// Validation failures for a draft that must be fixed before sending.
public enum DraftValidationError: Error, LocalizedError, Sendable, Equatable {
    /// The draft has no To, Cc, or Bcc recipients.
    case missingRecipients

    public var errorDescription: String? {
        switch self {
        case .missingRecipients:
            String(localized: "Add at least one recipient.", bundle: .module)
        }
    }
}

extension MailBackendError: LocalizedError {
    public var isNetwork: Bool {
        if case .network = self { return true }
        return false
    }

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            String(localized: "Mail backend is not connected.", bundle: .module)
        case .authenticationRequired:
            String(localized: "Sign in again to continue.", bundle: .module)
        case .notSupported:
            String(localized: "This mail backend doesn't support that action.", bundle: .module)
        case .notFound(let id):
            String(localized: "Couldn't find \(id).", bundle: .module)
        case .permissionDenied(let message):
            message
        case .quotaExceeded:
            String(localized: "Mailbox quota exceeded.", bundle: .module)
        case .rateLimited(let retryAfter):
            if let retryAfter {
                String(localized: "Rate limited. Try again in \(Int(retryAfter.rounded())) seconds.", bundle: .module)
            } else {
                String(localized: "Rate limited. Try again later.", bundle: .module)
            }
        case .network(let underlying):
            String(localized: "Network error: \(underlying)", bundle: .module)
        case .credentialStoreUnavailable:
            String(
                localized: "Couldn't read your saved sign-in yet (Keychain is locked). Try again in a moment.",
                bundle: .module
            )
        case .backendSpecific(let message):
            message
        }
    }
}

/// The surface every Brev backend exposes to the view layer.
///
/// View code (`apps/*`, `packages/BrevDesign/...`, future view-models)
/// always talks to this protocol — never to a concrete backend, never
/// to a Realm `Object`. See ADR-0001 and ADR-0028 invariants 1 / 2 / 5.
///
/// Implementations are reference types (`AnyObject`) so connection
/// state can be mutated internally. They are `Sendable` so view-models
/// can hold them across actors; the protocol contract is that all
/// mutating internal state is serialized inside the implementation.
public protocol MailBackend: AnyObject, Sendable {
    /// The account this backend is bound to. One backend instance per
    /// account; switching accounts means switching backends.
    var account: BrevAccount { get }

    /// What this backend supports. View code branches on capabilities,
    /// not on the concrete type.
    var capabilities: BackendCapabilities { get }

    /// Capability flags that overflow the fully-allocated 32-bit `capabilities`
    /// set. Defaults to empty; backends override to advertise extended
    /// features. See `BackendExtendedCapabilities` and ADR-0045.
    var extendedCapabilities: BackendExtendedCapabilities { get }

    // MARK: Lifecycle

    /// Open the connection — sign in, refresh tokens, prime any local
    /// cache. Throws `.authenticationRequired` if the user needs to
    /// re-auth.
    func connect() async throws

    /// Tear down the connection. Idempotent.
    func disconnect() async

    /// Replay any mutations that were queued while the device was offline.
    ///
    /// Call this when network connectivity is restored. Backends that do not
    /// support offline mutation queuing provide a default no-op.
    func replayOfflineMutations() async

    // MARK: Mailboxes

    /// All mailboxes this account exposes.
    func mailboxes() async throws -> [Mailbox]

    /// The currently active mailbox.
    func currentMailbox() async throws -> Mailbox

    /// Switch the active mailbox.
    func switchMailbox(id: String) async throws

    // MARK: Folders

    /// All folders the user can see, with current counts. The order is
    /// backend-defined; view code is responsible for sorting / nesting.
    func folders() async throws -> [Folder]

    /// Force a refresh of one folder's metadata + recent messages.
    func refresh(folder: Folder) async throws

    /// Create a folder. `parentID` is optional; `nil` creates a
    /// top-level custom folder.
    func createFolder(name: String, parentID: Folder.ID?) async throws -> Folder

    /// Rename an existing folder and return the updated folder.
    func renameFolder(id: Folder.ID, name: String) async throws -> Folder

    /// Delete a folder.
    func deleteFolder(id: Folder.ID) async throws

    /// Purge all messages from a folder (for example empty Trash/Spam).
    func flushFolder(id: Folder.ID) async throws

    /// Apply an offline-retention window to a folder's local cache by
    /// evicting message bodies that fall outside it. `retentionDays == nil`
    /// means no age cutoff; `keepsBodies == false` drops every cached body
    /// (Headers-only). Headers are preserved. Backends without a local body
    /// cache no-op. Plain `Int?`/`Bool` are used (not the BrevSettings enum)
    /// so this layer needs no dependency on the settings package.
    func applyRetention(folderID: Folder.ID, retentionDays: Int?, keepsBodies: Bool) async

    /// As `applyRetention(folderID:retentionDays:keepsBodies:)`, but never evicts a
    /// body whose message ID is in `keepingMessageIDs` — the per-message
    /// "keep offline" pins (#268). The default forwards to the pin-unaware sweep
    /// (ignoring pins); backends with a body cache override to honour them.
    func applyRetention(
        folderID: Folder.ID,
        retentionDays: Int?,
        keepsBodies: Bool,
        keepingMessageIDs: Set<MessageHeader.ID>
    ) async

    // MARK: Messages

    /// Headers for a single folder, sorted newest-first. `pageToken` is
    /// opaque; `nil` requests the first page. Returns the next page
    /// token (or `nil` when the folder is exhausted).
    func messages(in folder: Folder, pageToken: String?) async throws
        -> (headers: [MessageHeader], nextPageToken: String?)

    /// Like `messages(in:pageToken:)` but does NOT mark the folder as the
    /// active folder for live (IDLE) watching. Use for bulk or background
    /// enumeration — local rules, import/export — that must not hijack the
    /// folder the user is currently viewing.
    func enumerateMessages(in folder: Folder, pageToken: String?) async throws
        -> (headers: [MessageHeader], nextPageToken: String?)

    /// Full body for one message — HTML, plain text, attachment list.
    func body(for messageID: String) async throws -> MessageBody

    /// The message's raw RFC822 source. Cache-first: returns the cached source
    /// when present, otherwise fetches it over the existing connection and
    /// caches it — the same posture as `body(for:)`. Capability-gated by
    /// `BackendExtendedCapabilities.rawMessageSource`. See ADR-0045.
    func rawSource(for messageID: String) async throws -> String

    /// Download the bytes for an attachment. Backends without a
    /// dedicated download endpoint may throw `.notSupported`.
    func downloadAttachment(_ attachment: Attachment) async throws -> Data

    /// Toggle the read / unread flag.
    func setRead(_ isRead: Bool, for messageIDs: [String]) async throws

    /// Toggle the message flag.
    func setFlagged(_ isFlagged: Bool, for messageIDs: [String]) async throws

    /// Set (or clear, when `color` is `nil`) the flag color for messages.
    ///
    /// Capability-gated by `.flagColors` and surfaced through
    /// `BackendFeature.flagColors`. A non-nil color implies the message
    /// becomes flagged. Providers that can persist color (JMAP, IMAP with
    /// custom keywords) round-trip it as Apple-compatible keywords;
    /// providers that expose only a boolean flag set the boolean and
    /// store the color in Brev's local store. See ADR-0019.
    func setFlagColor(_ color: FlagColor?, for messageIDs: [String]) async throws

    /// Move messages between folders.
    func move(messageIDs: [String], to folder: Folder) async throws

    /// Copy messages into a folder, leaving the originals in place. Mirrors
    /// `move`. Capability-gated by `BackendExtendedCapabilities.messageCopy`.
    /// See ADR-0045.
    func copy(messageIDs: [String], to folder: Folder) async throws

    /// Delete messages. Implementations decide trash-vs-permanent based
    /// on the source folder.
    func delete(messageIDs: [String]) async throws

    // MARK: Drafts / send

    /// Persist a draft remotely (if supported) or just locally.
    func save(draft: Draft) async throws -> Draft

    /// Upload an attachment for the given draft. Returns the
    /// backend-assigned attachment ID to include in `Draft.attachmentIDs`.
    func uploadAttachment(draftID: String, data: Data, filename: String, mimeType: String) async throws -> String

    /// Stage an inline image for the given draft and return its attachment ID.
    ///
    /// Unlike `uploadAttachment`, inline images are kept in-memory for the
    /// compose session; they are emitted as `multipart/related` parts during
    /// MIME construction. The returned ID must be included in
    /// `Draft.attachmentIDs` so `stagedAttachments(for:)` finds them at send
    /// time.
    ///
    /// - Parameters:
    ///   - draftID: The draft that owns this image.
    ///   - contentID: The RFC 2392 Content-ID (no angle brackets) used in
    ///     the `<img src="cid:…">` reference in the HTML body.
    ///   - filename: A display filename for the attachment part.
    ///   - mimeType: The image MIME type (e.g. `image/png`).
    ///   - data: The raw image bytes.
    /// - Returns: A backend-assigned attachment ID.
    func stageInlineAttachment(
        draftID: String,
        contentID: String,
        filename: String,
        mimeType: String,
        data: Data
    ) async throws -> String

    /// Discard a draft.
    func discard(draftID: String) async throws

    /// Send a draft. Returns the resulting message id (or scheduled
    /// time, if the draft had `scheduledFor` set) plus non-fatal
    /// warnings for follow-up work that must not retry delivery.
    func send(draft: Draft) async throws -> SendResult

    // MARK: Aliases and server signatures — capability-gated

    /// Returns the server-side sender aliases for this account.
    ///
    /// Capability-gated by `BackendExtendedCapabilities.serverAliases`.
    /// Backends without the capability must throw `.notSupported`.
    func listAliases() async throws -> [ServerAlias]

    /// Returns the server-side signatures or signature templates.
    ///
    /// Capability-gated by `BackendExtendedCapabilities.serverSignatures`.
    /// Backends without the capability must throw `.notSupported`.
    func listServerSignatures() async throws -> [ServerSignature]

    // MARK: Junk / sender safety — capability-gated

    /// Mark messages as junk (isJunk = true) or not-junk (isJunk = false).
    ///
    /// Capability-gated by `.junkAPI`. Backends without the capability
    /// should throw `.notSupported`; the UI falls back to a folder-move
    /// to the spam folder via `move(messageIDs:to:)`.
    func setJunk(_ isJunk: Bool, for messageIDs: [String]) async throws

    /// Block the sender of a message via the provider's block list.
    ///
    /// Capability-gated by `.blockSender`. Messages from the blocked
    /// address are expected to land in the spam/junk folder after this
    /// call. View code must gate the action on the capability flag and
    /// display a confirmatory UI before calling.
    func blockSender(email: String) async throws

    // MARK: Search

    /// Search across folders. Backends with `.serverSideSearch` should
    /// hit their search endpoint; others scan a local index.
    func search(_ query: SearchQuery) async throws -> [MessageHeader]

    /// All locally cached headers for one folder, without connecting, fetching,
    /// or applying ordinary search result limits. Used by local condition evaluators.
    func cachedMessageHeaders(in folder: Folder, sourceID: MailSourceID) async throws -> [MessageHeader]

    // MARK: Cached attachment enumeration

    /// Returns attachment-bearing messages already present in Brev's local
    /// cache for the given folders, for the All Attachments view (#259/#264).
    ///
    /// Read-only and cache-only: implementations MUST NOT connect, fetch
    /// bodies, or download attachment bytes (ADR-0006, ADR-0041, ADR-0044).
    /// Folders or messages that are not cached are simply omitted; messages
    /// without attachments are excluded. Backends without a local body cache
    /// return an empty array via the default implementation, so any backend
    /// that gains a cache must override this to surface its attachments.
    func cachedAttachmentMessages(in folders: [Folder]) async -> [CachedAttachmentMessage]

    /// Source-scoped variant of `cachedAttachmentMessages(in:)`. Lets callers
    /// address a specific account/mailbox without relying on mutable active
    /// mailbox state. Same read-only, cache-only contract.
    func cachedAttachmentMessages(
        in folders: [Folder],
        sourceID: MailSourceID
    ) async -> [CachedAttachmentMessage]

    // MARK: Calendar — capability-gated

    /// Render an `ICS` attachment into a structured event. Backends
    /// without `.serverSideIcsRender` parse client-side.
    func calendarEvent(from attachmentID: String) async throws -> CalendarEvent

    /// Reply to a calendar invite. Backends with
    /// `.serverSideCalendarReply` POST the response to their server;
    /// others compose and send an iMIP REPLY.
    func replyToCalendarInvite(messageID: String, response: AttendeeState) async throws

    // MARK: Change stream

    /// A bounded async stream of coarse change events. Cancelling the
    /// stream releases backend resources; multiple subscribers are
    /// supported by the implementation choosing whether to multiplex.
    func subscribeToChanges() -> AsyncStream<MailEvent>

    // MARK: Source-scoped operations

    /// Stable source identity for a mailbox exposed by this backend.
    func sourceID(for mailbox: Mailbox) -> MailSourceID

    /// Source-scoped variants let callers address multiple accounts
    /// and multiple mailboxes without relying on mutable active
    /// mailbox state.
    func folders(in sourceID: MailSourceID) async throws -> [Folder]
    func refresh(folder: Folder, in sourceID: MailSourceID) async throws
    func applyRetention(
        folderID: Folder.ID,
        sourceID: MailSourceID,
        retentionDays: Int?,
        keepsBodies: Bool
    ) async throws
    func createFolder(
        name: String,
        parentID: Folder.ID?,
        sourceID: MailSourceID
    ) async throws -> Folder
    func renameFolder(
        id: Folder.ID,
        name: String,
        sourceID: MailSourceID
    ) async throws -> Folder
    func deleteFolder(id: Folder.ID, sourceID: MailSourceID) async throws
    func flushFolder(id: Folder.ID, sourceID: MailSourceID) async throws
    func messages(
        in folder: Folder,
        sourceID: MailSourceID,
        pageToken: String?
    ) async throws -> (headers: [MessageHeader], nextPageToken: String?)
    func enumerateMessages(
        in folder: Folder,
        sourceID: MailSourceID,
        pageToken: String?
    ) async throws -> (headers: [MessageHeader], nextPageToken: String?)
    func body(for messageID: String, sourceID: MailSourceID) async throws -> MessageBody
    func rawSource(for messageID: String, sourceID: MailSourceID) async throws -> String
    func downloadAttachment(_ attachment: Attachment, sourceID: MailSourceID) async throws -> Data
    func setRead(_ isRead: Bool, for messageIDs: [String], sourceID: MailSourceID) async throws
    func setFlagged(_ isFlagged: Bool, for messageIDs: [String], sourceID: MailSourceID) async throws
    func setFlagColor(_ color: FlagColor?, for messageIDs: [String], sourceID: MailSourceID) async throws
    func move(messageIDs: [String], to folder: Folder, sourceID: MailSourceID) async throws
    func copy(messageIDs: [String], to folder: Folder, sourceID: MailSourceID) async throws
    func delete(messageIDs: [String], sourceID: MailSourceID) async throws
    func save(draft: Draft, sourceID: MailSourceID) async throws -> Draft
    func uploadAttachment(
        draftID: String,
        data: Data,
        filename: String,
        mimeType: String,
        sourceID: MailSourceID
    ) async throws -> String
    func stageInlineAttachment(
        draftID: String,
        contentID: String,
        filename: String,
        mimeType: String,
        data: Data,
        sourceID: MailSourceID
    ) async throws -> String
    func discard(draftID: String, sourceID: MailSourceID) async throws
    func send(draft: Draft, sourceID: MailSourceID) async throws -> SendResult
    func setJunk(_ isJunk: Bool, for messageIDs: [String], sourceID: MailSourceID) async throws
    func blockSender(email: String, sourceID: MailSourceID) async throws
    func search(_ query: SearchQuery, sourceID: MailSourceID) async throws -> [MessageHeader]
    func calendarEvent(from attachmentID: String, sourceID: MailSourceID) async throws -> CalendarEvent
    func replyToCalendarInvite(
        messageID: String,
        response: AttendeeState,
        sourceID: MailSourceID
    ) async throws

    // MARK: Optional provider extensions

    /// Optional provider services for features outside core mail.
    ///
    /// Call sites must still gate on `BackendFeature` support and must
    /// tolerate `nil`; unsupported providers should never be reached
    /// through concrete backend type checks.
    func extensionService<Service>(_ type: Service.Type) -> Service?

    /// Injects a contact lookup provider. No-op by default; override in
    /// backends that support contact lookup.
    func setContactLookupProvider(_ provider: (any ContactLookupProviding)?)
}

/// Default implementations so existing backends compile without
/// implementing new optional surface immediately. Concrete backends
/// that can satisfy the call should override.
public extension MailBackend {
    func replayOfflineMutations() async {}

    /// Backends without a header cache cannot enumerate saved-view candidates.
    func cachedMessageHeaders(in folder: Folder, sourceID: MailSourceID) async throws -> [MessageHeader] {
        throw MailBackendError.notSupported(capabilities)
    }

    /// Default: no local body cache to prune, so retention is a no-op.
    /// Backends with a body cache (IMAP) override to evict bodies.
    func applyRetention(folderID: Folder.ID, retentionDays: Int?, keepsBodies: Bool) async {
        _ = folderID
        _ = retentionDays
        _ = keepsBodies
    }

    /// Default: ignore the "keep offline" pins and run the standard sweep.
    /// Backends with a body cache (IMAP) override to exempt `keepingMessageIDs`.
    func applyRetention(
        folderID: Folder.ID,
        retentionDays: Int?,
        keepsBodies: Bool,
        keepingMessageIDs: Set<MessageHeader.ID>
    ) async {
        _ = keepingMessageIDs
        await applyRetention(folderID: folderID, retentionDays: retentionDays, keepsBodies: keepsBodies)
    }

    func createFolder(name: String, parentID: Folder.ID?) async throws -> Folder {
        _ = name
        _ = parentID
        throw MailBackendError.notSupported(.folderCreate)
    }

    func renameFolder(id: Folder.ID, name: String) async throws -> Folder {
        _ = id
        _ = name
        throw MailBackendError.notSupported(.folderRename)
    }

    func deleteFolder(id: Folder.ID) async throws {
        _ = id
        throw MailBackendError.notSupported(.folderDelete)
    }

    func flushFolder(id: Folder.ID) async throws {
        _ = id
        throw MailBackendError.notSupported(.folderFlush)
    }

    func setFlagColor(_ color: FlagColor?, for messageIDs: [String]) async throws {
        _ = color
        _ = messageIDs
        throw MailBackendError.notSupported(.flagColors)
    }

    func downloadAttachment(_ attachment: Attachment) async throws -> Data {
        _ = attachment
        throw MailBackendError.notSupported(capabilities)
    }

    func uploadAttachment(draftID: String, data: Data, filename: String, mimeType: String) async throws -> String {
        throw MailBackendError.notSupported(capabilities)
    }

    func stageInlineAttachment(
        draftID: String,
        contentID: String,
        filename: String,
        mimeType: String,
        data: Data
    ) async throws -> String {
        throw MailBackendError.notSupported(capabilities)
    }

    func listAliases() async throws -> [ServerAlias] {
        throw MailBackendError.notSupported(capabilities)
    }

    func listServerSignatures() async throws -> [ServerSignature] {
        throw MailBackendError.notSupported(capabilities)
    }

    func setJunk(_ isJunk: Bool, for messageIDs: [String]) async throws {
        _ = isJunk
        _ = messageIDs
        throw MailBackendError.notSupported(.junkAPI)
    }

    func blockSender(email: String) async throws {
        _ = email
        throw MailBackendError.notSupported(.blockSender)
    }

    var extendedCapabilities: BackendExtendedCapabilities { [] }

    /// Whether `MessageHeader.threadID` groups a conversation on this backend,
    /// however the grouping is produced. Threading UI branches on this rather
    /// than on either capability flag alone, so a server-threaded provider and
    /// a standards IMAP account behave identically (ADR-0020, ADR-0052).
    var groupsMessagesIntoThreads: Bool {
        capabilities.contains(.serverSideThreading)
            || extendedCapabilities.contains(.clientSideThreading)
    }

    func copy(messageIDs: [String], to folder: Folder) async throws {
        _ = messageIDs
        _ = folder
        throw MailBackendError.notSupported(capabilities)
    }

    func rawSource(for messageID: String) async throws -> String {
        _ = messageID
        throw MailBackendError.notSupported(capabilities)
    }

    /// Default: no local body cache, so there are no cached attachments to
    /// enumerate. Backends with a body cache (IMAP) override to read it.
    func cachedAttachmentMessages(in folders: [Folder]) async -> [CachedAttachmentMessage] {
        _ = folders
        return []
    }

    /// Default: ignore the source scope and defer to the single-account
    /// variant. Backends that can address multiple sources override both.
    func cachedAttachmentMessages(
        in folders: [Folder],
        sourceID: MailSourceID
    ) async -> [CachedAttachmentMessage] {
        _ = sourceID
        return await cachedAttachmentMessages(in: folders)
    }

    func extensionService<Service>(_ type: Service.Type) -> Service? {
        _ = type
        return nil
    }

    func setContactLookupProvider(_ provider: (any ContactLookupProviding)?) {
        _ = provider
    }

    /// All mailboxes this account exposes. Default: a single
    /// synthesized mailbox derived from the account.
    func mailboxes() async throws -> [Mailbox] {
        [
            Mailbox(
                id: account.id,
                email: account.emailAddress,
                displayName: account.displayName,
                isPrimary: true
            )
        ]
    }

    /// The currently active mailbox. Default: the first entry from
    /// `mailboxes()`.
    func currentMailbox() async throws -> Mailbox {
        let all = try await mailboxes()
        guard let first = all.first else {
            throw MailBackendError.notFound(id: account.id)
        }
        return first
    }

    /// Switch the active mailbox. Default: throws `.notSupported`.
    func switchMailbox(id: String) async throws {
        _ = id
        throw MailBackendError.notSupported(capabilities)
    }

    /// Stable source identity for a mailbox exposed by this backend.
    func sourceID(for mailbox: Mailbox) -> MailSourceID {
        MailSourceID(accountID: account.id, mailboxID: mailbox.id)
    }

    /// Source-scoped variants let callers address multiple accounts
    /// and multiple mailboxes without relying on mutable active
    /// mailbox state. Backends should override these when they can
    /// read a mailbox directly; the default preserves compatibility
    /// by switching to the requested mailbox first.
    func folders(in sourceID: MailSourceID) async throws -> [Folder] {
        try await selectSourceIfNeeded(sourceID)
        return try await folders()
    }

    func refresh(folder: Folder, in sourceID: MailSourceID) async throws {
        try await selectSourceIfNeeded(sourceID)
        try await refresh(folder: folder)
    }

    func applyRetention(
        folderID: Folder.ID,
        sourceID: MailSourceID,
        retentionDays: Int?,
        keepsBodies: Bool
    ) async throws {
        try await selectSourceIfNeeded(sourceID)
        await applyRetention(
            folderID: folderID,
            retentionDays: retentionDays,
            keepsBodies: keepsBodies
        )
    }

    /// Source-scoped pin-aware retention (#268): selects the source, then runs
    /// the sweep exempting `keepingMessageIDs`.
    func applyRetention(
        folderID: Folder.ID,
        sourceID: MailSourceID,
        retentionDays: Int?,
        keepsBodies: Bool,
        keepingMessageIDs: Set<MessageHeader.ID>
    ) async throws {
        try await selectSourceIfNeeded(sourceID)
        await applyRetention(
            folderID: folderID,
            retentionDays: retentionDays,
            keepsBodies: keepsBodies,
            keepingMessageIDs: keepingMessageIDs
        )
    }

    func createFolder(
        name: String,
        parentID: Folder.ID?,
        sourceID: MailSourceID
    ) async throws -> Folder {
        try await selectSourceIfNeeded(sourceID)
        return try await createFolder(name: name, parentID: parentID)
    }

    func renameFolder(
        id: Folder.ID,
        name: String,
        sourceID: MailSourceID
    ) async throws -> Folder {
        try await selectSourceIfNeeded(sourceID)
        return try await renameFolder(id: id, name: name)
    }

    func deleteFolder(id: Folder.ID, sourceID: MailSourceID) async throws {
        try await selectSourceIfNeeded(sourceID)
        try await deleteFolder(id: id)
    }

    func flushFolder(id: Folder.ID, sourceID: MailSourceID) async throws {
        try await selectSourceIfNeeded(sourceID)
        try await flushFolder(id: id)
    }

    func messages(
        in folder: Folder,
        sourceID: MailSourceID,
        pageToken: String?
    ) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        try await selectSourceIfNeeded(sourceID)
        return try await messages(in: folder, pageToken: pageToken)
    }

    /// Default forwards to `messages(in:pageToken:)`; backends with live folder
    /// tracking (IMAP IDLE) override to skip the active-folder side effect.
    func enumerateMessages(in folder: Folder, pageToken: String?) async throws
        -> (headers: [MessageHeader], nextPageToken: String?) {
        try await messages(in: folder, pageToken: pageToken)
    }

    func enumerateMessages(
        in folder: Folder,
        sourceID: MailSourceID,
        pageToken: String?
    ) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        try await selectSourceIfNeeded(sourceID)
        return try await enumerateMessages(in: folder, pageToken: pageToken)
    }

    func body(for messageID: String, sourceID: MailSourceID) async throws -> MessageBody {
        try await selectSourceIfNeeded(sourceID)
        return try await body(for: messageID)
    }

    func rawSource(for messageID: String, sourceID: MailSourceID) async throws -> String {
        try await selectSourceIfNeeded(sourceID)
        return try await rawSource(for: messageID)
    }

    func downloadAttachment(_ attachment: Attachment, sourceID: MailSourceID) async throws -> Data {
        try await selectSourceIfNeeded(sourceID)
        return try await downloadAttachment(attachment)
    }

    func setRead(_ isRead: Bool, for messageIDs: [String], sourceID: MailSourceID) async throws {
        try await selectSourceIfNeeded(sourceID)
        try await setRead(isRead, for: messageIDs)
    }

    func setFlagged(_ isFlagged: Bool, for messageIDs: [String], sourceID: MailSourceID) async throws {
        try await selectSourceIfNeeded(sourceID)
        try await setFlagged(isFlagged, for: messageIDs)
    }

    func setFlagColor(_ color: FlagColor?, for messageIDs: [String], sourceID: MailSourceID) async throws {
        try await selectSourceIfNeeded(sourceID)
        try await setFlagColor(color, for: messageIDs)
    }

    func move(messageIDs: [String], to folder: Folder, sourceID: MailSourceID) async throws {
        try await selectSourceIfNeeded(sourceID)
        try await move(messageIDs: messageIDs, to: folder)
    }

    func copy(messageIDs: [String], to folder: Folder, sourceID: MailSourceID) async throws {
        try await selectSourceIfNeeded(sourceID)
        try await copy(messageIDs: messageIDs, to: folder)
    }

    func delete(messageIDs: [String], sourceID: MailSourceID) async throws {
        try await selectSourceIfNeeded(sourceID)
        try await delete(messageIDs: messageIDs)
    }

    func save(draft: Draft, sourceID: MailSourceID) async throws -> Draft {
        try await selectSourceIfNeeded(sourceID)
        return try await save(draft: draft)
    }

    func uploadAttachment(
        draftID: String,
        data: Data,
        filename: String,
        mimeType: String,
        sourceID: MailSourceID
    ) async throws -> String {
        try await selectSourceIfNeeded(sourceID)
        return try await uploadAttachment(
            draftID: draftID,
            data: data,
            filename: filename,
            mimeType: mimeType
        )
    }

    func stageInlineAttachment(
        draftID: String,
        contentID: String,
        filename: String,
        mimeType: String,
        data: Data,
        sourceID: MailSourceID
    ) async throws -> String {
        try await selectSourceIfNeeded(sourceID)
        return try await stageInlineAttachment(
            draftID: draftID,
            contentID: contentID,
            filename: filename,
            mimeType: mimeType,
            data: data
        )
    }

    func discard(draftID: String, sourceID: MailSourceID) async throws {
        try await selectSourceIfNeeded(sourceID)
        try await discard(draftID: draftID)
    }

    func send(draft: Draft, sourceID: MailSourceID) async throws -> SendResult {
        try await selectSourceIfNeeded(sourceID)
        return try await send(draft: draft)
    }

    func setJunk(_ isJunk: Bool, for messageIDs: [String], sourceID: MailSourceID) async throws {
        try await selectSourceIfNeeded(sourceID)
        try await setJunk(isJunk, for: messageIDs)
    }

    func blockSender(email: String, sourceID: MailSourceID) async throws {
        try await selectSourceIfNeeded(sourceID)
        try await blockSender(email: email)
    }

    func search(_ query: SearchQuery, sourceID: MailSourceID) async throws -> [MessageHeader] {
        try await selectSourceIfNeeded(sourceID)
        return try await search(query)
    }

    func calendarEvent(from attachmentID: String, sourceID: MailSourceID) async throws -> CalendarEvent {
        try await selectSourceIfNeeded(sourceID)
        return try await calendarEvent(from: attachmentID)
    }

    func replyToCalendarInvite(
        messageID: String,
        response: AttendeeState,
        sourceID: MailSourceID
    ) async throws {
        try await selectSourceIfNeeded(sourceID)
        try await replyToCalendarInvite(messageID: messageID, response: response)
    }

    private func selectSourceIfNeeded(_ sourceID: MailSourceID) async throws {
        guard sourceID.accountID == account.id else {
            throw MailBackendError.notFound(id: sourceID.accountID)
        }
        if let current = try? await currentMailbox(),
           current.id == sourceID.mailboxID {
            return
        }
        try await switchMailbox(id: sourceID.mailboxID)
    }
}
