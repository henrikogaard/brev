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

private enum UnifiedInboxInitialLoadResult: Sendable {
    case page(
        section: MailSourceSection,
        inbox: Folder,
        headers: [MessageHeader],
        nextPageToken: String?
    )
    case failure(message: String)
    case skipped
}

private enum UnifiedInboxSearchLoadResult: Sendable {
    case results([UnifiedInboxItem])
    case failure(String)
    case missing(String)
    case cancelled
}

private enum UnifiedInboxMoreLoadResult: Sendable {
    case page(sourceID: MailSourceID, headers: [MessageHeader], nextPageToken: String?)
    case failure(String)
    case missing(String)
}

struct UnifiedInboxListView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.undoQueue) private var undoQueue
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Bindable private var navigation: MailNavigationState
    @Binding private var localMessageWorkflowState: LocalMessageWorkflowState
    private let backends: [any MailBackend]
    private let sourceSections: [MailSourceSection]
    private let accountOwnedMailboxEmailsByAccountID: [BrevAccount.ID: Set<String>]
    private let smartView: MailboxSmartView?
    /// When non-nil this list is showing a persisted saved search: the unified
    /// items are additionally filtered by `savedSearchQuery` (ADR-0041).
    private let savedSearchID: String?
    private let savedSearchTitle: String?
    private let savedSearchQuery: SmartMailbox.SavedQuery?
    private let isMutationWorkBlocked: Bool
    private let isWorkBlocked: Bool
    private let composeActions: MailComposePresentationActions
    private let onSelectMessage: ((MessageHeader) -> Void)?
    private let onMutation: (MailEvent) async -> Void

    @State private var requestedScope: String?
    @State private var loadedContentKey: String?
    @State private var loadOwnership = MailListLoadOwnership()
    @State private var items: [UnifiedInboxItem] = []
    @State private var isLoading = false
    @State private var isMutating = false
    @State private var selectedItemIDs: Set<UnifiedInboxItem.ID> = []
    @State private var errorMessage: String?
    @State private var pageCursors: [MailSourceID: UnifiedInboxPageCursor] = [:]
    @State private var isLoadingMore = false
    @State private var activeSearchRequest: UnifiedInboxSearchRequest?
    @State private var loadedSavedQuery: SmartMailbox.SavedQuery?
    @State private var activeAttachmentSearchQueries: [SearchQuery] = []
    @State private var partialLoadErrorStatus: MessageListFooterStatus?
    @State private var mutationErrorStatus: MessageListFooterStatus?
    @State private var loadMoreErrorStatus: MessageListFooterStatus?
    @State private var pendingDeleteItemID: UnifiedInboxItem.ID?
    @State private var pendingSnoozeItems: [UnifiedInboxItem] = []
    @State private var followUpSettings = FollowUpSettings.load()
    /// Progressive disclosure for unified search execution chips.
    @State private var isSearchOptionsExpanded = false

    @AppStorage(MailboxViewPreferenceKey.showSenderAvatars) private var showSenderAvatars = true
    @AppStorage(MailboxViewPreferenceKey.showAbsoluteArrivalTime) private var showAbsoluteArrivalTime = false
    @AppStorage(MailboxViewPreferenceKey.previewLineCount) private var previewLineCountRaw = MailboxPreviewLineCount.one.rawValue
    @AppStorage(MailboxViewPreferenceKey.fontFamily) private var fontFamilyRaw = MailboxFontFamily.system.rawValue
    @AppStorage(MailboxViewPreferenceKey.textSize) private var textSizeRaw = MailboxTextSize.medium.rawValue
    @AppStorage(MailboxViewPreferenceKey.listDensity) private var listDensityRaw = MailboxListDensity.comfortable.rawValue
    @AppStorage(MailboxViewPreferenceKey.sortOrder) private var sortOrderRaw = MailboxSortOrder.newestFirst.rawValue
    @AppStorage(MailboxViewPreferenceKey.groupByDate) private var groupByDate = true
    @AppStorage(MailboxViewPreferenceKey.showFolderStats) private var showFolderStats = true
    @AppStorage(MailboxViewPreferenceKey.folderStatsDetail) private var folderStatsDetailRaw =
        MailboxFolderStatsDetail.compact.rawValue
    @AppStorage(MailboxViewPreferenceKey.inboxClassificationMode) private var inboxClassificationModeRaw =
        InboxClassificationMode.off.rawValue
    @AppStorage(MailboxViewPreferenceKey.groupByThread) private var groupByThread = true
    @AppStorage(MailPinnedMessages.storageKey) private var pinnedMessageIDsRaw = ""
    @State private var activeInboxCategory: InboxCategory = .all
    @State private var inboxCategoryOverrideRevision = 0
    @State private var inboxCategoryOverrideStore = InboxCategoryOverrideStore()
    @State private var presentationSnapshotCache = UnifiedInboxPresentationSnapshotCache()
    @State private var collapsedDateSectionIDs: Set<MessageListDateSection.ID> = []
    /// Expanded threads, keyed by `UnifiedInboxThreadGrouping.key(for:)` —
    /// a raw `threadID` would collide across accounts.
    @State private var expandedThreadKeys: Set<String> = []
    @State private var pinnedMessageIDSet: Set<MessageHeader.ID> = []

    init(
        navigation: MailNavigationState,
        backends: [any MailBackend],
        sourceSections: [MailSourceSection],
        accountOwnedMailboxEmailsByAccountID: [BrevAccount.ID: Set<String>] = [:],
        smartView: MailboxSmartView? = nil,
        savedSearchID: String? = nil,
        savedSearchTitle: String? = nil,
        savedSearchQuery: SmartMailbox.SavedQuery? = nil,
        localMessageWorkflowState: Binding<LocalMessageWorkflowState> = .constant(.defaults),
        isWorkBlocked: Bool,
        isMutationWorkBlocked: Bool = false,
        composeActions: MailComposePresentationActions,
        onSelectMessage: ((MessageHeader) -> Void)? = nil,
        onMutation: @escaping (MailEvent) async -> Void = { _ in }
    ) {
        self.navigation = navigation
        _localMessageWorkflowState = localMessageWorkflowState
        self.backends = backends
        self.sourceSections = sourceSections
        self.accountOwnedMailboxEmailsByAccountID = accountOwnedMailboxEmailsByAccountID
        self.smartView = smartView
        self.savedSearchID = savedSearchID
        self.savedSearchTitle = savedSearchTitle
        self.savedSearchQuery = savedSearchQuery
        self.isWorkBlocked = isWorkBlocked
        self.isMutationWorkBlocked = isMutationWorkBlocked
        self.composeActions = composeActions
        self.onSelectMessage = onSelectMessage
        self.onMutation = onMutation
        // A smart view *is* a saved filter, so entering one seeds the shared
        // filter with its query. The filter now lives on the navigation state
        // so the macOS toolbar can host the control, which means seeding it
        // here rather than in a `State` initial value.
        if let smartViewQuery = smartView?.query, navigation.mailboxFilter != smartViewQuery {
            navigation.mailboxFilter = smartViewQuery
        }
        if savedSearchQuery != nil {
            navigation.searchExecution = .cacheOnly
        } else if !navigation.hasUserSelectedSearchExecution {
            navigation.searchExecution = UnifiedInboxSearchPolicy.defaultExecution(
                from: sourceSections,
                capabilities: { sourceID in
                    backends.first { $0.account.id == sourceID.accountID }?.capabilities ?? []
                }
            )
        }
    }

    var body: some View {
        let presentation = presentationSnapshot
        VStack(spacing: 0) {
            LegacyPinNotice()
            #if os(iOS)
            MessageListSearchBand(navigation: navigation)
            #endif
            if !selectedItemIDs.isEmpty {
                bulkActionBar
            }
            if let mutationErrorStatus {
                BrevInlineStatus(
                    message: mutationErrorStatus.message,
                    tone: .danger,
                    actionTitle: mutationErrorStatus.actionTitle,
                    onAction: {
                        Task { await reloadVisibleItems() }
                    },
                    onDismiss: {
                        self.mutationErrorStatus = nil
                    }
                )
            }
            if let partialLoadErrorStatus {
                BrevInlineStatus(
                    message: partialLoadErrorStatus.message,
                    tone: .warning,
                    actionTitle: partialLoadErrorStatus.actionTitle,
                    onAction: {
                        Task { await reloadVisibleItems() }
                    },
                    onDismiss: {
                        self.partialLoadErrorStatus = nil
                    }
                )
            }
            if showsInboxCategoryBar {
                InboxCategoryBar(activeCategory: $activeInboxCategory)
            }
            if !trimmedSearchText.isEmpty {
                CollapsibleOptionsStrip(
                    isExpanded: $isSearchOptionsExpanded,
                    hasNonDefaultOptions: hasNonDefaultUnifiedSearchOptions,
                    summary: unifiedSearchOptionsSummary
                ) {
                    unifiedSearchExecutionBar
                }
            }
            if MessageListAttachmentSearchDisclosurePolicy.shouldShowDisclosure(
                queries: activeAttachmentSearchQueries,
                isLoading: isLoading
            ) {
                AttachmentSearchDisclosureView()
            }
            Group {
                if let errorMessage {
                    MessageListEmptyStateView(status: MessageListPresentation.errorStatus(errorMessage)) {
                        Task { await reloadVisibleItems() }
                    }
                } else if isLoading, items.isEmpty {
                    BrevSkeletonList(rowCount: 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if presentation.visibleItems.isEmpty {
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
                                ForEach(section.visibleItems) { item in
                                    messageRow(
                                        for: item,
                                        visibleIndex: presentation.visibleIndex(for: item.id) ?? -1,
                                        visibleCount: presentation.visibleItems.count,
                                        pinnedMessageIDs: presentation.pinnedMessageIDs,
                                        threadCounts: presentation.threadCounts
                                    )
                                }
                            }
                        } else {
                            ForEach(presentation.visibleItems) { item in
                                messageRow(
                                    for: item,
                                    visibleIndex: presentation.visibleIndex(for: item.id) ?? -1,
                                    visibleCount: presentation.visibleItems.count,
                                    pinnedMessageIDs: presentation.pinnedMessageIDs,
                                    threadCounts: presentation.threadCounts
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
                    .refreshable { await reloadVisibleItems() }
                }
            }
            if let folderStatsFooterPresentation = folderStatsFooterPresentation(for: presentation) {
                MessageListFolderStatsFooter(presentation: folderStatsFooterPresentation)
            }
        }
        .task(id: loadKey) {
            let scope = "\(reloadKey)|\(navigation.searchText)|\(navigation.searchExecution)"
            if requestedScope != scope {
                loadOwnership.invalidate()
                requestedScope = scope
            }
            guard !isWorkBlocked, !isMutating else { return }
            let request = loadOwnership.begin()
            selectedItemIDs.removeAll()
            navigation.bulkSelection.removeAll()
            reconcileSearchExecutionWithVisibleSources()
            followUpSettings = FollowUpSettings.load()
            if !trimmedSearchText.isEmpty {
                guard await loadOwnership.debounceSearch(request) else { return }
            }
            guard loadOwnership.accepts(request) else { return }
            activeSearchRequest = nil
            await reloadVisibleItems()
        }
        .onAppear { refreshPinnedMessageIDSet() }
        .onDisappear {
            loadOwnership.invalidate()
            activeSearchRequest = nil
            isLoading = false
            isLoadingMore = false
        }
        .onChange(of: reloadKey) {
            expandedThreadKeys.removeAll()
            isSearchOptionsExpanded = false
        }
        .onChange(of: pinnedMessageIDsRaw) { refreshPinnedMessageIDSet() }
        .onReceive(NotificationCenter.default.publisher(for: .brevFollowUpDidChange)) { _ in
            followUpSettings = FollowUpSettings.load()
        }
        .onChange(of: searchCapabilityKey) {
            reconcileSearchExecutionWithVisibleSources()
        }
        .alert(String(localized: "Delete Message?", bundle: .module), isPresented: isDeleteUnifiedItemAlertPresented) {
            Button(String(localized: "Delete", bundle: .module), role: .destructive) {
                Task { await confirmUnifiedItemDelete() }
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {
                pendingDeleteItemID = nil
            }
        } message: {
            if let item = pendingDeleteItem {
                Text("Delete \"\(item.header.subject)\"?", bundle: .module)
            } else {
                Text("Delete this message?", bundle: .module)
            }
        }
        .sheet(isPresented: isUnifiedSnoozePickerPresented) {
            if let item = pendingSnoozeItems.first {
                SnoozePickerView(
                    header: item.header,
                    sourceID: item.sourceID,
                    onConfirm: { wakeAt in
                        snoozePendingItems(until: wakeAt)
                    },
                    onCancel: {
                        pendingSnoozeItems = []
                    }
                )
                .brevTheme(theme)
            }
        }
    }

    private var isUnifiedSnoozePickerPresented: Binding<Bool> {
        Binding(
            get: { !pendingSnoozeItems.isEmpty },
            set: { isPresented in
                if !isPresented { pendingSnoozeItems = [] }
            }
        )
    }

    private var isDeleteUnifiedItemAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteItemID != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteItemID = nil
                }
            }
        )
    }

    private var pendingDeleteItem: UnifiedInboxItem? {
        guard let pendingDeleteItemID else { return nil }
        return items.first(where: { $0.id == pendingDeleteItemID })
    }

    private var supportsRowExport: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    private func confirmUnifiedItemDelete() async {
        guard let item = pendingDeleteItem else {
            pendingDeleteItemID = nil
            return
        }
        performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .delete))
        defer { pendingDeleteItemID = nil }
        await delete(item)
    }

    private struct LoadKey: Equatable {
        let context: String
        let savedQuery: SmartMailbox.SavedQuery?
    }

    private var loadKey: LoadKey {
        LoadKey(
            context: "\(reloadKey)|\(navigation.searchText)|\(navigation.searchExecution)|\(navigation.reloadRequestID)|\(isWorkBlocked)|\(isMutating)",
            savedQuery: savedSearchQuery
        )
    }

    private var reloadKey: String {
        let sourceKey = sourceSections
            .map { "\($0.id.accountID):\($0.id.mailboxID)" }
            .joined(separator: "|")
        return "\(savedSearchID ?? smartView?.id ?? "unified"):\(sourceKey)"
    }

    private var searchCapabilityKey: String {
        UnifiedInboxSearchPolicy.capabilityKey(
            from: sourceSections,
            capabilities: { sourceID in
                backend(for: sourceID)?.capabilities ?? []
            }
        )
    }

    private var presentationSnapshot: UnifiedInboxPresentationSnapshot {
        _ = inboxCategoryOverrideRevision
        let now = Date()
        let temporalInvalidationKey = MailboxListTemporalInvalidationKey.items(
            items,
            filter: navigation.mailboxFilter,
            workflowMode: workflowVisibilityMode,
            workflowState: localMessageWorkflowState,
            now: now
        )
        let key = UnifiedInboxPresentationSnapshotCache.Key(
            items: items,
            pinnedMessageIDsRaw: pinnedMessageIDsRaw,
            groupByDate: groupByDate,
            collapsedDateSectionIDs: collapsedDateSectionIDs,
            groupByThread: groupByThread,
            activeInboxCategory: activeInboxCategory,
            inboxClassificationModeRaw: inboxClassificationModeRaw,
            workflowVisibilityMode: workflowVisibilityMode,
            workflowState: localMessageWorkflowState,
            mailboxFilter: navigation.mailboxFilter,
            savedSearchText: navigation.searchText,
            savedSearchQuery: savedSearchQuery,
            mailboxSortOrder: mailboxSortOrder,
            temporalInvalidationKey: temporalInvalidationKey,
            calendarDay: calendar.startOfDay(for: now),
            calendarIdentifier: calendar.identifier,
            calendarTimeZoneIdentifier: calendar.timeZone.identifier,
            localeIdentifier: locale.identifier
        )
        return presentationSnapshotCache.snapshot(for: key) {
            let pinnedMessageIDs = UnifiedInboxPresentationSnapshot.pinnedMessageIDs(from: pinnedMessageIDsRaw)
            let listed = makeVisibleItems(
                pinnedMessageIDs: pinnedMessageIDs,
                now: now,
                calendar: calendar
            )
            return UnifiedInboxPresentationSnapshot(
                visibleItems: listed.items,
                pinnedMessageIDs: pinnedMessageIDs,
                groupByDate: groupByDate,
                collapsedDateSectionIDs: collapsedDateSectionIDs,
                referenceDate: now,
                calendar: calendar,
                threadCounts: listed.threadCounts
            )
        }
    }

    /// Whether the account behind `sourceID` can expand a thread. Unified
    /// lists mix accounts, so this is resolved per row's source.
    private func isThreadedSource(_ sourceID: MailSourceID) -> Bool {
        backend(for: sourceID)?.groupsMessagesIntoThreads ?? false
    }

    private func makeVisibleItems(
        pinnedMessageIDs: Set<MessageHeader.ID>,
        now: Date,
        calendar: Calendar
    ) -> (items: [UnifiedInboxItem], threadCounts: [String: Int]) {
        let workflowVisible = LocalMessageWorkflowVisibilityPolicy.items(
            items,
            mode: workflowVisibilityMode,
            state: localMessageWorkflowState,
            now: now
        )
        let categorized = InboxClassificationVisibilityPolicy.items(
            workflowVisible,
            selectedCategory: activeInboxCategory,
            settings: inboxClassificationSettings,
            overrideStore: inboxCategoryOverrideStore
        )
        let refinement = savedSearchQuery == nil ? nil : NaturalLanguageSearchPlanner.plan(
            for: navigation.searchText, execution: .cacheOnly, now: now, calendar: calendar
        ).query
        let filtered = categorized
            .filter { navigation.mailboxFilter.matches($0, now: now, calendar: calendar) }
            .filter { savedSearchQuery?.matches(
                $0.header,
                sourceID: $0.sourceID,
                folderRole: $0.folder.role,
                folderIDs: $0.folderMembershipIDs,
                now: now,
                calendar: calendar
            ) ?? true }
            .filter { refinement?.matches($0.header) ?? true }
        let sorted = MessageListSortPolicy.sortedItems(
            filtered,
            by: mailboxSortOrder,
            pinnedIDs: pinnedMessageIDs
        )
        guard groupByThread else { return (sorted, [:]) }
        let threadCounts = UnifiedInboxThreadGrouping.counts(
            for: sorted,
            isThreadedSource: isThreadedSource
        )
        return (
            UnifiedInboxThreadGrouping.parents(from: sorted, counts: threadCounts),
            threadCounts
        )
    }

    // MARK: - Date grouping

    private func dateSectionHeaderRow(_ section: UnifiedInboxDateSection) -> some View {
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

    private func toggleDateSection(_ sectionID: MessageListDateSection.ID) {
        if collapsedDateSectionIDs.contains(sectionID) {
            collapsedDateSectionIDs.remove(sectionID)
        } else {
            collapsedDateSectionIDs.insert(sectionID)
        }
    }

    private var workflowVisibilityMode: LocalMessageWorkflowVisibilityMode {
        if let smartView {
            return smartView.workflowMode
        }
        // A saved search should surface every match, including snoozed/done.
        if savedSearchQuery != nil {
            return .search
        }
        return trimmedSearchText.isEmpty ? .active : .search
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
        inboxClassificationSettings.mode == .categories && smartView == nil
    }

    private var mailboxFolderStatsDetail: MailboxFolderStatsDetail {
        MailboxFolderStatsDetail(rawValue: folderStatsDetailRaw) ?? .compact
    }

    private var pinnedMessageIDs: Set<MessageHeader.ID> {
        pinnedMessageIDSet
    }

    private var selectedItems: [UnifiedInboxItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    private func folderStatsFooterPresentation(
        for presentation: UnifiedInboxPresentationSnapshot
    ) -> MessageListFolderStatsFooterPresentation? {
        guard showFolderStats else { return nil }
        return MessageListPresentation.folderStatsFooter(
            MessageListFolderStats(
                folderName: savedSearchTitle ?? smartView?.title ?? "Unified Inbox",
                totalCount: max(unifiedInboxTotalCount, items.count),
                unreadCount: max(unifiedInboxUnreadCount, items.filter { !$0.header.isRead }.count),
                loadedCount: items.count,
                visibleCount: presentation.visibleItems.count,
                pinnedCount: items.filter { presentation.pinnedMessageIDs.contains($0.pinID) }.count,
                isThreaded: false,
                isConstrained: navigation.mailboxFilter.isActive || !trimmedSearchText.isEmpty
            ),
            detail: mailboxFolderStatsDetail
        )
    }

    private var unifiedInboxTotalCount: Int {
        sourceSections.reduce(into: 0) { count, section in
            count += section.folders.first { $0.role == .inbox }?.totalCount ?? 0
        }
    }

    private var unifiedInboxUnreadCount: Int {
        sourceSections.reduce(into: 0) { count, section in
            count += section.folders.first { $0.role == .inbox }?.unreadCount ?? 0
        }
    }

    private var trimmedSearchText: String {
        navigation.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var naturalLanguageSearchChips: [NaturalLanguageSearchChip] {
        if savedSearchQuery != nil {
            return NaturalLanguageSearchPlanner.plan(for: trimmedSearchText, execution: .cacheOnly).chips
        }
        guard !trimmedSearchText.isEmpty,
              let inboxID = sourceSections.first?.folders.first(where: { $0.role == .inbox })?.id
        else { return [] }
        return UnifiedInboxSearchPolicy.searchPlan(
            text: trimmedSearchText,
            inboxFolderID: inboxID,
            execution: navigation.searchExecution
        ).chips
    }

    private func removeSearchChip(_ chip: NaturalLanguageSearchChip) {
        navigation.searchText = NaturalLanguageSearchChipEditing.removing(
            chip,
            from: navigation.searchText
        )
    }

    private var hasNonDefaultUnifiedSearchOptions: Bool {
        navigation.hasUserSelectedSearchExecution || !naturalLanguageSearchChips.isEmpty
    }

    private var unifiedSearchOptionsSummary: String {
        var parts: [String] = [navigation.searchExecution.messageListTitle]
        if !naturalLanguageSearchChips.isEmpty {
            parts.append("\(naturalLanguageSearchChips.count) filters")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var unifiedSearchExecutionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrevSpacing.xs) {
                ForEach(availableSearchExecutions, id: \.self) { execution in
                    unifiedSearchExecutionChip(execution)
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
    private func unifiedSearchExecutionChip(_ execution: SearchExecution) -> some View {
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

    private var isMutationActionBlocked: Bool {
        isMutating || isWorkBlocked || isMutationWorkBlocked || undoQueue?.isUndoing == true
    }

    private var availableSearchExecutions: [SearchExecution] {
        if savedSearchQuery != nil { return [.cacheOnly] }
        return UnifiedInboxSearchPolicy.availableExecutions(from: sourceSections) { sourceID in
            backend(for: sourceID)?.capabilities ?? []
        }
    }

    private func reconcileSearchExecutionWithVisibleSources() {
        if savedSearchQuery != nil {
            navigation.searchExecution = .cacheOnly
            navigation.hasUserSelectedSearchExecution = false
            return
        }
        let reconciled = UnifiedInboxSearchPolicy.reconciledExecution(
            current: navigation.searchExecution,
            hasUserSelection: navigation.hasUserSelectedSearchExecution,
            from: sourceSections,
            capabilities: { sourceID in
                backend(for: sourceID)?.capabilities ?? []
            }
        )
        navigation.hasUserSelectedSearchExecution = reconciled.hasUserSelection
        if reconciled.execution != navigation.searchExecution {
            navigation.searchExecution = reconciled.execution
        }
    }

    @ViewBuilder
    private var bulkActionBar: some View {
        HStack(spacing: BrevSpacing.xs) {
            Text("\(selectedItemIDs.count) selected", bundle: .module)
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
                label: "Flag",
                systemImage: "flag",
                isDisabled: isMutationActionBlocked
            ) {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .toggleFlag))
                Task { await bulkSetFlag(true) }
            }
            BulkActionIconButton(
                label: "Archive",
                systemImage: "archivebox",
                isDisabled: isMutationActionBlocked || !selectedItems.allSatisfy { $0.archiveFolder != nil }
            ) {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .archive))
                Task { await bulkArchive() }
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
            unifiedBulkOverflowMenu
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
    private var unifiedBulkOverflowMenu: some View {
        let moveSourceID = singleMoveSourceID(for: selectedItems)
        Menu {
            Button(String(localized: "Unflag", bundle: .module)) {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .toggleFlag))
                Task { await bulkSetFlag(false) }
            }
            .disabled(isMutationActionBlocked)
            Button(String(localized: "Snooze…", bundle: .module)) {
                pendingSnoozeItems = selectedItems
            }
            .disabled(isMutationActionBlocked || selectedItems.isEmpty)
            Button(workflowVisibilityMode == .done ? "Not Done" : "Done") {
                if workflowVisibilityMode == .done {
                    clearDone(items: selectedItems)
                } else {
                    markDone(items: selectedItems)
                }
            }
            .disabled(isMutationActionBlocked || selectedItems.isEmpty)
            Button(String(localized: "Move…", bundle: .module)) {
                navigation.presentedSheet = .moveTo(
                    messageIDs: selectedItems.map(\.header.id),
                    sourceID: moveSourceID,
                    currentFolderID: singleCurrentFolderID(for: selectedItems)
                )
            }
            .disabled(isMutationActionBlocked || moveSourceID == nil)
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
    private func messageRow(
        for item: UnifiedInboxItem,
        visibleIndex: Int,
        visibleCount: Int,
        pinnedMessageIDs: Set<MessageHeader.ID>,
        threadCounts: [String: Int]
    ) -> some View {
        let threadKey = UnifiedInboxThreadGrouping.key(for: item)
        let threadCount = threadCounts[threadKey] ?? 1
        parentMessageRow(
            for: item,
            visibleIndex: visibleIndex,
            visibleCount: visibleCount,
            pinnedMessageIDs: pinnedMessageIDs,
            threadKey: threadKey,
            threadCount: threadCount
        )
        if threadCount > 1, expandedThreadKeys.contains(threadKey) {
            let children = UnifiedInboxThreadGrouping.children(
                for: threadKey,
                excludingParentID: item.id,
                from: items
            )
            ForEach(children) { child in
                ThreadInlineChildRow(
                    header: child.header,
                    isSelected: navigation.selectedSourceID == child.sourceID
                        && navigation.selectedMessageID == child.header.id
                ) {
                    if selectedItemIDs.isEmpty {
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
    private func parentMessageRow(
        for item: UnifiedInboxItem,
        visibleIndex: Int,
        visibleCount: Int,
        pinnedMessageIDs: Set<MessageHeader.ID>,
        threadKey: String,
        threadCount: Int
    ) -> some View {
        let followUpReminder = followUpSettings.reminder(for: item.header.id, sourceID: item.sourceID)
        MessageListRow(
            header: item.header,
            threadCount: threadCount,
            isSelected: navigation.selectedSourceID == item.sourceID
                && navigation.selectedMessageID == item.header.id,
            isChecked: selectedItemIDs.contains(item.id),
            isInSelectionMode: !selectedItemIDs.isEmpty,
            isPinned: pinnedMessageIDs.contains(item.pinID),
            isThreadExpanded: expandedThreadKeys.contains(threadKey),
            showAvatar: showSenderAvatars,
            previewLineCount: mailboxPreviewLineCount.visibleLineCount,
            fontFamily: mailboxFontFamily,
            textSize: mailboxTextSize,
            density: mailboxListDensity,
            showsAbsoluteArrivalTime: showAbsoluteArrivalTime,
            sourceContext: item.sourceContext,
            isBlockedSender: false,
            hasFollowUp: followUpReminder != nil,
            followUpDue: followUpReminder?.isDue() == true,
            onActivate: {
                if selectedItemIDs.isEmpty {
                    // Sources without threading never reach a count above 1,
                    // so the capability check already happened upstream.
                    MessageListInlineExpansion.expandIfNeeded(
                        threadID: threadKey,
                        threadCount: threadCount,
                        isThreadingEnabled: true,
                        in: &expandedThreadKeys
                    )
                    selectMessage(item)
                } else {
                    toggleSelection(for: item)
                }
            }
        ) {
            toggleSelection(for: item)
        } onToggleThread: {
            guard threadCount > 1 else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                MessageListInlineExpansion.toggle(
                    threadID: threadKey,
                    in: &expandedThreadKeys
                )
            }
        }
        .help("\(item.sourceTitle)\n\(item.sourceSubtitle)")
        .accessibilityHint(item.sourceSubtitle)
        .draggable(item.dragRepresentation)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .messageListThemedRowBackground()
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            ForEach(
                MessageCommandPresentation.trailingSwipeActions(hasArchive: item.archiveFolder != nil),
                id: \.self
            ) { action in
                trailingSwipeButton(action, for: item)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            ForEach(MessageCommandPresentation.leadingSwipeActions, id: \.self) { action in
                leadingSwipeButton(action, for: item)
            }
        }
        .contextMenu {
            messageContextMenu(for: item)
        }
        .onAppear {
            guard shouldLoadMore(
                visibleIndex: visibleIndex,
                visibleCount: visibleCount
            ) else { return }
            Task { await loadMore() }
        }
    }

    @ViewBuilder
    private func messageContextMenu(for item: UnifiedInboxItem) -> some View {
        let menu = MessageCommandPresentation.contextMenu(
            for: item.header,
            isSelected: selectedItemIDs.contains(item.id),
            isPinned: pinnedMessageIDs.contains(item.pinID),
            isSnoozed: isSnoozed(item),
            isDone: isDone(item),
            isKeptOffline: isKeptOffline(item),
            hasNote: hasNote(item),
            canOpenInNewWindow: false,
            canArchive: item.archiveFolder != nil,
            canMove: !moveFolderCandidates(for: item).isEmpty,
            canCopyToFolder: !moveFolderCandidates(for: item).isEmpty,
            junkActionTitle: junkActionTitle(for: item),
            canBlockSender: false,
            canDelete: true,
            canCreateTask: navigation.presentedSheet == nil,
            canCreateRule: navigation.presentedSheet == nil,
            canCreateMeeting: navigation.presentedSheet == nil,
            canAddNote: navigation.presentedSheet == nil,
            canFollowUp: navigation.presentedSheet == nil,
            hasFollowUp: followUpSettings.reminder(for: item.header.id, sourceID: item.sourceID) != nil,
            canReply: composeActions.isAvailable,
            canShowProperties: true,
            extendedCapabilities: backend(for: item.sourceID)?.extendedCapabilities ?? [],
            canExportEML: supportsRowExport
        )
        ForEach(menu.sections.indices, id: \.self) { sectionIndex in
            if sectionIndex > 0 {
                Divider()
            }
            ForEach(menu.sections[sectionIndex].actions, id: \.action) { action in
                messageContextMenuButton(action, for: item)
            }
        }
        Divider()
        inboxCategoryMenu(for: item)
        pluginMessageContextMenuItems
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

    private func inboxCategoryMenu(for item: UnifiedInboxItem) -> some View {
        let messageID = SourceMessageID(sourceID: item.sourceID, messageID: item.header.id)
        let currentCategory = InboxClassificationPolicy.classification(
            for: item.header,
            sourceID: item.sourceID,
            overrideStore: inboxCategoryOverrideStore
        ).category
        return Menu {
            ForEach(InboxCategory.assignableCases) { category in
                Button {
                    inboxCategoryOverrideStore.set(category, for: messageID)
                    inboxCategoryOverrideRevision += 1
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
        for item: UnifiedInboxItem
    ) -> some View {
        switch presentation.action {
        case .select:
            Button {
                toggleSelection(for: item)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutating || !presentation.isEnabled)
        case .pinToTop:
            Button {
                togglePinned(item)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .toggleRead:
            Button {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .toggleRead))
                Task { await setRead(!item.header.isRead, for: [item]) }
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .toggleFlag:
            Button {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .toggleFlag))
                Task { await setFlagged(!item.header.isFlagged, for: [item]) }
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .toggleSnooze:
            Button {
                if isSnoozed(item) {
                    clearSnooze(items: [item])
                } else {
                    pendingSnoozeItems = [item]
                }
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .toggleDone:
            Button {
                if isDone(item) {
                    clearDone(items: [item])
                } else {
                    markDone(items: [item])
                }
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .reply:
            Button {
                selectMessage(item)
                composeActions.reply(item.header, sourceID: item.sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .replyAll:
            Button {
                selectMessage(item)
                composeActions.replyAll(item.header, sourceID: item.sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .forward:
            Button {
                selectMessage(item)
                composeActions.forward(item.header, sourceID: item.sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .archive:
            Button {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .archive))
                Task { await archive(item) }
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .move:
            Button {
                navigation.presentedSheet = .moveTo(
                    messageIDs: [item.header.id],
                    sourceID: item.sourceID,
                    currentFolderID: item.folder.id
                )
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .copyToFolder:
            Button {
                navigation.presentedSheet = .copyTo(
                    messageIDs: [item.header.id],
                    sourceID: item.sourceID,
                    currentFolderID: item.folder.id
                )
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .setJunk:
            Button {
                let isInSpam = item.folder.role == .spam
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .move))
                Task { await setJunk(!isInSpam, for: item) }
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .delete:
            Button(role: .destructive) {
                pendingDeleteItemID = item.id
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(isMutationActionBlocked || !presentation.isEnabled)
        case .createTask:
            Button {
                selectMessage(item)
                navigation.presentedSheet = .createTask(header: item.header, sourceID: item.sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .followUp:
            Button {
                selectMessage(item)
                navigation.presentedSheet = .followUp(header: item.header, sourceID: item.sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .properties:
            Button {
                navigation.presentedSheet = .messageProperties(header: item.header)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .showHeaders:
            Button {
                navigation.presentedSheet = .showHeaders(header: item.header, sourceID: item.sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .viewSource:
            Button {
                navigation.presentedSheet = .viewSource(header: item.header, sourceID: item.sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .saveAs:
            Button {
                saveMessageAsEML(item)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .createRule:
            Button {
                navigation.presentedSheet = .createRule(header: item.header, sourceID: item.sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .downloadOffline:
            Button {
                toggleKeepOffline(item)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .createMeeting:
            Button {
                navigation.presentedSheet = .createMeeting(header: item.header, sourceID: item.sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .addNote:
            Button {
                navigation.presentedSheet = .messageNote(header: item.header, sourceID: item.sourceID)
            } label: {
                Label(presentation.title, systemImage: presentation.symbolName)
            }
            .disabled(!presentation.isEnabled)
        case .openInNewWindow, .blockSender, .print, .exportPDF:
            EmptyView()
        }
    }

    @ViewBuilder
    private func trailingSwipeButton(
        _ action: MessageCommandPresentation.DirectAction,
        for item: UnifiedInboxItem
    ) -> some View {
        switch action {
        case .archive:
            Button {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .archive))
                Task { await archive(item) }
            } label: {
                Label(String(localized: "Archive", bundle: .module), systemImage: "archivebox")
            }
            .tint(theme.accent.color)
            .disabled(isMutationActionBlocked)
        case .delete:
            Button(role: .destructive) {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .delete))
                Task { await delete(item) }
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
        for item: UnifiedInboxItem
    ) -> some View {
        switch action {
        case .toggleFlag:
            Button {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .toggleFlag))
                Task { await setFlagged(!item.header.isFlagged, for: [item]) }
            } label: {
                Label(
                    MessageCommandPresentation.flagToggleTitle(for: item.header),
                    systemImage: MessageCommandPresentation.flagToggleSymbolName(for: item.header)
                )
            }
            .tint(item.header.isFlagged ? theme.textTertiary.color : theme.warning.color)
            .disabled(isMutationActionBlocked)
        case .toggleRead:
            Button {
                performDirectMessageActionFeedback(MessageCommandPresentation.feedback(for: .toggleRead))
                Task { await setRead(!item.header.isRead, for: [item]) }
            } label: {
                Label(
                    item.header.isRead ? "Unread" : "Read",
                    systemImage: item.header.isRead ? "envelope.badge" : "envelope.open"
                )
            }
            .tint(theme.accent.color)
            .disabled(isMutationActionBlocked)
        default:
            EmptyView()
        }
    }

    private func reload() async {
        if let savedSearchQuery {
            await reloadSavedSearch(savedSearchQuery)
            return
        }
        guard !isWorkBlocked, !isMutating, !Task.isCancelled else { return }
        let loadRequest = loadOwnership.begin()
        defer { if loadOwnership.current == loadRequest { isLoading = false } }
        activeSearchRequest = nil
        activeAttachmentSearchQueries = []
        let contentKey = "folder:\(reloadKey)"
        if loadedContentKey != contentKey { items = [] }
        loadedContentKey = contentKey
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        pageCursors = [:]
        partialLoadErrorStatus = nil
        loadMoreErrorStatus = nil
        var loadedItems = items
        var nextCursors: [MailSourceID: UnifiedInboxPageCursor] = [:]
        var firstError: (any Error)?
        let interval = MailUIPerformanceDiagnostics.beginInterval("Unified Inbox Reload")
        defer { MailUIPerformanceDiagnostics.endInterval(interval) }

        let backendsByAccountID = backends.reduce(into: [BrevAccount.ID: any MailBackend]()) {
            $0[$1.account.id] = $1
        }
        await MailConcurrentWork.forEachResult(sourceSections) { section -> UnifiedInboxInitialLoadResult in
            guard let inbox = section.folders.first(where: { $0.role == .inbox }),
                  let backend = backendsByAccountID[section.account.id]
            else {
                return .skipped
            }
            do {
                let page = try await backend.messages(
                    in: inbox,
                    sourceID: section.id,
                    pageToken: nil
                )
                return .page(
                    section: section,
                    inbox: inbox,
                    headers: page.headers,
                    nextPageToken: page.nextPageToken
                )
            } catch {
                return .failure(message: error.localizedDescription)
            }
        } receive: { _, result in
            guard loadOwnership.accepts(loadRequest) else { return }
            switch result {
            case .page(let section, let inbox, let headers, let nextPageToken):
                recordRecentRecipients(headers, account: section.account)
                loadedItems.removeAll { $0.sourceID == section.id }
                loadedItems.append(contentsOf: headers.map {
                    UnifiedInboxItem(
                        sourceID: section.id,
                        folder: inbox,
                        header: $0,
                        sourceTitle: section.title,
                        sourceSubtitle: section.subtitle,
                        archiveFolder: section.folders.first { $0.role == FolderRole.archive }
                    )
                })
                if let cursor = UnifiedInboxPageCursor(
                    section: section,
                    inbox: inbox,
                    nextPageToken: nextPageToken
                ) {
                    nextCursors[section.id] = cursor
                }
            case .failure(let message):
                firstError = firstError ?? MailBackendError.backendSpecific(message: message)
            case .skipped:
                break
            }
            items = UnifiedInboxPagination.sortedItems(loadedItems)
            reconcileNavigationAfterItemsChanged()
        }

        guard loadOwnership.accepts(loadRequest) else { return }
        items = UnifiedInboxPagination.sortedItems(loadedItems)
        reconcileNavigationAfterItemsChanged()
        pageCursors = nextCursors
        if items.isEmpty, let firstError {
            errorMessage = MessageListPresentation.loadErrorMessage(for: firstError)
            MailUIPerformanceDiagnostics.logListFailed(
                surface: .unifiedInbox,
                path: .reload,
                error: firstError,
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
        } else if let firstError {
            partialLoadErrorStatus = MessageListPresentation.partialLoadErrorStatus(
                for: firstError
            )
            MailUIPerformanceDiagnostics.logListFinished(
                surface: .unifiedInbox,
                path: .reload,
                resultCount: items.count,
                hasMore: !pageCursors.isEmpty,
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
        } else {
            MailUIPerformanceDiagnostics.logListFinished(
                surface: .unifiedInbox,
                path: .reload,
                resultCount: items.count,
                hasMore: !pageCursors.isEmpty,
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
        }
        isLoading = false
    }

    private func reloadSavedSearch(_ query: SmartMailbox.SavedQuery) async {
        guard !isWorkBlocked, !isMutating, !Task.isCancelled else { return }
        let request = loadOwnership.begin()
        defer { if loadOwnership.current == request { isLoading = false } }
        activeSearchRequest = nil
        activeAttachmentSearchQueries = []
        let contentKey = "saved:\(reloadKey)"
        if loadedContentKey != contentKey { items = [] }
        loadedContentKey = contentKey
        loadedSavedQuery = nil
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        partialLoadErrorStatus = nil
        loadMoreErrorStatus = nil
        pageCursors = [:]
        var loaded: [UnifiedInboxItem] = []
        var firstError: String?
        let byAccount = Dictionary(backends.map { ($0.account.id, $0) }, uniquingKeysWith: { first, _ in first })
        await MailConcurrentWork.forEachResult(sourceSections) { section -> ([UnifiedInboxItem], String?) in
            guard let backend = byAccount[section.account.id] else { return ([], nil) }
            do {
                return try await (SavedSearchMessageLoader.load(section: section, backend: backend, query: query), nil)
            } catch {
                return ([], error.localizedDescription)
            }
        } receive: { _, result in
            guard loadOwnership.accepts(request) else { return }
            loaded.append(contentsOf: result.0)
            firstError = firstError ?? result.1
        }
        guard loadOwnership.accepts(request) else { return }
        items = UnifiedInboxPagination.sortedItems(loaded)
        loadedSavedQuery = firstError == nil ? query : nil
        reconcileNavigationAfterItemsChanged()
        if let firstError {
            let error = MailBackendError.backendSpecific(message: firstError)
            if items.isEmpty {
                errorMessage = MessageListPresentation.loadErrorMessage(for: error)
            } else {
                partialLoadErrorStatus = MessageListPresentation.partialLoadErrorStatus(for: error)
            }
        }
    }

    private func recordRecentRecipients(_ headers: [MessageHeader], account: BrevAccount) {
        let observations = RecentRecipientObservationBuilder.observations(
            from: headers,
            accountID: account.id,
            excludingEmails: [account.emailAddress]
                + Array(accountOwnedMailboxEmailsByAccountID[account.id] ?? [])
        )
        guard !observations.isEmpty else { return }
        Task(priority: .utility) {
            await RecentRecipientRecorder.shared.record(observations)
        }
    }

    private func reloadVisibleItems() async {
        switch MessageListReloadPolicy.operation(forSearchText: navigation.searchText) {
        case .folder:
            await reload()
        case .search(let query):
            await search(query: query)
        }
    }

    private func search(query: String) async {
        if let savedSearchQuery {
            if loadedContentKey != "saved:\(reloadKey)" || loadedSavedQuery != savedSearchQuery {
                await reloadSavedSearch(savedSearchQuery)
            }
            return
        }
        guard !isWorkBlocked, !isMutating, !Task.isCancelled else { return }
        let contentKey = "search:\(reloadKey):\(query):\(navigation.searchExecution)"
        if loadedContentKey != contentKey { items = [] }
        loadedContentKey = contentKey
        let sourceIDs = sourceSections.map(\.id)
        let request = UnifiedInboxSearchRequest(
            query: query,
            sourceIDs: sourceIDs,
            execution: navigation.searchExecution
        )
        guard activeSearchRequest != request || !isLoading else { return }
        let loadRequest = loadOwnership.begin()
        defer { if loadOwnership.current == loadRequest { isLoading = false } }
        activeSearchRequest = request
        activeAttachmentSearchQueries = []
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        pageCursors = [:]
        partialLoadErrorStatus = nil
        loadMoreErrorStatus = nil
        mutationErrorStatus = nil
        let interval = MailUIPerformanceDiagnostics.beginInterval("Unified Inbox Search")
        defer { MailUIPerformanceDiagnostics.endInterval(interval) }

        let searchPlans = UnifiedInboxSearchPolicy.searchPlans(
            text: query,
            from: sourceSections,
            execution: navigation.searchExecution,
            capabilities: { sourceID in
                backend(for: sourceID)?.capabilities ?? []
            }
        )
        activeAttachmentSearchQueries = searchPlans.map(\.query)
        var loadedItems: [UnifiedInboxItem] = []
        var firstError: (any Error)?
        let backendsByAccountID = Dictionary(backends.map { ($0.account.id, $0) }) { _, latest in latest }

        let results = await MailConcurrentWork.map(searchPlans) { plan in
            let source = plan.source
            guard let backend = backendsByAccountID[source.sourceID.accountID] else {
                return UnifiedInboxSearchLoadResult.missing(source.sourceID.accountID)
            }
            do {
                let headers = try await backend.search(plan.query, sourceID: source.sourceID)
                return UnifiedInboxSearchLoadResult.results(
                    UnifiedInboxSearchPolicy.items(from: headers, source: source)
                )
            } catch is CancellationError {
                return UnifiedInboxSearchLoadResult.cancelled
            } catch {
                return UnifiedInboxSearchLoadResult.failure(error.localizedDescription)
            }
        }
        guard loadOwnership.accepts(loadRequest) else { return }
        for result in results {
            switch result {
            case .results(let sourceItems):
                loadedItems.append(contentsOf: sourceItems)
            case .failure(let message):
                firstError = firstError ?? MailBackendError.backendSpecific(message: message)
            case .missing(let accountID):
                firstError = firstError ?? MailBackendError.notFound(id: accountID)
            case .cancelled:
                finishSearch(request)
                return
            }
        }

        guard loadOwnership.accepts(loadRequest), UnifiedInboxSearchResponsePolicy.canApplySearchResponse(
            request: request,
            activeRequest: activeSearchRequest,
            currentSearchText: navigation.searchText,
            currentSourceIDs: sourceSections.map(\.id)
        ) else {
            finishSearch(request)
            return
        }

        items = UnifiedInboxPagination.sortedItems(loadedItems)
        reconcileNavigationAfterItemsChanged()
        let skippedCount = sourceSections.count - searchPlans.count
        if items.isEmpty, let firstError {
            errorMessage = MessageListPresentation.searchErrorMessage(for: firstError)
            MailUIPerformanceDiagnostics.logListFailed(
                surface: .unifiedInbox,
                path: .search,
                error: firstError,
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
        } else if let firstError {
            partialLoadErrorStatus = MessageListPresentation.partialLoadErrorStatus(
                for: firstError
            )
            MailUIPerformanceDiagnostics.logListSearchFinished(
                surface: .unifiedInbox,
                execution: navigation.searchExecution,
                resultCount: items.count,
                skippedSourceCount: skippedCount,
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
        } else if skippedCount > 0 {
            partialLoadErrorStatus = MessageListFooterStatus(
                message: "\(skippedCount) mailbox\(skippedCount == 1 ? "" : "es") skipped because server search is unavailable.",
                actionTitle: "Refresh"
            )
            MailUIPerformanceDiagnostics.logListSearchFinished(
                surface: .unifiedInbox,
                execution: navigation.searchExecution,
                resultCount: items.count,
                skippedSourceCount: skippedCount,
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
        } else {
            MailUIPerformanceDiagnostics.logListSearchFinished(
                surface: .unifiedInbox,
                execution: navigation.searchExecution,
                resultCount: items.count,
                skippedSourceCount: skippedCount,
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
        }
        finishSearch(request)
    }

    private func finishSearch(_ request: UnifiedInboxSearchRequest) {
        guard activeSearchRequest == request else { return }
        activeSearchRequest = nil
        activeAttachmentSearchQueries = []
        isLoading = false
    }

    private func loadMore() async {
        guard !isWorkBlocked,
              !pageCursors.isEmpty,
              !isLoadingMore,
              !isLoading,
              MessageListReloadPolicy.operation(forSearchText: navigation.searchText) == .folder
        else { return }
        let loadRequest = loadOwnership.current
        defer { if loadOwnership.current == loadRequest { isLoadingMore = false } }
        isLoadingMore = true
        loadMoreErrorStatus = nil
        var updatedCursors = pageCursors
        var loadedItems: [UnifiedInboxItem] = []
        var didLoadAnyPage = false
        var firstError: (any Error)?
        let interval = MailUIPerformanceDiagnostics.beginInterval("Unified Inbox Load More")
        defer { MailUIPerformanceDiagnostics.endInterval(interval) }

        let orderedCursors = sourceSections.compactMap { pageCursors[$0.id] }
        let backendsByAccountID = Dictionary(backends.map { ($0.account.id, $0) }) { _, latest in latest }
        let results = await MailConcurrentWork.map(orderedCursors) { cursor in
            guard let backend = backendsByAccountID[cursor.sourceID.accountID] else {
                return UnifiedInboxMoreLoadResult.missing(cursor.sourceID.accountID)
            }
            do {
                let page = try await backend.messages(
                    in: cursor.inbox,
                    sourceID: cursor.sourceID,
                    pageToken: cursor.nextPageToken
                )
                return UnifiedInboxMoreLoadResult.page(
                    sourceID: cursor.sourceID,
                    headers: page.headers,
                    nextPageToken: page.nextPageToken
                )
            } catch {
                return UnifiedInboxMoreLoadResult.failure(error.localizedDescription)
            }
        }
        guard loadOwnership.accepts(loadRequest) else { return }
        for (cursor, result) in zip(orderedCursors, results) {
            switch result {
            case .page(let sourceID, let headers, let nextPageToken):
                didLoadAnyPage = true
                if let backend = backendsByAccountID[sourceID.accountID] {
                    recordRecentRecipients(headers, account: backend.account)
                }
                loadedItems.append(contentsOf: cursor.items(from: headers))
                if let nextPageToken {
                    updatedCursors[sourceID] = cursor.advanced(to: nextPageToken)
                } else {
                    updatedCursors.removeValue(forKey: sourceID)
                }
            case .failure(let message):
                firstError = firstError ?? MailBackendError.backendSpecific(message: message)
            case .missing(let accountID):
                firstError = firstError ?? MailBackendError.notFound(id: accountID)
            }
        }

        if !didLoadAnyPage, let firstError {
            loadMoreErrorStatus = MessageListPresentation.loadMoreErrorStatus(for: firstError)
            MailUIPerformanceDiagnostics.logListFailed(
                surface: .unifiedInbox,
                path: .loadMore,
                error: firstError,
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
        } else {
            items = UnifiedInboxPagination.appendUniquePage(loadedItems, to: items)
            reconcileNavigationAfterItemsChanged()
            if let firstError {
                partialLoadErrorStatus = MessageListPresentation.partialLoadErrorStatus(
                    for: firstError
                )
            }
            pageCursors = updatedCursors
            MailUIPerformanceDiagnostics.logListFinished(
                surface: .unifiedInbox,
                path: .loadMore,
                resultCount: loadedItems.count,
                hasMore: !pageCursors.isEmpty,
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
        }
        isLoadingMore = false
    }

    private func shouldLoadMore(
        visibleIndex: Int,
        visibleCount: Int
    ) -> Bool {
        UnifiedInboxPagination.shouldLoadMore(
            visibleIndex: visibleIndex,
            visibleCount: visibleCount,
            hasMore: !pageCursors.isEmpty,
            isLoadingMore: isLoadingMore,
            searchText: navigation.searchText
        )
    }

    private func selectMessage(_ item: UnifiedInboxItem) {
        navigation.selectMessage(
            item.header,
            in: item.sourceID,
            headers: items.filter { $0.sourceID == item.sourceID }.map(\.header)
        )
        selectedItemIDs.removeAll()
        onSelectMessage?(item.header)
    }

    private func reconcileNavigationAfterItemsChanged(selectFirstIfNeeded: Bool = false) {
        if let selectedSourceID = navigation.selectedSourceID {
            let sourceHeaders = items
                .filter { $0.sourceID == selectedSourceID }
                .map(\.header)
            navigation.replaceCurrentFolderHeaders(
                sourceHeaders,
                selectFirstIfNeeded: selectFirstIfNeeded
            )
            if navigation.selectedMessageID != nil {
                return
            }
        }
        guard selectFirstIfNeeded, let first = presentationSnapshot.visibleItems.first else { return }
        selectMessage(first)
    }

    private func toggleSelection(for item: UnifiedInboxItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    private func togglePinned(_ item: UnifiedInboxItem) {
        do {
            pinnedMessageIDsRaw = try MailPinnedMessages.toggling(
                sourceID: item.sourceID, messageID: item.header.id, in: pinnedMessageIDsRaw
            )
            refreshPinnedMessageIDSet()
        } catch {
            mutationErrorStatus = MessageListPresentation.mutationErrorStatus(for: error)
        }
    }

    private func refreshPinnedMessageIDSet() {
        pinnedMessageIDSet = UnifiedInboxPresentationSnapshot.pinnedMessageIDs(from: pinnedMessageIDsRaw)
    }

    private func bulkSetRead(_ isRead: Bool) async {
        await setRead(isRead, for: selectedItems)
    }

    private func bulkSetFlag(_ isFlagged: Bool) async {
        await setFlagged(isFlagged, for: selectedItems)
    }

    private func bulkArchive() async {
        await archive(selectedItems)
    }

    private func bulkMove(to destination: Folder) async {
        await move(selectedItems, to: destination)
    }

    private func bulkDelete() async {
        await delete(selectedItems)
    }

    private func setRead(_ isRead: Bool, for targetItems: [UnifiedInboxItem]) async {
        let targetItems = targetItems.filter { $0.header.isRead != isRead }
        guard !targetItems.isEmpty else { return }
        let undoLease = undoQueue?.beginMutation(navigation: navigation)
        defer { if let undoLease { undoQueue?.endMutation(undoLease) } }
        var actions: [UndoableMutation?] = []
        await performMutation(targetItems) { sourceID, messageIDs in
            guard let backend = backend(for: sourceID) else {
                throw MailBackendError.notFound(id: sourceID.accountID)
            }
            try await backend.setRead(isRead, for: messageIDs, sourceID: sourceID)
            actions.append(MailFlagUndo.action(
                .read,
                originals: targetItems.filter { $0.sourceID == sourceID && messageIDs.contains($0.header.id) }.map(\.header),
                newValue: isRead,
                sourceID: sourceID,
                backend: backend,
                description: MailFlagUndo.description(.read, value: isRead)
            ))
        } optimisticUpdate: { item in
            item.header.isRead = isRead
        } event: {
            MessageCommandRefreshPolicy.updated($0.header)
        }
        undoQueue?.registerBatch(actions, description: MailFlagUndo.description(.read, value: isRead), lease: undoLease)
    }

    private func setFlagged(_ isFlagged: Bool, for targetItems: [UnifiedInboxItem]) async {
        let targetItems = targetItems.filter { $0.header.isFlagged != isFlagged }
        guard !targetItems.isEmpty else { return }
        let undoLease = undoQueue?.beginMutation(navigation: navigation)
        defer { if let undoLease { undoQueue?.endMutation(undoLease) } }
        var actions: [UndoableMutation?] = []
        await performMutation(targetItems) { sourceID, messageIDs in
            guard let backend = backend(for: sourceID) else {
                throw MailBackendError.notFound(id: sourceID.accountID)
            }
            try await backend.setFlagged(isFlagged, for: messageIDs, sourceID: sourceID)
            actions.append(MailFlagUndo.action(
                .flagged,
                originals: targetItems.filter { $0.sourceID == sourceID && messageIDs.contains($0.header.id) }.map(\.header),
                newValue: isFlagged,
                sourceID: sourceID,
                backend: backend,
                description: MailFlagUndo.description(.flagged, value: isFlagged)
            ))
        } optimisticUpdate: { item in
            item.header.isFlagged = isFlagged
        } event: {
            MessageCommandRefreshPolicy.updated($0.header)
        }
        undoQueue?.registerBatch(actions, description: MailFlagUndo.description(.flagged, value: isFlagged), lease: undoLease)
    }

    private func moveFolderCandidates(for item: UnifiedInboxItem) -> [Folder] {
        guard let section = sourceSections.filter({ $0.id == item.sourceID }).first else {
            return []
        }
        return MessageCommandPresentation.moveFolderCandidates(
            from: section.folders,
            currentFolderID: item.folder.id
        )
    }

    private func junkActionTitle(for item: UnifiedInboxItem) -> String? {
        guard let section = sourceSections.first(where: { $0.id == item.sourceID }) else {
            return nil
        }
        return MessageCommandPresentation.junkActionTitle(
            currentFolder: item.folder,
            capabilities: backend(for: item.sourceID)?.capabilities ?? [],
            folders: section.folders
        )
    }

    private var bulkMoveFolderCandidates: [Folder] {
        guard let sourceID = selectedItems.first?.sourceID,
              selectedItems.allSatisfy({ $0.sourceID == sourceID }),
              let section = sourceSections.first(where: { $0.id == sourceID }) else {
            return []
        }
        return MessageCommandPresentation.moveFolderCandidates(
            from: section.folders,
            currentFolderID: nil
        )
    }

    private func move(_ item: UnifiedInboxItem, to destination: Folder) async {
        await move([item], to: destination)
    }

    private func move(_ targetItems: [UnifiedInboxItem], to destination: Folder) async {
        let targetItems = targetItems.filter { $0.folder.id != destination.id }
        guard !targetItems.isEmpty else { return }
        let undoLease = undoQueue?.beginMutation(navigation: navigation)
        defer { if let undoLease { undoQueue?.endMutation(undoLease) } }
        var receipts: [MailMoveUndo?] = []
        await performMutation(targetItems, removeFromList: true) { sourceID, messageIDs in
            guard let backend = backend(for: sourceID) else {
                throw MailBackendError.notFound(id: sourceID.accountID)
            }
            let sourceItems = targetItems.filter { $0.sourceID == sourceID && messageIDs.contains($0.header.id) }
            for (_, group) in Dictionary(grouping: sourceItems, by: \.folder.id).sorted(by: { $0.key < $1.key }) {
                guard let first = group.first, first.folder.id != destination.id else { continue }
                try await receipts.append(backend.moveWithUndo(
                    messageIDs: group.map(\.header.id),
                    from: first.folder,
                    to: destination,
                    sourceID: sourceID
                ))
            }
        } optimisticUpdate: { _ in } event: {
            MessageCommandRefreshPolicy.removed($0.header)
        }
        undoQueue?.registerMoves(
            receipts,
            description: String(localized: "Moved to \(destination.name)", bundle: .module),
            lease: undoLease
        )
    }

    private func archive(_ item: UnifiedInboxItem) async {
        await archive([item])
    }

    private func archive(_ targetItems: [UnifiedInboxItem]) async {
        let targetItems = targetItems.filter { $0.folder.id != $0.archiveFolder?.id }
        guard !targetItems.isEmpty else { return }
        let undoLease = undoQueue?.beginMutation(navigation: navigation)
        defer { if let undoLease { undoQueue?.endMutation(undoLease) } }
        var receipts: [MailMoveUndo?] = []
        await performMutation(targetItems, removeFromList: true) { sourceID, messageIDs in
            guard let firstItem = targetItems.first(where: { $0.sourceID == sourceID }),
                  let archiveFolder = firstItem.archiveFolder,
                  let backend = backend(for: sourceID)
            else {
                throw MailBackendError.notFound(id: sourceID.mailboxID)
            }
            let sourceItems = targetItems.filter { $0.sourceID == sourceID && messageIDs.contains($0.header.id) }
            for (_, group) in Dictionary(grouping: sourceItems, by: \.folder.id).sorted(by: { $0.key < $1.key }) {
                guard let first = group.first, first.folder.id != archiveFolder.id else { continue }
                try await receipts.append(backend.moveWithUndo(
                    messageIDs: group.map(\.header.id),
                    from: first.folder,
                    to: archiveFolder,
                    sourceID: sourceID
                ))
            }
        } optimisticUpdate: { _ in } event: {
            MessageCommandRefreshPolicy.removed($0.header)
        }
        undoQueue?.registerMoves(receipts, description: String(localized: "Archived", bundle: .module), lease: undoLease)
    }

    private func setJunk(_ isJunk: Bool, for item: UnifiedInboxItem) async {
        let undoLease = undoQueue?.beginMutation(navigation: navigation)
        defer { if let undoLease { undoQueue?.endMutation(undoLease) } }
        var actions: [UndoableMutation?] = []
        await performMutation([item], removeFromList: true) { sourceID, _ in
            guard let backend = backend(for: sourceID),
                  let section = sourceSections.first(where: { $0.id == sourceID }) else {
                throw MailBackendError.notFound(id: sourceID.accountID)
            }
            try await actions.append(MailJunkUndo.perform(isJunk, header: item.header, folders: section.folders,
                                                          sourceID: sourceID, backend: backend, lease: undoLease))
        } optimisticUpdate: { _ in } event: {
            MessageCommandRefreshPolicy.removed($0.header)
        }
        undoQueue?.registerBatch(actions, description: MailJunkUndo.description(isJunk), lease: undoLease)
    }

    private func delete(_ item: UnifiedInboxItem) async {
        await delete([item])
    }

    private func delete(_ targetItems: [UnifiedInboxItem]) async {
        let undoLease = undoQueue?.beginMutation(navigation: navigation)
        defer { if let undoLease { undoQueue?.endMutation(undoLease) } }
        var receipts: [MailMoveUndo?] = []
        await performMutation(targetItems, removeFromList: true) { sourceID, messageIDs in
            guard let backend = backend(for: sourceID) else {
                throw MailBackendError.notFound(id: sourceID.accountID)
            }
            let sourceItems = targetItems.filter { $0.sourceID == sourceID && messageIDs.contains($0.header.id) }
            for (_, group) in Dictionary(grouping: sourceItems, by: \.folder.id).sorted(by: { $0.key < $1.key }) {
                guard let first = group.first else { continue }
                try await receipts.append(MailUndoableDelete.perform(messageIDs: group.map(\.header.id), from: first.folder,
                                                                     folders: sourceSections.first { $0.id == sourceID }?
                                                                         .folders ?? [],
                                                                     sourceID: sourceID, backend: backend))
            }
        } optimisticUpdate: { _ in } event: {
            MessageCommandRefreshPolicy.removed($0.header)
        }
        undoQueue?.registerMoves(receipts, description: String(localized: "Deleted", bundle: .module), lease: undoLease)
    }

    private func snoozePendingItems(until wakeAt: Date) {
        let items = pendingSnoozeItems
        pendingSnoozeItems = []
        snooze(items: items, until: wakeAt)
    }

    private func snooze(items targetItems: [UnifiedInboxItem], until wakeAt: Date) {
        guard !targetItems.isEmpty else { return }
        let previousState = localMessageWorkflowState
        var nextState = localMessageWorkflowState
        for sourceMessageID in sourceMessageIDs(for: targetItems) {
            nextState = LocalMessageWorkflowStatePolicy.snoozing(
                sourceMessageID,
                until: wakeAt,
                in: nextState
            )
        }
        saveLocalMessageWorkflowState(nextState)
        removeSelectionAndReconcileAfterLocalWorkflowMutation(targetItems)
        pushLocalWorkflowUndo(
            description: targetItems.count == 1 ? "Snoozed" : "Snoozed \(targetItems.count) messages",
            previousState: previousState
        )
    }

    private func clearSnooze(items targetItems: [UnifiedInboxItem]) {
        guard !targetItems.isEmpty else { return }
        let previousState = localMessageWorkflowState
        let nextState = LocalMessageWorkflowStatePolicy.clearingSnooze(
            sourceMessageIDs(for: targetItems),
            in: localMessageWorkflowState
        )
        saveLocalMessageWorkflowState(nextState)
        removeSelectionAndReconcileAfterLocalWorkflowMutation(targetItems)
        pushLocalWorkflowUndo(
            description: targetItems.count == 1 ? "Unsnoozed" : "Unsnoozed \(targetItems.count) messages",
            previousState: previousState
        )
    }

    private func markDone(items targetItems: [UnifiedInboxItem]) {
        guard !targetItems.isEmpty else { return }
        let previousState = localMessageWorkflowState
        let nextState = LocalMessageWorkflowStatePolicy.markingDone(
            sourceMessageIDs(for: targetItems),
            in: localMessageWorkflowState
        )
        saveLocalMessageWorkflowState(nextState)
        removeSelectionAndReconcileAfterLocalWorkflowMutation(targetItems)
        pushLocalWorkflowUndo(
            description: targetItems.count == 1 ? "Marked Done" : "Marked \(targetItems.count) Done",
            previousState: previousState
        )
    }

    private func clearDone(items targetItems: [UnifiedInboxItem]) {
        guard !targetItems.isEmpty else { return }
        let previousState = localMessageWorkflowState
        let nextState = LocalMessageWorkflowStatePolicy.clearingDone(
            sourceMessageIDs(for: targetItems),
            in: localMessageWorkflowState
        )
        saveLocalMessageWorkflowState(nextState)
        removeSelectionAndReconcileAfterLocalWorkflowMutation(targetItems)
        pushLocalWorkflowUndo(
            description: targetItems.count == 1 ? "Marked Not Done" : "Marked \(targetItems.count) Not Done",
            previousState: previousState
        )
    }

    private func sourceMessageIDs(
        for items: [UnifiedInboxItem]
    ) -> [SourceMessageID] {
        items.map {
            SourceMessageID(sourceID: $0.sourceID, messageID: $0.header.id)
        }
    }

    private func singleMoveSourceID(for items: [UnifiedInboxItem]) -> MailSourceID? {
        let sourceIDs = Set(items.map(\.sourceID))
        return sourceIDs.count == 1 ? sourceIDs.first : nil
    }

    private func singleCurrentFolderID(for items: [UnifiedInboxItem]) -> Folder.ID? {
        let folderIDs = Set(items.map(\.folder.id))
        return folderIDs.count == 1 ? folderIDs.first : nil
    }

    private func isSnoozed(_ item: UnifiedInboxItem) -> Bool {
        localMessageWorkflowState.isSnoozed(
            SourceMessageID(sourceID: item.sourceID, messageID: item.header.id)
        )
    }

    private func isDone(_ item: UnifiedInboxItem) -> Bool {
        localMessageWorkflowState.isDone(
            SourceMessageID(sourceID: item.sourceID, messageID: item.header.id)
        )
    }

    private func isKeptOffline(_ item: UnifiedInboxItem) -> Bool {
        MessageOfflineRetentionOverrideStore().isKeptOffline(
            SourceMessageID(sourceID: item.sourceID, messageID: item.header.id)
        )
    }

    private func hasNote(_ item: UnifiedInboxItem) -> Bool {
        localMessageWorkflowState.note(
            for: SourceMessageID(sourceID: item.sourceID, messageID: item.header.id)
        ) != nil
    }

    /// Toggles the per-message "keep offline" pin (#268). On pin we make a
    /// best-effort body fetch (errors swallowed) so a cached copy is more likely
    /// to exist; the pin then exempts the body from the retention sweep.
    /// Un-pinning only clears the pin; it does not evict the cached body.
    private func toggleKeepOffline(_ item: UnifiedInboxItem) {
        let store = MessageOfflineRetentionOverrideStore()
        let id = SourceMessageID(sourceID: item.sourceID, messageID: item.header.id)
        let nowKept = !store.isKeptOffline(id)
        store.setKeptOffline(nowKept, for: id)
        if nowKept, let backend = backend(for: item.sourceID) {
            Task { _ = try? await backend.body(for: item.header.id, sourceID: item.sourceID) }
        }
    }

    private func saveLocalMessageWorkflowState(_ state: LocalMessageWorkflowState) {
        localMessageWorkflowState = state
        LocalMessageWorkflowStateStorage.save(state)
    }

    private func removeSelectionAndReconcileAfterLocalWorkflowMutation(
        _ targetItems: [UnifiedInboxItem]
    ) {
        let targetIDs = Set(targetItems.map(\.id))
        let removedSelectedMessage = targetItems.contains { item in
            navigation.selectedSourceID == item.sourceID
                && navigation.selectedMessageID == item.header.id
        }
        selectedItemIDs.subtract(targetIDs)
        if removedSelectedMessage {
            navigation.selectedMessageID = nil
        }
        reconcileNavigationAfterItemsChanged(selectFirstIfNeeded: removedSelectedMessage)
    }

    private func pushLocalWorkflowUndo(
        description: String,
        previousState: LocalMessageWorkflowState
    ) {
        undoQueue?.push(UndoableMutation(description: description) {
            await MainActor.run {
                localMessageWorkflowState = previousState
                LocalMessageWorkflowStateStorage.save(previousState)
                reconcileNavigationAfterItemsChanged(selectFirstIfNeeded: true)
            }
        })
    }

    private struct SourceFolderKey: Hashable {
        let sourceID: MailSourceID
        let folderID: Folder.ID
    }

    private func performMutation(
        _ targetItems: [UnifiedInboxItem],
        removeFromList: Bool = false,
        operation: (MailSourceID, [MessageHeader.ID]) async throws -> Void,
        optimisticUpdate: (inout UnifiedInboxItem) -> Void,
        event: (UnifiedInboxItem) -> MailEvent
    ) async {
        guard !targetItems.isEmpty, !isMutationActionBlocked else { return }
        let rollback = UnifiedInboxMutationRollback(
            items: items,
            selectedItemIDs: selectedItemIDs,
            navigation: navigation
        )
        let targetIDs = Set(targetItems.map(\.id))
        isMutating = true
        mutationErrorStatus = nil
        if removeFromList {
            let removedSelectedMessage = targetItems.contains { item in
                navigation.selectedSourceID == item.sourceID
                    && navigation.selectedMessageID == item.header.id
            }
            items.removeAll { targetIDs.contains($0.id) }
            reconcileNavigationAfterItemsChanged(selectFirstIfNeeded: removedSelectedMessage)
        } else {
            for index in items.indices where targetIDs.contains(items[index].id) {
                optimisticUpdate(&items[index])
                navigation.updateHeader(id: items[index].header.id, sourceID: items[index].sourceID) { header in
                    header = items[index].header
                }
            }
        }
        selectedItemIDs.subtract(targetIDs)
        let selectionRevision = navigation.readerSelectionRevision

        let request = loadOwnership.begin()
        isLoading = false
        isLoadingMore = false
        let grouped = Dictionary(grouping: targetItems, by: { SourceFolderKey(sourceID: $0.sourceID, folderID: $0.folder.id) })
        var failedItemIDs: Set<UnifiedInboxItem.ID> = []
        var firstError: (any Error)?
        var successfulCount = 0
        let orderedGroups = targetItems.map { SourceFolderKey(sourceID: $0.sourceID, folderID: $0.folder.id) }
            .reduce(into: [SourceFolderKey]()) { keys, key in
                if !keys.contains(key) { keys.append(key) }
            }
        for key in orderedGroups {
            let sourceID = key.sourceID
            guard let sourceItems = grouped[key] else { continue }
            do {
                try await operation(sourceID, sourceItems.map(\.header.id))
                successfulCount += sourceItems.count
                for item in sourceItems {
                    await onMutation(event(item))
                }
            } catch {
                failedItemIDs.formUnion(sourceItems.map(\.id))
                firstError = firstError ?? error
            }
        }
        guard loadOwnership.accepts(request) else {
            isMutating = false
            return
        }
        if let firstError {
            let restored = rollback.restoring(failedItemIDs: failedItemIDs, in: items)
            items = restored.items
            selectedItemIDs = restored.selectedItemIDs
            rollback.restoreFailedReader(
                in: navigation,
                failedItemIDs: failedItemIDs,
                expectedSelectionRevision: selectionRevision
            )
            reconcileNavigationAfterItemsChanged()
            let failedCount = failedItemIDs.count
            mutationErrorStatus = MessageListFooterStatus(
                message: String(
                    localized: "Updated \(successfulCount) messages; \(failedCount) failed. \(firstError.localizedDescription)",
                    bundle: .module
                ),
                actionTitle: String(localized: "Refresh", bundle: .module)
            )
        }
        isMutating = false
    }

    private func backend(for sourceID: MailSourceID) -> (any MailBackend)? {
        backends.first { $0.account.id == sourceID.accountID }
    }

    private func saveMessageAsEML(_ item: UnifiedInboxItem) {
        #if canImport(AppKit)
        Task {
            do {
                guard let backend = backend(for: item.sourceID) else {
                    throw MailBackendError.notConnected
                }
                let rawSource = try await backend.rawSource(for: item.header.id, sourceID: item.sourceID)
                _ = try await MainActor.run {
                    try MessageEMLExport.presentSavePanel(header: item.header, rawSource: rawSource)
                }
            } catch {
                mutationErrorStatus = MessageListPresentation.mutationErrorStatus(for: error)
            }
        }
        #endif
    }
}
