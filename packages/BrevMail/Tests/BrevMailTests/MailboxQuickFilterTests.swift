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
import BrevDesign
@testable import BrevMail
import Foundation
import Testing

@Suite("MailboxQuickFilter")
struct MailboxQuickFilterTests {
    @Test("empty filter matches all headers")
    func emptyFilterMatchesAll() {
        let filter = MailboxFilterQuery.none
        let header = Self.makeHeader(isRead: true, isFlagged: false, hasAttachments: false)
        #expect(filter.matches(header))
    }

    @Test("unread filter matches unread only")
    func unreadFilterMatchesUnreadOnly() {
        let filter = MailboxFilterQuery(activeFilters: [.unread], senderEmail: nil)
        let unread = Self.makeHeader(isRead: false)
        let read = Self.makeHeader(isRead: true)

        #expect(filter.matches(unread))
        #expect(!filter.matches(read))
    }

    @Test("flagged filter matches flagged only")
    func flaggedFilterMatchesFlaggedOnly() {
        let filter = MailboxFilterQuery(activeFilters: [.flagged], senderEmail: nil)
        let flagged = Self.makeHeader(isFlagged: true)
        let unflagged = Self.makeHeader(isFlagged: false)

        #expect(filter.matches(flagged))
        #expect(!filter.matches(unflagged))
    }

    @Test("attachment filter matches attachment messages only")
    func attachmentFilterMatchesOnly() {
        let filter = MailboxFilterQuery(activeFilters: [.hasAttachment], senderEmail: nil)
        let withAtt = Self.makeHeader(hasAttachments: true)
        let withoutAtt = Self.makeHeader(hasAttachments: false)

        #expect(filter.matches(withAtt))
        #expect(!filter.matches(withoutAtt))
    }

    @Test("today filter matches today's messages")
    func todayFilterMatchesTodaysMessages() {
        let filter = MailboxFilterQuery(activeFilters: [.today], senderEmail: nil)
        let today = Self.makeHeader(date: Date())
        let yesterday = Self.makeHeader(date: Date().addingTimeInterval(-86400))

        #expect(filter.matches(today))
        #expect(!filter.matches(yesterday))
    }

    @Test("combined filters require all predicates to match")
    func combinedFiltersRequireAllPredicates() {
        let filter = MailboxFilterQuery(activeFilters: [.unread, .flagged], senderEmail: nil)
        let both = Self.makeHeader(isRead: false, isFlagged: true)
        let onlyUnread = Self.makeHeader(isRead: false, isFlagged: false)
        let onlyFlagged = Self.makeHeader(isRead: true, isFlagged: true)

        #expect(filter.matches(both))
        #expect(!filter.matches(onlyUnread))
        #expect(!filter.matches(onlyFlagged))
    }

    @Test("toggle adds and removes filters")
    func toggleAddsAndRemoves() {
        var filter = MailboxFilterQuery.none
        filter.toggle(.unread)
        #expect(filter.activeFilters == [.unread])
        filter.toggle(.unread)
        #expect(filter.activeFilters.isEmpty)
    }

    @Test("clear removes all filters")
    func clearRemovesAll() {
        var filter = MailboxFilterQuery(activeFilters: [.unread, .flagged], senderEmail: "me@example.org")
        filter.clear()
        #expect(!filter.isActive)
        #expect(filter.senderEmail == nil)
    }

    @Test("from sender filter matches specific email")
    func fromSenderFilterMatchesEmail() {
        let filter = MailboxFilterQuery(activeFilters: [.fromSender], senderEmail: "boss@example.org")
        let boss = Self.makeHeader(from: "Boss", email: "boss@example.org")
        let colleague = Self.makeHeader(from: "Colleague", email: "colleague@example.org")

        #expect(filter.matches(boss))
        #expect(!filter.matches(colleague))
    }

    @Test("source filter matches only messages from selected mailbox sources")
    func sourceFilterMatchesSelectedMailboxSources() {
        let allowedSource = MailSourceID(accountID: "account-a", mailboxID: "mailbox-a")
        let otherSource = MailSourceID(accountID: "account-b", mailboxID: "mailbox-b")
        let filter = MailboxFilterQuery(
            activeFilters: [],
            senderEmail: nil,
            sourceIDs: [allowedSource]
        )

        #expect(filter.matches(Self.item(sourceID: allowedSource)))
        #expect(!filter.matches(Self.item(sourceID: otherSource)))
    }

