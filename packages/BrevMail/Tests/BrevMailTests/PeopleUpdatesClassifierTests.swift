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

@Suite("People and Updates classification and bundling")
@MainActor
struct PeopleUpdatesClassifierTests {
    private static let source = MailSourceID(accountID: "acct", mailboxID: "box")
    private static let now = Date(timeIntervalSince1970: 1_794_500_000)

    private static func header(
        id: String,
        fromName: String? = "Maya",
        fromEmail: String = "maya@example.com",
        subject: String = "Coffee tomorrow?",
        snippet: String = "Are you free at 10?",
        minutesAgo: Double = 0,
        isRead: Bool = false
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: id,
            folderID: "inbox",
            from: Correspondent(name: fromName, email: fromEmail),
            subject: subject,
            snippet: snippet,
            date: now.addingTimeInterval(-minutesAgo * 60),
            isRead: isRead
        )
    }

    private static func isolatedOverrideStore() -> (InboxSenderCategoryOverrideStore, () -> Void) {
        let suite = "PeopleUpdatesClassifierTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (
            InboxSenderCategoryOverrideStore(defaults: defaults),
            { defaults.removePersistentDomain(forName: suite) }
        )
    }

    @Test("Classifier routes List-Unsubscribe, bulk precedence, no-reply, and transactional mail to Updates")
    func classifiesUpdateSignals() {
        let (store, cleanup) = Self.isolatedOverrideStore()
        defer { cleanup() }

        let listMessage = Self.header(id: "m1", fromName: "Maya", fromEmail: "maya@digest.example", subject: "Weekly notes")
        let listResult = PeopleUpdatesClassifier.classify(
            header: listMessage,
            signals: PeopleUpdatesHeaderSignals(hasListUnsubscribe: true),
            repliedSenderEmails: [],
            senderOverrideStore: store
        )
        #expect(listResult.bucket == .updates)
        #expect(listResult.signal == .listUnsubscribeHeader)

        let bulkResult = PeopleUpdatesClassifier.classify(
            header: Self.header(id: "m2", fromName: "Team", fromEmail: "team@example.com", subject: "Status"),
            signals: PeopleUpdatesHeaderSignals(isBulkPrecedence: true),
            repliedSenderEmails: [],
            senderOverrideStore: store
        )
        #expect(bulkResult.bucket == .updates)
        #expect(bulkResult.signal == .bulkPrecedence)

        let noReplyResult = PeopleUpdatesClassifier.classify(
            header: Self.header(id: "m3", fromName: "Linear", fromEmail: "no-reply@linear.app", subject: "Assigned to you"),
            repliedSenderEmails: [],
            senderOverrideStore: store
        )
        #expect(noReplyResult.bucket == .updates)
        #expect(noReplyResult.signal == .automatedSenderAddress)

        let receiptResult = PeopleUpdatesClassifier.classify(
            header: Self.header(
                id: "m4",
                fromName: "Acme Store",
                fromEmail: "orders@acme.example",
                subject: "Your receipt for order #42"
            ),
            repliedSenderEmails: [],
            senderOverrideStore: store
        )
        #expect(receiptResult.bucket == .updates)

        let vercelResult = PeopleUpdatesClassifier.classify(
            header: Self.header(
                id: "m5",
                fromName: "Vercel",
                fromEmail: "deployments@vercel.com",
                subject: "Production deployment succeeded",
                snippet: "harbour-data deployed from main with no build warnings."
            ),
            repliedSenderEmails: [],
            senderOverrideStore: store
        )
        #expect(vercelResult.bucket == .updates)
        #expect(vercelResult.signal == .automatedSenderAddress)

        let ciSubjectResult = PeopleUpdatesClassifier.classify(
            header: Self.header(
                id: "m6",
                fromName: "Buildkite",
                fromEmail: "hello@buildkite.example",
                subject: "Build failed on main",
                snippet: "Pipeline failed in integration step."
            ),
            repliedSenderEmails: [],
            senderOverrideStore: store
        )
        #expect(ciSubjectResult.bucket == .updates)
    }

    @Test("Classifier keeps direct people and senders the user has written to in People")
    func classifiesDirectAndRepliedSendersAsPeople() {
        let (store, cleanup) = Self.isolatedOverrideStore()
        defer { cleanup() }

        let human = Self.header(id: "m1", fromName: "Daniel", fromEmail: "daniel@example.com", subject: "Lunch?")
        let directResult = PeopleUpdatesClassifier.classify(
            header: human,
            repliedSenderEmails: [],
            senderOverrideStore: store
        )
        #expect(directResult.bucket == .people)
        #expect(directResult.signal == .directPerson)

        // Human names whose suffix matches short role tokens (e.g. "ci", "bot") stay in People.
        for (name, email) in [("Staci", "staci@example.com"), ("Abbot", "abbot@example.com")] {
            let result = PeopleUpdatesClassifier.classify(
                header: Self.header(id: email, fromName: name, fromEmail: email, subject: "Quick question"),
                repliedSenderEmails: [],
                senderOverrideStore: store
            )
            #expect(result.bucket == .people)
            #expect(result.signal == .directPerson)
        }

        // Even if the subject mentions "invoice", a sender I have written to stays in People.
        let replied = Self.header(id: "m2", fromName: "Sara", fromEmail: "sara@studio.example", subject: "Re: invoice question")
        let repliedResult = PeopleUpdatesClassifier.classify(
            header: replied,
            repliedSenderEmails: ["sara@studio.example"],
            senderOverrideStore: store
        )
        #expect(repliedResult.bucket == .people)
        #expect(repliedResult.signal == .repliedToSender)
    }

    @Test("People tab keeps date section headers while Updates tab stays sender-bundled")
    func peopleTabUsesDateSectionHeaders() {
        #expect(PeopleUpdatesListLayoutPolicy.usesDateSectionHeaders(
            showsPeopleUpdatesBar: true,
            activeTab: .people,
            groupByDate: true
        ))
        #expect(PeopleUpdatesListLayoutPolicy.usesDateSectionHeaders(
            showsPeopleUpdatesBar: true,
            activeTab: .all,
            groupByDate: true
        ))
        #expect(!PeopleUpdatesListLayoutPolicy.usesDateSectionHeaders(
            showsPeopleUpdatesBar: true,
            activeTab: .updates,
            groupByDate: true
        ))
        #expect(!PeopleUpdatesListLayoutPolicy.usesDateSectionHeaders(
            showsPeopleUpdatesBar: true,
            activeTab: .people,
            groupByDate: false
        ))
    }

    @Test("Collapsed People date sections are excluded from both bulk selectable headers and visible row IDs (#370)")
    func collapsedPeopleDateSectionExcludedFromBulkSelectAndVisibleRows() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 15, minute: 0))!

        let todayMsg = MessageHeader(
            id: "today-1",
            threadID: "t-today",
            folderID: "inbox",
            from: Correspondent(name: "Maya", email: "maya@example.com"),
            subject: "Today's check-in",
            snippet: "Quick sync at 4?",
            date: referenceDate.addingTimeInterval(-1800)
        )
        let yesterdayMsg = MessageHeader(
            id: "yesterday-1",
            threadID: "t-yesterday",
            folderID: "inbox",
            from: Correspondent(name: "Daniel", email: "daniel@example.com"),
            subject: "Yesterday's notes",
            snippet: "Following up on Monday.",
            date: referenceDate.addingTimeInterval(-86400)
        )
        let snapshot = MessageListPresentationSnapshot(
            headers: [todayMsg, yesterdayMsg],
            pinnedMessageIDs: [],
            groupByDate: true,
            collapsedDateSectionIDs: ["Yesterday"],
            referenceDate: referenceDate,
            calendar: calendar,
            sourceHeaders: [todayMsg, yesterdayMsg],
            filteredUngroupedHeaders: [todayMsg, yesterdayMsg],
            navigationHeaders: [todayMsg, yesterdayMsg],
            sourceID: Self.source,
            groupsThreads: true
        )

        // People tab: both bulk Select All projection and visible date-section rows exclude collapsed Yesterday.
        let peopleSelectable = PeopleUpdatesListLayoutPolicy.selectableHeaders(
            in: snapshot,
            showsPeopleUpdatesBar: true,
            activeTab: .people,
            groupByDate: true,
            sourceID: Self.source,
            expandedUpdateBundleIDs: []
        )
        let expectedVisibleIDs = snapshot.dateSections.flatMap(\.visibleHeaders).map(\.id)
        #expect(expectedVisibleIDs == ["today-1"])
        #expect(peopleSelectable.map(\.id) == expectedVisibleIDs)

        // All tab: matches the exact same collapsed-section visibility.
        let allSelectable = PeopleUpdatesListLayoutPolicy.selectableHeaders(
            in: snapshot,
            showsPeopleUpdatesBar: true,
            activeTab: .all,
            groupByDate: true,
            sourceID: Self.source,
            expandedUpdateBundleIDs: []
        )
        #expect(allSelectable.map(\.id) == ["today-1"])

        // Updates tab: preserves the sender-bundle projection rather than date sections.
        let update1 = Self.header(id: "u1", fromName: "Linear", fromEmail: "notifications@linear.app", subject: "One")
        let update2 = Self.header(id: "u2", fromName: "Linear", fromEmail: "notifications@linear.app", subject: "Two")
        let updateSolo = Self.header(id: "u3", fromName: "Vercel", fromEmail: "deployments@vercel.com", subject: "Deploy")
        let updatesSnapshot = MessageListPresentationSnapshot(
            headers: [update1, update2, updateSolo],
            pinnedMessageIDs: [],
            groupByDate: true,
            collapsedDateSectionIDs: ["Today"],
            referenceDate: Self.now,
            calendar: calendar,
            sourceHeaders: [update1, update2, updateSolo],
            filteredUngroupedHeaders: [update1, update2, updateSolo],
            navigationHeaders: [update1, update2, updateSolo],
            sourceID: Self.source,
            groupsThreads: true
        )
        let updatesSelectableCollapsed = PeopleUpdatesListLayoutPolicy.selectableHeaders(
            in: updatesSnapshot,
            showsPeopleUpdatesBar: true,
            activeTab: .updates,
            groupByDate: true,
            sourceID: Self.source,
            expandedUpdateBundleIDs: []
        )
        #expect(updatesSelectableCollapsed.map(\.id) == ["u3"])

        let updatesSelectableExpanded = PeopleUpdatesListLayoutPolicy.selectableHeaders(
            in: updatesSnapshot,
            showsPeopleUpdatesBar: true,
            activeTab: .updates,
            groupByDate: true,
            sourceID: Self.source,
            expandedUpdateBundleIDs: ["notifications@linear.app"]
        )
        #expect(updatesSelectableExpanded.map(\.id) == ["u1", "u2", "u3"])
    }

    @Test("Sender overrides persist across reloads and take precedence over heuristics")
    func senderOverridesPersistAndWin() {
        let suite = "PeopleUpdatesOverride-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = InboxSenderCategoryOverrideStore(defaults: defaults)
        store.set(.people, forSenderEmail: "No-Reply@Linear.app")

        let reloaded = InboxSenderCategoryOverrideStore(defaults: defaults)
        let linear = Self.header(id: "m1", fromName: "Linear", fromEmail: "no-reply@linear.app", subject: "Notification")
        let movedToPeople = PeopleUpdatesClassifier.classify(
            header: linear,
            signals: PeopleUpdatesHeaderSignals(hasListUnsubscribe: true),
            repliedSenderEmails: [],
            senderOverrideStore: reloaded
        )
        #expect(movedToPeople.bucket == .people)
        #expect(movedToPeople.signal == .senderOverride(.people))

        reloaded.set(.updates, forSenderEmail: "daniel@example.com")
        let movedToUpdates = PeopleUpdatesClassifier.classify(
            header: Self.header(id: "m2", fromName: "Daniel", fromEmail: "daniel@example.com", subject: "Hello"),
            repliedSenderEmails: ["daniel@example.com"],
            senderOverrideStore: reloaded
        )
        #expect(movedToUpdates.bucket == .updates)
        #expect(movedToUpdates.signal == .senderOverride(.updates))
    }

    @Test("Updates bundler groups multiple messages per sender and formats summary line")
    func updatesBundlerGroupsBySender() {
        let h1 = Self.header(
            id: "m1",
            fromName: "Linear",
            fromEmail: "notifications@linear.app",
            subject: "Issue #1",
            minutesAgo: 5,
            isRead: false
        )
        let h2 = Self.header(
            id: "m2",
            fromName: "Linear",
            fromEmail: "notifications@linear.app",
            subject: "Issue #2",
            minutesAgo: 30,
            isRead: false
        )
        let h3 = Self.header(
            id: "m3",
            fromName: "GitHub",
            fromEmail: "notifications@github.com",
            subject: "PR review",
            minutesAgo: 15,
            isRead: true
        )

        let bundles = UpdatesSenderBundler.bundle([h1, h2, h3], sourceID: Self.source)
        #expect(bundles.count == 2)
        #expect(bundles[0].senderName == "Linear")
        #expect(bundles[0].headers.map(\.id) == ["m1", "m2"])
        #expect(bundles[0].unreadCount == 2)
        #expect(bundles[0].additionalCount == 1)
        #expect(bundles[0].summaryLine(locale: Locale(identifier: "en")) == "Linear 2 · 2 new · 1 more from Linear")
        #expect(bundles[1].senderName == "GitHub")
        #expect(bundles[1].headers.map(\.id) == ["m3"])
    }

    @Test("Counts on MockBackend inbox split People, Updates, and All accurately")
    func mockMailboxCounts() async throws {
        let (store, cleanup) = Self.isolatedOverrideStore()
        defer { cleanup() }

        let backend = MockBackend()
        let folders = try await backend.folders()
        let inbox = try #require(folders.first { $0.role == .inbox })
        let headers = try await backend.messages(in: inbox, pageToken: nil).headers

        let counts = PeopleUpdatesCounts.compute(
            headers: headers,
            repliedSenderEmails: [],
            senderOverrideStore: store
        )
        #expect(counts.allCount == headers.count)
        #expect(counts.peopleCount + counts.updatesCount == counts.allCount)
        #expect(counts.peopleCount > 0)
        #expect(counts.updatesCount > 0)
    }

    @Test("Subscriptions catalog groups List-Unsubscribe senders and archives all with Undo")
    func subscriptionsCatalogAndArchiveAllWithUndo() async throws {
        let backend = MockBackend()
        let folders = try await backend.folders()
        let inbox = try #require(folders.first { $0.role == .inbox })
        let archive = try #require(folders.first { $0.role == .archive })
        let sourceID = MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)

        let h1 = Self.header(
            id: "m7",
            fromName: "Coastal Post",
            fromEmail: "news@example.org",
            subject: "Edition 1",
            minutesAgo: 10
        )
        let h2 = Self.header(
            id: "newsletter-1",
            fromName: "Coastal Post",
            fromEmail: "news@example.org",
            subject: "Edition 2",
            minutesAgo: 60
        )
        let b1 = try await backend.body(for: "m7", sourceID: sourceID)
        let b2 = try await backend.body(for: "newsletter-1", sourceID: sourceID)

        let groups = SubscriptionsCatalogBuilder.build(
            candidates: [
                SubscriptionsCandidate(sourceID: sourceID, header: h1, listUnsubscribe: b1.listUnsubscribe),
                SubscriptionsCandidate(sourceID: sourceID, header: h2, listUnsubscribe: b2.listUnsubscribe),
            ]
        )

        #expect(groups.count == 1)
        #expect(groups[0].senderEmail == "news@example.org")
        #expect(groups[0].messageCount == 2)
        #expect(groups[0].lastReceived == h1.date)
        #expect(groups[0].unsubscribeOptions.requiresExplicitConfirmation)
        #expect(groups[0].confirmationSummary != nil)

        // Verify real cross-folder Archive all + Undo on MockBackend
        let inboxHeaders = try await backend.messages(in: inbox, pageToken: nil).headers
        let target1 = try #require(inboxHeaders.first)
        let customFolder = folders.first { $0.role == .custom }
        var groupedHeaders = [target1]
        if let customFolder,
           let customHeader = try await backend.messages(in: customFolder, pageToken: nil).headers.first {
            groupedHeaders.append(customHeader)
        }
        let senderGroup = SubscriptionSenderGroup(
            id: "\(sourceID.accountID):\(sourceID.mailboxID):\(target1.from.email.lowercased())",
            sourceID: sourceID,
            senderName: target1.from.displayName,
            senderEmail: target1.from.email.lowercased(),
            headers: groupedHeaders,
            lastReceived: target1.date,
            unsubscribeOptions: groups[0].unsubscribeOptions
        )
        let undoQueue = UndoQueue(timeout: 30)
        let archived = await SubscriptionsActions.archiveAllMessages(
            in: senderGroup,
            folders: folders,
            backend: backend,
            undoQueue: undoQueue
        )
        #expect(archived)
        let afterArchive = try await backend.messages(in: inbox, pageToken: nil).headers
        #expect(!afterArchive.contains { $0.id == target1.id })

        let undone = await undoQueue.undo()?.value ?? false
        #expect(undone)
        let afterUndo = try await backend.messages(in: inbox, pageToken: nil).headers
        #expect(afterUndo.contains { $0.id == target1.id })

        // Verify failure returns false when no archive folder exists
        let failed = await SubscriptionsActions.archiveAllMessages(
            in: senderGroup,
            folders: [inbox],
            backend: backend,
            undoQueue: undoQueue
        )
        #expect(!failed)
    }

    @Test("Simultaneously initialized override stores merge writes across windows without clobbering")
    func overrideStoreMergesAcrossWindows() throws {
        let suite = "PeopleUpdatesCrossWindow-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let windowOne = InboxSenderCategoryOverrideStore(defaults: defaults)
        let windowTwo = InboxSenderCategoryOverrideStore(defaults: defaults)

        windowOne.set(.updates, forSenderEmail: "maya@company.com")
        windowTwo.set(.people, forSenderEmail: "notifications@linear.app")

        let fresh = InboxSenderCategoryOverrideStore(defaults: defaults)
        #expect(fresh.bucket(forSenderEmail: "maya@company.com") == .updates)
        #expect(fresh.bucket(forSenderEmail: "notifications@linear.app") == .people)
    }

    @Test("Updates bundler retains multiple messages from the same thread when built from ungrouped headers")
    func updatesBundlerIncludesAllThreadedMessages() {
        let m1 = MessageHeader(
            id: "u1",
            threadID: "shared-thread",
            folderID: "inbox",
            from: Correspondent(name: "Linear", email: "notifications@linear.app"),
            to: [],
            subject: "Issue #1 updated",
            snippet: "Assigned to you",
            date: Date().addingTimeInterval(-60),
            isRead: false,
            isFlagged: false,
            hasAttachments: false
        )
        let m2 = MessageHeader(
            id: "u2",
            threadID: "shared-thread",
            folderID: "inbox",
            from: Correspondent(name: "Linear", email: "notifications@linear.app"),
            to: [],
            subject: "Re: Issue #1 updated",
            snippet: "New comment",
            date: Date().addingTimeInterval(-120),
            isRead: false,
            isFlagged: false,
            hasAttachments: false
        )
        let bundles = UpdatesSenderBundler.bundle([m1, m2], sourceID: nil)
        #expect(bundles.count == 1)
        #expect(bundles[0].headers.map(\.id) == ["u1", "u2"])
    }

    @Test("Mixed People and Updates thread keeps People sibling out of Updates bundles")
    func mixedThreadKeepsPeopleOutOfUpdatesBundles() {
        let bulkNotice = MessageHeader(
            id: "u1",
            threadID: "mixed-thread",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            to: [],
            subject: "Monthly release digest",
            snippet: "Changes this month",
            date: Date().addingTimeInterval(-3600),
            isRead: false,
            isFlagged: false,
            hasAttachments: false
        )
        let personalFollowUp = MessageHeader(
            id: "p1",
            threadID: "mixed-thread",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            to: [],
            subject: "Re: Monthly release digest",
            snippet: "Can we chat at 3pm?",
            date: Date().addingTimeInterval(-60),
            isRead: false,
            isFlagged: false,
            hasAttachments: false
        )
        let allHeaders = [personalFollowUp, bulkNotice]
        let updatesOnly = [bulkNotice]
        let navHeaders = MessageListNavigationHeaders.headers(from: updatesOnly, threadContext: allHeaders)
        // Reader context retains the People reply, but filteredUngroupedHeaders must not.
        #expect(navHeaders.map(\.id).contains("p1"))

        let snapshot = MessageListPresentationSnapshot(
            headers: updatesOnly,
            pinnedMessageIDs: [],
            groupByDate: false,
            collapsedDateSectionIDs: [],
            sourceHeaders: allHeaders,
            filteredUngroupedHeaders: updatesOnly,
            navigationHeaders: navHeaders,
            groupsThreads: true
        )
        let bundles = UpdatesSenderBundler.bundle(snapshot.filteredUngroupedHeaders, sourceID: Self.source)
        #expect(bundles.count == 1)
        #expect(bundles[0].headers.map(\.id) == ["u1"])
    }

    @Test("Updates selectableHeaders excludes collapsed multi-message bundles and includes expanded rows")
    func updatesSelectableHeadersMatchesRenderedBundleRows() {
        let m1 = MessageHeader(
            id: "u1",
            threadID: "shared-thread",
            folderID: "inbox",
            from: Correspondent(name: "Linear", email: "notifications@linear.app"),
            to: [],
            subject: "Issue #1",
            snippet: "Update 1",
            date: Date().addingTimeInterval(-60),
            isRead: false,
            isFlagged: false,
            hasAttachments: false
        )
        let m2 = MessageHeader(
            id: "u2",
            threadID: "shared-thread",
            folderID: "inbox",
            from: Correspondent(name: "Linear", email: "notifications@linear.app"),
            to: [],
            subject: "Re: Issue #1",
            snippet: "Update 2",
            date: Date().addingTimeInterval(-120),
            isRead: false,
            isFlagged: false,
            hasAttachments: false
        )
        let single = MessageHeader(
            id: "u3",
            threadID: "solo-thread",
            folderID: "inbox",
            from: Correspondent(name: "GitHub", email: "notifications@github.com"),
            to: [],
            subject: "Release",
            snippet: "v2",
            date: Date().addingTimeInterval(-180),
            isRead: false,
            isFlagged: false,
            hasAttachments: false
        )
        let headers = [m1, m2, single]

        // Collapsed multi-message bundle hides u1 & u2 from selectable rows; single u3 stays selectable.
        let collapsed = UpdatesSenderBundler.selectableHeaders(
            from: headers,
            sourceID: Self.source,
            expandedBundleIDs: []
        )
        #expect(collapsed.map(\.id) == ["u3"])

        // Expanding Linear's bundle exposes both u1 and u2 in exact rendered order (newest first, no duplicates).
        let expanded = UpdatesSenderBundler.selectableHeaders(
            from: headers,
            sourceID: Self.source,
            expandedBundleIDs: ["notifications@linear.app"]
        )
        #expect(expanded.map(\.id) == ["u1", "u2", "u3"])
    }

    @MainActor
    @Test("Updates keyboard arrow and paging navigation clear stale reader expansion while keeping bulk selection")
    func updatesKeyboardSelectionClearsReaderExpansionPreference() {
        let newer = MessageHeader(
            id: "u1",
            threadID: "shared-thread",
            folderID: "inbox",
            from: Correspondent(name: "Linear", email: "notifications@linear.app"),
            to: [],
            subject: "Re: Issue #1",
            snippet: "Latest update",
            date: Date().addingTimeInterval(-60),
            isRead: false,
            isFlagged: false,
            hasAttachments: false
        )
        let older = MessageHeader(
            id: "u2",
            threadID: "shared-thread",
            folderID: "inbox",
            from: Correspondent(name: "Linear", email: "notifications@linear.app"),
            to: [],
            subject: "Issue #1",
            snippet: "Earlier update",
            date: Date().addingTimeInterval(-120),
            isRead: true,
            isFlagged: false,
            hasAttachments: false
        )
        let rows = [newer, older]
        let navigation = MailNavigationState()

        // Arrow path: explicit older-reply expansion is cleared when moving Up to the newer message.
        navigation.selectMessage(older, from: rows, expandsSelectedMessage: true)
        navigation.bulkSelection = [older.id]
        #expect(navigation.readerExpansionSelectionID == older.id)

        UpdatesSenderBundler.applyKeyboardSelection(delta: -1, rows: rows, navigation: navigation)
        #expect(navigation.selectedMessageID == newer.id)
        #expect(navigation.readerExpansionSelectionID == nil)
        #expect(navigation.bulkSelection == Set([older.id]))

        // Paging / Home path: explicit older-reply expansion is also cleared on moveToStart/pageUp.
        navigation.selectMessage(older, from: rows, expandsSelectedMessage: true)
        navigation.bulkSelection = [newer.id]
        #expect(navigation.readerExpansionSelectionID == older.id)

        UpdatesSenderBundler.applyKeyboardSelection(command: .moveToStart, rows: rows, navigation: navigation)
        #expect(navigation.selectedMessageID == newer.id)
        #expect(navigation.readerExpansionSelectionID == nil)
        #expect(navigation.bulkSelection == Set([newer.id]))
    }

    @Test("HTTPS unsubscribe confirmation states browser opening accurately even when one-click is advertised")
    func unsubscribeConfirmationMatchesBrowserBehavior() {
        let oneClick = ListUnsubscribeOptions.parse(
            listUnsubscribe: "<https://lists.example.org/unsub>",
            listUnsubscribePost: "List-Unsubscribe=One-Click"
        )
        let group = SubscriptionSenderGroup(
            id: "g1",
            sourceID: Self.source,
            senderName: "Digest",
            senderEmail: "digest@example.org",
            headers: [],
            lastReceived: Date(),
            unsubscribeOptions: oneClick
        )
        let summary = group.confirmationSummary ?? ""
        #expect(summary.contains("in your browser"))
        #expect(!summary.contains("one-click"))
    }

    @Test("People, Updates, and Subscriptions strings have Norwegian localizations")
    func norwegianCopy() throws {
        let catalog = try LocalizationCatalogTestSupport.loadCatalogStrings()
        let requiredKeys = [
            "Subscriptions",
            "Unsubscribe",
            "Archive all",
            "Move sender to People",
            "Move sender to Updates",
            "No subscriptions found",
            "Archive bundle",
            "%lld messages",
            "%lld new",
            "%lld more from %@",
        ]
        for key in requiredKeys {
            let entry = try #require(catalog[key] as? [String: Any], "Missing catalog key \(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any])
            let nb = try #require(localizations["nb"] as? [String: Any])
            let unitValue = (nb["stringUnit"] as? [String: Any])?["value"] as? String
            let hasVariations = (nb["variations"] as? [String: Any]) != nil
            #expect((unitValue?.isEmpty == false) || hasVariations, "Missing nb localization for \(key)")
        }
    }

    @Test("Updates bundles and selectable headers rank woken snoozes by effective wake date")
    func updatesBundlesRespectWakeDateOverrides() {
        let monday = Date(timeIntervalSince1970: 1_700_000_000)
        let thursday = monday.addingTimeInterval(3 * 86400)
        let friday = monday.addingTimeInterval(4 * 86400)

        let wokenMonday = MessageHeader(
            id: "news-monday",
            threadID: "t-mon",
            folderID: "inbox",
            from: Correspondent(name: "Monday Digest", email: "monday@news.example"),
            subject: "Monday edition",
            snippet: "Snoozed until Friday",
            date: monday
        )
        let newerThursday = MessageHeader(
            id: "news-thursday",
            threadID: "t-thu",
            folderID: "inbox",
            from: Correspondent(name: "Thursday Digest", email: "thursday@news.example"),
            subject: "Thursday edition",
            snippet: "Arrived Thursday",
            date: thursday
        )

        let overrides = ["news-monday": friday]
        let bundles = UpdatesSenderBundler.bundle(
            [wokenMonday, newerThursday],
            sourceID: Self.source,
            effectiveDateOverrides: overrides
        )
        #expect(bundles.map(\.senderEmail) == ["monday@news.example", "thursday@news.example"])

        let selectable = UpdatesSenderBundler.selectableHeaders(
            from: [wokenMonday, newerThursday],
            sourceID: Self.source,
            expandedBundleIDs: [],
            effectiveDateOverrides: overrides
        )
        #expect(selectable.map(\.id) == ["news-monday", "news-thursday"])
    }
}
