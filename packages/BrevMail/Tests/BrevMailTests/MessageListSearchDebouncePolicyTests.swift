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
@testable import BrevMail
import Testing

@Suite("MessageListSearchDebouncePolicy")
struct MessageListSearchDebouncePolicyTests {
    @Test("attachment search disclosure is shown only while an attachment search is fetching")
    func attachmentSearchDisclosureRequiresActiveFetch() {
        #expect(
            MessageListAttachmentSearchDisclosurePolicy.shouldShowDisclosure(
                query: SearchQuery(hasAttachments: true),
                isLoading: true
            )
        )
        #expect(
            !MessageListAttachmentSearchDisclosurePolicy.shouldShowDisclosure(
                query: SearchQuery(hasAttachments: true, execution: .cacheOnly),
                isLoading: true
            )
        )
        #expect(
            !MessageListAttachmentSearchDisclosurePolicy.shouldShowDisclosure(
                query: SearchQuery(hasAttachments: true),
                isLoading: false
            )
        )
        #expect(
            !MessageListAttachmentSearchDisclosurePolicy.shouldShowDisclosure(
                query: SearchQuery(),
                isLoading: true
            )
        )
    }

    @Test("unified attachment disclosure requires at least one fetching source")
    func unifiedAttachmentDisclosureRequiresFetchingSource() {
        let cacheOnly = SearchQuery(hasAttachments: true, execution: .cacheOnly)
        let server = SearchQuery(hasAttachments: true, execution: .serverOnly)

        #expect(
            MessageListAttachmentSearchDisclosurePolicy.shouldShowDisclosure(
                queries: [cacheOnly, server],
                isLoading: true
            )
        )
        #expect(
            !MessageListAttachmentSearchDisclosurePolicy.shouldShowDisclosure(
                queries: [cacheOnly],
                isLoading: true
            )
        )
        #expect(
            !MessageListAttachmentSearchDisclosurePolicy.shouldShowDisclosure(
                queries: [server],
                isLoading: false
            )
        )
    }

    @Test("iOS search uses in-pane field without keyboard assistant")
    func iOSSearchUsesInPaneFieldWithoutKeyboardAssistant() {
        let configuration = MessageListSearchFieldPolicy.configuration(platform: .iOS)

        #expect(configuration.placement == .inPaneField)
        #expect(configuration.disablesAutocorrection)
        #expect(configuration.hidesInputAssistant)
        #expect(configuration.chromeHeight == 44)
    }

    @Test("category chrome preserves native platform density")
    func categoryChromePreservesNativePlatformDensity() {
        #expect(InboxCategoryBarPresentation.height(platform: .iOS) == 44)
        #expect(InboxCategoryBarPresentation.height(platform: .macOS) == 34)
    }

    /// The macOS field is a plain item in the message list column's toolbar
    /// section, never `.searchable`, whose window-level `NSSearchToolbarItem`
    /// re-lays out and collapses to a magnifying glass on its own when the AI
    /// Sidebar column appears.
    @Test("macOS search stays scoped to the message list column")
    func macOSSearchStaysScopedToMessageListColumn() {
        let configuration = MessageListSearchFieldPolicy.configuration(platform: .macOS)

        #expect(configuration.placement == .inPaneField)
        #expect(!configuration.disablesAutocorrection)
        #expect(!configuration.hidesInputAssistant)
        #expect(configuration.chromeHeight == 24)
    }

    /// Clicking away always collapses the control, and the query survives so
    /// reopening restores it. The collapsed button then has to read as active,
    /// or the list looks filtered for no visible reason.
    @Test("collapsed search button marks a retained query")
    func collapsedSearchButtonMarksRetainedQuery() {
        #expect(MessageListSearchExpansionPolicy.collapsesOnEndEditing())

        #expect(MessageListSearchExpansionPolicy.showsRetainedQuery(isToggledOpen: false, query: "budget"))
        #expect(!MessageListSearchExpansionPolicy.showsRetainedQuery(isToggledOpen: false, query: ""))
        #expect(!MessageListSearchExpansionPolicy.showsRetainedQuery(isToggledOpen: false, query: "  \n "))
        // While open the field shows the query itself, so the button state is moot.
        #expect(!MessageListSearchExpansionPolicy.showsRetainedQuery(isToggledOpen: true, query: "budget"))
    }

    /// An unbounded field takes its width from the reader's action icons, which
    /// then spill back over the message list.
    @Test("expanded search field is bounded by the reader it sits over")
    func expandedSearchFieldIsBoundedByReaderItSitsOver() {
        let onWideReader = MessageListSearchExpansionPolicy.expandedFieldWidth(readerWidth: 1200)
        let onMediumReader = MessageListSearchExpansionPolicy.expandedFieldWidth(readerWidth: 560)
        let onNarrowReader = MessageListSearchExpansionPolicy.expandedFieldWidth(readerWidth: 420)

        #expect(onWideReader == MessageListSearchExpansionPolicy.maximumFieldWidth)
        // 560 - 380 reserved for the rest of the cluster.
        #expect(onMediumReader == 180)
        // Past the floor the field stops shrinking; the reader's own minimum
        // width is what keeps this case rare.
        #expect(onNarrowReader == MessageListSearchExpansionPolicy.minimumFieldWidth)
    }

    /// When the cluster condenses, three buttons leave the section, so the
    /// expanded field may take that width back instead of overflowing.
    @Test("condensed clusters reserve less width beside the expanded field")
    func condensedClustersReserveLessWidth() {
        let full = MessageListSearchExpansionPolicy.reservedClusterWidth(isCondensed: false)
        let condensed = MessageListSearchExpansionPolicy.reservedClusterWidth(isCondensed: true)

        #expect(full == 380)
        #expect(condensed < full)

        let fieldOnCondensedNarrowReader = MessageListSearchExpansionPolicy.expandedFieldWidth(
            readerWidth: 480,
            reservedClusterWidth: condensed
        )
        #expect(fieldOnCondensedNarrowReader > MessageListSearchExpansionPolicy.minimumFieldWidth)
    }

    @MainActor
    @Test("search focus requests increment monotonically")
    func searchFocusRequestsIncrementMonotonically() {
        let navigation = MailNavigationState()

        #expect(navigation.searchFocusRequestID == 0)
        navigation.requestSearchFocus()
        #expect(navigation.searchFocusRequestID == 1)
        navigation.requestSearchFocus()
        #expect(navigation.searchFocusRequestID == 2)
    }

    @Test("folder scoped search plan anchors and queries selected folder")
    func folderScopedSearchPlanAnchorsAndQueriesSelectedFolder() {
        let sourceID = MailSourceID(accountID: "account-a", mailboxID: "mailbox-a")
        let plan = MessageListSearchPlanPolicy.plan(
            text: "budget",
            sourceID: sourceID,
            selectedFolderID: "inbox",
            execution: .cacheOnly,
            searchAllFolders: false,
            searchScope: .all
        )

        #expect(plan.request == MessageListSearchRequest(
            query: "budget",
            sourceID: sourceID,
            folderID: "inbox",
            execution: .cacheOnly
        ))
        #expect(plan.query.text == "budget")
        #expect(plan.query.folderID == "inbox")
        #expect(plan.query.execution == .cacheOnly)
    }

    @Test("all folders search plan keeps selected folder as response anchor and request scope")
    func allFoldersSearchPlanKeepsSelectedFolderAsResponseAnchorAndRequestScope() {
        let sourceID = MailSourceID(accountID: "account-a", mailboxID: "mailbox-a")
        let plan = MessageListSearchPlanPolicy.plan(
            text: "quarterly budget",
            sourceID: sourceID,
            selectedFolderID: "inbox",
            execution: .serverOnly,
            searchAllFolders: true,
            searchScope: .subject
        )

        #expect(plan.request == MessageListSearchRequest(
            query: "quarterly budget",
            sourceID: sourceID,
            searchAllFolders: true,
            searchScope: .subject,
            folderID: "inbox",
            execution: .serverOnly
        ))
        #expect(plan.query.text == "")
        #expect(plan.query.subject == "quarterly budget")
        #expect(plan.query.folderID == nil)
        #expect(plan.query.execution == .serverOnly)
    }

    @Test("search can start when no search request is active")
    func searchCanStartWhenNoSearchRequestIsActive() {
        #expect(MessageListSearchStartPolicy.canStartSearch(
            request: MessageListSearchRequest(query: "budget", folderID: "inbox"),
            activeRequest: nil,
            isBlocked: false
        ))
    }

    @Test("search cannot start while the same query and folder request is active")
    func searchCannotStartWhileSameQueryAndFolderRequestIsActive() {
        let request = MessageListSearchRequest(query: "budget", folderID: "inbox")

        #expect(!MessageListSearchStartPolicy.canStartSearch(
            request: request,
            activeRequest: request,
            isBlocked: false
        ))
    }

    @Test("search cannot start while root work is active")
    func searchCannotStartWhileRootWorkIsActive() {
        #expect(!MessageListSearchStartPolicy.canStartSearch(
            request: MessageListSearchRequest(query: "budget", folderID: "inbox"),
            activeRequest: nil,
            isBlocked: true
        ))
    }

    @Test("search can start when query or folder changes")
    func searchCanStartWhenQueryOrFolderChanges() {
        let activeRequest = MessageListSearchRequest(query: "budget", folderID: "inbox")

        #expect(MessageListSearchStartPolicy.canStartSearch(
            request: MessageListSearchRequest(query: "travel", folderID: "inbox"),
            activeRequest: activeRequest,
            isBlocked: false
        ))
        #expect(MessageListSearchStartPolicy.canStartSearch(
            request: MessageListSearchRequest(query: "budget", folderID: "archive"),
            activeRequest: activeRequest,
            isBlocked: false
        ))
    }

    @Test("search can start when execution changes")
    func searchCanStartWhenExecutionChanges() {
        let activeRequest = MessageListSearchRequest(
            query: "budget",
            folderID: "inbox",
            execution: .cacheOnly
        )

        #expect(MessageListSearchStartPolicy.canStartSearch(
            request: MessageListSearchRequest(
                query: "budget",
                folderID: "inbox",
                execution: .serverOnly
            ),
            activeRequest: activeRequest,
            isBlocked: false
        ))
    }

    @Test("search can start when all-folder mode or scope changes")
    func searchCanStartWhenAllFolderModeOrScopeChanges() {
        let activeRequest = MessageListSearchRequest(
            query: "budget",
            searchAllFolders: false,
            searchScope: .all,
            folderID: "inbox",
            execution: .cacheThenServer
        )

        #expect(MessageListSearchStartPolicy.canStartSearch(
            request: MessageListSearchRequest(
                query: "budget",
                searchAllFolders: true,
                searchScope: .all,
                folderID: "inbox",
                execution: .cacheThenServer
            ),
            activeRequest: activeRequest,
            isBlocked: false
        ))
        #expect(MessageListSearchStartPolicy.canStartSearch(
            request: MessageListSearchRequest(
                query: "budget",
                searchAllFolders: false,
                searchScope: .subject,
                folderID: "inbox",
                execution: .cacheThenServer
            ),
            activeRequest: activeRequest,
            isBlocked: false
        ))
    }

    @Test("server-capable backends default search to cache then server")
    func serverCapableBackendsDefaultSearchToCacheThenServer() {
        #expect(MessageListSearchExecutionPolicy.defaultExecution(
            capabilities: .serverSideSearch
        ) == .cacheThenServer)
    }

    @Test("server-capable backends expose local auto and server search choices")
    func serverCapableBackendsExposeLocalAutoAndServerSearchChoices() {
        #expect(MessageListSearchExecutionPolicy.availableExecutions(
            capabilities: .serverSideSearch
        ) == [.cacheOnly, .cacheThenServer, .serverOnly])
    }

    @Test("backends without server search default search to cache")
    func backendsWithoutServerSearchDefaultSearchToCache() {
        #expect(MessageListSearchExecutionPolicy.defaultExecution(
            capabilities: []
        ) == .cacheOnly)
    }

    @Test("backends without server search expose only local search choice")
    func backendsWithoutServerSearchExposeOnlyLocalSearchChoice() {
        #expect(MessageListSearchExecutionPolicy.availableExecutions(
            capabilities: []
        ) == [.cacheOnly])
    }

    @Test("message list reconciles default search execution after capability hydration")
    func messageListReconcilesDefaultSearchExecutionAfterCapabilityHydration() {
        let reconciled = MessageListSearchExecutionPolicy.reconciledExecution(
            current: .cacheOnly,
            hasUserSelection: false,
            capabilities: .serverSideSearch
        )
        let userSelectedLocal = MessageListSearchExecutionPolicy.reconciledExecution(
            current: .cacheOnly,
            hasUserSelection: true,
            capabilities: .serverSideSearch
        )

        #expect(reconciled == SearchExecutionReconciliation(
            execution: .cacheThenServer,
            hasUserSelection: false
        ))
        #expect(userSelectedLocal == SearchExecutionReconciliation(
            execution: .cacheOnly,
            hasUserSelection: true
        ))
    }

    @Test("message list falls back when selected server search becomes unavailable")
    func messageListFallsBackWhenSelectedServerSearchBecomesUnavailable() {
        let reconciled = MessageListSearchExecutionPolicy.reconciledExecution(
            current: .serverOnly,
            hasUserSelection: true,
            capabilities: []
        )

        #expect(reconciled == SearchExecutionReconciliation(
            execution: .cacheOnly,
            hasUserSelection: false
        ))
    }

    @Test("search execution chips label local auto and server distinctly")
    func searchExecutionChipsLabelLocalAutoAndServerDistinctly() {
        #expect(SearchExecution.cacheOnly.messageListTitle == "Local")
        #expect(SearchExecution.cacheThenServer.messageListTitle == "Auto")
        #expect(SearchExecution.serverOnly.messageListTitle == "Server")
        #expect(SearchExecution.cacheOnly.messageListSymbolName == "internaldrive")
        #expect(SearchExecution.cacheThenServer.messageListSymbolName == "arrow.triangle.2.circlepath")
        #expect(SearchExecution.serverOnly.messageListSymbolName == "network")
    }

    @Test("fallback policy treats rejected IMAP search as local fallback")
    func fallbackPolicyTreatsRejectedIMAPSearchAsLocalFallback() {
        #expect(MessageListSearchFallbackPolicy.shouldApplyLocalFallback(
            for: IMAPClientError.commandFailed(
                command: "UID SEARCH",
                response: "BAD unsupported search key"
            ),
            execution: .cacheThenServer
        ))
        #expect(MessageListSearchFallbackPolicy.shouldApplyLocalFallback(
            for: IMAPClientError.unsupportedSearchCriterion("attachments"),
            execution: .cacheThenServer
        ))
        #expect(MessageListSearchFallbackPolicy.shouldApplyLocalFallback(
            for: MailBackendError.notConnected,
            execution: .cacheThenServer
        ))
        #expect(!MessageListSearchFallbackPolicy.shouldApplyLocalFallback(
            for: MailBackendError.authenticationRequired,
            execution: .cacheThenServer
        ))
        #expect(!MessageListSearchFallbackPolicy.shouldApplyLocalFallback(
            for: IMAPClientError.authenticationFailed("bad credentials"),
            execution: .cacheThenServer
        ))
    }

    @Test("fallback policy does not hide explicit server search failures")
    func fallbackPolicyDoesNotHideExplicitServerSearchFailures() {
        #expect(!MessageListSearchFallbackPolicy.shouldApplyLocalFallback(
            for: IMAPClientError.commandFailed(
                command: "UID SEARCH",
                response: "BAD unsupported search key"
            ),
            execution: .serverOnly
        ))
        #expect(!MessageListSearchFallbackPolicy.shouldApplyLocalFallback(
            for: MailBackendError.notConnected,
            execution: .serverOnly
        ))
        #expect(MessageListSearchFallbackPolicy.shouldApplyLocalFallback(
            for: MailBackendError.notConnected,
            execution: .cacheOnly
        ))
    }

    @Test("cancelled debounce does not continue search")
    func cancelledDebounceDoesNotContinueSearch() async {
        let shouldContinue = await MessageListSearchDebouncePolicy.waitForDebounce { _ in
            throw CancellationError()
        }

        #expect(shouldContinue == false)
    }

    @Test("completed debounce continues unchanged search query")
    func completedDebounceContinuesUnchangedSearchQuery() async {
        let shouldContinue = await MessageListSearchDebouncePolicy.waitForDebounce { _ in
        }

        #expect(shouldContinue == true)
        #expect(MessageListSearchDebouncePolicy.isCurrentSearch(
            requestedQuery: "budget",
            currentSearchText: "  budget \n"
        ))
    }

    @Test("changed or blank search text does not continue old query")
    func changedOrBlankSearchTextDoesNotContinueOldQuery() {
        #expect(!MessageListSearchDebouncePolicy.isCurrentSearch(
            requestedQuery: "budget",
            currentSearchText: "budget update"
        ))
        #expect(!MessageListSearchDebouncePolicy.isCurrentSearch(
            requestedQuery: "budget",
            currentSearchText: " \n\t "
        ))
    }

    @Test("search responses only apply to the same query and folder")
    func searchResponsesOnlyApplyToSameQueryAndFolder() {
        let request = MessageListSearchRequest(query: "budget", folderID: "inbox")

        #expect(MessageListSearchDebouncePolicy.canApplySearchResponse(
            request: request,
            activeRequest: request,
            currentSearchText: " budget ",
            currentFolderID: "inbox"
        ))

        #expect(!MessageListSearchDebouncePolicy.canApplySearchResponse(
            request: request,
            activeRequest: request,
            currentSearchText: "budget",
            currentFolderID: "archive"
        ))

        #expect(!MessageListSearchDebouncePolicy.canApplySearchResponse(
            request: request,
            activeRequest: request,
            currentSearchText: "quarterly budget",
            currentFolderID: "inbox"
        ))
    }

    @Test("search responses only apply to the same source")
    func searchResponsesOnlyApplyToSameSource() {
        let sourceA = MailSourceID(accountID: "account-a", mailboxID: "mailbox-a")
        let sourceB = MailSourceID(accountID: "account-b", mailboxID: "mailbox-b")
        let request = MessageListSearchRequest(
            query: "budget",
            sourceID: sourceA,
            folderID: "inbox"
        )

        #expect(MessageListSearchDebouncePolicy.canApplySearchResponse(
            request: request,
            activeRequest: request,
            currentSearchText: "budget",
            currentSourceID: sourceA,
            currentFolderID: "inbox"
        ))

        #expect(!MessageListSearchDebouncePolicy.canApplySearchResponse(
            request: request,
            activeRequest: request,
            currentSearchText: "budget",
            currentSourceID: sourceB,
            currentFolderID: "inbox"
        ))
    }

    @Test("changed or missing active search request rejects stale search response")
    func changedOrMissingActiveSearchRequestRejectsStaleSearchResponse() {
        let request = MessageListSearchRequest(query: "budget", folderID: "inbox")

        #expect(!MessageListSearchDebouncePolicy.canApplySearchResponse(
            request: request,
            activeRequest: MessageListSearchRequest(query: "travel", folderID: "inbox"),
            currentSearchText: "budget",
            currentFolderID: "inbox"
        ))
        #expect(!MessageListSearchDebouncePolicy.canApplySearchResponse(
            request: request,
            activeRequest: nil,
            currentSearchText: "budget",
            currentFolderID: "inbox"
        ))
    }
}
