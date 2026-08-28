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
import Foundation
import Testing

@Suite("Unified Inbox pagination")
struct UnifiedInboxPaginationTests {
    @Test("page cursors preserve source context for later pages")
    func pageCursorsPreserveSourceContextForLaterPages() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let section = MailSourceSection(
            id: Self.sourceID(account: "account-a", mailbox: "mailbox-a"),
            account: BrevAccount(
                id: "account-a",
                displayName: "Ada",
                emailAddress: "ada@example.org"
            ),
            mailbox: Mailbox(
                id: "mailbox-a",
                email: "ada@example.org",
                displayName: "Personal",
                isPrimary: true
            ),
            folders: [inbox, archive]
        )

        let cursor = UnifiedInboxPageCursor(
            section: section,
            inbox: inbox,
            nextPageToken: "next-1"
        )

        #expect(cursor?.sourceID == section.id)
        #expect(cursor?.inbox == inbox)
        #expect(cursor?.sourceTitle == "Personal")
        #expect(cursor?.sourceSubtitle == "ada@example.org")
        #expect(cursor?.archiveFolder == archive)
        #expect(cursor?.nextPageToken == "next-1")
    }

    @Test("appending a page de-duplicates by source and message and keeps newest first")
    func appendingPageDeduplicatesAndSortsNewestFirst() {
        let sourceA = Self.sourceID(account: "account-a", mailbox: "mailbox-a")
        let sourceB = Self.sourceID(account: "account-b", mailbox: "mailbox-b")
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let existing = [
            Self.item(
                sourceID: sourceA,
                folder: folder,
                messageID: "old",
                date: Date(timeIntervalSince1970: 10)
            ),
            Self.item(
                sourceID: sourceB,
                folder: folder,
                messageID: "shared",
                date: Date(timeIntervalSince1970: 20)
            ),
        ]
        let nextPage = [
            Self.item(
                sourceID: sourceA,
                folder: folder,
                messageID: "new",
                date: Date(timeIntervalSince1970: 30)
            ),
            Self.item(
                sourceID: sourceA,
                folder: folder,
                messageID: "old",
                date: Date(timeIntervalSince1970: 10)
            ),
            Self.item(
                sourceID: sourceB,
                folder: folder,
                messageID: "shared",
                date: Date(timeIntervalSince1970: 40)
            ),
        ]

        let merged = UnifiedInboxPagination.appendUniquePage(nextPage, to: existing)

        #expect(merged.map(\.id) == [
            "account-a:mailbox-a:new",
            "account-b:mailbox-b:shared",
            "account-a:mailbox-a:old",
        ])
    }

    @Test("load more starts near the bottom when a source has another page")
    func loadMoreStartsNearBottomWhenSourceHasAnotherPage() {
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let items = (0 ..< 12).map { index in
            Self.item(
                sourceID: Self.sourceID(account: "account-a", mailbox: "mailbox-a"),
                folder: folder,
                messageID: "message-\(index)",
                date: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        #expect(UnifiedInboxPagination.shouldLoadMore(
            visibleIndex: 4,
            visibleCount: items.count,
            hasMore: true,
            isLoadingMore: false,
            searchText: ""
        ))
        #expect(!UnifiedInboxPagination.shouldLoadMore(
            visibleIndex: 3,
            visibleCount: items.count,
            hasMore: true,
            isLoadingMore: false,
            searchText: ""
        ))
        #expect(!UnifiedInboxPagination.shouldLoadMore(
            visibleIndex: 11,
            visibleCount: items.count,
            hasMore: false,
            isLoadingMore: false,
            searchText: ""
        ))
    }

    @Test("server search skips visible sources without search capability")
    func serverSearchSkipsVisibleSourcesWithoutSearchCapability() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let capable = Self.section(account: "account-a", mailbox: "mailbox-a", folders: [inbox])
        let unsupported = Self.section(account: "account-b", mailbox: "mailbox-b", folders: [inbox])

        let sources = UnifiedInboxSearchPolicy.searchableSources(
            from: [capable, unsupported],
            execution: .serverOnly,
            capabilities: { sourceID in
                sourceID == capable.id ? .serverSideSearch : []
            }
        )

        #expect(sources.map(\.sourceID) == [capable.id])
        #expect(sources.first?.inbox == inbox)
    }

    @Test("cache search includes visible sources without server search capability")
    func cacheSearchIncludesVisibleSourcesWithoutServerSearchCapability() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let first = Self.section(account: "account-a", mailbox: "mailbox-a", folders: [inbox])
        let second = Self.section(account: "account-b", mailbox: "mailbox-b", folders: [inbox])

        let sources = UnifiedInboxSearchPolicy.searchableSources(
            from: [first, second],
            execution: .cacheOnly,
            capabilities: { _ in [] }
        )

        #expect(sources.map(\.sourceID) == [first.id, second.id])
    }

    @Test("unified inbox defaults to auto search when any visible source supports it")
    func unifiedInboxDefaultsToAutoSearchWhenAnyVisibleSourceSupportsIt() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let capable = Self.section(account: "account-a", mailbox: "mailbox-a", folders: [inbox])
        let unsupported = Self.section(account: "account-b", mailbox: "mailbox-b", folders: [inbox])

        let execution = UnifiedInboxSearchPolicy.defaultExecution(
            from: [capable, unsupported],
            capabilities: { sourceID in
                sourceID == capable.id ? .serverSideSearch : []
            }
        )

        #expect(execution == .cacheThenServer)
    }

    @Test("unified inbox search helpers default to auto search")
    func unifiedInboxSearchHelpersDefaultToAutoSearch() {
        let sourceID = Self.sourceID(account: "account-a", mailbox: "mailbox-a")
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let capable = Self.section(account: "account-a", mailbox: "mailbox-a", folders: [inbox])

        let request = UnifiedInboxSearchRequest(query: "receipt", sourceIDs: [sourceID])
        let sources = UnifiedInboxSearchPolicy.searchableSources(
            from: [capable],
            capabilities: { _ in .serverSideSearch }
        )

        #expect(request.execution == .cacheThenServer)
        #expect(sources.map(\.sourceID) == [capable.id])
    }

    @Test("unified inbox exposes local auto and server when any source supports server search")
    func unifiedInboxExposesLocalAutoAndServerWhenAnySourceSupportsServerSearch() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let capable = Self.section(account: "account-a", mailbox: "mailbox-a", folders: [inbox])
        let unsupported = Self.section(account: "account-b", mailbox: "mailbox-b", folders: [inbox])

        let executions = UnifiedInboxSearchPolicy.availableExecutions(
            from: [capable, unsupported],
            capabilities: { sourceID in
                sourceID == capable.id ? .serverSideSearch : []
            }
        )

        #expect(executions == [.cacheOnly, .cacheThenServer, .serverOnly])
    }

    @Test("unified inbox defaults to cache search when no visible source supports server search")
    func unifiedInboxDefaultsToCacheSearchWhenNoVisibleSourceSupportsServerSearch() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let first = Self.section(account: "account-a", mailbox: "mailbox-a", folders: [inbox])
        let second = Self.section(account: "account-b", mailbox: "mailbox-b", folders: [inbox])

        let execution = UnifiedInboxSearchPolicy.defaultExecution(
            from: [first, second],
            capabilities: { _ in [] }
        )

        #expect(execution == .cacheOnly)
    }

    @Test("unified inbox exposes only local search when no source supports server search")
    func unifiedInboxExposesOnlyLocalSearchWhenNoSourceSupportsServerSearch() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let first = Self.section(account: "account-a", mailbox: "mailbox-a", folders: [inbox])
        let second = Self.section(account: "account-b", mailbox: "mailbox-b", folders: [inbox])

        let executions = UnifiedInboxSearchPolicy.availableExecutions(
            from: [first, second],
            capabilities: { _ in [] }
        )

        #expect(executions == [.cacheOnly])
    }

    @Test("unified inbox search capability key changes when source capabilities hydrate")
    func unifiedInboxSearchCapabilityKeyChangesWhenSourceCapabilitiesHydrate() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let first = Self.section(account: "account-a", mailbox: "mailbox-a", folders: [inbox])
        let second = Self.section(account: "account-b", mailbox: "mailbox-b", folders: [inbox])

        let cold = UnifiedInboxSearchPolicy.capabilityKey(
            from: [first, second],
            capabilities: { _ in [] }
        )
        let hydrated = UnifiedInboxSearchPolicy.capabilityKey(
            from: [first, second],
            capabilities: { sourceID in
                sourceID == second.id ? .serverSideSearch : []
            }
        )

        #expect(cold != hydrated)
        #expect(hydrated.contains("\(second.id.accountID):\(second.id.mailboxID):1"))
    }

    @Test("unified inbox reconciles default search execution after source hydration")
    func unifiedInboxReconcilesDefaultSearchExecutionAfterSourceHydration() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let capable = Self.section(account: "account-a", mailbox: "mailbox-a", folders: [inbox])
        let unsupported = Self.section(account: "account-b", mailbox: "mailbox-b", folders: [inbox])

        let reconciled = UnifiedInboxSearchPolicy.reconciledExecution(
            current: .cacheOnly,
            hasUserSelection: false,
            from: [capable, unsupported],
            capabilities: { sourceID in
                sourceID == capable.id ? .serverSideSearch : []
            }
        )
        let userSelectedLocal = UnifiedInboxSearchPolicy.reconciledExecution(
            current: .cacheOnly,
            hasUserSelection: true,
            from: [capable, unsupported],
            capabilities: { sourceID in
                sourceID == capable.id ? .serverSideSearch : []
            }
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

    @Test("unified inbox falls back when selected server search becomes unavailable")
    func unifiedInboxFallsBackWhenSelectedServerSearchBecomesUnavailable() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let unsupported = Self.section(account: "account-a", mailbox: "mailbox-a", folders: [inbox])

        let reconciled = UnifiedInboxSearchPolicy.reconciledExecution(
            current: .serverOnly,
            hasUserSelection: true,
            from: [unsupported],
            capabilities: { _ in [] }
        )

        #expect(reconciled == SearchExecutionReconciliation(
            execution: .cacheOnly,
            hasUserSelection: false
        ))
    }

    @Test("auto search plans use local search for visible sources without server search")
    func autoSearchPlansUseLocalSearchForVisibleSourcesWithoutServerSearch() throws {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let capable = Self.section(account: "account-a", mailbox: "mailbox-a", folders: [inbox])
        let unsupported = Self.section(account: "account-b", mailbox: "mailbox-b", folders: [inbox])

        let plans = UnifiedInboxSearchPolicy.searchPlans(
            text: "receipt",
            from: [capable, unsupported],
            execution: .cacheThenServer,
            capabilities: { sourceID in
                sourceID == capable.id ? .serverSideSearch : []
            }
        )

        #expect(plans.map(\.source.sourceID) == [capable.id, unsupported.id])
        #expect(plans.map(\.query.execution) == [.cacheThenServer, .cacheOnly])
    }

    @Test("unified attachment search disclosure follows per-source execution")
    func unifiedAttachmentSearchDisclosureFollowsPerSourceExecution() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let capable = Self.section(account: "account-a", mailbox: "mailbox-a", folders: [inbox])
        let unsupported = Self.section(account: "account-b", mailbox: "mailbox-b", folders: [inbox])

        let autoPlans = UnifiedInboxSearchPolicy.searchPlans(
            text: "with attachments",
            from: [capable, unsupported],
            execution: .cacheThenServer,
            capabilities: { sourceID in
                sourceID == capable.id ? .serverSideSearch : []
            }
        )
        let cachePlans = UnifiedInboxSearchPolicy.searchPlans(
            text: "with attachments",
            from: [capable, unsupported],
            execution: .cacheOnly,
            capabilities: { _ in .serverSideSearch }
        )

        #expect(autoPlans.allSatisfy { $0.query.hasAttachments == true })
        #expect(
            MessageListAttachmentSearchDisclosurePolicy.shouldShowDisclosure(
                queries: autoPlans.map(\.query),
                isLoading: true
            )
        )
        #expect(
            !MessageListAttachmentSearchDisclosurePolicy.shouldShowDisclosure(
                queries: cachePlans.map(\.query),
                isLoading: true
            )
        )
    }

    @Test("server search plans query only capable visible sources")
    func serverSearchPlansQueryOnlyCapableVisibleSources() throws {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let capable = Self.section(account: "account-a", mailbox: "mailbox-a", folders: [inbox])
        let unsupported = Self.section(account: "account-b", mailbox: "mailbox-b", folders: [inbox])

        let plans = UnifiedInboxSearchPolicy.searchPlans(
            text: "receipt",
            from: [capable, unsupported],
            execution: .serverOnly,
            capabilities: { sourceID in
                sourceID == capable.id ? .serverSideSearch : []
            }
        )

        let plan = try #require(plans.first)
        #expect(plans.count == 1)
        #expect(plan.source.sourceID == capable.id)
        #expect(plan.query.text == "receipt")
        #expect(plan.query.folderID == inbox.id)
        #expect(plan.query.execution == .serverOnly)
    }

    @Test("server search result items preserve source and folder identity")
    func serverSearchResultItemsPreserveSourceAndFolderIdentity() throws {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let section = Self.section(
            account: "account-a",
            mailbox: "mailbox-a",
            folders: [inbox, archive]
        )
        let source = try #require(UnifiedInboxSearchPolicy.searchableSources(
            from: [section],
            capabilities: { _ in .serverSideSearch }
        ).first)
        let header = Self.header(id: "match", folderID: "archive")

        let items = UnifiedInboxSearchPolicy.items(from: [header], source: source)

        #expect(items.map(\.id) == ["account-a:mailbox-a:match"])
        #expect(items.first?.sourceID == section.id)
        #expect(items.first?.folder == archive)
        #expect(items.first?.archiveFolder == archive)
        #expect(items.first?.sourceTitle == section.title)
        #expect(items.first?.sourceSubtitle == section.subtitle)
    }

    @Test("server search responses reject stale queries and source sets")
    func serverSearchResponsesRejectStaleQueriesAndSourceSets() {
        let sourceA = Self.sourceID(account: "account-a", mailbox: "mailbox-a")
        let sourceB = Self.sourceID(account: "account-b", mailbox: "mailbox-b")
        let request = UnifiedInboxSearchRequest(
            query: "budget",
            sourceIDs: [sourceA, sourceB],
            execution: .serverOnly
        )

        #expect(UnifiedInboxSearchResponsePolicy.canApplySearchResponse(
            request: request,
            activeRequest: request,
            currentSearchText: " budget ",
            currentSourceIDs: [sourceA, sourceB]
        ))

        #expect(!UnifiedInboxSearchResponsePolicy.canApplySearchResponse(
            request: request,
            activeRequest: request,
            currentSearchText: "budget",
            currentSourceIDs: [sourceA]
        ))
        #expect(!UnifiedInboxSearchResponsePolicy.canApplySearchResponse(
            request: request,
            activeRequest: request,
            currentSearchText: "quarterly budget",
            currentSourceIDs: [sourceA, sourceB]
        ))
    }

    private static func sourceID(account: String, mailbox: String) -> MailSourceID {
        MailSourceID(accountID: account, mailboxID: mailbox)
    }

    private static func item(
        sourceID: MailSourceID,
        folder: Folder,
        messageID: String,
        date: Date
    ) -> UnifiedInboxItem {
        UnifiedInboxItem(
            sourceID: sourceID,
            folder: folder,
            header: MessageHeader(
                id: messageID,
                threadID: messageID,
                folderID: folder.id,
                from: Correspondent(email: "sender@example.org"),
                subject: messageID,
                snippet: "Preview",
                date: date
            ),
            sourceTitle: "Mailbox",
            sourceSubtitle: "mailbox@example.org",
            archiveFolder: nil
        )
    }

    private static func section(
        account: String,
        mailbox: String,
        folders: [Folder]
    ) -> MailSourceSection {
        MailSourceSection(
            id: sourceID(account: account, mailbox: mailbox),
            account: BrevAccount(
                id: account,
                displayName: account,
                emailAddress: "\(account)@example.org"
            ),
            mailbox: Mailbox(
                id: mailbox,
                email: "\(mailbox)@example.org",
                displayName: mailbox,
                isPrimary: true
            ),
            folders: folders
        )
    }

    private static func header(id: String, folderID: String) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: id,
            folderID: folderID,
            from: Correspondent(email: "sender@example.org"),
            subject: id,
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 100)
        )
    }
}
