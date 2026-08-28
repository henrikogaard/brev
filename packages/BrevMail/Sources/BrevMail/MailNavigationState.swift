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
import BrevSettings
import Foundation
import Observation

/// Top-level mutable navigation state shared by the mail UI.
///
/// One instance per scene. Holds the selected folder, the selected
/// message (within that folder), the current search query, and any
/// presented sheet. Views observe this directly via `@Bindable`.
///
/// `@Observable` requires iOS 17 / macOS 14, which Brev targets
/// (ADR-0004). No Combine, no `@StateObject`.
@Observable
@MainActor
public final class MailNavigationState {
    public nonisolated static let unifiedInboxFolderID = "__brev_unified_inbox"
    public nonisolated static let todaySmartViewFolderID = "__brev_smart_today"
    public nonisolated static let flaggedSmartViewFolderID = "__brev_smart_flagged"
    public nonisolated static let snoozedSmartViewFolderID = "__brev_smart_snoozed"
    public nonisolated static let doneSmartViewFolderID = "__brev_smart_done"
    public nonisolated static let vipSmartViewFolderID = "__brev_smart_vip"
    public nonisolated static let allAttachmentsSmartViewFolderID = "__brev_smart_all_attachments"
    private static let savedSearchFolderIDPrefix = "__brev_saved_search_"

    public enum Sheet: Hashable, Sendable {
        case themePicker
        case compose
        case profiles
        case mailboxAssistant
        /// Pending offline mutations (outbox) — retry or discard.
        case outbox
        /// Editable system task handoff for a message.
        case createTask(header: MessageHeader, sourceID: MailSourceID?)
        /// Prefilled local-rule editor seeded from a message.
        case createRule(header: MessageHeader, sourceID: MailSourceID?)
        /// Prefilled calendar-event editor seeded from a message.
        case createMeeting(header: MessageHeader, sourceID: MailSourceID?)
        /// Local note editor for a message.
        case messageNote(header: MessageHeader, sourceID: MailSourceID?)
        /// Local follow-up reminder picker for a message.
        case followUp(header: MessageHeader, sourceID: MailSourceID?)
        /// Move-to quick chooser for the given message IDs.
        case moveTo(messageIDs: [String], sourceID: MailSourceID?, currentFolderID: Folder.ID?)
        /// Copy-to quick chooser for the given message IDs.
        case copyTo(messageIDs: [String], sourceID: MailSourceID?, currentFolderID: Folder.ID?)
        /// Read-only metadata inspector for a single message.
        case messageProperties(header: MessageHeader)
        /// Read-only raw RFC 822 source viewer for a single message.
        case viewSource(header: MessageHeader, sourceID: MailSourceID?)
        /// Read-only header block viewer for a single message.
        case showHeaders(header: MessageHeader, sourceID: MailSourceID?)
    }

    /// The currently selected account/mailbox source. Folder and
    /// message identifiers are only unique within this scope.
    public var selectedSourceID: MailSourceID?

    /// The currently selected folder, or `nil` while folders load.
    public var selectedFolderID: Folder.ID?

    /// The currently selected message in the selected folder, or `nil`
    /// while nothing is open in the reading pane.
    public var selectedMessageID: MessageHeader.ID?

    /// Search query bound to the message list search field. Empty string
    /// means "no filter".
    public var searchText: String

    /// Incremented when a menu command or shortcut asks the message list
    /// search field to take focus. The field observes the counter rather than
    /// a boolean so repeated requests re-focus even when it is already first
    /// responder.
    public var searchFocusRequestID = 0

    /// Quick-filter selection for the visible message list.
    ///
    /// Owned here rather than by the list views themselves so the macOS window
    /// toolbar can host the filter control the way Mail does, while the list
    /// that applies the filter stays a child of the message list column.
    var mailboxFilter = MailboxFilterQuery.none

    /// Active search execution shared across the visible mail surfaces so
    /// cross-pane shortcuts can force local-only search before a query runs.
    public var searchExecution: SearchExecution

    /// Tracks whether `searchExecution` came from an explicit user or shortcut
    /// choice rather than backend capability defaults.
    public var hasUserSelectedSearchExecution: Bool

    /// Currently presented sheet, if any.
    public var presentedSheet: Sheet?

    /// Incremented each time a compose sheet is intentionally opened.
    /// Root view code uses this to tie async compose completions back
    /// to the mailbox context that launched them.
    public var composePresentationID: Int

    /// When the user opens compose as a reply, this is set so the
    /// sheet can prefill recipients + subject. Cleared on dismiss.
    public var composeReplyTo: MessageHeader?

