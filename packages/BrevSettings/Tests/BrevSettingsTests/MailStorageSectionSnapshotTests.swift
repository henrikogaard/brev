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
@testable import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

/// Snapshot coverage for the "Local folders" row added by ADR-0077 decision 6.
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh the baselines.
@Suite("MailStorageSection local folders snapshots")
@MainActor
struct MailStorageSectionSnapshotTests {
    @Test("local folders group shows size and not-a-cache copy", arguments: ["light", "dark"])
    func localFoldersRow(_ mode: String) throws {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mailstorage-\(UUID().uuidString)", isDirectory: true)
        let local = LocalMailBackend(store: LocalMaildirStore(rootURL: root))
        let account = BrevAccount(
            id: "imap-smtp:ada@example.org",
            displayName: "Ada",
            emailAddress: "ada@example.org"
        )
        let suiteName = "MailStorageSnapshots-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let view = MailStorageSection(
            account: account,
            backend: nil,
            settingsStore: SettingsPersistenceStore(defaults: defaults),
            localBackend: local
        )
        .frame(width: 560, height: 520)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        host.view.frame.size = CGSize(width: 560, height: 520)
        host.view.layoutSubtreeIfNeeded()
        // Let the `.task` reload() populate the local size.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.view.layoutSubtreeIfNeeded()
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 560, height: 520)),
            named: "mailstorage-local-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    /// ADR-0078: the per-account "Attachment index" row with Rebuild/Remove
    /// renders inside the search-index group when the backend advertises
    /// `.localAttachmentIndex`.
    @Test("attachment index row shows size and actions", arguments: ["light", "dark"])
    func attachmentIndexRow(_ mode: String) throws {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let account = BrevAccount(
            id: "imap-smtp:ada@example.org",
            displayName: "Ada",
            emailAddress: "ada@example.org"
        )
        let backend = MockBackend(
            account: account,
            extendedCapabilities: [.localAttachmentIndex],
            folders: [],
            messagesByFolder: [:]
        )
        let suiteName = "MailStorageAttachIdx-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let view = MailStorageSection(
            account: account,
            backend: backend,
            settingsStore: SettingsPersistenceStore(defaults: defaults),
            initiallyAdvancedExpanded: true
        )
        .frame(width: 560, height: 720)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        host.view.frame.size = CGSize(width: 560, height: 720)
        host.view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.view.layoutSubtreeIfNeeded()
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 560, height: 720)),
            named: "mailstorage-attachment-index-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
