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
import SnapshotTesting
import SwiftUI
import Testing

/// The reply docked under the reader (#302 slice 1): the full composer with
/// its own action row instead of the window toolbar. Set
/// `RECORD_SNAPSHOTS=YES` to record.
@Suite("Inline reply snapshots")
@MainActor
struct InlineReplySnapshotTests {
    @Test("docked reply across light and dark themes", arguments: [
        "brevMonoLight", "brevMonoDark", "solarizedLight", "solarizedDark", "gruvboxLight", "gruvboxDark",
    ])
    func dockedReply(_ themeName: String) throws {
        try assertDockedReply(themeName, testName: "dockedReply(_:)", aiWriterOn: false)
    }

    /// With AI Writer on, the quick reply starters and the "Describe your
    /// reply" field sit under the fields (#302 slice 2).
    @Test("docked reply with quick reply starters", arguments: [
        "brevMonoLight", "brevMonoDark", "solarizedLight", "solarizedDark", "gruvboxLight", "gruvboxDark",
    ])
    func dockedReplyWithStarters(_ themeName: String) throws {
        try assertDockedReply(themeName, testName: "dockedReplyWithStarters(_:)", aiWriterOn: true)
    }

    /// An open AI preview in the fixed-height dock: the fields and starters
    /// step aside so the draft text stays readable (#302).
    @Test("docked reply with an AI preview", arguments: [
        "brevMonoLight", "brevMonoDark", "solarizedLight", "solarizedDark", "gruvboxLight", "gruvboxDark",
    ])
    func dockedReplyWithAIPreview(_ themeName: String) throws {
        let request = ComposeAIShortcutRequest(
            action: .improveWriting,
            bodyText: "Sounds good, see you Tuesday.",
            target: .wholeDraft
        )
        let preview = ComposeAIPreviewState(
            id: 1,
            action: .replyStarter(.declinePolitely),
            request: request,
            providerLabel: "Sent to: Snapshot AI",
            phase: .loading
        ).succeeded(with: """
        Hi Maya,

        Thanks for including me. I can't make the final review this time, \
        but I'm happy to read the notes afterwards.

        Best regards
        """)
        try assertDockedReply(
            themeName, testName: "dockedReplyWithAIPreview(_:)", aiWriterOn: true, aiPreview: preview
        )
    }

    private func assertDockedReply(
        _ themeName: String,
        testName: String,
        aiWriterOn: Bool,
        aiPreview: ComposeAIPreviewState? = nil
    ) throws {
        let theme = try #require(Self.theme(named: themeName))
        let backend = MockBackend(supportsScheduledSend: false)
        let original = MessageHeader(
            id: "original", threadID: "t", folderID: "inbox",
            from: Correspondent(name: "Maya Okafor", email: "maya@example.com"),
            subject: "Q4 roadmap: final review", snippet: "", date: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let suiteName = "InlineReplySnapshotTests-\(testName)-\(themeName)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(aiWriterOn, forKey: AIWriterSettings.Key.isEnabled)
        defaults.set(aiWriterOn, forKey: AIWriterSettings.Key.consentGiven)
        let view = ComposeView(
            backend: backend,
            from: Correspondent(name: backend.account.displayName, email: backend.account.emailAddress),
            senderOptions: [],
            replyingTo: original,
            prefill: ComposePrefill(bodyText: "Sounds good, see you Tuesday."),
            aiBackend: aiWriterOn ? StarterSnapshotAIBackend() : nil,
            backendSupportsAIWriter: aiWriterOn,
            recoveryDefaults: defaults,
            hostStyle: .inline,
            initialAIPreview: aiPreview
        )
        .frame(width: 760, height: MailRootInlineReplyLayout.height)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .defaultAppStorage(defaults)
        .htmlBodyRenderTarget(.staticSnapshot)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        let size = CGSize(width: 760, height: MailRootInlineReplyLayout.height)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: theme.mode.colorScheme == .dark ? .darkAqua : .aqua)
        host.view.frame = CGRect(origin: .zero, size: size)
        assertSnapshot(of: host, as: .image(size: size), named: themeName,
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil,
                       testName: testName)
    }

    private static func theme(named name: String) -> BrevTheme? {
        switch name {
        case "brevMonoLight": .brevMonoLight
        case "brevMonoDark": .brevMonoDark
        case "solarizedLight": .solarizedLight
        case "solarizedDark": .solarizedDark
        case "gruvboxLight": .gruvboxLight
        case "gruvboxDark": .gruvboxDark
        default: nil
        }
    }
}

private struct StarterSnapshotAIBackend: AIBackend {
    let identifier = "snapshot-ai"
    let displayName = "Snapshot AI"
    let transparencyLabel = "Sent to: Snapshot AI"

    func generateReply(to messages: [AIMessage], instruction: String?) async throws -> AIResponse {
        AIResponse(text: "Unused")
    }

    func shortcut(_ action: AIShortcutAction, on text: String) async throws -> AIResponse {
        AIResponse(text: "Unused")
    }
}
#endif
