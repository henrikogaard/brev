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

/// The macOS thread header (#306 slice 4): subject, participant names, the
/// "N messages" chip and an inline Summarize link, in a column centred in a
/// wide reader. Set `RECORD_SNAPSHOTS=YES` to record the baselines.
@Suite("Thread header snapshots")
@MainActor
struct ThreadHeaderSnapshotTests {
    @Test("thread header across light and dark themes", arguments: [
        "brevMonoLight", "brevMonoDark", "solarizedLight", "solarizedDark", "gruvboxLight", "gruvboxDark",
    ])
    func header(_ themeName: String) throws {
        let theme = try #require(Self.theme(named: themeName))
        let suite = "ThreadHeaderSnapshotTests-\(themeName)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AIWriterSettings.Key.isEnabled)
        defaults.set(true, forKey: AIWriterSettings.Key.consentGiven)

        let senders = [
            Correspondent(name: "Maya Okafor", email: "maya@example.com"),
            Correspondent(name: "Daniel Reyes", email: "daniel@example.com"),
            Correspondent(name: "Priya Natarajan", email: "priya@example.com"),
        ]
        let headers = senders.enumerated().map { index, sender in
            MessageHeader(
                id: "m\(index)", threadID: "thread", folderID: "inbox", from: sender,
                to: [Correspondent(name: "Team", email: "team@example.com")],
                subject: "Q4 roadmap: final review", snippet: "Notes on the final review.",
                date: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 3600), isRead: true
            )
        }
        let source = MailSourceID(accountID: "work", mailboxID: "work")
        let navigation = MailNavigationState(
            selectedSourceID: source, selectedFolderID: "inbox", selectedMessageID: nil,
            currentFolderHeaders: headers
        )
        let width: CGFloat = 1100, height: CGFloat = 220
        let view = ThreadConversationView(
            threadHeaders: headers, backend: MockBackend(), sourceID: source, navigation: navigation,
            aiBackend: SnapshotSummaryAIBackend(), showsAvatars: false, autoScrollsToExpandedMessage: false,
            dateTextProvider: { _ in "Sep 4, 14:20" }
        )
        .frame(width: width, height: height)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .htmlBodyRenderTarget(.staticSnapshot)
        .defaultAppStorage(defaults)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: theme.mode.colorScheme == .dark ? .darkAqua : .aqua)
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        assertSnapshot(of: host, as: .image(size: CGSize(width: width, height: height)), named: themeName,
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
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

/// Makes the inline Summarize link enabled; the snapshot never runs it.
private struct SnapshotSummaryAIBackend: AIBackend {
    let identifier = "snapshot-summary-ai"
    let displayName = "Snapshot AI"
    let transparencyLabel = "Sent to: Snapshot AI"

    func generateReply(to messages: [AIMessage], instruction: String?) async throws -> AIResponse {
        _ = messages
        _ = instruction
        return AIResponse(text: "Unused")
    }

    func shortcut(_ action: AIShortcutAction, on text: String) async throws -> AIResponse {
        _ = action
        _ = text
        return AIResponse(text: "Unused")
    }
}
#endif