    /// Whether the reply compose sheet targets just the sender or
    /// all visible recipients.
    public var composeReplyMode: ComposeReplyMode

    /// When the user opens compose as a forward, this is set so the
    /// sheet can prefill the subject. Cleared on dismiss.
    public var composeForwardOf: MessageHeader?

    /// Source that launched compose, when known. Used for unified/smart
    /// views where the selected folder is not itself source-scoped.
    public var composeSourceID: MailSourceID?

    /// Prefill for a new compose sheet opened from an external input
    /// such as the iOS share extension. Cleared on dismiss.
    public var composePrefill: ComposePrefill?

    /// Headers currently loaded for the selected folder. Owned by
    /// `MessageListView` after each load so the detail pane can look
    /// up the selected message and thread peers without re-fetching
    /// headers from the backend. Cleared when the folder changes.
    public var currentFolderHeaders: [MessageHeader]

    /// Multi-selection in the message list. Empty means single-select
    /// mode (the row tap drives the detail pane). Non-empty means the
    /// list is in bulk-action mode.
    public var bulkSelection: Set<MessageHeader.ID>

    /// Incremented when a command or toolbar action asks the current
    /// message list to reload its visible folder.
    public var reloadRequestID: Int

    public init(
        selectedSourceID: MailSourceID? = nil,
        selectedFolderID: Folder.ID? = nil,
        selectedMessageID: MessageHeader.ID? = nil,
        searchText: String = "",
        searchExecution: SearchExecution = .cacheOnly,
        hasUserSelectedSearchExecution: Bool = false,
        presentedSheet: Sheet? = nil,
        composePresentationID: Int = 0,
        composeReplyMode: ComposeReplyMode = .sender,
        composeSourceID: MailSourceID? = nil,
        currentFolderHeaders: [MessageHeader] = [],
        bulkSelection: Set<MessageHeader.ID> = [],
        reloadRequestID: Int = 0
    ) {
        self.selectedSourceID = selectedSourceID
        self.selectedFolderID = selectedFolderID
        self.selectedMessageID = selectedMessageID
        self.searchText = searchText
        self.searchExecution = searchExecution
        self.hasUserSelectedSearchExecution = hasUserSelectedSearchExecution
        self.presentedSheet = presentedSheet
        self.composePresentationID = composePresentationID
        self.composeReplyMode = composeReplyMode
        self.composeSourceID = composeSourceID
        self.currentFolderHeaders = currentFolderHeaders
        self.bulkSelection = bulkSelection
        self.reloadRequestID = reloadRequestID
    }

    /// Convenience lookup used by the detail pane.
    public var selectedHeader: MessageHeader? {
        guard let id = selectedMessageID else { return nil }
        return currentFolderHeaders.first { $0.id == id }
    }

    public var selectedSourceFolderID: SourceFolderID? {
        guard let selectedSourceID, let selectedFolderID else { return nil }
        return SourceFolderID(sourceID: selectedSourceID, folderID: selectedFolderID)
    }

    public var isUnifiedInboxSelected: Bool {
        selectedSourceID == nil && selectedFolderID == Self.unifiedInboxFolderID
    }

    public var isFlaggedSmartViewSelected: Bool {
        selectedSourceID == nil && selectedFolderID == Self.flaggedSmartViewFolderID
    }

    public var isTodaySmartViewSelected: Bool {
        selectedSourceID == nil && selectedFolderID == Self.todaySmartViewFolderID
    }

    public var isSnoozedSmartViewSelected: Bool {
        selectedSourceID == nil && selectedFolderID == Self.snoozedSmartViewFolderID
    }

    public var isDoneSmartViewSelected: Bool {
        selectedSourceID == nil && selectedFolderID == Self.doneSmartViewFolderID
    }

    public var isVIPSmartViewSelected: Bool {
        selectedSourceID == nil && selectedFolderID == Self.vipSmartViewFolderID
    }

    public var isAllAttachmentsSelected: Bool {
        selectedSourceID == nil && selectedFolderID == Self.allAttachmentsSmartViewFolderID
    }

    public var selectedSavedSearchID: SmartMailbox.ID? {
        guard selectedSourceID == nil,
              let folderID = selectedFolderID,
              folderID.hasPrefix(Self.savedSearchFolderIDPrefix)
        else { return nil }
        return String(folderID.dropFirst(Self.savedSearchFolderIDPrefix.count))
    }

    public func isSavedSearchSelected(id: SmartMailbox.ID) -> Bool {
        selectedSavedSearchID == id
    }

