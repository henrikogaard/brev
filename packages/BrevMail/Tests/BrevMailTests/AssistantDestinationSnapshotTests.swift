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

#if os(macOS)
import AppKit
import BrevAI
import BrevBackend
import BrevDesign
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

/// Assistant sidebar destination with grounded conversation cards (#294).
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh the baseline.
@Suite("Assistant destination snapshots")
@MainActor
struct AssistantDestinationSnapshotTests {
    private struct SnapshotAI: AIBackend {
        let identifier = "snapshot-local"
        let displayName = "On this Mac"
        let transparencyLabel = "On this Mac"

        func generateReply(to messages: [AIMessage], instruction: String?) async throws -> AIResponse {
            AIResponse(text: "")
        }

        func shortcut(_ action: AIShortcutAction, on text: String) async throws -> AIResponse {
            AIResponse(text: "")
        }
    }

    @Test("Assistant empty state renders centered hero, 2x2 starter cards, and inline composer", arguments: ["light", "dark"])
    func assistantEmptyState(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let source = MailSourceID(accountID: "acct", mailboxID: "box")
        let view = AssistantDestinationView(
            sourceID: source,
            aiBackend: SnapshotAI(),
            search: { _, _ in [] },
            onOpenCard: { _ in },
            onReplyCard: { _ in },
            preloadedTurns: []
        )
        .frame(width: 720, height: 680)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 720, height: 680)),
            named: "assistant-empty-hero-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("Assistant renders grouped grounded cards and action chips", arguments: ["light", "dark"])
    func assistantAnswerCards(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 15, minute: 0))!
        let source = MailSourceID(accountID: "acct", mailboxID: "box")

        let citations: [MailboxChatCitation] = [
            MailboxChatCitation(
                id: "m1",
                folderID: "inbox",
                sourceID: source,
                subject: "Q4 roadmap: final review before Thursday",
                date: now.addingTimeInterval(-3600),
                senderName: "Maya Okafor",
                senderEmail: "maya@northwind.example",
                snippet: "Can you sign off on section 2 before the partner call?",
                isRead: false,
                isFlagged: true,
                isAnswered: false
            ),
            MailboxChatCitation(
                id: "m2",
                folderID: "inbox",
                sourceID: source,
                subject: "Design notes from Monday",
                date: now.addingTimeInterval(-6 * 3600),
                senderName: "Daniel Reyes",
                senderEmail: "daniel@example.com",
                snippet: "Shared the revised typography scale for review.",
                isRead: true,
                isFlagged: false,
                isAnswered: true
            ),
            MailboxChatCitation(
                id: "m3",
                folderID: "inbox",
                sourceID: source,
                subject: "Weekly workspace digest",
                date: now.addingTimeInterval(-12 * 3600),
                senderName: "Linear",
                senderEmail: "notifications@linear.app",
                snippet: "14 issues completed across Core and Mobile.",
                isRead: false,
                isFlagged: false,
                isAnswered: false
            ),
        ]

        let turns: [MailboxChatTurnKind] = [
            .user("What needs me today?"),
            .answer(
                text: "Maya needs your sign-off on the Q4 roadmap today, and Daniel shared Monday's design notes.",
                citations: citations,
                providerLabel: "On this Mac"
            ),
        ]

        let view = AssistantDestinationView(
            sourceID: source,
            aiBackend: SnapshotAI(),
            search: { _, _ in [] },
            onOpenCard: { _ in },
            onReplyCard: { _ in },
            preloadedTurns: turns
        )
        .frame(width: 720, height: 680)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 720, height: 680)),
            named: "assistant-cards-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("Assistant renders multi-sender archive confirmation review card", arguments: ["light", "dark"])
    func assistantArchiveReviewCard(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 9, minute: 30))!
        let source = MailSourceID(accountID: "acct", mailboxID: "box")
        let folders = [
            Folder(id: "inbox", name: "Inbox", role: .inbox),
            Folder(id: "archive", name: "Archive", role: .archive),
        ]
        let card1 = AssistantConversationCard(
            messageID: "m1",
            folderID: "inbox",
            sourceID: source,
            senderName: "Linear",
            senderEmail: "notifications@linear.app",
            subject: "Weekly workspace digest",
            snippet: "14 issues completed.",
            date: now.addingTimeInterval(-3600),
            section: .updatesAndNewsletters,
            tags: [],
            citation: MailboxChatCitation(
                id: "m1",
                folderID: "inbox",
                sourceID: source,
                subject: "Weekly workspace digest",
                date: now.addingTimeInterval(-3600),
                senderName: "Linear",
                senderEmail: "notifications@linear.app",
                snippet: "14 issues completed.",
                isRead: false,
                isFlagged: false,
                isAnswered: false
            )
        )
        let card2 = AssistantConversationCard(
            messageID: "m2",
            folderID: "inbox",
            sourceID: source,
            senderName: "GitHub",
            senderEmail: "notifications@github.com",
            subject: "Release notes v2.4",
            snippet: "New features shipped.",
            date: now.addingTimeInterval(-7200),
            section: .updatesAndNewsletters,
            tags: [],
            citation: MailboxChatCitation(
                id: "m2",
                folderID: "inbox",
                sourceID: source,
                subject: "Release notes v2.4",
                date: now.addingTimeInterval(-7200),
                senderName: "GitHub",
                senderEmail: "notifications@github.com",
                snippet: "New features shipped.",
                isRead: true,
                isFlagged: false,
                isAnswered: false
            )
        )
        let planned = MailboxActionAgentPlanner().planArchive(cards: [card1, card2], folders: folders)
        guard case .planned(let plan) = planned else {
            Issue.record("Expected planned archive review")
            return
        }
        let turns: [MailboxChatTurnKind] = [
            .actionReview(plan, providerLabel: MailboxChatProviderLabelPolicy.actionPlanner()),
        ]
        let view = AssistantDestinationView(
            sourceID: source,
            aiBackend: SnapshotAI(),
            actionFolders: folders,
            search: { _, _ in [] },
            onOpenCard: { _ in },
            onReplyCard: { _ in },
            preloadedTurns: turns
        )
        .frame(width: 720, height: 340)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 720, height: 340)),
            named: "assistant-archive-review-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
