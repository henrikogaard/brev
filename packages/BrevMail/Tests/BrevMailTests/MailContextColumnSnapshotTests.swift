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
@testable import BrevMail
import BrevThemes
import Combine
import SnapshotTesting
import SwiftUI
import Testing

/// Snapshot coverage for the Mail Context inspector shell.
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh the baseline.
@Suite("Mail Context snapshots")
@MainActor
struct MailContextColumnSnapshotTests {
    @Test("Mail Context idle shell renders")
    func placeholderEmptyState() {
        let theme = BrevTheme.brevPaper
        let view = MailContextColumn()
            .frame(width: 320, height: 600)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 600)

        assertSnapshot(
            of: Self.retinaImage(of: host, size: CGSize(width: 320, height: 600)),
            as: .image,
            named: "placeholder-empty",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("AI Sidebar resize handle renders in dark theme")
    func resizablePanelsDarkTheme() {
        let theme = BrevTheme.brevSlate
        let view = MailContextColumn()
            .frame(width: 320, height: 600)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 600)

        assertSnapshot(
            of: Self.retinaImage(of: host, size: CGSize(width: 320, height: 600)),
            as: .image,
            named: "resizable-panels-dark",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("Mail Context without selection keeps mailbox chat available")
    func mailboxChatWithoutSelectionState() {
        let theme = BrevTheme.brevPaper

        withAIWriterSettings(isEnabled: true, consentGiven: true) {
            let view = MailContextColumn(
                sourceID: Self.sourceScope.sourceID,
                aiBackend: SnapshotAIBackend(),
                focusedFolder: Self.inboxFolder,
                actionSourceScope: Self.sourceScope
            )
            .frame(width: 320, height: 600)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)

            let host = NSHostingController(rootView: view)
            host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 600)

            assertSnapshot(
                of: Self.retinaImage(of: host, size: CGSize(width: 320, height: 600)),
                as: .image,
                named: "mailbox-no-selection",
                record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
            )
        }
    }

    @Test("AI Sidebar renders as an in-window trailing column")
    func inWindowSidebarState() {
        let theme = BrevTheme.brevPaper

        withAIWriterSettings(isEnabled: false, consentGiven: false) {
            let view = Color.clear
                .modifier(MailContextInspectorModifier(
                    isPresented: .constant(true),
                    platform: .macOS,
                    selectedHeader: nil,
                    sourceID: nil,
                    backend: nil,
                    aiBackend: nil,
                    actionFolders: [],
                    focusedFolder: nil,
                    actionSourceScope: .currentMailbox,
                    executeAction: nil,
                    folderNameByID: [:],
                    composeActions: MailComposePresentationActions(
                        newMessage: {},
                        reply: { _, _ in },
                        replyAll: { _, _ in },
                        forward: { _, _ in }
                    ),
                    onOpenMessage: { _ in },
                    onShowAllFromSender: { _ in }
                ))
                .frame(width: 960, height: 600)
                .background(theme.bgPrimary.color)
                .brevTheme(theme)

            let host = NSHostingController(rootView: view)
            host.view.frame = CGRect(x: 0, y: 0, width: 960, height: 600)

            assertSnapshot(
                of: Self.retinaImage(of: host, size: CGSize(width: 960, height: 600)),
                as: .image,
                named: "in-window-sidebar",
                record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
            )
        }
    }

    @Test("AI Sidebar preserves the three-pane workspace while toggling")
    func inWindowSidebarPreservesThreePaneWorkspace() throws {
        let presentation = SidebarPresentation()
        let host = NSHostingController(rootView: SidebarWorkspaceHarness(presentation: presentation))
        let window = NSWindow(contentViewController: host)
        window.setContentSize(NSSize(width: 960, height: 600))

        host.view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let initialMessageListToken = try #require(presentation.messageListAppearanceTokens.first)
        presentation.isPresented = true
        // The freeze-and-reveal transition pins the content, then unfreezes
        // ~0.3s after the toggle — wait for the whole motion to settle.
        // Window growth itself is not assertable here: the width adjuster's
        // NSView never attaches to a window in a headless hosting harness
        // (its policy is covered by MailContextWindowGrowthPolicyTests, and
        // the animated resize was verified on screen with frame captures).
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
        host.view.layoutSubtreeIfNeeded()

        #expect(host.view.bounds.height == 600)
        #expect(!host.view.hasAmbiguousLayout)
        #expect(presentation.messageListAppearanceTokens == [initialMessageListToken])
        #expect(presentation.messageListDisappearances == 0)
    }