    public var isSmartViewSelected: Bool {
        isTodaySmartViewSelected
            || isFlaggedSmartViewSelected
            || isSnoozedSmartViewSelected
            || isDoneSmartViewSelected
            || isVIPSmartViewSelected
    }

    public func selectUnifiedInbox() {
        selectedSourceID = nil
        selectedFolderID = Self.unifiedInboxFolderID
        selectedMessageID = nil
        currentFolderHeaders = []
        bulkSelection.removeAll()
    }

    public func selectFlaggedSmartView() {
        selectSmartView(folderID: Self.flaggedSmartViewFolderID)
    }

    /// Selects the built-in view for messages received today.
    public func selectTodaySmartView() {
        selectSmartView(folderID: Self.todaySmartViewFolderID)
    }

    public func selectSnoozedSmartView() {
        selectSmartView(folderID: Self.snoozedSmartViewFolderID)
    }

    public func selectDoneSmartView() {
        selectSmartView(folderID: Self.doneSmartViewFolderID)
    }

    /// Selects the built-in view for messages from locally configured VIP senders.
    public func selectVIPSmartView() {
        selectSmartView(folderID: Self.vipSmartViewFolderID)
    }

    public func selectAllAttachmentsSmartView() {
        selectSmartView(folderID: Self.allAttachmentsSmartViewFolderID)
    }

    public func selectSavedSearch(id: SmartMailbox.ID) {
        selectSmartView(folderID: Self.savedSearchFolderIDPrefix + id)
    }

    /// Opens a sender-scoped search and forces it to stay local-only so the
    /// sender panel never triggers a network lookup.
    public func showAllMailFromSender(_ email: String) {
        bulkSelection.removeAll()
        presentedSheet = nil
        searchExecution = .cacheOnly
        hasUserSelectedSearchExecution = true
        searchText = "from: \(email)"
    }

    /// Ask the visible message list search field to take focus, replacing the
    /// Find shortcut that `.searchable` used to provide from the toolbar.
    public func requestSearchFocus() {
        searchFocusRequestID += 1
    }

    func selectSmartView(folderID: Folder.ID) {
        selectedSourceID = nil
        selectedFolderID = folderID
        selectedMessageID = nil
        currentFolderHeaders = []
        bulkSelection.removeAll()
    }

    /// Select a folder within a specific account/mailbox source.
    public func selectFolder(_ folderID: Folder.ID, in sourceID: MailSourceID) {
        selectedSourceID = sourceID
        selectedFolderID = folderID
        selectedMessageID = nil
        currentFolderHeaders = []
        bulkSelection.removeAll()
    }

    /// Mutate a header in `currentFolderHeaders` in place. Used by
    /// optimistic updates (mark read, toggle flag) so the list
    /// reflects the change without re-fetching.
    public func updateHeader(id: MessageHeader.ID, _ mutate: (inout MessageHeader) -> Void) {
        guard let index = currentFolderHeaders.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutate(&currentFolderHeaders[index])
    }

    /// Replace the loaded headers after a backend reload while keeping
    /// the current selection valid. If the selected message vanished,
    /// choose the header that took its index, or the previous final
    /// header when the vanished message was last.
    public func replaceCurrentFolderHeaders(
        _ headers: [MessageHeader],
        selectFirstIfNeeded: Bool = false
    ) {
        let selectedIndex = selectedMessageID.flatMap { selected in
            currentFolderHeaders.firstIndex(where: { $0.id == selected })
        }
        currentFolderHeaders = headers
        guard let selected = selectedMessageID else {
            if selectFirstIfNeeded {
                selectedMessageID = headers.first?.id
            }
            return
        }
        if headers.contains(where: { $0.id == selected }) {
            return
        }
        if let selectedIndex {
            selectedMessageID = headers[safe: selectedIndex]?.id ?? headers.last?.id
        } else {
            selectedMessageID = nil
        }
    }

    /// Remove headers in place (e.g. after move or delete).
    public func removeHeaders(ids: Set<MessageHeader.ID>) {
        let selectedRemovalIndex = selectedMessageID.flatMap { selected in
            ids.contains(selected)
                ? currentFolderHeaders.firstIndex(where: { $0.id == selected })
                : nil
        }

        // Capture the survivor that should inherit the selection *before*
        // mutating: the first header at-or-after the removed selection that
        // isn't itself being removed. Resolving by surviving id (not by a
        // pre-removal index) avoids an off-by-one when the same batch also
        // removes rows *before* the selection — those shifts would otherwise
        // push a saved index past the intended survivor.
        let inheritedSelectionID: MessageHeader.ID? = selectedRemovalIndex.flatMap { index in
            currentFolderHeaders[index...].first { !ids.contains($0.id) }?.id
        }

        currentFolderHeaders.removeAll { ids.contains($0.id) }
        if selectedRemovalIndex != nil {
            selectedMessageID = inheritedSelectionID ?? currentFolderHeaders.last?.id
        }
    }