    @Test("flagged smart view exposes a provider neutral flagged query")
    func flaggedSmartViewExposesProviderNeutralFlaggedQuery() {
        let view = MailboxSmartView.flagged

        #expect(view.title == "Flagged")
        #expect(view.symbolName == "flag")
        #expect(view.query.activeFilters == [.flagged])
        #expect(view.workflowMode == .active)
        #expect(view.query.sourceIDs == nil)
        #expect(view.query.matches(Self.item(
            sourceID: MailSourceID(accountID: "account-a", mailboxID: "mailbox-a"),
            isFlagged: true
        )))
        #expect(!view.query.matches(Self.item(
            sourceID: MailSourceID(accountID: "account-a", mailboxID: "mailbox-a"),
            isFlagged: false
        )))
    }

    @Test("VIP smart view resolves the persisted sender set")
    func vipSmartViewResolvesSenders() {
        let view = MailboxSmartView.vip.resolvingVIPEmails(["boss@example.org"])

        #expect(view.query.matches(Self.makeHeader(from: "Boss", email: "boss@example.org")))
        #expect(!view.query.matches(Self.makeHeader(from: "Peer", email: "peer@example.org")))
    }

    @Test("workflow smart views expose snoozed and done modes")
    func workflowSmartViewsExposeSnoozedAndDoneModes() {
        #expect(MailboxSmartView.today.title == "Today")
        #expect(MailboxSmartView.today.symbolName == "calendar")
        #expect(MailboxSmartView.today.query.activeFilters == [.today])

        #expect(MailboxSmartView.snoozed.title == "Snoozed")
        #expect(MailboxSmartView.snoozed.symbolName == "clock")
        #expect(MailboxSmartView.snoozed.workflowMode == .snoozed)

        #expect(MailboxSmartView.done.title == "Done")
        #expect(MailboxSmartView.done.symbolName == "checkmark.circle")
        #expect(MailboxSmartView.done.workflowMode == .done)

        #expect(MailboxSmartView.builtIns.map(\.id) == ["today", "flagged", "snoozed", "done", "vip"])
    }

    @Test("selected smart view maps every navigation smart view")
    @MainActor
    func selectedSmartViewMapsEveryNavigationSmartView() {
        let navigation = MailNavigationState()

        navigation.selectTodaySmartView()
        #expect(MailboxSmartView.selected(for: navigation) == .today)

        navigation.selectFlaggedSmartView()
        #expect(MailboxSmartView.selected(for: navigation) == .flagged)

        navigation.selectSnoozedSmartView()
        #expect(MailboxSmartView.selected(for: navigation) == .snoozed)

        navigation.selectDoneSmartView()
        #expect(MailboxSmartView.selected(for: navigation) == .done)

        navigation.selectVIPSmartView()
        #expect(MailboxSmartView.selected(for: navigation) == .vip)

        navigation.selectFolder(
            "inbox",
            in: MailSourceID(accountID: "account-a", mailboxID: "mailbox-a")
        )
        #expect(MailboxSmartView.selected(for: navigation) == nil)
    }

    @Test("filter menu title names a single active filter and counts several")
    func filterMenuTitleNamesOrCounts() {
        let all: [MailboxQuickFilter] = [.unread, .flagged, .hasAttachment]
        #expect(MailboxFilterMenuPresentation.title(activeFilters: [], allFilters: all) == "Filter")
        #expect(MailboxFilterMenuPresentation.title(activeFilters: [.flagged], allFilters: all) == "Flagged")
        #expect(MailboxFilterMenuPresentation.title(
            activeFilters: [.unread, .flagged],
            allFilters: all
        ) == "2 Filters")
    }

    @Test("filter menu title ignores active filters the menu does not present")
    func filterMenuTitleIgnoresUnpresentedFilters() {
        #expect(MailboxFilterMenuPresentation.title(
            activeFilters: [.vip],
            allFilters: [.unread, .flagged]
        ) == "Filter")
    }

    /// The menu now carries sort order as well as the quick filters, so the
    /// spoken label has to name both jobs and report the current sort.
    @Test("filter menu accessibility label names the control before its state")
    func filterMenuAccessibilityLabelNamesControl() {
        #expect(MailboxFilterMenuPresentation.accessibilityLabel(
            activeCount: 0,
            sortOrder: .newestFirst
        ) == "Sort and filter, sorted newest first")
        #expect(MailboxFilterMenuPresentation.accessibilityLabel(
            activeCount: 1,
            sortOrder: .oldestFirst
        ) == "Sort and filter, 1 filter active, sorted oldest first")
        #expect(MailboxFilterMenuPresentation.accessibilityLabel(
            activeCount: 3,
            sortOrder: .unreadFirst
        ) == "Sort and filter, 3 filters active, sorted unread first")
    }

    @Test("sort control presentation exposes the selected sort order")
    func sortControlPresentationExposesSelectedSortOrder() {
        let presentation = MailboxSortControlPresentation.presentation(for: .unreadFirst)

        #expect(presentation.title == "Unread first")
        #expect(presentation.symbolName == "envelope.badge")
        #expect(presentation.accessibilityLabel == "Sort order: Unread first")
        #expect(presentation.help == "Show unread messages at the top.")
    }

    @Test("date filters are grouped outside the primary filter strip")
    func dateFiltersAreGroupedOutsidePrimaryFilterStrip() {
        #expect(MailboxQuickFilterPresentation.primaryFilters == [.unread, .flagged, .hasAttachment, .vip])
        #expect(MailboxQuickFilterPresentation.dateFilters == [.today, .lastWeek])
    }

    private static func makeHeader(
        isRead: Bool = false,
        isFlagged: Bool = false,
        hasAttachments: Bool = false,
        date: Date = Date(),
        from name: String = "Test",
        email: String = "test@example.org"
    ) -> MessageHeader {
        MessageHeader(
            id: UUID().uuidString,
            threadID: "thread-1",
            folderID: "inbox",
            from: Correspondent(name: name, email: email),
            subject: "Test",
            snippet: "Test message",
            date: date,
            isRead: isRead,
            isFlagged: isFlagged,
            hasAttachments: hasAttachments
        )
    }

    private static func item(
        sourceID: MailSourceID,
        isFlagged: Bool = false
    ) -> UnifiedInboxItem {
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        return UnifiedInboxItem(
            sourceID: sourceID,
            folder: folder,
            header: makeHeader(isFlagged: isFlagged),
            sourceTitle: "Mailbox",
            sourceSubtitle: "mailbox@example.org",
            archiveFolder: nil
        )
    }
}
