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
        let theme = try #require(Self.theme(named: themeName))
        let backend = MockBackend()
        let original = MessageHeader(
            id: "original", threadID: "t", folderID: "inbox",
            from: Correspondent(name: "Maya Okafor", email: "maya@example.com"),
            subject: "Q4 roadmap: final review", snippet: "", date: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let defaults = try #require(UserDefaults(suiteName: "InlineReplySnapshotTests-\(themeName)"))
        defaults.removePersistentDomain(forName: "InlineReplySnapshotTests-\(themeName)")
        defer { defaults.removePersistentDomain(forName: "InlineReplySnapshotTests-\(themeName)") }
        let view = ComposeView(
            backend: backend,
            from: Correspondent(name: backend.account.displayName, email: backend.account.emailAddress),
            senderOptions: [],
            replyingTo: original,
            prefill: ComposePrefill(bodyText: "Sounds good, see you Tuesday."),
            recoveryDefaults: defaults,
            hostStyle: .inline
        )
        .frame(width: 760, height: MailRootInlineReplyLayout.height)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .htmlBodyRenderTarget(.staticSnapshot)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        let size = CGSize(width: 760, height: MailRootInlineReplyLayout.height)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: theme.mode.colorScheme == .dark ? .darkAqua : .aqua)
        host.view.frame = CGRect(origin: .zero, size: size)
        assertSnapshot(of: host, as: .image(size: size), named: themeName,
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
#endif
