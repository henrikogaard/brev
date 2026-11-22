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
@testable import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

/// Optional macOS new-mail drop-down panel card (#307).
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh the baseline.
@Suite("New-mail drop-down panel snapshots")
@MainActor
struct NewMailDropDownPanelSnapshotTests {
    @Test("drop-down panel shows sender, one-line preview, and action buttons", arguments: ["light", "dark"])
    func dropDownPanel(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let payload = NewMailPanelPayload(
            route: NotificationMailRoute(accountID: "acct-1", folderID: "inbox", messageID: "msg-1"),
            senderName: "Maya Okafor",
            senderEmail: "maya@northwind.example",
            previewLine: "Q4 roadmap: final review — Can you sign off before Thursday?",
            receivedAt: Date(timeIntervalSince1970: 1_794_500_000)
        )

        let view = NewMailDropDownPanelView(
            payload: payload,
            onArchive: {},
            onMarkRead: {},
            onReply: {},
            onDismiss: {},
            onHoverChanged: { _ in }
        )
        .padding(16)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 412, height: 136)),
            named: "new-mail-panel-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("Notification settings section displays macOS new-mail drop-down panel toggle")
    func macNotificationSectionDropDownToggle() throws {
        let suite = "NewMailPanelSettingsSnap-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = NotificationSettings.defaults
        settings.newMailPanelEnabled = true
        let store = SettingsPersistenceStore(defaults: defaults)
        store.save(settings)

        let theme = BrevTheme.brevMonoLight
        let view = NotificationSection(
            settingsStore: store,
            accounts: [.preview],
            authorizationStatus: { .authorized }
        )
        .frame(width: 620, height: 680)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, .light)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 620, height: 680)),
            named: "mac-notification-section-panel-toggle",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
