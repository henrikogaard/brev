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
import BrevDesign
@testable import BrevMail
import BrevThemes
import Foundation
import SnapshotTesting
import SwiftUI
import Testing

/// macOS snapshot coverage for `ThreadMessageCard` in native mode (`useRichRenderer == false`)
/// rendering the manual remote-content consent banner above the fallback body (#8).
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh baselines on macOS 26+.
@Suite("Thread native remote-blocked banner snapshots")
@MainActor
struct ThreadNativeRemoteBlockedSnapshotTests {
    @Test("expanded thread card renders native remote-content consent banner", arguments: ["light", "dark"])
    func nativeRemoteBlockedBanner(_ mode: String) throws {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let suiteName = "ThreadNativeRemoteBlockedSnapshot-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: MailboxViewPreferenceKey.useRichRenderer)
        defaults.set(false, forKey: MailboxViewPreferenceKey.allowRemoteContent)
        defaults.set(false, forKey: MailboxViewPreferenceKey.allowRemoteContentForTrustedSenders)

        let header = MessageHeader(
            id: "msg-native-blocked",
            threadID: "thread-native-blocked",
            folderID: "inbox",
            from: Correspondent(name: "Ada Lovelace", email: "ada@example.org"),
            to: [Correspondent(name: "Henrik", email: "henrik@example.org")],
            subject: "Quarterly Update",
            snippet: "Here is the quarterly update.",
            date: Date(timeIntervalSince1970: 1_732_456_800),
            isRead: true
        )
        let body = RenderedBody(
            html: #"<p>Hi team,</p><img src="https://cdn.example.org/chart.png" width="600" height="300">"#,
            plainText: "Hi team,\n\nHere is the quarterly update.",
            attachments: []
        )

        let view = ThreadMessageCard(
            header: header,
            isExpanded: true,
            backend: MockBackend(),
            sourceID: nil,
            showsAvatar: false,
            dateTextOverride: "Nov 24, 2:00 PM",
            initialRenderedBody: body,
            onToggle: {}
        )
        .defaultAppStorage(defaults)
        .frame(width: 560, height: 190, alignment: .topLeading)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 560, height: 190)),
            named: "thread-native-remote-blocked-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
