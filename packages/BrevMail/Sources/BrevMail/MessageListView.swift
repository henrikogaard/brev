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

import BrevAvatars
import BrevBackend
import BrevDesign
import BrevPlugins
import BrevSettings
import BrevThemes
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

func performDirectMessageActionFeedback(
    _ feedback: MessageCommandPresentation.DirectActionFeedback
) {
    #if os(iOS)
    switch feedback {
    case .impact:
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    case .warning:
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    #endif
}

/// Message list for the currently selected folder.
///
/// Loads `MessageHeader`s lazily from the backend; updates when the
/// selected folder changes. Selection writes back into
/// `MailNavigationState`.
public struct MessageListView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.undoQueue) private var undoQueue
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Bindable private var navigation: MailNavigationState
    @Binding private var localMessageWorkflowState: LocalMessageWorkflowState
    private let backend: any MailBackend
    private let sourceID: MailSourceID?
    private let accountOwnedMailboxEmails: Set<String>
    private let folder: Folder?
    private let folderDisplayName: String?
    private let allFolders: [Folder]
    private let searchSyntaxDescription: ServerSearchSyntaxDescription?
    private let isMutationWorkBlocked: Bool
    private let isWorkBlocked: Bool
    private let composeActions: MailComposePresentationActions
    private let onSelectMessage: ((MessageHeader) -> Void)?
    private let onMutation: (MailEvent) async -> Void
    private let onUnreadCountChanged: (Folder.ID, Int) -> Void
    private let onOpenInNewWindow: ((MessageHeader) -> Void)?

    @State private var loadedFolderHeaders: [MessageHeader] = []
    @State private var headers: [MessageHeader] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var nextPageToken: String?
    @State private var hasMore = false
    @State private var firstPageHeaderIDs: Set<MessageHeader.ID> = []
    /// A successful first-page load remains meaningful even when it contains no
    /// headers: the next same-folder refresh may contain newly arrived mail.
    @State private var hasLoadedFirstPage = false
    /// Recent server arrivals, kept briefly so only genuinely new cached-first
    /// reconciliation rows animate into the list.
    @State private var refreshArrivalIDs: [MessageHeader.ID] = []
    @State private var refreshArrivalClearTask: Task<Void, Never>?
    /// Identity (`account:mailbox:folder`) of the folder whose headers are
    /// currently loaded. Used to detect a folder/account switch so a refresh
    /// merge never carries one mailbox's messages into another.
    @State private var loadedFolderIdentity: String?
    @State private var errorMessage: String?
    @State private var mutationErrorStatus: MessageListFooterStatus?
    @State private var loadMoreErrorStatus: MessageListFooterStatus?
    @State private var needsReloadAfterWorkUnblocks = false
    @State private var activeFolderLoadRequest: MessageListFolderLoadRequest?
    @State private var activeLoadMoreRequest: MessageListPageRequest?
    @State private var activeSearchRequest: MessageListSearchRequest?
    @State private var activeAttachmentSearchQuery: SearchQuery?
    @State private var nextMutationRequestID = 0
    @State private var activeMutationRequest: MessageListMutationRequest?
    @State private var collapsedDateSectionIDs: Set<MessageListDateSection.ID> = []
    @State private var expandedThreadIDs: Set<String> = []
    @State private var pendingDeleteHeaderID: MessageHeader.ID?
    @State private var pendingBlockSenderHeader: MessageHeader?
    @State private var pendingSnoozeHeaders: [MessageHeader] = []
    @State private var searchScope: SearchScope = .all
    /// When true, search spans every folder in the mailbox instead of just
    /// the folder being viewed. Resets to false on folder/account switch.
    @State private var searchAllFolders = false
    /// Progressive disclosure for search execution / scope chips. Expands
    /// automatically when the user leaves the default search options.
    @State private var isSearchOptionsExpanded = false

    @AppStorage(MailboxViewPreferenceKey.groupByThread) private var groupByThread = true
    @AppStorage(MailboxViewPreferenceKey.groupByDate) private var groupByDate = true
    @AppStorage(MailboxViewPreferenceKey.showAbsoluteArrivalTime) private var showAbsoluteArrivalTime = false
    @AppStorage(MailboxViewPreferenceKey.showSenderAvatars) private var showSenderAvatars = true
    @AppStorage(MailboxViewPreferenceKey.previewLineCount) private var previewLineCountRaw = MailboxPreviewLineCount.one.rawValue
    @AppStorage(MailboxViewPreferenceKey.fontFamily) private var fontFamilyRaw = MailboxFontFamily.system.rawValue
    @AppStorage(MailboxViewPreferenceKey.textSize) private var textSizeRaw = MailboxTextSize.medium.rawValue
    @AppStorage(MailboxViewPreferenceKey.listDensity) private var listDensityRaw = MailboxListDensity.comfortable.rawValue
    @AppStorage(MailboxViewPreferenceKey.sortOrder) private var sortOrderRaw = MailboxSortOrder.newestFirst.rawValue
    @AppStorage(MailboxViewPreferenceKey.showFolderStats) private var showFolderStats = true
    @AppStorage(MailboxViewPreferenceKey.folderStatsDetail) private var folderStatsDetailRaw =
        MailboxFolderStatsDetail.compact.rawValue
    @AppStorage(MailboxViewPreferenceKey.inboxClassificationMode) private var inboxClassificationModeRaw =
        InboxClassificationMode.off.rawValue
    @AppStorage(MailPinnedMessages.storageKey) private var pinnedMessageIDsRaw = ""
    @AppStorage(LocalRulesSettings.Key.isAutomaticExecutionEnabled)
    private var isAutomaticLocalRulesEnabled = false
    @State private var activeInboxCategory: InboxCategory = .all
    @State private var inboxCategoryOverrideRevision = 0
    @State private var inboxCategoryOverrideStore = InboxCategoryOverrideStore()
    @State private var blockedSendersSettings = BlockedSendersSettings.load()
    @State private var followUpSettings = FollowUpSettings.load()
    // Derived caches: rebuilt only when their inputs change rather than on every
    // body pass. `threadCounts` keeps the per-row thread tally O(1) instead of an
    // O(n) scan per row (which made list rendering O(n^2)); `pinnedMessageIDSet`
    // avoids re-splitting `pinnedMessageIDsRaw` on every access.
    @State private var threadCounts: [String: Int] = [:]
    @State private var pinnedMessageIDSet: Set<MessageHeader.ID> = []
    @State private var presentationSnapshotCache = MessageListPresentationSnapshotCache()
    // Debounce handle for `rebuildThreadCounts`. Rapid `headers` changes (sync
    // bursts, flag-only mutations) coalesce into one O(n) pass instead of
    // rebuilding on every intermediate update.
    @State private var threadCountsRebuildTask: Task<Void, Never>?

    public init(
        navigation: MailNavigationState,
        backend: any MailBackend,
        sourceID: MailSourceID? = nil,
        accountOwnedMailboxEmails: Set<String> = [],
        folder: Folder?,
        folderDisplayName: String? = nil,
        allFolders: [Folder] = [],
        searchSyntaxDescription: ServerSearchSyntaxDescription? = nil,
        localMessageWorkflowState: Binding<LocalMessageWorkflowState> = .constant(.defaults),
        isWorkBlocked: Bool = false,
        isMutationWorkBlocked: Bool = false,
        composeActions: MailComposePresentationActions,
        onSelectMessage: ((MessageHeader) -> Void)? = nil,
        onMutation: @escaping (MailEvent) async -> Void = { _ in },
        onUnreadCountChanged: @escaping (Folder.ID, Int) -> Void = { _, _ in },
        onOpenInNewWindow: ((MessageHeader) -> Void)? = nil
    ) {
        self.navigation = navigation
        _localMessageWorkflowState = localMessageWorkflowState
        self.backend = backend
        self.sourceID = sourceID
        self.accountOwnedMailboxEmails = accountOwnedMailboxEmails
        self.folder = folder
        self.folderDisplayName = folderDisplayName
        self.allFolders = allFolders
        self.searchSyntaxDescription = searchSyntaxDescription
        self.isWorkBlocked = isWorkBlocked
        self.isMutationWorkBlocked = isMutationWorkBlocked
        self.composeActions = composeActions
        self.onSelectMessage = onSelectMessage
        self.onMutation = onMutation
        self.onUnreadCountChanged = onUnreadCountChanged
        self.onOpenInNewWindow = onOpenInNewWindow
        if !navigation.hasUserSelectedSearchExecution {
            navigation.searchExecution = MessageListSearchExecutionPolicy.defaultExecution(
                capabilities: backend.capabilities
            )
        }
    }

    public var body: some View {
        let presentation = presentationSnapshot
        VStack(spacing: 0) {
            LegacyPinNotice()
            #if os(iOS)
            MessageListSearchBand(navigation: navigation)
            #endif
            if !navigation.bulkSelection.isEmpty {
                bulkActionBar(visibleHeaders: presentation.headers)
            }
            if let mutationErrorStatus {
                BrevInlineStatus(
                    message: mutationErrorStatus.message,
                    tone: .danger,
                    actionTitle: mutationErrorStatus.actionTitle,
                    onAction: {
                        Task { await reloadVisibleMessages() }
                    },
                    onDismiss: {
                        self.mutationErrorStatus = nil
                    }
                )
            }
            if !trimmedSearchText.isEmpty {
                CollapsibleOptionsStrip(
                    isExpanded: $isSearchOptionsExpanded,
                    hasNonDefaultOptions: hasNonDefaultSearchOptions,
                    summary: searchOptionsSummary
                ) {
                    searchScopeBar
                }
            }
            if let query = activeAttachmentSearchQuery,
               MessageListAttachmentSearchDisclosurePolicy.shouldShowDisclosure(
                   query: query,
                   isLoading: isLoading
               ) {
                AttachmentSearchDisclosureView()
            }
            Group {
                if folder != nil {
                    // The scroll edge blur is mounted on the list itself, not
                    // on the pane: transient bars above it (bulk actions,
                    // search options) push the scroll viewport down, and a
                    // pane-top band would sit above where rows actually clip.
                    // The inbox category bar instead floats as a safe-area
                    // inset over the list, so rows slide beneath it and the
                    // band blurs them behind its clear background — the same
                    // "behind translucent chrome" reading as the toolbar edge.
                    listContent(presentation: presentation)
                        .brevMailPaneScrollEdgeBlur()
                        .safeAreaInset(edge: .top, spacing: 0) {
                            if showsInboxCategoryBar {
                                InboxCategoryBar(activeCategory: $activeInboxCategory)
                            }
                        }
                } else {
                    MessageListEmptyStateView(
                        status: MessageListPresentation.noFolderStatus()
                    )
                }
            }
            if let footer = folderStatsFooterPresentation(visibleCount: presentation.headers.count) {
                MessageListFolderStatsFooter(presentation: footer)
            }
        }
        .task(id: reloadKey) {
            navigation.bulkSelection.removeAll()
            searchScope = .all
            searchAllFolders = false
            isSearchOptionsExpanded = false
            reconcileSearchExecutionWithBackendCapabilities()
            refreshPinnedMessageIDSet()
            followUpSettings = FollowUpSettings.load()
            await reloadVisibleMessages()
        }
        .onReceive(NotificationCenter.default.publisher(for: .brevFollowUpDidChange)) { _ in
            followUpSettings = FollowUpSettings.load()
        }
        .onChange(of: headers) {
            refreshPinnedMessageIDSet()
            scheduleDebouncedThreadCountsRebuild()
        }
        .task(id: navigation.searchText) { await reloadForSearchChange() }
        // Consolidated search-filter task: when the user changes scope,
        // execution, or all-folders during an active search, a single
        // composite-keyed task fires instead of three separate ones each
        // doing their own debounce wait and search-plan computation.
        .task(id: searchFilterKey) {
            guard !trimmedSearchText.isEmpty else { return }
            await reloadForSearchChange()
        }
        .onChange(of: groupByThread) {
            activeMutationRequest = nil
            // Cancel any pending debounced rebuild so a stale capture cannot
            // undo this structural clear/rebuild after the debounce window.
            threadCountsRebuildTask?.cancel()
            threadCountsRebuildTask = nil
            rebuildThreadCounts()
            reconcileNavigationHeaders(selectFirstIfNeeded: selectsFirstMessageWhenNeeded)
        }
        .onChange(of: groupByDate) {
            reconcileNavigationHeaders(selectFirstIfNeeded: selectsFirstMessageWhenNeeded)
        }
        .onChange(of: pinnedMessageIDsRaw) {
            refreshPinnedMessageIDSet()
            reconcileNavigationHeaders(selectFirstIfNeeded: selectsFirstMessageWhenNeeded)
        }
        // Switching category tabs (or toggling classification) re-filters the
        // visible rows immediately, but the reader resolves its selection
        // against `currentFolderHeaders`, which only rebuilds on reconcile.
        // Without these, selecting a row that the previous category filtered
        // out leaves the reader on "No message selected" despite the highlight.
        .onChange(of: activeInboxCategory) {
            reconcileNavigationHeaders(selectFirstIfNeeded: selectsFirstMessageWhenNeeded)
        }
        .onChange(of: inboxClassificationModeRaw) {
            reconcileNavigationHeaders(selectFirstIfNeeded: selectsFirstMessageWhenNeeded)
        }
        .onChange(of: backend.capabilities) {
            reconcileSearchExecutionWithBackendCapabilities()
        }
        .onChange(of: isWorkBlocked) { oldValue, newValue in
            guard MessageListWorkResumePolicy.shouldReloadVisibleMessages(
                wasBlocked: oldValue,
                isBlocked: newValue,
                hasPendingReload: needsReloadAfterWorkUnblocks
            ) else { return }
            needsReloadAfterWorkUnblocks = false
            Task { await reloadVisibleMessages() }
        }
        .onChange(of: folder?.id) { _, _ in
            expandedThreadIDs.removeAll()
        }
        .alert(String(localized: "Delete Message?", bundle: .module), isPresented: isDeleteMessageAlertPresented) {
            Button(String(localized: "Delete", bundle: .module), role: .destructive) {
                Task { await confirmContextMenuDelete() }
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {
                pendingDeleteHeaderID = nil
            }
        } message: {
            if let header = pendingDeleteHeader {
                Text("Delete \"\(header.subject)\"?", bundle: .module)
            } else {
                Text("Delete this message?", bundle: .module)
            }
        }
        .alert(String(localized: "Block Sender?", bundle: .module), isPresented: isBlockSenderAlertPresented) {
            Button(String(localized: "Block", bundle: .module), role: .destructive) {
                Task { await confirmBlockSender() }
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {
                pendingBlockSenderHeader = nil
            }
        } message: {
            if let header = pendingBlockSenderHeader {
                Text("Block \"\(header.from.email)\"? Future messages from this address will be marked as junk.", bundle: .module)
            } else {
                Text("Block this sender?", bundle: .module)
            }
        }
        .sheet(isPresented: isSnoozePickerPresented) {
            if let header = pendingSnoozeHeaders.first {
                SnoozePickerView(
                    header: header,
                    sourceID: workflowSourceID,
                    onConfirm: { wakeAt in
                        snoozePendingHeaders(until: wakeAt)
                    },
                    onCancel: {
                        pendingSnoozeHeaders = []
                    }
                )
                .brevTheme(theme)
            }
        }
    }

    private var isSnoozePickerPresented: Binding<Bool> {
        Binding(
            get: { !pendingSnoozeHeaders.isEmpty },
            set: { isPresented in
                if !isPresented { pendingSnoozeHeaders = [] }
            }
        )
    }

    private var isBlockSenderAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingBlockSenderHeader != nil },
            set: { isPresented in
                if !isPresented { pendingBlockSenderHeader = nil }
            }
        )
    }

    private func confirmBlockSender() async {
        guard let header = pendingBlockSenderHeader else {
            pendingBlockSenderHeader = nil
            return
        }
        defer { pendingBlockSenderHeader = nil }
        await blockSender(email: header.from.email, header: header)
    }

    private var isDeleteMessageAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteHeaderID != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteHeaderID = nil
                }
            }
        )
    }

    private var pendingDeleteHeader: MessageHeader? {
        guard let pendingDeleteHeaderID else { return nil }
        return headers.first(where: { $0.id == pendingDeleteHeaderID })
    }

    private func confirmContextMenuDelete() async {
        guard let header = pendingDeleteHeader else {
            pendingDeleteHeaderID = nil
            return
        }
        performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .delete))
        defer { pendingDeleteHeaderID = nil }
        await deleteRow(header: header)
    }

    private var reloadKey: String {
        "\(folderIdentityKey):\(navigation.reloadRequestID)"
    }

    /// The folder/account identity, independent of the reload request id. A
    /// change here means a real folder or account switch (not a same-folder
    /// refresh), which must reset the loaded-header carry-over.
    private var folderIdentityKey: String {
        "\(sourceKey):\(folder?.id ?? "none")"
    }

    private var sourceKey: String {
        guard let sourceID else { return "none" }
        return "\(sourceID.accountID):\(sourceID.mailboxID)"
    }

    private var workflowSourceID: MailSourceID {
        sourceID ?? MailSourceID(
            accountID: backend.account.id,
            mailboxID: backend.account.id
        )
    }

    private var workflowVisibilityMode: LocalMessageWorkflowVisibilityMode {
        trimmedSearchText.isEmpty ? .active : .search
    }

    private var selectsFirstMessageWhenNeeded: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// Row-level Print / Export-as-PDF are wired only on macOS, where the
    /// right-click menu is their primary surface. iOS exposes the same
    /// actions from the reader's toolbar instead, so the row entries stay
    /// disabled there rather than duplicating share-sheet plumbing.
    private var supportsRowPrinting: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    private var isPerformingMutation: Bool {
        activeMutationRequest != nil
    }

    private var isMutationActionBlocked: Bool {
        isPerformingMutation || isWorkBlocked || isMutationWorkBlocked
    }

    private var archiveFolder: Folder? {
        allFolders.first { $0.role == .archive }
    }

    private var mailboxFontFamily: MailboxFontFamily {
        MailboxFontFamily(rawValue: fontFamilyRaw) ?? .system
    }

    private var mailboxTextSize: MailboxTextSize {
        MailboxTextSize(rawValue: textSizeRaw) ?? .medium
    }

    private var mailboxListDensity: MailboxListDensity {
        MailboxListDensity(rawValue: listDensityRaw) ?? .comfortable
    }

    private var mailboxPreviewLineCount: MailboxPreviewLineCount {
        MailboxPreviewLineCount(rawValue: previewLineCountRaw) ?? .one
    }

    private var mailboxSortOrder: MailboxSortOrder {
        MailboxSortOrder(rawValue: sortOrderRaw) ?? .newestFirst
    }

    private var inboxClassificationSettings: InboxClassificationSettings {
        InboxClassificationSettings(
            mode: InboxClassificationMode(rawValue: inboxClassificationModeRaw) ?? .off
        )
    }

    private var showsInboxCategoryBar: Bool {
        inboxClassificationSettings.mode == .categories && folder?.role == .inbox
    }

    private var mailboxFolderStatsDetail: MailboxFolderStatsDetail {
        MailboxFolderStatsDetail(rawValue: folderStatsDetailRaw) ?? .compact
    }

    @ViewBuilder
    private func bulkActionBar(visibleHeaders: [MessageHeader]) -> some View {
        HStack(spacing: BrevSpacing.xs) {
            Text("\(navigation.bulkSelection.count) selected", bundle: .module)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
            Spacer(minLength: BrevSpacing.sm)
            BulkActionIconButton(
                label: "Mark Read",
                systemImage: "envelope.open",
                isDisabled: isMutationActionBlocked
            ) {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .toggleRead))
                Task { await bulkSetRead(true) }
            }
            BulkActionIconButton(
                label: "Mark Unread",
                systemImage: "envelope.badge",
                isDisabled: isMutationActionBlocked
            ) {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .toggleRead))
                Task { await bulkSetRead(false) }
            }
            BulkActionIconButton(
                label: "Star",
                systemImage: "star",
                isDisabled: isMutationActionBlocked
            ) {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .toggleFlag))
                Task { await bulkSetFlag(true) }
            }
            if archiveFolder != nil {
                BulkActionIconButton(
                    label: "Archive",
                    systemImage: "archivebox",
                    isDisabled: isMutationActionBlocked
                ) {
                    performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .archive))
                    Task { await bulkArchive() }
                }
            }
            BulkActionIconButton(
                label: "Delete",
                systemImage: "trash",
                isDisabled: isMutationActionBlocked,
                isDestructive: true
            ) {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .delete))
                Task { await bulkDelete() }
            }
            bulkOverflowMenu(visibleHeaders: visibleHeaders)
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrevSeparator.color(for: theme))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func bulkOverflowMenu(visibleHeaders: [MessageHeader]) -> some View {
        let allVisible = Set(visibleHeaders.map(\.id))
        let allSelected = !allVisible.isEmpty && allVisible.isSubset(of: navigation.bulkSelection)
        let moveFolderCandidates = MessageCommandPresentation.moveFolderCandidates(
            from: allFolders,
            currentFolderID: folder?.id
        )
        Menu {
            Button(allSelected ? "Deselect All" : "Select All") {
                if allSelected {
                    navigation.bulkSelection.subtract(allVisible)
                } else {
                    navigation.bulkSelection.formUnion(allVisible)
                }
            }
            .disabled(isPerformingMutation)
            Button(String(localized: "Unstar", bundle: .module)) {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .toggleFlag))
                Task { await bulkSetFlag(false) }
            }
            .disabled(isMutationActionBlocked)
            Button(String(localized: "Snooze…", bundle: .module)) {
                pendingSnoozeHeaders = selectedBulkHeaders
            }
            .disabled(isMutationActionBlocked || selectedBulkHeaders.isEmpty)
            Button(workflowVisibilityMode == .done ? "Not Done" : "Done") {
                if workflowVisibilityMode == .done {
                    clearDone(headers: selectedBulkHeaders)
                } else {
                    markDone(headers: selectedBulkHeaders)
                }
            }
            .disabled(isMutationActionBlocked || selectedBulkHeaders.isEmpty)
            if !moveFolderCandidates.isEmpty {
                Button(String(localized: "Move…", bundle: .module)) {
                    performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .move))
                    navigation.presentedSheet = .moveTo(
                        messageIDs: Array(navigation.bulkSelection),
                        sourceID: sourceID,
                        currentFolderID: folder?.id
                    )
                }
                .disabled(isMutationActionBlocked)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.textSecondary.color)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(String(localized: "More bulk actions", bundle: .module))
        .help(String(localized: "More bulk actions", bundle: .module))
    }

    @ViewBuilder
    private func listContent(presentation: MessageListPresentationSnapshot) -> some View {
        if let errorMessage {
            let status = MessageListPresentation.errorStatus(errorMessage)
            MessageListEmptyStateView(status: status) {
                Task { await reloadVisibleMessages() }
            }
        } else if isLoading, headers.isEmpty {
            BrevSkeletonList(rowCount: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if headers.isEmpty {
            MessageListEmptyStateView(
                status: MessageListPresentation.emptyStatus(searchText: navigation.searchText)
            ) {
                navigation.searchText = ""
            }
        } else {
            List {
                if groupByDate {
                    ForEach(presentation.dateSections) { section in
                        dateSectionHeaderRow(section)
                        ForEach(section.visibleHeaders) { header in
                            messageRow(
                                for: header,
                                visibleIndex: presentation.visibleIndex(for: header.id) ?? 0,
                                visibleCount: presentation.headers.count
                            )
                        }
                    }
                } else {
                    ForEach(presentation.headers) { header in
                        messageRow(
                            for: header,
                            visibleIndex: presentation.visibleIndex(for: header.id) ?? 0,
                            visibleCount: presentation.headers.count
                        )
                    }
                }
                if isLoadingMore {
                    ProgressView()
                        .padding(BrevSpacing.md)
                        .listRowSeparator(.hidden)
                        .messageListThemedRowBackground()
                } else if let loadMoreErrorStatus {
                    MessageListFooterStatusView(status: loadMoreErrorStatus) {
                        Task { await loadMore() }
                    }
                    .listRowSeparator(.hidden)
                    .messageListThemedRowBackground()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await reloadVisibleMessages() }
        }
    }

    private func dateSectionHeaderRow(_ section: MessageListVisibleDateSection) -> some View {
        MessageListDateSectionHeader(
            title: section.title,
            count: section.totalCount,
            isCollapsed: section.isCollapsed
        ) {
            toggleDateSection(section.id)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .messageListThemedRowBackground()
    }

    @ViewBuilder
    private func parentMessageRow(
        for header: MessageHeader,
        visibleIndex: Int,
        visibleCount: Int
    ) -> some View {
        let followUpReminder = followUpSettings.reminder(for: header.id, sourceID: sourceID)
        MessageListRow(
            header: header,
            threadCount: threadCount(for: header),
            isSelected: navigation.selectedMessageID == header.id,
            isChecked: navigation.bulkSelection.contains(header.id),
            isInSelectionMode: !navigation.bulkSelection.isEmpty,
            isPinned: pinnedMessageIDs.contains(header.id),
            isThreadExpanded: expandedThreadIDs.contains(header.threadID),
            showAvatar: showSenderAvatars,
            previewLineCount: mailboxPreviewLineCount.visibleLineCount,
            isCompactWidth: usesCompactMessageRows,
            fontFamily: mailboxFontFamily,
            textSize: mailboxTextSize,
            density: mailboxListDensity,
            showsAbsoluteArrivalTime: showAbsoluteArrivalTime,
            sourceContext: nil,
            isBlockedSender: blockedSendersSettings.isBlocked(header.from.email),
            hasFollowUp: followUpReminder != nil,
            followUpDue: followUpReminder?.isDue() == true,
            onActivate: {
                if navigation.bulkSelection.isEmpty {
                    MessageListInlineExpansion.expandIfNeeded(
                        threadID: header.threadID,
                        threadCount: threadCount(for: header),
                        isThreadingEnabled: backend.groupsMessagesIntoThreads,
                        in: &expandedThreadIDs
                    )
                    selectMessage(header)
                } else {
                    toggleSelection(for: header)
                }
            }
        ) {
            toggleSelection(for: header)
        } onToggleThread: {
            guard backend.groupsMessagesIntoThreads,
                  threadCount(for: header) > 1
            else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                MessageListInlineExpansion.toggle(
                    threadID: header.threadID,
                    in: &expandedThreadIDs
                )
            }
        }
        .draggable(draggablePayload(for: header))
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .messageListThemedRowBackground()
        // Double-click opens the message in its own window. A simultaneous
        // high-count tap gesture (rather than a second `onTapGesture(count:)`)
        // keeps single-click selection instant while still recognizing the
        // double-click — stacked tap gestures of differing counts do not
        // disambiguate reliably on macOS List rows.
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onOpenInNewWindow?(header)
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            ForEach(
                MessageCommandPresentation.trailingSwipeActions(hasArchive: archiveFolder != nil),
                id: \.self
            ) { action in
                trailingSwipeButton(action, for: header)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            ForEach(MessageCommandPresentation.leadingSwipeActions, id: \.self) { action in
                leadingSwipeButton(action, for: header)
            }
        }
        .contextMenu {
            messageContextMenu(for: header)
        }
        .messageListRefreshArrival(
            isArrival: MessageListRefreshArrivalPolicy.shouldAnimate(
                headerID: header.id,
                arrivalIDs: refreshArrivalIDs,
                isSearchActive: !navigation.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ),
            delay: refreshArrivalDelay(for: header.id)
        )
        .onAppear {
            guard shouldLoadMore(
                afterAppearingAt: visibleIndex,
                totalCount: visibleCount
            ) else { return }
            Task { await loadMore() }
        }
    }

    private var usesCompactMessageRows: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    @ViewBuilder
    private func messageContextMenu(for header: MessageHeader) -> some View {
        let menu = MessageCommandPresentation.contextMenu(
            for: header,
            isSelected: navigation.bulkSelection.contains(header.id),
            isPinned: pinnedMessageIDs.contains(header.id),
            isSnoozed: isSnoozed(header),
            isDone: isDone(header),
            isKeptOffline: isKeptOffline(header),
            hasNote: hasNote(header),
            canOpenInNewWindow: onOpenInNewWindow != nil,
            canArchive: archiveFolder != nil,
            canMove: !MessageCommandPresentation.moveFolderCandidates(
                from: allFolders,
                currentFolderID: folder?.id
            ).isEmpty,
            canCopyToFolder: !MessageCommandPresentation.moveFolderCandidates(
                from: allFolders,
                currentFolderID: folder?.id
            ).isEmpty,
            junkActionTitle: MessageCommandPresentation.junkActionTitle(
                currentFolder: folder,
                capabilities: backend.capabilities,
                folders: allFolders
            ),
            canBlockSender: backend.capabilities.contains(.blockSender),
            canDelete: true,
            canCreateTask: navigation.presentedSheet == nil,
            canCreateRule: navigation.presentedSheet == nil,
            canCreateMeeting: navigation.presentedSheet == nil,
            canAddNote: navigation.presentedSheet == nil,
            canFollowUp: navigation.presentedSheet == nil,
            hasFollowUp: followUpSettings.reminder(for: header.id, sourceID: sourceID) != nil,
            canReply: composeActions.isAvailable,
            canPrint: supportsRowPrinting,
            canExportPDF: supportsRowPrinting,
            canShowProperties: true,
            extendedCapabilities: backend.extendedCapabilities,
            canExportEML: supportsRowPrinting
        )
        ForEach(menu.sections.indices, id: \.self) { sectionIndex in
            if sectionIndex > 0 {
                Divider()
            }
            ForEach(menu.sections[sectionIndex].actions, id: \.action) { action in
                messageContextMenuButton(action, for: header)
            }
        }
        if let sourceID {
            Divider()
            inboxCategoryMenu(for: header, sourceID: sourceID)
        }
        // Capability-driven (ADR-0028 invariant 2): the label menu appears only
        // when the backend advertises `.labels` and offers the label service.
        if backend.capabilities.contains(.labels),
           let labelService = backend.extensionService(MessageLabelManaging.self) {
            let candidates = MessageLabelPresentation.candidateLabels(from: allFolders)
            if !candidates.isEmpty {
                Divider()
                messageLabelMenu(for: header, candidates: candidates, service: labelService)
            }
        }
        pluginMessageContextMenuItems
    }

    private func messageLabelMenu(
        for header: MessageHeader,
        candidates: [String],
        service: any MessageLabelManaging
    ) -> some View {
        Menu {
            ForEach(candidates, id: \.self) { label in
                let isApplied = header.labels.contains(label)
                Button {
                    Task { await setLabel(label, isEnabled: !isApplied, for: header, service: service) }
                } label: {
                    Label(label, systemImage: isApplied ? "checkmark" : "tag")
                }
                .disabled(isMutationActionBlocked)
            }
        } label: {
            Label(String(localized: "Labels", bundle: .module), systemImage: "tag")
        }
    }

    @ViewBuilder
    private var pluginMessageContextMenuItems: some View {
        let contributions = BrevPluginRegistry.shared.registeredContributions(for: .messageContextMenu)
        if !contributions.isEmpty {
            Divider()
            ForEach(contributions) { contribution in
                if let view = BrevPluginRegistry.shared.view(for: contribution) {
                    view
                }
            }
        }
    }

    private func inboxCategoryMenu(
        for header: MessageHeader,
        sourceID: MailSourceID
    ) -> some View {
        let messageID = SourceMessageID(sourceID: sourceID, messageID: header.id)
        let currentCategory = InboxClassificationPolicy.classification(
            for: header,
            sourceID: sourceID,
            overrideStore: inboxCategoryOverrideStore
        ).category
        return Menu {
            ForEach(InboxCategory.assignableCases) { category in
                Button {
                    inboxCategoryOverrideStore.set(category, for: messageID)
                    inboxCategoryOverrideRevision += 1
                    reconcileNavigationHeaders()
                } label: {
                    Label(
                        category.title,
                        systemImage: currentCategory == category ? "checkmark" : category.symbolName
                    )
                }
            }
            Divider()
            Button {
                inboxCategoryOverrideStore.clear(messageID)
                inboxCategoryOverrideRevision += 1
                reconcileNavigationHeaders()
            } label: {
                Label(String(localized: "Use automatic category", bundle: .module), systemImage: "wand.and.stars")
            }
        } label: {
            Label(String(localized: "Category", bundle: .module), systemImage: "tray.2")
        }
    }

    @ViewBuilder
    private func messageContextMenuButton(
        _ presentation: MessageContextMenuActionPresentation,
        for header: MessageHeader
    ) -> some View {
        switch presentation.action {
        case .openInNewWindow:
            Button {
                onOpenInNewWindow?(header)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .select:
            Button {
                toggleSelection(for: header)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isPerformingMutation || !presentation.isEnabled)
        case .pinToTop:
            Button {
                togglePinned(header)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .toggleRead:
            Button {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .toggleRead))
                Task { await toggleRead(for: header) }
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .toggleFlag:
            Button {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .toggleFlag))
                Task { await toggleFlag(for: header) }
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .toggleSnooze:
            Button {
                if isSnoozed(header) {
                    clearSnooze(headers: [header])
                } else {
                    pendingSnoozeHeaders = [header]
                }
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .toggleDone:
            Button {
                if isDone(header) {
                    clearDone(headers: [header])
                } else {
                    markDone(headers: [header])
                }
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .reply:
            Button {
                composeActions.reply(header, sourceID: sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .replyAll:
            Button {
                composeActions.replyAll(header, sourceID: sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .forward:
            Button {
                composeActions.forward(header, sourceID: sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .archive:
            Button {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .archive))
                Task { await archiveRow(header: header) }
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .move:
            Button {
                navigation.presentedSheet = .moveTo(
                    messageIDs: [header.id],
                    sourceID: sourceID,
                    currentFolderID: folder?.id
                )
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .copyToFolder:
            Button {
                navigation.presentedSheet = .copyTo(
                    messageIDs: [header.id],
                    sourceID: sourceID,
                    currentFolderID: folder?.id
                )
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .setJunk:
            Button {
                let isInSpam = folder?.role == .spam
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .move))
                Task { await setJunk(!isInSpam, for: header) }
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .blockSender:
            Button(role: .destructive) {
                pendingBlockSenderHeader = header
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .delete:
            Button(role: .destructive) {
                pendingDeleteHeaderID = header.id
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .createTask:
            Button {
                navigation.presentedSheet = .createTask(header: header, sourceID: sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .followUp:
            Button {
                navigation.presentedSheet = .followUp(header: header, sourceID: sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .print:
            Button {
                printMessage(header)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .exportPDF:
            Button {
                exportMessagePDF(header)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .properties:
            Button {
                navigation.presentedSheet = .messageProperties(header: header)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .showHeaders:
            Button {
                navigation.presentedSheet = .showHeaders(header: header, sourceID: sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .viewSource:
            Button {
                navigation.presentedSheet = .viewSource(header: header, sourceID: sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .saveAs:
            Button {
                saveMessageAsEML(header)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .createRule:
            Button {
                navigation.presentedSheet = .createRule(header: header, sourceID: sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .downloadOffline:
            Button {
                toggleKeepOffline(header)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .createMeeting:
            Button {
                navigation.presentedSheet = .createMeeting(header: header, sourceID: sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .addNote:
            Button {
                navigation.presentedSheet = .messageNote(header: header, sourceID: sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        }
    }

    /// Loads the message body so the printout/PDF carries the content (not
    /// just headers) and shows the shared print panel. macOS only; the
    /// action is disabled on other platforms so this is never reached there.
    private func printMessage(_ header: MessageHeader) {
        #if os(macOS)
        Task {
            let body = await loadBodyForPrinting(header)
            MessagePrintExportRenderer.presentPrintPanel(header: header, body: body)
        }
        #endif
    }

    /// Loads the body, prompts for a destination, and writes a PDF export.
    private func exportMessagePDF(_ header: MessageHeader) {
        #if os(macOS)
        Task {
            let body = await loadBodyForPrinting(header)
            let panel = NSSavePanel()
            panel.title = String(localized: "Export Message as PDF", bundle: .module)
            panel.nameFieldStringValue = exportPDFBaseName(for: header) + ".pdf"
            panel.allowedContentTypes = [.pdf]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try MessagePrintExportRenderer.exportPDF(header: header, body: body, to: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = String(localized: "PDF export failed", bundle: .module)
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
        #endif
    }

    /// Best-effort body fetch for print/export. Returns nil on failure so the
    /// renderer can still emit a header-only document rather than blocking.
    private func loadBodyForPrinting(_ header: MessageHeader) async -> MessageBody? {
        if let sourceID {
            return try? await backend.body(for: header.id, sourceID: sourceID)
        }
        return try? await backend.body(for: header.id)
    }

    private func exportPDFBaseName(for header: MessageHeader) -> String {
        let trimmed = header.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "message" : trimmed
        return base.replacingOccurrences(of: "/", with: "-")
    }

    private func saveMessageAsEML(_ header: MessageHeader) {
        #if canImport(AppKit)
        Task {
            do {
                let rawSource: String
                if let sourceID {
                    rawSource = try await backend.rawSource(for: header.id, sourceID: sourceID)
                } else {
                    rawSource = try await backend.rawSource(for: header.id)
                }
                _ = try await MainActor.run {
                    try MessageEMLExport.presentSavePanel(header: header, rawSource: rawSource)
                }
            } catch {
                mutationErrorStatus = MessageListPresentation.mutationErrorStatus(for: error)
            }
        }
        #endif
    }

    @ViewBuilder
    private func messageRow(
        for header: MessageHeader,
        visibleIndex: Int,
        visibleCount: Int
    ) -> some View {
        parentMessageRow(
            for: header,
            visibleIndex: visibleIndex,
            visibleCount: visibleCount
        )
        if backend.groupsMessagesIntoThreads,
           threadCount(for: header) > 1,
           expandedThreadIDs.contains(header.threadID) {
            let children = MessageListInlineExpansion.childHeaders(
                for: header.threadID,
                excludingParentID: header.id,
                from: headers
            )
            ForEach(children) { child in
                ThreadInlineChildRow(
                    header: child,
                    isSelected: navigation.selectedMessageID == child.id
                ) {
                    if navigation.bulkSelection.isEmpty {
                        selectMessage(child)
                    } else {
                        toggleSelection(for: child)
                    }
                }
                .padding(.leading, BrevSpacing.xl)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .messageListThemedRowBackground()
            }
        }
    }

    @ViewBuilder
    private func trailingSwipeButton(
        _ action: MessageCommandPresentation.DirectAction,
        for header: MessageHeader
    ) -> some View {
        switch action {
        case .archive:
            Button {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .archive))
                Task { await archiveRow(header: header) }
            } label: {
                Label(String(localized: "Archive", bundle: .module), systemImage: "archivebox")
            }
            .tint(theme.accent.color)
            .disabled(isMutationActionBlocked)
        case .delete:
            Button(role: .destructive) {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .delete))
                Task { await deleteRow(header: header) }
            } label: {
                Label(String(localized: "Delete", bundle: .module), systemImage: "trash")
            }
            .disabled(isMutationActionBlocked)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func leadingSwipeButton(
        _ action: MessageCommandPresentation.DirectAction,
        for header: MessageHeader
    ) -> some View {
        switch action {
        case .toggleFlag:
            Button {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .toggleFlag))
                Task { await toggleFlag(for: header) }
            } label: {
                Label(
                    MessageCommandPresentation.flagToggleTitle(for: header),
                    systemImage: MessageCommandPresentation.flagToggleSymbolName(for: header)
                )
            }
            .tint(header.isFlagged ? theme.textTertiary.color : theme.warning.color)
            .disabled(isMutationActionBlocked)
        case .toggleRead:
            Button {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .toggleRead))
                Task { await toggleRead(for: header) }
            } label: {
                Label(
                    header.isRead ? "Unread" : "Read",
                    systemImage: header.isRead ? "envelope.badge" : "envelope.open"
                )
            }
            .tint(theme.accent.color)
            .disabled(isMutationActionBlocked)
        default:
            EmptyView()
        }
    }

    // MARK: - Search scope chip bar

    private var hasNonDefaultSearchOptions: Bool {
        searchScope != .all
            || searchAllFolders
            || navigation.hasUserSelectedSearchExecution
            || !naturalLanguageSearchChips.isEmpty
    }

    private var searchOptionsSummary: String {
        var parts: [String] = [navigation.searchExecution.messageListTitle]
        parts.append(searchAllFolders ? "All mailboxes" : "This folder")
        if searchScope != .all {
            parts.append(searchScope.title)
        }
        if !naturalLanguageSearchChips.isEmpty {
            parts.append("\(naturalLanguageSearchChips.count) filters")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var searchScopeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrevSpacing.xs) {
                ForEach(MessageListSearchExecutionPolicy.availableExecutions(
                    capabilities: backend.capabilities
                ), id: \.self) { execution in
                    searchExecutionChip(execution)
                }
                Rectangle()
                    .fill(BrevSeparator.color(for: theme))
                    .frame(width: 1, height: 18)
                    .padding(.horizontal, BrevSpacing.xxs)
                searchFolderScopeChip
                Rectangle()
                    .fill(BrevSeparator.color(for: theme))
                    .frame(width: 1, height: 18)
                    .padding(.horizontal, BrevSpacing.xxs)
                ForEach(SearchScope.allCases) { scope in
                    searchScopeChip(scope)
                }
                if !naturalLanguageSearchChips.isEmpty {
                    Rectangle()
                        .fill(BrevSeparator.color(for: theme))
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, BrevSpacing.xxs)
                    NaturalLanguageSearchChipStrip(
                        chips: naturalLanguageSearchChips,
                        onRemove: removeSearchChip
                    )
                }
                if let searchSyntaxDescription,
                   ServerSearchSyntaxHintPolicy.shouldShow(searchSyntaxDescription) {
                    Rectangle()
                        .fill(BrevSeparator.color(for: theme))
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, BrevSpacing.xxs)
                    ServerSearchSyntaxHint(description: searchSyntaxDescription)
                }
            }
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.xs)
        }
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrevSeparator.color(for: theme))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func searchScopeChip(_ scope: SearchScope) -> some View {
        let isActive = searchScope == scope
        Button {
            if searchScope != scope {
                searchScope = scope
            }
        } label: {
            HStack(spacing: BrevSpacing.xxs) {
                Image(systemName: scope.symbolName)
                    .font(.system(size: 11))
                Text(scope.title)
                    .brevFont(.caption)
            }
            .foregroundStyle(isActive ? theme.bgPrimary.color : theme.textSecondary.color)
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, BrevSpacing.xxs)
            .background(
                Capsule().fill(isActive ? theme.accent.color : theme.bgSecondary.color)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Search scope: \(scope.title)", bundle: .module))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private var searchFolderScopeChip: some View {
        let isActive = searchAllFolders
        Button {
            searchAllFolders.toggle()
        } label: {
            HStack(spacing: BrevSpacing.xxs) {
                Image(systemName: isActive ? "tray.2" : "tray")
                    .font(.system(size: 11))
                Text(isActive ? "All mailboxes" : "This folder")
                    .brevFont(.caption)
            }
            .foregroundStyle(isActive ? theme.bgPrimary.color : theme.textSecondary.color)
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, BrevSpacing.xxs)
            .background(
                Capsule().fill(isActive ? theme.accent.color : theme.bgSecondary.color)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "Searching all mailboxes" : "Searching this folder")
        .accessibilityHint(String(localized: "Toggle to search across every folder", bundle: .module))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private func searchExecutionChip(_ execution: SearchExecution) -> some View {
        let isActive = navigation.searchExecution == execution
        Button {
            if navigation.searchExecution != execution {
                navigation.hasUserSelectedSearchExecution = true
                navigation.searchExecution = execution
            }
        } label: {
            HStack(spacing: BrevSpacing.xxs) {
                Image(systemName: execution.messageListSymbolName)
                    .font(.system(size: 11))
                Text(execution.messageListTitle)
                    .brevFont(.caption)
            }
            .foregroundStyle(isActive ? theme.bgPrimary.color : theme.textSecondary.color)
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, BrevSpacing.xxs)
            .background(
                Capsule().fill(isActive ? theme.accent.color : theme.bgSecondary.color)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Search location: \(execution.messageListTitle)", bundle: .module))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func reconcileSearchExecutionWithBackendCapabilities() {
        let reconciled = MessageListSearchExecutionPolicy.reconciledExecution(
            current: navigation.searchExecution,
            hasUserSelection: navigation.hasUserSelectedSearchExecution,
            capabilities: backend.capabilities
        )
        navigation.hasUserSelectedSearchExecution = reconciled.hasUserSelection
        if reconciled.execution != navigation.searchExecution {
            navigation.searchExecution = reconciled.execution
        }
    }

    // MARK: - Bulk archive

    private func bulkArchive() async {
        guard let archive = archiveFolder else { return }
        await bulkMove(to: archive)
    }

    // MARK: - Drag payload

    private func draggablePayload(for header: MessageHeader) -> DraggableMessageID {
        if navigation.bulkSelection.contains(header.id), !navigation.bulkSelection.isEmpty {
            return DraggableMessageID(ids: Array(navigation.bulkSelection), sourceID: sourceID)
        }
        return DraggableMessageID(ids: [header.id], sourceID: sourceID)
    }

    private var presentationSnapshot: MessageListPresentationSnapshot {
        let now = Date()
        let temporalInvalidationKey = MailboxListTemporalInvalidationKey.headers(
            headers,
            filter: navigation.mailboxFilter,
            workflowMode: workflowVisibilityMode,
            workflowState: localMessageWorkflowState,
            now: now
        )
        let key = MessageListPresentationSnapshotCache.Key(
            headers: headers,
            groupByThread: groupByThread,
            pinnedMessageIDs: pinnedMessageIDs,
            mailboxFilter: navigation.mailboxFilter,
            workflowSourceID: workflowSourceID,
            workflowVisibilityMode: workflowVisibilityMode,
            workflowState: localMessageWorkflowState,
            sourceID: sourceID,
            activeInboxCategory: activeInboxCategory,
            inboxClassificationModeRaw: inboxClassificationModeRaw,
            inboxCategoryOverrideRevision: inboxCategoryOverrideRevision,
            mailboxSortOrder: mailboxSortOrder,
            groupByDate: groupByDate,
            collapsedDateSectionIDs: collapsedDateSectionIDs,
            temporalInvalidationKey: temporalInvalidationKey,
            calendarDay: calendar.startOfDay(for: now),
            calendarIdentifier: calendar.identifier,
            calendarTimeZoneIdentifier: calendar.timeZone.identifier,
            localeIdentifier: locale.identifier
        )
        return presentationSnapshotCache.snapshot(for: key) {
            let presentationHeaders = MessageListSortPolicy.sorted(
                visibleHeaders(for: workflowVisibleHeaders(from: headers, now: now, calendar: calendar)),
                by: mailboxSortOrder,
                pinnedIDs: pinnedMessageIDs
            )
            return MessageListPresentationSnapshot(
                headers: presentationHeaders,
                pinnedMessageIDs: pinnedMessageIDs,
                groupByDate: groupByDate,
                collapsedDateSectionIDs: collapsedDateSectionIDs,
                referenceDate: now,
                calendar: calendar
            )
        }
    }

    private var selectedBulkHeaders: [MessageHeader] {
        headers.filter { navigation.bulkSelection.contains($0.id) }
    }

    private func workflowVisibleHeaders(
        from headers: [MessageHeader],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MessageHeader] {
        _ = inboxCategoryOverrideRevision
        let filtered = MessageListSortPolicy.filtered(
            headers,
            by: navigation.mailboxFilter,
            now: now,
            calendar: calendar
        )
        let workflowVisible = LocalMessageWorkflowVisibilityPolicy.headers(
            filtered,
            sourceID: workflowSourceID,
            mode: workflowVisibilityMode,
            state: localMessageWorkflowState,
            now: now
        )
        return InboxClassificationVisibilityPolicy.headers(
            workflowVisible,
            sourceID: sourceID,
            selectedCategory: activeInboxCategory,
            settings: inboxClassificationSettings,
            overrideStore: inboxCategoryOverrideStore
        )
    }

    private var pinnedMessageIDs: Set<MessageHeader.ID> {
        pinnedMessageIDSet
    }

    private func folderStatsFooterPresentation(
        visibleCount: Int
    ) -> MessageListFolderStatsFooterPresentation? {
        guard showFolderStats, let folder else { return nil }
        return MessageListPresentation.folderStatsFooter(
            MessageListFolderStats(
                folderName: folderDisplayName ?? folder.name,
                totalCount: max(folder.totalCount, max(loadedFolderHeaders.count, headers.count)),
                unreadCount: max(folder.unreadCount, headers.filter { !$0.isRead }.count),
                loadedCount: max(loadedFolderHeaders.count, headers.count),
                visibleCount: visibleCount,
                pinnedCount: headers.filter { pinnedMessageIDs.contains($0.id) }.count,
                isThreaded: groupByThread,
                isConstrained: navigation.mailboxFilter.isActive || !trimmedSearchText.isEmpty
            ),
            detail: mailboxFolderStatsDetail
        )
    }

    private var trimmedSearchText: String {
        navigation.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Composite key for the consolidated search-filter `.task`. Changes to
    /// `searchScope`, `navigation.searchExecution`, or `searchAllFolders` during an
    /// active search fire a single task through this key instead of three
    /// separate tasks each doing their own debounce wait and search-plan
    /// computation.
    private var searchFilterKey: String {
        "\(searchScope.rawValue)|\(navigation.searchExecution.rawValue)|\(searchAllFolders)"
    }

    private var naturalLanguageSearchChips: [NaturalLanguageSearchChip] {
        guard !trimmedSearchText.isEmpty else { return [] }
        return MessageListSearchQueryPolicy.plan(
            text: trimmedSearchText,
            folderID: folder?.id,
            execution: navigation.searchExecution,
            searchScope: searchScope
        ).chips
    }

    private func removeSearchChip(_ chip: NaturalLanguageSearchChip) {
        navigation.searchText = NaturalLanguageSearchChipEditing.removing(
            chip,
            from: navigation.searchText
        )
    }

    private func shouldLoadMore(
        afterAppearingAt index: Int,
        totalCount: Int
    ) -> Bool {
        MessageListPaginationTriggerPolicy.shouldLoadMore(
            appearingIndex: index,
            totalCount: totalCount,
            hasMore: hasMore,
            isLoadingMore: isLoadingMore,
            isSearching: MessageListReloadPolicy.operation(
                forSearchText: navigation.searchText
            ) != .folder
        )
    }

    private func togglePinned(_ header: MessageHeader) {
        do {
            pinnedMessageIDsRaw = try MailPinnedMessages.toggling(
                sourceID: workflowSourceID, messageID: header.id, in: pinnedMessageIDsRaw
            )
            refreshPinnedMessageIDSet()
        } catch {
            mutationErrorStatus = MessageListPresentation.mutationErrorStatus(for: error)
        }
    }

    private func toggleDateSection(_ sectionID: MessageListDateSection.ID) {
        if collapsedDateSectionIDs.contains(sectionID) {
            collapsedDateSectionIDs.remove(sectionID)
        } else {
            collapsedDateSectionIDs.insert(sectionID)
        }
    }

    /// ADR-0020: a backend that cannot group conversations must render a
    /// single message — no count badge and no chevron that cannot expand.
    private func threadCount(for header: MessageHeader) -> Int {
        guard groupByThread,
              backend.groupsMessagesIntoThreads
        else { return 1 }
        return threadCounts[header.threadID] ?? 1
    }

    private func selectMessage(_ header: MessageHeader) {
        navigation.selectMessage(header, from: navigationHeaders(for: headers))
        onSelectMessage?(header)
    }

    /// Rebuilds the per-thread message tally. Cheap O(n) pass run only when
    /// `headers` or `groupByThread` change — not per row, per render.
    private func rebuildThreadCounts() {
        guard groupByThread else {
            threadCounts = [:]
            return
        }
        threadCounts = headers.reduce(into: [:]) { counts, header in
            counts[header.threadID, default: 0] += 1
        }
    }

    private func recordRecentRecipients(from headers: [MessageHeader]) {
        let observations = RecentRecipientObservationBuilder.observations(
            from: headers,
            accountID: backend.account.id,
            excludingEmails: [backend.account.emailAddress] + Array(accountOwnedMailboxEmails)
        )
        guard !observations.isEmpty else { return }
        Task(priority: .utility) {
            await RecentRecipientRecorder.shared.record(observations)
        }
    }

    /// Schedules a debounced `rebuildThreadCounts`. Rapid `headers` changes
    /// (sync bursts, flag-only mutations like mark-read) coalesce into one
    /// O(n) pass after a short quiet period instead of rebuilding on every
    /// intermediate update. The last-scheduled task wins; prior pending
    /// tasks are cancelled. Uses live `headers` / `groupByThread` after the
    /// wait so a structural toggle cannot be undone by a stale capture.
    private func scheduleDebouncedThreadCountsRebuild() {
        threadCountsRebuildTask?.cancel()
        threadCountsRebuildTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 40_000_000) // 40ms debounce window
            guard !Task.isCancelled else { return }
            rebuildThreadCounts()
        }
    }

    /// Re-parses the pinned-message identifier list from its stored string form.
    private func refreshPinnedMessageIDSet() {
        let keys = Set(pinnedMessageIDsRaw.split(separator: "\n").map(String.init))
        pinnedMessageIDSet = Set(headers.filter {
            keys.contains(MailPinnedMessages.key(sourceID: workflowSourceID, messageID: $0.id))
        }.map(\.id))
    }

    private func reload() async {
        guard let folder else {
            clearRefreshArrivals()
            loadedFolderHeaders = []
            headers = []
            navigation.currentFolderHeaders = []
            nextPageToken = nil
            hasMore = false
            firstPageHeaderIDs = []
            hasLoadedFirstPage = false
            loadedFolderIdentity = nil
            isLoading = false
            isLoadingMore = false
            activeFolderLoadRequest = nil
            activeLoadMoreRequest = nil
            activeSearchRequest = nil
            activeMutationRequest = nil
            needsReloadAfterWorkUnblocks = false
            mutationErrorStatus = nil
            loadMoreErrorStatus = nil
            return
        }
        let request = MessageListFolderLoadRequest(
            folderID: folder.id,
            sourceID: sourceID,
            reloadRequestID: navigation.reloadRequestID
        )
        guard canStartFolderLoad(request) else {
            rememberReloadAfterWorkUnblocks()
            return
        }
        let isSameFolder = loadedFolderIdentity == request.identityKey
        if !isSameFolder {
            clearRefreshArrivals()
            hasLoadedFirstPage = false
        }
        needsReloadAfterWorkUnblocks = false
        activeFolderLoadRequest = request
        activeSearchRequest = nil
        isLoading = true
        errorMessage = nil
        mutationErrorStatus = nil
        loadMoreErrorStatus = nil
        isLoadingMore = false
        activeLoadMoreRequest = nil
        activeMutationRequest = nil
        let interval = MailUIPerformanceDiagnostics.beginInterval("Message List Reload")
        defer { MailUIPerformanceDiagnostics.endInterval(interval) }
        do {
            let page = try await messages(in: folder, pageToken: nil)
            guard canApplyFolderLoadResponse(request) else { return }
            let finalHeaders = await applyAutomaticLocalRulesIfNeeded(
                headers: page.headers,
                folder: folder
            )
            let mergedHeaders = MessageListRefreshMerge.headers(
                refreshedFirstPage: finalHeaders,
                previousLoadedHeaders: loadedFolderHeaders,
                previousFirstPageHeaderIDs: firstPageHeaderIDs,
                isSameFolder: isSameFolder
            )
            let arrivalIDs = MessageListRefreshArrivalPolicy.arrivalIDs(
                refreshedFirstPageIDs: finalHeaders.map(\.id),
                previousLoadedIDs: Set(loadedFolderHeaders.map(\.id)),
                previousFirstPageWasLoaded: hasLoadedFirstPage,
                isSameFolder: isSameFolder
            )
            showRefreshArrivals(arrivalIDs)
            loadedFolderHeaders = mergedHeaders
            headers = mergedHeaders
            // Learn only the refreshed first page. Older loaded rows are
            // already indexed by their own page load, so scanning the complete
            // visible cache here makes recipient suggestions scale with mailbox
            // size instead of the 50-row refresh budget.
            recordRecentRecipients(from: finalHeaders)
            navigation.replaceCurrentFolderHeaders(
                navigationHeaders(for: mergedHeaders),
                selectFirstIfNeeded: selectsFirstMessageWhenNeeded
            )
            nextPageToken = page.nextPageToken
            hasMore = page.nextPageToken != nil
            firstPageHeaderIDs = Set(finalHeaders.map(\.id))
            hasLoadedFirstPage = true
            loadedFolderIdentity = request.identityKey
            MailUIPerformanceDiagnostics.logListFinished(
                surface: .messageList,
                path: .reload,
                resultCount: mergedHeaders.count,
                hasMore: hasMore,
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
            finishFolderLoad(request)
        } catch is CancellationError {
            guard canApplyFolderLoadResponse(request) else { return }
            finishFolderLoad(request)
        } catch {
            guard canApplyFolderLoadResponse(request) else { return }
            errorMessage = MessageListPresentation.loadErrorMessage(for: error)
            loadedFolderHeaders = []
            headers = []
            navigation.replaceCurrentFolderHeaders([])
            nextPageToken = nil
            hasMore = false
            firstPageHeaderIDs = []
            hasLoadedFirstPage = false
            loadedFolderIdentity = nil
            isLoadingMore = false
            activeLoadMoreRequest = nil
            loadMoreErrorStatus = nil
            MailUIPerformanceDiagnostics.logListFailed(
                surface: .messageList,
                path: .reload,
                error: error,
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
            finishFolderLoad(request)
        }
    }

    private func reloadVisibleMessages() async {
        switch MessageListReloadPolicy.operation(forSearchText: navigation.searchText) {
        case .folder:
            await reload()
        case .search:
            await reloadForSearchChange()
        }
    }

    private func refreshArrivalDelay(for headerID: MessageHeader.ID) -> TimeInterval {
        guard let index = refreshArrivalIDs.firstIndex(of: headerID) else { return 0 }
        return Double(index) * 0.04
    }

    private func showRefreshArrivals(_ messageIDs: [MessageHeader.ID]) {
        guard !messageIDs.isEmpty else { return }
        refreshArrivalClearTask?.cancel()
        refreshArrivalIDs = messageIDs
        refreshArrivalClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            refreshArrivalIDs = []
        }
    }

    private func clearRefreshArrivals() {
        refreshArrivalClearTask?.cancel()
        refreshArrivalClearTask = nil
        refreshArrivalIDs = []
    }

    private func loadMore() async {
        guard let folder, let token = nextPageToken else { return }
        let request = MessageListPageRequest(
            folderID: folder.id,
            sourceID: sourceID,
            pageToken: token
        )
        guard canStartLoadMore(request) else {
            rememberReloadAfterWorkUnblocks()
            return
        }
        needsReloadAfterWorkUnblocks = false
        activeLoadMoreRequest = request
        isLoadingMore = true
        loadMoreErrorStatus = nil
        let interval = MailUIPerformanceDiagnostics.beginInterval("Message List Load More")
        defer { MailUIPerformanceDiagnostics.endInterval(interval) }
        do {
            let page = try await messages(in: folder, pageToken: token)
            guard canApplyPageResponse(request) else { return }
            // De-dupe by id in case of overlap at the page boundary.
            let existing = Set(headers.map(\.id))
            let new = page.headers.filter { !existing.contains($0.id) }
            loadedFolderHeaders.append(contentsOf: new)
            headers.append(contentsOf: new)
            recordRecentRecipients(from: new)
            reconcileNavigationHeaders()
            nextPageToken = page.nextPageToken
            hasMore = page.nextPageToken != nil
            MailUIPerformanceDiagnostics.logListFinished(
                surface: .messageList,
                path: .loadMore,
                resultCount: new.count,
                hasMore: hasMore,
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
            finishLoadMore(request)
        } catch is CancellationError {
            guard canApplyPageResponse(request) else { return }
            finishLoadMore(request)
        } catch {
            guard canApplyPageResponse(request) else { return }
            loadMoreErrorStatus = MessageListPresentation.loadMoreErrorStatus(for: error)
            hasMore = false
            MailUIPerformanceDiagnostics.logListFailed(
                surface: .messageList,
                path: .loadMore,
                error: error,
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
            finishLoadMore(request)
        }
    }

    private func canApplyFolderLoadResponse(_ request: MessageListFolderLoadRequest) -> Bool {
        MessageListFolderLoadResponsePolicy.canApplyFolderLoadResponse(
            request: request,
            activeRequest: activeFolderLoadRequest,
            currentSourceID: navigation.selectedSourceID,
            currentFolderID: navigation.selectedFolderID,
            currentReloadRequestID: navigation.reloadRequestID,
            currentSearchText: navigation.searchText
        )
    }

    private func applyAutomaticLocalRulesIfNeeded(
        headers: [MessageHeader],
        folder: Folder
    ) async -> [MessageHeader] {
        guard isAutomaticLocalRulesEnabled else { return headers }
        let settings = LocalRulesSettings.load()
        let rules = settings.rules.filter(\.isEnabled)
        guard !rules.isEmpty else { return headers }

        let archiveFolderID = allFolders.first(where: { $0.role == .archive })?.id
        let trashFolderID = allFolders.first(where: { $0.role == .trash })?.id
        let plan = LocalRulesRuntime.plan(
            rules: rules,
            headers: headers,
            folders: allFolders,
            capabilities: backend.capabilities,
            archiveFolderID: archiveFolderID,
            trashFolderID: trashFolderID,
            mode: .automatic
        )
        guard plan.totalExecutableActionCount > 0 else {
            return plan.executionResult.headers
        }

        do {
            try await LocalRulesRuntime.apply(
                plan: plan,
                backend: backend,
                sourceID: sourceID
            )
            let refreshedPage = try await messages(in: folder, pageToken: nil)
            return refreshedPage.headers
        } catch {
            mutationErrorStatus = MessageListPresentation.mutationErrorStatus(for: error)
            return plan.executionResult.headers
        }
    }

    private func canStartFolderLoad(_ request: MessageListFolderLoadRequest) -> Bool {
        MessageListFolderLoadStartPolicy.canStartFolderLoad(
            request: request,
            activeRequest: activeFolderLoadRequest,
            isBlocked: isWorkBlocked
        )
    }

    private func finishFolderLoad(_ request: MessageListFolderLoadRequest) {
        guard activeFolderLoadRequest == request else { return }
        activeFolderLoadRequest = nil
        isLoading = false
    }

    private func canApplyPageResponse(_ request: MessageListPageRequest) -> Bool {
        MessageListPageResponsePolicy.canApplyPageResponse(
            request: request,
            activeRequest: activeLoadMoreRequest,
            currentSourceID: navigation.selectedSourceID,
            currentFolderID: navigation.selectedFolderID,
            currentSearchText: navigation.searchText
        )
    }

    private func canStartLoadMore(_ request: MessageListPageRequest) -> Bool {
        MessageListPageStartPolicy.canStartPageLoad(
            request: request,
            activeRequest: activeLoadMoreRequest,
            isBlocked: isWorkBlocked
        )
    }

    private func finishLoadMore(_ request: MessageListPageRequest) {
        guard activeLoadMoreRequest == request else { return }
        activeLoadMoreRequest = nil
        isLoadingMore = false
    }

    private func reloadForSearchChange() async {
        guard case .search(let query) = MessageListReloadPolicy.operation(
            forSearchText: navigation.searchText
        ) else {
            activeSearchRequest = nil
            activeAttachmentSearchQuery = nil
            await reload()
            return
        }
        clearRefreshArrivals()
        let searchPlan = MessageListSearchPlanPolicy.plan(
            text: query,
            sourceID: sourceID,
            selectedFolderID: folder?.id,
            execution: navigation.searchExecution,
            searchAllFolders: searchAllFolders,
            searchScope: searchScope
        )
        let request = searchPlan.request
        guard canStartSearch(request) else {
            rememberReloadAfterWorkUnblocks()
            return
        }
        needsReloadAfterWorkUnblocks = false
        activeSearchRequest = request
        activeAttachmentSearchQuery = nil
        isLoading = false
        isLoadingMore = false
        activeFolderLoadRequest = nil
        activeLoadMoreRequest = nil
        activeMutationRequest = nil
        loadMoreErrorStatus = nil
        // Light debounce so the user can finish typing.
        let interval = MailUIPerformanceDiagnostics.beginInterval("Message List Search")
        defer { MailUIPerformanceDiagnostics.endInterval(interval) }
        guard await MessageListSearchDebouncePolicy.waitForDebounce() else {
            finishSearch(request)
            return
        }
        guard canApplySearchResponse(request) else {
            finishSearch(request)
            return
        }
        isLoading = true
        activeAttachmentSearchQuery = searchPlan.query.hasAttachments == true
            && searchPlan.query.execution != .cacheOnly
            ? searchPlan.query
            : nil
        errorMessage = nil
        mutationErrorStatus = nil
        loadMoreErrorStatus = nil
        do {
            let results = try await search(searchPlan.query)
            guard canApplySearchResponse(request) else {
                finishSearch(request)
                return
            }
            headers = results
            navigation.replaceCurrentFolderHeaders(
                navigationHeaders(for: results),
                selectFirstIfNeeded: selectsFirstMessageWhenNeeded
            )
            MailUIPerformanceDiagnostics.logListSearchFinished(
                surface: .messageList,
                execution: navigation.searchExecution,
                resultCount: results.count,
                skippedSourceCount: 0,
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
            finishSearch(request)
        } catch is CancellationError {
            guard canApplySearchResponse(request) else {
                finishSearch(request)
                return
            }
            finishSearch(request)
        } catch {
            if MessageListSearchFallbackPolicy.shouldApplyLocalFallback(
                for: error,
                execution: navigation.searchExecution
            ) {
                // Backend/server search is temporarily unavailable or rejected;
                // fall back to the already-loaded page without alarming the user.
                let resultCount = applyLocalSearchFallback(
                    searchQuery: searchPlan.query,
                    request: request
                )
                MailUIPerformanceDiagnostics.logListSearchFinished(
                    surface: .messageList,
                    execution: navigation.searchExecution,
                    resultCount: resultCount,
                    skippedSourceCount: 0,
                    durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
                )
                return
            }
            guard canApplySearchResponse(request) else {
                finishSearch(request)
                return
            }
            errorMessage = MessageListPresentation.searchErrorMessage(for: error)
            MailUIPerformanceDiagnostics.logListFailed(
                surface: .messageList,
                path: .search,
                error: error,
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
            finishSearch(request)
        }
    }

    /// Apply the current search predicates over the already-loaded page when
    /// the server can't be searched (no server-side search, or a transient
    /// disconnect). Guarded by `canApplySearchResponse` so a stale response
    /// never clobbers a newer query.
    @discardableResult
    private func applyLocalSearchFallback(
        searchQuery: SearchQuery,
        request: MessageListSearchRequest
    ) -> Int {
        guard canApplySearchResponse(request) else {
            finishSearch(request)
            return 0
        }
        let results = MessageSearchFallback.filteredHeaders(
            in: loadedFolderHeaders,
            searchQuery: searchQuery
        )
        headers = results
        navigation.replaceCurrentFolderHeaders(
            navigationHeaders(for: results),
            selectFirstIfNeeded: selectsFirstMessageWhenNeeded
        )
        finishSearch(request)
        return results.count
    }

    private func canStartSearch(_ request: MessageListSearchRequest) -> Bool {
        MessageListSearchStartPolicy.canStartSearch(
            request: request,
            activeRequest: activeSearchRequest,
            isBlocked: isWorkBlocked
        )
    }

    private func finishSearch(_ request: MessageListSearchRequest) {
        guard activeSearchRequest == request else { return }
        activeSearchRequest = nil
        activeAttachmentSearchQuery = nil
        isLoading = false
    }

    private func rememberReloadAfterWorkUnblocks() {
        if isWorkBlocked {
            needsReloadAfterWorkUnblocks = true
        }
    }

    private func canApplySearchResponse(_ request: MessageListSearchRequest) -> Bool {
        MessageListSearchDebouncePolicy.canApplySearchResponse(
            request: request,
            activeRequest: activeSearchRequest,
            currentSearchText: navigation.searchText,
            currentSourceID: navigation.selectedSourceID,
            currentFolderID: navigation.selectedFolderID
        )
    }

    private func toggleRead(for header: MessageHeader) async {
        guard canStartMutation() else { return }
        let newValue = !header.isRead
        let request = startMutationRequest()
        let rollback = makeMutationRollback()
        mutationErrorStatus = nil
        navigation.updateHeader(id: header.id) { $0.isRead = newValue }
        updateCachedHeaders(ids: [header.id]) {
            $0.isRead = newValue
        }
        do {
            try await setRead(newValue, for: [header.id])
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            finishMutation(request)
            await notifyMutationUpdated(messageIDs: [header.id])
        } catch {
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            handleMutationFailure(error, rollback: rollback)
            finishMutation(request)
        }
    }

    private func toggleFlag(for header: MessageHeader) async {
        guard canStartMutation() else { return }
        let newValue = !header.isFlagged
        let request = startMutationRequest()
        let rollback = makeMutationRollback()
        mutationErrorStatus = nil
        navigation.updateHeader(id: header.id) { $0.isFlagged = newValue }
        updateCachedHeaders(ids: [header.id]) {
            $0.isFlagged = newValue
        }
        do {
            try await setFlagged(newValue, for: [header.id])
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            finishMutation(request)
            await notifyMutationUpdated(messageIDs: [header.id])
        } catch {
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            handleMutationFailure(error, rollback: rollback)
            finishMutation(request)
        }
    }

    /// Marks a single message as junk or not-junk.
    ///
    /// When marking as junk the message is removed from the current view
    /// (optimistically); not-junk moves the message back to the inbox.
    private func setJunk(_ isJunk: Bool, for header: MessageHeader) async {
        guard canStartMutation() else { return }
        let request = startMutationRequest()
        let rollback = makeMutationRollback()
        let ids: Set<MessageHeader.ID> = [header.id]
        mutationErrorStatus = nil
        // Optimistically remove from the visible folder either way.
        navigation.removeHeaders(ids: ids)
        removeCachedHeaders(ids: ids)
        do {
            try await setJunkOrMoveToFallbackFolder(isJunk, for: header)
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            finishMutation(request)
            await notifyMutationRemoved(messageIDs: [header.id])
        } catch {
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            handleMutationFailure(error, rollback: rollback)
            finishMutation(request)
        }
    }

    private func setJunkOrMoveToFallbackFolder(_ isJunk: Bool, for header: MessageHeader) async throws {
        do {
            if let sourceID {
                try await backend.setJunk(isJunk, for: [header.id], sourceID: sourceID)
            } else {
                try await backend.setJunk(isJunk, for: [header.id])
            }
        } catch MailBackendError.notSupported {
            guard let fallbackFolder = MessageCommandPresentation.junkFallbackFolder(
                isJunk: isJunk,
                folders: allFolders
            ) else {
                throw MailBackendError.notSupported(backend.capabilities)
            }
            if let sourceID {
                try await backend.move(messageIDs: [header.id], to: fallbackFolder, sourceID: sourceID)
            } else {
                try await backend.move(messageIDs: [header.id], to: fallbackFolder)
            }
        }
    }

    /// Blocks the sender of a message via the backend's block-sender API.
    ///
    /// Requires prior user confirmation (the alert uses `.destructive`
    /// role). On success the message is removed from the current view.
    private func blockSender(email: String, header: MessageHeader) async {
        guard canStartMutation() else { return }
        let request = startMutationRequest()
        let rollback = makeMutationRollback()
        let ids: Set<MessageHeader.ID> = [header.id]
        mutationErrorStatus = nil
        do {
            if let sourceID {
                try await backend.blockSender(email: email, sourceID: sourceID)
            } else {
                try await backend.blockSender(email: email)
            }
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            // Also move the message to junk so it disappears from inbox.
            navigation.removeHeaders(ids: ids)
            removeCachedHeaders(ids: ids)
            finishMutation(request)
            await notifyMutationRemoved(messageIDs: [header.id])
        } catch {
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            handleMutationFailure(error, rollback: rollback)
            finishMutation(request)
        }
    }

    private func deleteRow(header: MessageHeader) async {
        guard canStartMutation() else { return }
        let request = startMutationRequest()
        let rollback = makeMutationRollback()
        let ids: Set<MessageHeader.ID> = [header.id]
        mutationErrorStatus = nil
        navigation.removeHeaders(ids: ids)
        removeCachedHeaders(ids: ids)
        do {
            try await delete(messageIDs: [header.id])
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            finishMutation(request)
            await notifyMutationRemoved(messageIDs: [header.id])
        } catch {
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            handleMutationFailure(error, rollback: rollback)
            finishMutation(request)
        }
    }

    private func archiveRow(header: MessageHeader) async {
        guard canStartMutation(),
              let archive = archiveFolder
        else { return }
        let request = startMutationRequest()
        let rollback = makeMutationRollback()
        let ids: Set<MessageHeader.ID> = [header.id]
        mutationErrorStatus = nil
        navigation.removeHeaders(ids: ids)
        removeCachedHeaders(ids: ids)
        do {
            try await move(messageIDs: [header.id], to: archive)
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            finishMutation(request)
            await notifyMutationRemoved(messageIDs: [header.id])
        } catch {
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            handleMutationFailure(error, rollback: rollback)
            finishMutation(request)
        }
    }

    private func moveRow(header: MessageHeader, to destination: Folder) async {
        guard canStartMutation() else { return }
        let request = startMutationRequest()
        let rollback = makeMutationRollback()
        let ids: Set<MessageHeader.ID> = [header.id]
        mutationErrorStatus = nil
        navigation.removeHeaders(ids: ids)
        removeCachedHeaders(ids: ids)
        do {
            try await move(messageIDs: [header.id], to: destination)
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            finishMutation(request)
            await notifyMutationRemoved(messageIDs: [header.id])
        } catch {
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            handleMutationFailure(error, rollback: rollback)
            finishMutation(request)
        }
    }

    private func toggleSelection(for header: MessageHeader) {
        guard !isPerformingMutation else { return }
        if navigation.bulkSelection.contains(header.id) {
            navigation.bulkSelection.remove(header.id)
        } else {
            navigation.bulkSelection.insert(header.id)
        }
    }

    private func bulkSetRead(_ value: Bool) async {
        let ids = Array(navigation.bulkSelection)
        guard !ids.isEmpty, canStartMutation() else { return }
        let idSet = Set(ids)
        let request = startMutationRequest()
        let rollback = makeMutationRollback()
        mutationErrorStatus = nil
        for id in idSet {
            navigation.updateHeader(id: id) { $0.isRead = value }
        }
        updateCachedHeaders(ids: idSet) {
            $0.isRead = value
        }
        do {
            try await setRead(value, for: ids)
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            finishMutation(request)
            // Optimistic unread-count reconciliation — counts are
            // adjusted on the source folder and clamped to >= 0
            // (The related feature request). The next folder-list refresh from the
            // backend will correct any drift.
            if let currentFolderID = folder?.id {
                onUnreadCountChanged(currentFolderID, value ? -ids.count : ids.count)
            }
            await notifyMutationUpdated(messageIDs: ids)
        } catch {
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            handleMutationFailure(error, rollback: rollback)
            finishMutation(request)
        }
    }

    private func bulkSetFlag(_ value: Bool) async {
        let ids = Array(navigation.bulkSelection)
        guard !ids.isEmpty, canStartMutation() else { return }
        let idSet = Set(ids)
        let request = startMutationRequest()
        let rollback = makeMutationRollback()
        mutationErrorStatus = nil
        for id in idSet {
            navigation.updateHeader(id: id) { $0.isFlagged = value }
        }
        updateCachedHeaders(ids: idSet) {
            $0.isFlagged = value
        }
        do {
            try await setFlagged(value, for: ids)
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            finishMutation(request)
            await notifyMutationUpdated(messageIDs: ids)
        } catch {
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            handleMutationFailure(error, rollback: rollback)
            finishMutation(request)
        }
    }

    private func bulkMove(to destination: Folder) async {
        let ids = Array(navigation.bulkSelection)
        guard !ids.isEmpty, canStartMutation() else { return }
        let idSet = Set(ids)
        let request = startMutationRequest()
        let rollback = makeMutationRollback()
        mutationErrorStatus = nil
        navigation.removeHeaders(ids: idSet)
        removeCachedHeaders(ids: idSet)
        navigation.bulkSelection.removeAll()
        do {
            try await move(messageIDs: ids, to: destination)
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            finishMutation(request)
            // Optimistic unread-count reconciliation — the source
            // folder loses the unread count, the destination gains it
            // (The related feature request). A future folder-list refresh from the
            // backend will correct any drift.
            if let currentFolderID = folder?.id, currentFolderID != destination.id {
                onUnreadCountChanged(currentFolderID, -ids.count)
            }
            onUnreadCountChanged(destination.id, ids.count)
            await notifyMutationRemoved(messageIDs: ids)
        } catch {
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            handleMutationFailure(error, rollback: rollback)
            finishMutation(request)
        }
    }

    private func bulkDelete() async {
        let ids = Array(navigation.bulkSelection)
        guard !ids.isEmpty, canStartMutation() else { return }
        let idSet = Set(ids)
        let request = startMutationRequest()
        let rollback = makeMutationRollback()
        mutationErrorStatus = nil
        navigation.removeHeaders(ids: idSet)
        removeCachedHeaders(ids: idSet)
        navigation.bulkSelection.removeAll()
        do {
            try await delete(messageIDs: ids)
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            finishMutation(request)
            await notifyMutationRemoved(messageIDs: ids)
        } catch {
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            handleMutationFailure(error, rollback: rollback)
            finishMutation(request)
        }
    }

    private func snoozePendingHeaders(until wakeAt: Date) {
        let headers = pendingSnoozeHeaders
        pendingSnoozeHeaders = []
        snooze(headers: headers, until: wakeAt)
    }

    private func snooze(headers targetHeaders: [MessageHeader], until wakeAt: Date) {
        guard !targetHeaders.isEmpty else { return }
        let previousState = localMessageWorkflowState
        let sourceMessageIDs = sourceMessageIDs(for: targetHeaders)
        var nextState = localMessageWorkflowState
        for sourceMessageID in sourceMessageIDs {
            nextState = LocalMessageWorkflowStatePolicy.snoozing(
                sourceMessageID,
                until: wakeAt,
                in: nextState
            )
        }
        saveLocalMessageWorkflowState(nextState)
        navigation.bulkSelection.subtract(Set(targetHeaders.map(\.id)))
        reconcileNavigationHeaders(selectFirstIfNeeded: selectsFirstMessageWhenNeeded)
        pushLocalWorkflowUndo(
            description: targetHeaders.count == 1 ? "Snoozed" : "Snoozed \(targetHeaders.count) messages",
            previousState: previousState
        )
    }

    private func clearSnooze(headers targetHeaders: [MessageHeader]) {
        guard !targetHeaders.isEmpty else { return }
        let previousState = localMessageWorkflowState
        let nextState = LocalMessageWorkflowStatePolicy.clearingSnooze(
            sourceMessageIDs(for: targetHeaders),
            in: localMessageWorkflowState
        )
        saveLocalMessageWorkflowState(nextState)
        navigation.bulkSelection.subtract(Set(targetHeaders.map(\.id)))
        reconcileNavigationHeaders(selectFirstIfNeeded: selectsFirstMessageWhenNeeded)
        pushLocalWorkflowUndo(
            description: targetHeaders.count == 1 ? "Unsnoozed" : "Unsnoozed \(targetHeaders.count) messages",
            previousState: previousState
        )
    }

    private func markDone(headers targetHeaders: [MessageHeader]) {
        guard !targetHeaders.isEmpty else { return }
        let previousState = localMessageWorkflowState
        let nextState = LocalMessageWorkflowStatePolicy.markingDone(
            sourceMessageIDs(for: targetHeaders),
            in: localMessageWorkflowState
        )
        saveLocalMessageWorkflowState(nextState)
        navigation.bulkSelection.subtract(Set(targetHeaders.map(\.id)))
        reconcileNavigationHeaders(selectFirstIfNeeded: selectsFirstMessageWhenNeeded)
        pushLocalWorkflowUndo(
            description: targetHeaders.count == 1 ? "Marked Done" : "Marked \(targetHeaders.count) Done",
            previousState: previousState
        )
    }

    private func clearDone(headers targetHeaders: [MessageHeader]) {
        guard !targetHeaders.isEmpty else { return }
        let previousState = localMessageWorkflowState
        let nextState = LocalMessageWorkflowStatePolicy.clearingDone(
            sourceMessageIDs(for: targetHeaders),
            in: localMessageWorkflowState
        )
        saveLocalMessageWorkflowState(nextState)
        navigation.bulkSelection.subtract(Set(targetHeaders.map(\.id)))
        reconcileNavigationHeaders(selectFirstIfNeeded: selectsFirstMessageWhenNeeded)
        pushLocalWorkflowUndo(
            description: targetHeaders.count == 1 ? "Marked Not Done" : "Marked \(targetHeaders.count) Not Done",
            previousState: previousState
        )
    }

    private func sourceMessageIDs(
        for headers: [MessageHeader]
    ) -> [SourceMessageID] {
        headers.map {
            SourceMessageID(sourceID: workflowSourceID, messageID: $0.id)
        }
    }

    private func isSnoozed(_ header: MessageHeader) -> Bool {
        localMessageWorkflowState.isSnoozed(
            SourceMessageID(sourceID: workflowSourceID, messageID: header.id)
        )
    }

    private func isDone(_ header: MessageHeader) -> Bool {
        localMessageWorkflowState.isDone(
            SourceMessageID(sourceID: workflowSourceID, messageID: header.id)
        )
    }

    private func isKeptOffline(_ header: MessageHeader) -> Bool {
        MessageOfflineRetentionOverrideStore().isKeptOffline(
            SourceMessageID(sourceID: workflowSourceID, messageID: header.id)
        )
    }

    private func hasNote(_ header: MessageHeader) -> Bool {
        localMessageWorkflowState.note(
            for: SourceMessageID(sourceID: workflowSourceID, messageID: header.id)
        ) != nil
    }

    /// Toggles the per-message "keep offline" pin (#268). On pin we make a
    /// best-effort body fetch (errors swallowed — e.g. offline) so a cached copy
    /// is more likely to exist; the pin then exempts the body from the retention
    /// sweep. Un-pinning only clears the pin; it does not evict the cached body.
    private func toggleKeepOffline(_ header: MessageHeader) {
        let store = MessageOfflineRetentionOverrideStore()
        let id = SourceMessageID(sourceID: workflowSourceID, messageID: header.id)
        let nowKept = !store.isKeptOffline(id)
        store.setKeptOffline(nowKept, for: id)
        if nowKept {
            Task { _ = try? await backend.body(for: header.id, sourceID: workflowSourceID) }
        }
    }

    private func saveLocalMessageWorkflowState(_ state: LocalMessageWorkflowState) {
        localMessageWorkflowState = state
        LocalMessageWorkflowStateStorage.save(state)
    }

    private func pushLocalWorkflowUndo(
        description: String,
        previousState: LocalMessageWorkflowState
    ) {
        undoQueue?.push(UndoableMutation(description: description) {
            await MainActor.run {
                localMessageWorkflowState = previousState
                LocalMessageWorkflowStateStorage.save(previousState)
                reconcileNavigationHeaders(selectFirstIfNeeded: selectsFirstMessageWhenNeeded)
            }
        })
    }

    private func canStartMutation() -> Bool {
        MessageListMutationStartPolicy.canStartMutation(
            activeRequest: activeMutationRequest,
            isBlocked: isWorkBlocked
        )
    }

    private func startMutationRequest() -> MessageListMutationRequest {
        nextMutationRequestID += 1
        let request = MessageListMutationRequest(
            id: nextMutationRequestID,
            sourceID: sourceID,
            folderID: folder?.id,
            reloadRequestID: navigation.reloadRequestID,
            searchText: navigation.searchText
        )
        activeMutationRequest = request
        return request
    }

    private func canApplyMutationResponse(_ request: MessageListMutationRequest) -> Bool {
        MessageListMutationResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: activeMutationRequest,
            currentSourceID: navigation.selectedSourceID,
            currentFolderID: navigation.selectedFolderID,
            currentReloadRequestID: navigation.reloadRequestID,
            currentSearchText: navigation.searchText
        )
    }

    private func finishMutation(_ request: MessageListMutationRequest) {
        guard activeMutationRequest == request else { return }
        activeMutationRequest = nil
    }

    private func handleMutationFailure(_ error: any Error, rollback: MessageListMutationRollback) {
        let restored = rollback.restore(navigation: navigation)
        headers = restored.headers
        loadedFolderHeaders = restored.loadedFolderHeaders
        mutationErrorStatus = MessageListPresentation.mutationErrorStatus(for: error)
    }

    private func makeMutationRollback() -> MessageListMutationRollback {
        MessageListMutationRollback(
            visibleHeaders: headers,
            loadedFolderHeaders: loadedFolderHeaders,
            navigation: navigation
        )
    }

    private func updateCachedHeaders(
        ids: Set<MessageHeader.ID>,
        mutate: (inout MessageHeader) -> Void
    ) {
        headers = MessageListHeaderMutation.updating(headers, ids: ids, mutate: mutate)
        loadedFolderHeaders = MessageListHeaderMutation.updating(
            loadedFolderHeaders,
            ids: ids,
            mutate: mutate
        )
    }

    private func removeCachedHeaders(ids: Set<MessageHeader.ID>) {
        headers = MessageListHeaderMutation.removing(headers, ids: ids)
        loadedFolderHeaders = MessageListHeaderMutation.removing(loadedFolderHeaders, ids: ids)
    }

    private func reconcileNavigationHeaders(selectFirstIfNeeded: Bool = false) {
        navigation.replaceCurrentFolderHeaders(
            navigationHeaders(for: headers),
            selectFirstIfNeeded: selectFirstIfNeeded
        )
    }

    private func navigationHeaders(for headers: [MessageHeader]) -> [MessageHeader] {
        MessageListNavigationHeaders.headers(
            from: workflowVisibleHeaders(from: headers),
            pinnedIDs: pinnedMessageIDs
        )
    }

    private func visibleHeaders(for headers: [MessageHeader]) -> [MessageHeader] {
        MessageListVisibleHeaders.headers(
            from: headers,
            groupByThread: groupByThread,
            pinnedIDs: pinnedMessageIDs
        )
    }

    private func notifyMutationUpdated(messageIDs: [MessageHeader.ID]) async {
        if let event = MessageListMutationRefreshPolicy.updated(messageIDs: messageIDs, in: folder) {
            await onMutation(event)
        }
    }

    private func notifyMutationRemoved(messageIDs: [MessageHeader.ID]) async {
        if let event = MessageListMutationRefreshPolicy.removed(messageIDs: messageIDs, from: folder) {
            await onMutation(event)
        }
    }

    private func messages(
        in folder: Folder,
        pageToken: String?
    ) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        if let sourceID {
            return try await backend.messages(in: folder, sourceID: sourceID, pageToken: pageToken)
        }
        return try await backend.messages(in: folder, pageToken: pageToken)
    }

    private func search(_ query: SearchQuery) async throws -> [MessageHeader] {
        if let sourceID {
            return try await backend.search(query, sourceID: sourceID)
        }
        return try await backend.search(query)
    }

    /// Adds or removes one provider label on a message, optimistically
    /// updating the row and rolling back on failure like flag toggles.
    private func setLabel(
        _ label: String,
        isEnabled: Bool,
        for header: MessageHeader,
        service: any MessageLabelManaging
    ) async {
        guard canStartMutation() else { return }
        let request = startMutationRequest()
        let rollback = makeMutationRollback()
        mutationErrorStatus = nil
        let mutate: (inout MessageHeader) -> Void = { header in
            if isEnabled {
                if !header.labels.contains(label) { header.labels.append(label) }
            } else {
                header.labels.removeAll { $0 == label }
            }
        }
        navigation.updateHeader(id: header.id, mutate)
        updateCachedHeaders(ids: [header.id], mutate: mutate)
        do {
            try await service.setLabels([label], isEnabled: isEnabled, for: [header.id], sourceID: sourceID)
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            finishMutation(request)
            await notifyMutationUpdated(messageIDs: [header.id])
        } catch {
            guard canApplyMutationResponse(request) else {
                finishMutation(request)
                return
            }
            handleMutationFailure(error, rollback: rollback)
            finishMutation(request)
        }
    }

    private func setRead(_ isRead: Bool, for messageIDs: [String]) async throws {
        if let sourceID {
            try await backend.setRead(isRead, for: messageIDs, sourceID: sourceID)
        } else {
            try await backend.setRead(isRead, for: messageIDs)
        }
    }

    private func setFlagged(_ isFlagged: Bool, for messageIDs: [String]) async throws {
        if let sourceID {
            try await backend.setFlagged(isFlagged, for: messageIDs, sourceID: sourceID)
        } else {
            try await backend.setFlagged(isFlagged, for: messageIDs)
        }
    }

    private func move(messageIDs: [String], to folder: Folder) async throws {
        if let sourceID {
            try await backend.move(messageIDs: messageIDs, to: folder, sourceID: sourceID)
        } else {
            try await backend.move(messageIDs: messageIDs, to: folder)
        }
    }

    private func delete(messageIDs: [String]) async throws {
        if let sourceID {
            try await backend.delete(messageIDs: messageIDs, sourceID: sourceID)
        } else {
            try await backend.delete(messageIDs: messageIDs)
        }
    }
}

struct NaturalLanguageSearchChipStrip: View {
    @Environment(\.brevTheme) private var theme

    let chips: [NaturalLanguageSearchChip]
    let onRemove: (NaturalLanguageSearchChip) -> Void

    var body: some View {
        ForEach(chips) { chip in
            Button {
                onRemove(chip)
            } label: {
                HStack(spacing: BrevSpacing.xxs) {
                    Image(systemName: chip.kind.symbolName)
                        .font(.system(size: 11))
                    Text(chip.label)
                        .brevFont(.caption)
                        .lineLimit(1)
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                }
                .foregroundStyle(theme.textPrimary.color)
                .padding(.horizontal, BrevSpacing.sm)
                .padding(.vertical, BrevSpacing.xxs)
                .background(
                    Capsule().fill(theme.bgSecondary.color)
                )
                .overlay {
                    Capsule().stroke(theme.border.color, lineWidth: 0.5)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Remove search predicate: \(chip.label)", bundle: .module))
            .help(String(localized: "Remove \(chip.label)", bundle: .module))
        }
    }
}

private extension NaturalLanguageSearchChip.Kind {
    var symbolName: String {
        switch self {
        case .keyword:
            return "magnifyingglass"
        case .sender:
            return "person"
        case .subject:
            return "text.alignleft"
        case .date:
            return "calendar"
        case .unread:
            return "envelope.badge"
        case .attachment:
            return "paperclip"
        case .flagged:
            return "flag"
        }
    }
}

struct InboxCategoryBar: View {
    @Environment(\.brevTheme) private var theme
    @Binding var activeCategory: InboxCategory

    private var platform: MessageListSearchFieldPlatform {
        #if os(iOS)
        .iOS
        #else
        .macOS
        #endif
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrevSpacing.xs) {
                ForEach(InboxCategory.selectableCases) { category in
                    categoryButton(category)
                }
            }
            .padding(.horizontal, BrevSpacing.md)
        }
        .frame(height: InboxCategoryBarPresentation.height(platform: platform))
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrevSeparator.color(for: theme))
                .frame(height: 0.5)
        }
        .dynamicTypeSize(MailDenseChromeDynamicType.compactRange)
    }

    private func categoryButton(_ category: InboxCategory) -> some View {
        let isSelected = activeCategory == category
        return Button {
            activeCategory = category
        } label: {
            HStack(spacing: 4) {
                Image(systemName: category.symbolName)
                    .font(.caption2)
                Text(category.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, BrevSpacing.xs)
            .background(
                Capsule()
                    .fill(isSelected ? theme.accent.color.opacity(0.18) : theme.bgSecondary.color.opacity(0.46))
            )
            .overlay {
                Capsule()
                    .stroke(
                        isSelected ? theme.accent.color.opacity(0.55) : theme.border.color.opacity(0.68),
                        lineWidth: 0.5
                    )
            }
            .foregroundStyle(isSelected ? theme.accent.color : theme.textPrimary.color)
            .fixedSize(horizontal: true, vertical: false)
            .inboxCategoryTouchTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(String(localized: "Show \(category.title.lowercased()) mail", bundle: .module))
    }
}

/// Single menu covering both sort order and quick filters, rather than a
/// horizontally scrolling chip strip beside a separate sort control. macOS
/// has no idiom for chrome that scrolls controls out of reach, and the eight
/// quick filters do not fit a segmented control, so this follows the filter
/// menu pattern: every criterion is reachable in one press, with checkmarks
/// showing what is active. Folding sort in keeps it to one control.
/// The glyph for the sort-and-filter menu.
enum MailboxFilterSymbol {
    /// Deliberately the variant without an enclosing circle, in both the
    /// inactive and active state.
    ///
    /// macOS 26 draws every toolbar item inside its own circular bordered
    /// container, so `line.3.horizontal.decrease.circle` put a circle inside a
    /// circle. Mail uses the bare glyph for the same control. The active state
    /// rides on the accent tint rather than on a `.fill` variant, which the bare
    /// symbol does not have.
    static let name = "line.3.horizontal.decrease"
}

struct MailboxFilterMenu: View {
    @Environment(\.brevTheme) private var theme
    @Binding var activeFilter: MailboxFilterQuery
    @Binding var sortOrder: MailboxSortOrder
    var lockedFilters: Set<MailboxQuickFilter> = []
    private let visibleFilters = MailboxQuickFilterPresentation.primaryFilters

    var body: some View {
        filterMenu
    }

    private var filterMenu: some View {
        Menu {
            Section(String(localized: "Sort By", bundle: .module)) {
                ForEach(MailboxSortOrder.allCases) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        if sortOrder == order {
                            Label(order.title, systemImage: "checkmark")
                        } else {
                            Label(order.title, systemImage: order.symbolName)
                        }
                    }
                }
            }
            Section(String(localized: "Filter By", bundle: .module)) {
                ForEach(visibleFilters) { filter in
                    filterToggle(filter)
                }
            }
            Section(String(localized: "Date", bundle: .module)) {
                ForEach(MailboxQuickFilterPresentation.dateFilters) { filter in
                    filterToggle(filter)
                }
            }
            if showsClearFilters {
                Divider()
                Button(String(localized: "Clear Filters", bundle: .module), role: .destructive, action: clearFilters)
            }
        } label: {
            menuLabel
        }
        .accessibilityLabel(filterMenuAccessibilityLabel)
        .help(filterMenuAccessibilityLabel)
    }

    @ViewBuilder
    private var menuLabel: some View {
        // Bare glyph, no title: the toolbar already sizes and backs its
        // items, and the accent tint carries the active state that the old
        // in-pane capsule's fill used to carry. `Label` + `.iconOnly` rather
        // than a bare `Image` so the control keeps an accessibility element
        // in the iPhone navigation bar (the related feature request).
        Label(filterMenuAccessibilityLabel, systemImage: MailboxFilterSymbol.name)
            .labelStyle(.iconOnly)
            .foregroundStyle(
                activeFilterCount > 0 ? theme.accent.color : theme.textPrimary.color
            )
    }

    private func filterToggle(_ filter: MailboxQuickFilter) -> some View {
        Toggle(isOn: Binding(
            get: { activeFilter.activeFilters.contains(filter) },
            set: { _ in activeFilter.toggle(filter) }
        )) {
            Label(filter.title, systemImage: filter.symbolName)
        }
        .disabled(lockedFilters.contains(filter))
    }

    private var activeFilterCount: Int {
        activeFilter.activeFilters.count
    }

    private var filterMenuAccessibilityLabel: String {
        MailboxFilterMenuPresentation.accessibilityLabel(
            activeCount: activeFilterCount,
            sortOrder: sortOrder
        )
    }

    private func clearFilters() {
        let lockedActiveFilters = activeFilter.activeFilters.intersection(lockedFilters)
        activeFilter.clear()
        activeFilter.activeFilters.formUnion(lockedActiveFilters)
    }

    private var showsClearFilters: Bool {
        let hasUnlockedFilters = !activeFilter.activeFilters.subtracting(lockedFilters).isEmpty
        let hasScopedConstraints = activeFilter.senderEmail != nil || activeFilter.sourceIDs?.isEmpty == false
        return activeFilter.isActive && (hasUnlockedFilters || hasScopedConstraints)
    }
}

/// Reports the thread chevron's frame in the enclosing row's coordinate
/// space so the row-level tap gesture can route taps to it.
struct MessageListThreadTogglePreference: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Shared type weight for sender identity throughout the message list.
enum MessageListSenderPresentation {
    static let fontWeight: Font.Weight = .bold

    /// Floor for the sender column so the name stays identifiable at the 280-point
    /// minimum list width. Without it the widest ADR-0023 absolute arrival label
    /// starves the sender down to an ellipsis; past this floor the timestamp
    /// truncates instead, because the sender is the primary scan target.
    static let minimumWidth: CGFloat = 96
}

struct MessageListRowContentPresentation: Equatable, Sendable {
    let showsSourceContext: Bool
    let showsLabelChips: Bool
    let previewLineCount: Int
    let showsStatusIcons: Bool
}

enum MessageListRowContentPolicy {
    static func presentation(
        isCompactWidth: Bool,
        requestedPreviewLineCount: Int
    ) -> MessageListRowContentPresentation {
        MessageListRowContentPresentation(
            showsSourceContext: !isCompactWidth,
            showsLabelChips: !isCompactWidth,
            previewLineCount: isCompactWidth ? 0 : requestedPreviewLineCount,
            // Compact rows keep these states in their VoiceOver value and in the
            // message detail. The visual icons yield so sender and subject remain
            // recognizable at phone width.
            showsStatusIcons: !isCompactWidth
        )
    }
}

private extension View {
    @ViewBuilder
    func inboxCategoryTouchTarget() -> some View {
        #if os(iOS)
        frame(minHeight: 44)
            .contentShape(Rectangle())
        #else
        self
        #endif
    }

    @ViewBuilder
    func accessibilityCompactStatusValue(_ enabled: Bool, value: String) -> some View {
        if enabled, !value.isEmpty {
            accessibilityValue(Text(verbatim: value))
        } else {
            self
        }
    }

    /// Adds a VoiceOver expand/collapse action to rows that group a thread.
    @ViewBuilder
    func accessibilityThreadToggleAction(
        isThreadExpanded: Bool,
        isThread: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if isThread {
            accessibilityAction(
                named: Text(isThreadExpanded ? "Collapse thread" : "Expand thread"),
                action
            )
        } else {
            self
        }
    }
}

struct MessageListRow: View {
    @Environment(\.brevTheme) private var theme
    // Arrival labels are formatted from the environment rather than the process
    // locale so locale/time-zone overrides reach the row and snapshots stay
    // deterministic across machines.
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
    #endif
    let header: MessageHeader
    let threadCount: Int
    let isSelected: Bool
    let isChecked: Bool
    let isInSelectionMode: Bool
    let isPinned: Bool
    let isThreadExpanded: Bool
    let showAvatar: Bool
    let previewLineCount: Int
    let isCompactWidth: Bool
    let fontFamily: MailboxFontFamily
    let textSize: MailboxTextSize
    let density: MailboxListDensity
    let showsAbsoluteArrivalTime: Bool
    let sourceContext: String?
    let isBlockedSender: Bool
    let hasFollowUp: Bool
    let followUpDue: Bool
    let onActivate: () -> Void
    let onToggleCheck: () -> Void
    let onToggleThread: () -> Void

    /// Coordinate space the row's tap gesture and the thread chevron share.
    fileprivate static let rowCoordinateSpace = "brev.messageListRow"

    @State private var isHovered = false
    @State private var threadToggleFrame: CGRect = .zero

    init(
        header: MessageHeader,
        threadCount: Int,
        isSelected: Bool,
        isChecked: Bool,
        isInSelectionMode: Bool,
        isPinned: Bool,
        isThreadExpanded: Bool,
        showAvatar: Bool,
        previewLineCount: Int,
        isCompactWidth: Bool = false,
        fontFamily: MailboxFontFamily,
        textSize: MailboxTextSize,
        density: MailboxListDensity,
        showsAbsoluteArrivalTime: Bool,
        sourceContext: String?,
        isBlockedSender: Bool,
        hasFollowUp: Bool,
        followUpDue: Bool = false,
        onActivate: @escaping () -> Void,
        onToggleCheck: @escaping () -> Void,
        onToggleThread: @escaping () -> Void
    ) {
        self.header = header
        self.threadCount = threadCount
        self.isSelected = isSelected
        self.isChecked = isChecked
        self.isInSelectionMode = isInSelectionMode
        self.isPinned = isPinned
        self.isThreadExpanded = isThreadExpanded
        self.showAvatar = showAvatar
        self.previewLineCount = previewLineCount
        self.isCompactWidth = isCompactWidth
        self.fontFamily = fontFamily
        self.textSize = textSize
        self.density = density
        self.showsAbsoluteArrivalTime = showsAbsoluteArrivalTime
        self.sourceContext = sourceContext
        self.isBlockedSender = isBlockedSender
        self.hasFollowUp = hasFollowUp
        self.followUpDue = followUpDue
        self.onActivate = onActivate
        self.onToggleCheck = onToggleCheck
        self.onToggleThread = onToggleThread
    }

    var body: some View {
        let contentPresentation = MessageListRowContentPolicy.presentation(
            isCompactWidth: isCompactWidth,
            requestedPreviewLineCount: previewLineCount
        )
        HStack(alignment: .top, spacing: BrevSpacing.md) {
            if isInSelectionMode {
                Button(action: onToggleCheck) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isChecked ? theme.accent.color : theme.textTertiary.color)
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
            }
            if showAvatar {
                BrevAvatarView(
                    email: header.from.email,
                    displayName: header.from.name,
                    size: density.avatarSize
                )
            }
            unreadDot
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                HStack(spacing: BrevSpacing.xs) {
                    Text(header.from.displayName)
                        .font(fontFamily.font(
                            size: textSize.listTitlePointSize,
                            weight: MessageListSenderPresentation.fontWeight
                        ))
                        .foregroundStyle(theme.textPrimary.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(
                            minWidth: MessageListSenderPresentation.minimumWidth,
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    // Thread badge and timestamp sit on the trailing edge so they
                    // never compete with the sender for width; the sender absorbs
                    // truncation instead. See ADR-0023's narrow-layout risk note.
                    if threadCount > 1 {
                        Text(verbatim: "\(threadCount)")
                            .font(fontFamily.font(size: textSize.captionPointSize))
                            .foregroundStyle(theme.textSecondary.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(theme.bgSecondary.color)
                            )
                        // Rendered as a plain glyph, not a Button: the row's
                        // high-priority tap gesture wins over nested buttons,
                        // so the tap is routed by hit frame instead.
                        Image(systemName: isThreadExpanded ? "chevron.down" : "chevron.right")
                            .font(fontFamily.font(size: textSize.captionPointSize, weight: .medium))
                            .foregroundStyle(theme.textTertiary.color)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: MessageListThreadTogglePreference.self,
                                        value: proxy.frame(in: .named(Self.rowCoordinateSpace))
                                    )
                                }
                            }
                    }
                    Text(dateLabel)
                        .font(fontFamily.font(size: textSize.captionPointSize))
                        .foregroundStyle(theme.textTertiary.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                // Unread subjects carry the weight and primary colour so the row
                // has a read/unread signal beyond the 8-point dot alone. The
                // sender keeps the emphasis established in #366.
                Text(header.subject)
                    .font(fontFamily.font(
                        size: textSize.listDetailPointSize,
                        weight: header.isRead ? .regular : .semibold
                    ))
                    .foregroundStyle(header.isRead ? theme.textSecondary.color : theme.textPrimary.color)
                    .lineLimit(1)
                if contentPresentation.showsSourceContext, let sourceContext {
                    Text(sourceContext)
                        .font(fontFamily.font(size: textSize.captionPointSize))
                        .foregroundStyle(theme.textTertiary.color)
                        .lineLimit(1)
                }
                if contentPresentation.showsLabelChips {
                    labelChips
                }
                if contentPresentation.previewLineCount > 0 {
                    Text(MessageListPresentation.previewText(from: header.snippet, subject: header.subject))
                        .font(fontFamily.font(size: textSize.listDetailPointSize))
                        .foregroundStyle(theme.textTertiary.color)
                        .lineLimit(contentPresentation.previewLineCount)
                }
            }
            if contentPresentation.showsStatusIcons {
                rowStatusIcons
            }
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, density.verticalPadding)
        .background(rowBackground)
        .opacity(isBlockedSender ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .coordinateSpace(name: Self.rowCoordinateSpace)
        .onPreferenceChange(MessageListThreadTogglePreference.self) { frame in
            threadToggleFrame = frame
        }
        .highPriorityGesture(
            SpatialTapGesture(coordinateSpace: .named(Self.rowCoordinateSpace))
                .onEnded { value in
                    switch MessageListRowTapRouting.destination(
                        for: value.location,
                        threadToggleFrame: threadToggleFrame
                    ) {
                    case .toggleThread:
                        onToggleThread()
                    case .activate:
                        onActivate()
                    }
                }
        )
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityCompactStatusValue(
            isCompactWidth,
            value: compactAccessibilityStatusValue
        )
        .accessibilityAction(named: "Open", onActivate)
        .accessibilityThreadToggleAction(
            isThreadExpanded: isThreadExpanded,
            isThread: threadCount > 1,
            action: onToggleThread
        )
        .dynamicTypeSize(MailDenseChromeDynamicType.range)
    }

    private var compactAccessibilityStatusValue: String {
        var values: [String] = []
        if !header.isRead {
            values.append(String(localized: "Unread", bundle: .module))
        }
        values.append(contentsOf: MessageListRowIndicator.indicators(for: header).map(\.accessibilityLabel))
        if isPinned {
            values.append(String(localized: "Pinned", bundle: .module))
        }
        if header.isFlagged {
            values.append(String(localized: "Flagged", bundle: .module))
        }
        if hasFollowUp {
            values.append(
                followUpDue
                    ? String(localized: "Follow-up reminder due", bundle: .module)
                    : String(localized: "Follow-up reminder set", bundle: .module)
            )
        }
        if isBlockedSender {
            values.append(String(localized: "Blocked sender", bundle: .module))
        }
        if header.hasAttachments {
            values.append(String(localized: "Has attachments", bundle: .module))
        }
        return values.joined(separator: ", ")
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected || isHovered {
            RoundedRectangle(cornerRadius: BrevRadius.md, style: .continuous)
                .fill(isSelected ? selectionFill : theme.bgSecondary.color)
                .padding(.horizontal, BrevSpacing.xxs)
        } else {
            Color.clear
        }
    }

    /// macOS tints list selection with the accent while the window is active and
    /// falls back to a neutral fill when it is not, so the selected row reads as
    /// live rather than stale. The accent is softened so the existing row text
    /// colours keep their contrast instead of needing an inverted treatment.
    private var selectionFill: Color {
        #if os(macOS)
        guard controlActiveState != .inactive else { return theme.selection.color }
        return theme.accent.color.opacity(0.28)
        #else
        return theme.selection.color
        #endif
    }

    @ViewBuilder
    private var unreadDot: some View {
        let diameter: CGFloat = 8
        Circle()
            .fill(header.isRead ? Color.clear : theme.accent.color)
            .frame(width: diameter, height: diameter)
            // Centre the dot on the sender's first line rather than a fixed
            // offset so it tracks the mailbox text-size preference.
            .padding(.top, max(0, (textSize.listTitlePointSize * 1.2 - diameter) / 2))
    }

    /// Provider label chips (Gmail labels). `header.labels` is only populated
    /// by backends advertising `.labels`, so an empty set renders nothing and
    /// folder-only accounts keep the current row height.
    @ViewBuilder
    private var labelChips: some View {
        let chips = MessageLabelPresentation.rowChips(from: header.labels)
        if !chips.visible.isEmpty {
            HStack(spacing: BrevSpacing.xs) {
                ForEach(chips.visible, id: \.self) { label in
                    labelChip(label)
                }
                if chips.overflowCount > 0 {
                    labelChip("+\(chips.overflowCount)")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                String(
                    localized: "Labels: \(MessageLabelPresentation.displayLabels(from: header.labels).joined(separator: ", "))",
                    bundle: .module
                )
            )
        }
    }

    private func labelChip(_ text: String) -> some View {
        Text(text)
            .font(fontFamily.font(size: textSize.captionPointSize))
            .foregroundStyle(theme.textSecondary.color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(theme.bgSecondary.color))
            .overlay(Capsule().stroke(theme.border.color, lineWidth: 0.5))
    }

    private var dateLabel: String {
        MessageListDatePresentation.label(
            for: header.date,
            showsAbsoluteArrivalTime: showsAbsoluteArrivalTime,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
    }

    @ViewBuilder
    private var rowStatusIcons: some View {
        Group {
            ForEach(MessageListRowIndicator.indicators(for: header), id: \.self) { indicator in
                Image(systemName: indicator.symbolName)
                    .foregroundStyle(theme.textTertiary.color)
                    .font(fontFamily.font(size: textSize.captionPointSize))
                    .accessibilityLabel(indicator.accessibilityLabel)
            }
            if isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(theme.accent.color)
                    .font(fontFamily.font(size: textSize.captionPointSize))
                    .accessibilityLabel(String(localized: "Pinned", bundle: .module))
            }
            if header.isFlagged {
                Image(systemName: "flag.fill")
                    .foregroundStyle(theme.warning.color)
                    .font(fontFamily.font(size: textSize.captionPointSize))
                    .accessibilityLabel(String(localized: "Flagged", bundle: .module))
            }
            if hasFollowUp {
                Image(systemName: followUpDue ? "flag.fill" : "flag")
                    .foregroundStyle(theme.warning.color)
                    .font(fontFamily.font(size: textSize.captionPointSize))
                    .accessibilityLabel(
                        followUpDue
                            ? String(localized: "Follow-up reminder due", bundle: .module)
                            : String(localized: "Follow-up reminder set", bundle: .module)
                    )
            }
            if isBlockedSender {
                Image(systemName: "nosign")
                    .foregroundStyle(theme.danger.color)
                    .font(fontFamily.font(size: textSize.captionPointSize))
                    .accessibilityLabel(String(localized: "Blocked sender", bundle: .module))
            }
            if header.hasAttachments {
                Image(systemName: "paperclip")
                    .foregroundStyle(theme.textTertiary.color)
                    .font(fontFamily.font(size: textSize.captionPointSize))
                    .accessibilityLabel(String(localized: "Has attachments", bundle: .module))
            }
        }
        .dynamicTypeSize(MailDenseChromeDynamicType.compactRange)
    }
}

/// Collapsible date-section header. Shared by the per-folder `MessageListView`
/// and the `UnifiedInboxListView` so both group by date identically.
struct MessageListDateSectionHeader: View {
    @Environment(\.brevTheme) private var theme
    let title: String
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        let presentation = MessageListPresentation.sectionHeader(title: title)
        Button(action: onToggle) {
            HStack(spacing: BrevSpacing.xs) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .brevFont(.caption)
                    .foregroundStyle(disclosureColor(for: presentation.style))
                    .frame(width: 12)
                    .accessibilityHidden(true)

                if let icon = presentation.icon {
                    Image(systemName: icon)
                        .brevFont(.caption)
                        .foregroundStyle(theme.accent.color)
                        .accessibilityHidden(true)
                }

                Text(presentation.title)
                    .brevFont(.caption)
                    .foregroundStyle(titleColor(for: presentation.style))

                Spacer(minLength: BrevSpacing.xs)

                Text(verbatim: "\(count)")
                    .brevFont(.caption)
                    .foregroundStyle(countColor(for: presentation.style))
                    .monospacedDigit()
            }
            .textCase(nil)
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor(for: presentation.style))
            .overlay(alignment: .leading) {
                if presentation.style == .pinned {
                    Rectangle()
                        .fill(theme.accent.color)
                        .frame(width: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isCollapsed
                ? "\(title), \(count) messages, collapsed"
                : "\(title), \(count) messages, expanded"
        )
        .accessibilityHint(String(
            localized: "Double-tap to \(isCollapsed ? "expand" : "collapse") this section",
            bundle: .module
        ))
        .dynamicTypeSize(MailDenseChromeDynamicType.compactRange)
    }

    private func disclosureColor(
        for style: MessageListSectionHeaderPresentation.Style
    ) -> Color {
        style == .pinned ? theme.accent.color : theme.textTertiary.color
    }

    private func titleColor(
        for style: MessageListSectionHeaderPresentation.Style
    ) -> Color {
        style == .pinned ? theme.accent.color : theme.textTertiary.color
    }

    private func countColor(
        for style: MessageListSectionHeaderPresentation.Style
    ) -> Color {
        style == .pinned ? theme.accent.color : theme.textTertiary.color
    }

    private func backgroundColor(
        for style: MessageListSectionHeaderPresentation.Style
    ) -> Color {
        style == .pinned ? theme.accentMuted.color.opacity(0.18) : Color.clear
    }
}

struct MessageListEmptyStateView: View {
    @Environment(\.brevTheme) private var theme
    let status: MessageListStatus
    var onAction: (() -> Void)?

    var body: some View {
        VStack(spacing: BrevSpacing.md) {
            Image(systemName: status.icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(theme.textTertiary.color.opacity(0.6))
            Text(status.title)
                .brevFont(.title)
                .foregroundStyle(theme.textSecondary.color)
            Text(status.subtitle)
                .brevFont(.footnote)
                .foregroundStyle(theme.textTertiary.color)
                .multilineTextAlignment(.center)
            if let actionTitle = status.actionTitle,
               let onAction {
                Button(actionTitle, action: onAction)
                    .buttonStyle(.borderless)
                    .foregroundStyle(theme.accent.color)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MessageListFooterStatusView: View {
    @Environment(\.brevTheme) private var theme
    let status: MessageListFooterStatus
    let onAction: () -> Void

    var body: some View {
        VStack(spacing: BrevSpacing.xs) {
            Text(status.message)
                .brevFont(.caption)
                .foregroundStyle(theme.textTertiary.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(status.actionTitle, action: onAction)
                .buttonStyle(.borderless)
                .foregroundStyle(theme.accent.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
    }
}

struct MessageListFolderStatsFooter: View {
    @Environment(\.brevTheme) private var theme
    let presentation: MessageListFolderStatsFooterPresentation

    var body: some View {
        HStack(spacing: BrevSpacing.xs) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.caption)
                .foregroundStyle(theme.textTertiary.color)
            Text(presentation.text)
                .brevFont(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(theme.textSecondary.color)
            Spacer(minLength: BrevSpacing.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.xs)
        .background(Color.clear)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(BrevSeparator.color(for: theme))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

extension View {
    @ViewBuilder
    func messageListThemedRowBackground() -> some View {
        if MessageListPresentation.listChrome.clearsSystemRowBackgrounds {
            listRowBackground(Color.clear)
        } else {
            self
        }
    }
}