    /// Move the reading-pane selection to the next loaded header. If
    /// nothing is selected yet, start at the first loaded header.
    public func selectNextHeader() {
        guard !currentFolderHeaders.isEmpty else {
            selectedMessageID = nil
            return
        }
        guard let selected = selectedMessageID,
              let index = currentFolderHeaders.firstIndex(where: { $0.id == selected })
        else {
            selectedMessageID = currentFolderHeaders.first?.id
            return
        }
        selectedMessageID = currentFolderHeaders[safe: index + 1]?.id ?? selected
    }

    /// Move the reading-pane selection to the previous loaded header.
    /// If nothing is selected yet, start at the first loaded header.
    public func selectPreviousHeader() {
        guard !currentFolderHeaders.isEmpty else {
            selectedMessageID = nil
            return
        }
        guard let selected = selectedMessageID,
              let index = currentFolderHeaders.firstIndex(where: { $0.id == selected })
        else {
            selectedMessageID = currentFolderHeaders.first?.id
            return
        }
        selectedMessageID = currentFolderHeaders[safe: index - 1]?.id ?? selected
    }

    /// Ask the active message list to refetch the currently visible
    /// folder. Commands use this instead of reaching into list state.
    public func requestReload() {
        reloadRequestID += 1
    }

    /// Ask the active list to reload when a backend event touches the
    /// folder the user is currently viewing.
    public func requestReloadIfVisibleFolderChanged(_ event: MailEvent) {
        let changedFolderID: Folder.ID?
        switch event {
        case .folderRefreshed(let folderID),
             .messagesAdded(let folderID, _),
             .messagesRemoved(let folderID, _),
             .messagesUpdated(let folderID, _):
            changedFolderID = folderID
        case .accountConnected,
             .accountDisconnected,
             .mailboxChanged,
             .syncProgress:
            changedFolderID = nil
        }

        if changedFolderID == selectedFolderID {
            requestReload()
        }
    }

    /// Clear state tied to the active mailbox before rebuilding the
    /// folder/message surface for a newly selected mailbox.
    public func resetForMailboxSwitch() {
        selectedSourceID = nil
        selectedFolderID = nil
        selectedMessageID = nil
        currentFolderHeaders = []
        bulkSelection.removeAll()
    }

    /// Open compose for a new outgoing message.
    public func presentNewMessage() {
        guard canPresentCompose else { return }
        composeReplyTo = nil
        composeReplyMode = .sender
        composeForwardOf = nil
        composeSourceID = nil
        composePrefill = nil
        presentCompose()
    }

    /// Open compose with prefilled content from an external source.
    public func presentNewMessage(prefill: ComposePrefill) {
        guard canPresentCompose else { return }
        composeReplyTo = nil
        composeReplyMode = .sender
        composeForwardOf = nil
        composeSourceID = nil
        composePrefill = prefill
        presentCompose()
    }

    /// Open compose as a reply to the selected message.
    public func presentReply(to header: MessageHeader, sourceID: MailSourceID? = nil) {
        guard canPresentCompose else { return }
        composeReplyTo = header
        composeReplyMode = .sender
        composeForwardOf = nil
        composeSourceID = sourceID
        composePrefill = nil
        presentCompose()
    }

    /// Open compose as a reply-all to the selected message.
    public func presentReplyAll(to header: MessageHeader, sourceID: MailSourceID? = nil) {
        guard canPresentCompose else { return }
        composeReplyTo = header
        composeReplyMode = .all
        composeForwardOf = nil
        composeSourceID = sourceID
        composePrefill = nil
        presentCompose()
    }

    /// Open compose as a forward of the selected message.
    public func presentForward(of header: MessageHeader, sourceID: MailSourceID? = nil) {
        guard canPresentCompose else { return }
        composeForwardOf = header
        composeReplyTo = nil
        composeReplyMode = .sender
        composeSourceID = sourceID
        composePrefill = nil
        presentCompose()
    }

    private func presentCompose() {
        composePresentationID += 1
        presentedSheet = .compose
    }

    private var canPresentCompose: Bool {
        presentedSheet == nil
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