    @Test("Sender panel loaded state renders")
    func senderPanelLoadedState() {
        let theme = BrevTheme.brevPaper
        let header = MessageHeader(
            id: "selected",
            threadID: "thread-selected",
            folderID: "archive",
            from: Correspondent(name: "Ada Lovelace", email: "ada@example.com"),
            subject: "Selected",
            snippet: "Selected preview",
            date: Self.date(day: 5)
        )
        let snapshot = SenderContextSnapshot(
            identity: SenderContextIdentity(
                email: "ada@example.com",
                displayName: "Ada Lovelace",
                contactDisplayName: "Ada"
            ),
            messageCount: 4,
            firstSeen: Self.date(day: 2),
            lastSeen: Self.date(day: 5),
            recent: [
                SenderContextRecentItem(
                    id: "inbox-1",
                    folderID: "inbox",
                    subject: "Newest",
                    date: Self.date(day: 5),
                    folderName: "Inbox",
                    sourceID: MailSourceID(accountID: "acct", mailboxID: "primary")
                ),
                SenderContextRecentItem(
                    id: "archive-1",
                    folderID: "archive",
                    subject: "Older",
                    date: Self.date(day: 2),
                    folderName: "Archive",
                    sourceID: MailSourceID(accountID: "acct", mailboxID: "primary")
                ),
            ]
        )
        let view = SenderContextPanel(
            state: .loaded(header, snapshot),
            sourceID: MailSourceID(accountID: "acct", mailboxID: "primary"),
            composeActions: MailComposePresentationActions(
                newMessage: {},
                reply: { _, _ in },
                replyAll: { _, _ in },
                forward: { _, _ in }
            ),
            onOpenMessage: { _ in },
            onShowAllFromSender: { _ in }
        )
        .frame(width: 320, height: 320)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 320)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 320, height: 320)),
            named: "sender-panel-loaded",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("Mailbox chat action review renders")
    func mailboxChatActionReviewState() {
        let theme = BrevTheme.brevPaper
        let plan = Self.sampleActionReviewPlan()

        withAIWriterSettings(isEnabled: true, consentGiven: true) {
            let view = MailboxChatPanel(
                scope: .sender(email: "ada@example.com"),
                sourceID: MailSourceID(accountID: "acct", mailboxID: "primary"),
                aiBackend: SnapshotAIBackend(),
                actionFolders: [Self.inboxFolder],
                actionSourceScope: Self.sourceScope,
                executeAction: { _ in "Deleted 1 message from ada@example.com." },
                initialTurns: [
                    .user("delete all mail from ada@example.com"),
                    .actionReview(plan, providerLabel: MailboxChatController.localActionProviderLabel),
                ]
            )
            .frame(width: 320, height: 420)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)

            let host = NSHostingController(rootView: view)
            host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 420)

            assertSnapshot(
                of: host,
                as: .image(size: CGSize(width: 320, height: 420)),
                named: "chat-action-review",
                record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
            )
        }
    }

    @Test("Mailbox chat local clarification renders with provider label")
    func mailboxChatLocalClarificationRenders() {
        let theme = BrevTheme.brevPaper

        withAIWriterSettings(isEnabled: true, consentGiven: true) {
            let view = MailboxChatPanel(
                scope: .sender(email: "ada@example.com"),
                sourceID: MailSourceID(accountID: "acct", mailboxID: "primary"),
                aiBackend: SnapshotAIBackend(),
                initialTurns: [
                    .user("Did Ada pay the invoice?"),
                    .clarification(
                        text: "I couldn't find cached messages from ada@example.com that answer that yet.",
                        providerLabel: MailboxChatProviderLabelPolicy.localClarification()
                    ),
                ]
            )
            .frame(width: 320, height: 360)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)

            let host = NSHostingController(rootView: view)
            host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 360)

            assertSnapshot(
                of: host,
                as: .image(size: CGSize(width: 320, height: 360)),
                named: "chat-local-clarification",
                record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
            )
        }
    }

    @Test("Mailbox chat disabled state renders")
    func mailboxChatDisabledState() {
        let theme = BrevTheme.brevPaper

        withAIWriterSettings(isEnabled: false, consentGiven: false) {
            let sourceID = MailSourceID(accountID: "acct", mailboxID: "primary")
            let view = MailboxChatPanel(
                scope: .sender(email: "ada@example.com"),
                sourceID: sourceID,
                aiBackend: SnapshotAIBackend(),
                focusedFolder: Folder(id: "inbox", name: "Inbox", role: .inbox),
                actionSourceScope: MailboxActionAgentSourceScope(
                    sourceID: sourceID,
                    accountName: "Work",
                    mailboxName: "Primary",
                    mailboxAddress: "me@example.com"
                )
            )
            .frame(width: 320, height: 360)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)

            let host = NSHostingController(rootView: view)
            host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 360)

            assertSnapshot(
                of: host,
                as: .image(size: CGSize(width: 320, height: 360)),
                named: "chat-disabled",
                record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
            )
        }
    }

    private static func date(day: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day * 86400))
    }

    private static func retinaImage<Content: View>(
        of host: NSHostingController<Content>,
        size: CGSize
    ) -> NSImage {
        let view = host.view
        let originalSize = view.frame.size
        view.frame.size = size
        view.layoutSubtreeIfNeeded()
        defer { view.frame.size = originalSize }

        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: .alphaFirst,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.size = size
        view.cacheDisplay(in: view.bounds, to: bitmap)

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    private static let inboxFolder = Folder(id: "inbox", name: "Inbox", role: .inbox)

    private static let sourceScope = MailboxActionAgentSourceScope(
        sourceID: MailSourceID(accountID: "acct", mailboxID: "primary"),
        accountName: "Work",
        mailboxName: "Primary",
        mailboxAddress: "me@example.com"
    )

    private static func sampleActionReviewPlan() -> MailboxActionAgentPlan {
        let planID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let planner = MailboxActionAgentPlanner(idGenerator: { planID })
        let header = MessageHeader(
            id: "message-1",
            threadID: "thread-1",
            folderID: "inbox",
            from: Correspondent(name: "Ada Lovelace", email: "ada@example.com"),
            subject: "Invoice",
            snippet: "Snippet",
            date: date(day: 5)
        )

        guard case .planned(let plan) = planner.plan(
            request: "delete all mail from ada@example.com",
            headers: [header],
            folders: [inboxFolder],
            focusedFolder: nil,
            sourceScope: sourceScope
        ) else {
            fatalError("Expected a planned mailbox action")
        }

        return plan
    }

    private func withAIWriterSettings(
        isEnabled: Bool,
        consentGiven: Bool,
        perform: () -> Void
    ) {
        let defaults = UserDefaults.standard
        let previousEnabled = defaults.object(forKey: AIWriterSettings.Key.isEnabled)
        let previousConsent = defaults.object(forKey: AIWriterSettings.Key.consentGiven)

        defaults.set(isEnabled, forKey: AIWriterSettings.Key.isEnabled)
        defaults.set(consentGiven, forKey: AIWriterSettings.Key.consentGiven)
        defer {
            restore(previousEnabled, key: AIWriterSettings.Key.isEnabled, defaults: defaults)
            restore(previousConsent, key: AIWriterSettings.Key.consentGiven, defaults: defaults)
        }

        perform()
    }

    private func restore(_ value: Any?, key: String, defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

@MainActor
private final class SidebarPresentation: ObservableObject {
    @Published var isPresented = false
    var messageListAppearanceTokens: [UUID] = []
    var messageListDisappearances = 0
}

private struct SidebarWorkspaceHarness: View {
    @ObservedObject var presentation: SidebarPresentation

    var body: some View {
        NavigationSplitView {
            Text("Folders")
                .frame(minWidth: 220)
        } content: {
            MessageListStateProbe(presentation: presentation)
                .frame(minWidth: 280)
        } detail: {
            Text("Reader")
                .frame(minWidth: 400)
        }
        .modifier(MailContextInspectorModifier(
            isPresented: $presentation.isPresented,
            platform: .macOS,
            selectedHeader: nil,
            sourceID: nil,
            backend: nil,
            aiBackend: nil,
            actionFolders: [],
            focusedFolder: nil,
            actionSourceScope: .currentMailbox,
            executeAction: nil,
            folderNameByID: [:],
            composeActions: MailComposePresentationActions(
                newMessage: {},
                reply: { _, _ in },
                replyAll: { _, _ in },
                forward: { _, _ in }
            ),
            onOpenMessage: { _ in },
            onShowAllFromSender: { _ in }
        ))
    }
}

private struct MessageListStateProbe: View {
    @ObservedObject var presentation: SidebarPresentation
    @State private var token = UUID()

    var body: some View {
        Text("Messages")
            .onAppear {
                presentation.messageListAppearanceTokens.append(token)
            }
            .onDisappear {
                presentation.messageListDisappearances += 1
            }
    }
}

private struct SnapshotAIBackend: AIBackend {
    let identifier = "snapshot-ai"
    let displayName = "Snapshot AI"
    let transparencyLabel = "Sent to: Snapshot AI"

    func generateReply(
        to messages: [AIMessage],
        instruction: String?
    ) async throws -> AIResponse {
        _ = messages
        _ = instruction
        return AIResponse(text: "Unused")
    }

    func shortcut(
        _ action: AIShortcutAction,
        on text: String
    ) async throws -> AIResponse {
        _ = action
        _ = text
        return AIResponse(text: "Unused")
    }
}
#endif
