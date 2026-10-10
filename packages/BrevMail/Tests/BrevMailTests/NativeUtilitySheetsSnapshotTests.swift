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

#if canImport(UIKit)
import BrevBackend
@testable import BrevMail
import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

/// The iOS utility sheets (Move To, Note, Properties, Task, Event, View Source)
/// and the shared sheet appearance modifier that themes them.
@Suite("Native utility sheet snapshots")
@MainActor
struct NativeUtilitySheetsSnapshotTests {
    private static func header() -> MessageHeader {
        MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Alex Rivera", email: "alex@example.org"),
            subject: "Quarterly report follow-up",
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600),
            isRead: false,
            isFlagged: false
        )
    }

    /// Fresh defaults holding one saved appearance mode, so the shared sheet
    /// modifier resolves its theme from settings the way the app does.
    private static func defaults(mode: AppearanceThemeMode) throws -> UserDefaults {
        let name = "brev.sheet-appearance.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let json = Data(#"{"mode":"\#(mode.rawValue)"}"#.utf8)
        try JSONDecoder().decode(AppearanceThemeSettings.self, from: json).save(to: defaults)
        return defaults
    }

    /// Applies the shared sheet modifier the way a presented sheet gets it, and
    /// paints the background a real sheet would get from `presentationBackground`
    /// (a hosting controller has no presentation to carry it).
    private static func themed(
        _ view: some View,
        mode: AppearanceThemeMode,
        system: UIUserInterfaceStyle,
        presenter: BrevTheme = .brevMonoLight
    ) throws -> some View {
        let defaults = try defaults(mode: mode)
        let resolved = BrevSheetAppearanceResolution.resolve(
            presenterTheme: presenter,
            settings: AppearanceThemeSettings.load(from: defaults),
            prefersDark: system == .dark,
            increasedContrast: false
        )
        return view
            .brevSheetAppearance(presenter, defaults: defaults)
            .background(resolved.theme.bgPrimary.color.ignoresSafeArea())
    }

    private static func note() -> LocalMessageNote {
        LocalMessageNote(
            messageID: SourceMessageID(
                sourceID: MailSourceID(accountID: "acct", mailboxID: "inbox"),
                messageID: "m1"
            ),
            body: "Follow up after launch. Confirm the rollout date with the platform team.",
            createdAt: Date(timeIntervalSince1970: 1_779_960_000),
            updatedAt: Date(timeIntervalSince1970: 1_779_961_200)
        )
    }

    private static func noteSheet() -> MessageNoteSheet {
        MessageNoteSheet(header: header(), note: note(), onSave: { _ in }, onDelete: {}, onClose: {})
    }

    private static func snapshot(
        _ view: some View,
        style: UIUserInterfaceStyle,
        named name: String,
        testName: String = #function,
        line: UInt = #line
    ) {
        let traits = UITraitCollection(traitsFrom: [
            .init(displayScale: 2),
            .init(userInterfaceStyle: style)
        ])
        let host = UIHostingController(rootView: view.environment(\.locale, Locale(identifier: "en_US")))
        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: traits),
            named: name,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil,
            testName: testName,
            line: line
        )
    }

    // MARK: Shared sheet appearance

    @Test("follow-system dark renders dark even when the presenter's theme is stale light")
    func followSystemDark() throws {
        let view = try Self.themed(Self.noteSheet(), mode: .followSystem, system: .dark, presenter: .brevMonoLight)
        Self.snapshot(view, style: .dark, named: "note-follow-system-dark")
    }

    /// A bare hosting controller cannot carry the window pin that
    /// `preferredColorScheme` applies, so the always-dark-on-a-light-system
    /// case is covered by `SheetAppearanceTests.alwaysDarkPinsDarkOnLightSystem`
    /// and the simulator run; this renders the pinned dark theme itself.
    @Test("an always-dark theme renders dark")
    func alwaysDark() throws {
        let view = try Self.themed(Self.noteSheet(), mode: .alwaysDark, system: .dark, presenter: .brevMonoDark)
        Self.snapshot(view, style: .dark, named: "note-always-dark")
    }

    @Test("a light theme renders light")
    func lightTheme() throws {
        let view = try Self.themed(Self.noteSheet(), mode: .alwaysLight, system: .light)
        Self.snapshot(view, style: .light, named: "note-light")
    }

    // MARK: Utility sheets

    @Test("Move To is a searchable folder list under a Cancel-only navigation bar", arguments: [false, true])
    func moveTo(dark: Bool) throws {
        let folders = [
            Folder(id: "inbox", name: "Inbox", role: .inbox, unreadCount: 4),
            Folder(id: "archive", name: "Archive", role: .archive),
            Folder(id: "receipts", name: "Receipts", role: .custom, unreadCount: 2),
            Folder(id: "trash", name: "Trash", role: .trash)
        ]
        let sheet = MoveToSheet(
            allFolders: folders,
            messageIDs: ["m1"],
            currentFolderID: "inbox",
            onMove: { _, _ in }
        )
        let style: UIUserInterfaceStyle = dark ? .dark : .light
        let view = try Self.themed(sheet, mode: .followSystem, system: style)
        Self.snapshot(view, style: style, named: dark ? "move-to-dark" : "move-to-light")
    }

    @Test("Properties is a grouped list with Done in the navigation bar")
    func properties() throws {
        let view = try Self.themed(
            MessagePropertiesSheet(header: Self.header(), onClose: {}),
            mode: .followSystem,
            system: .light
        )
        Self.snapshot(view, style: .light, named: "properties-light")
    }

    @Test("Create Task is a form with Cancel and Create in the navigation bar")
    func createTask() throws {
        let draft = try #require(MessageTaskDraftBuilder.draft(for: Self.header(), accountID: "acct"))
        let sheet = MessageTaskSheet(
            draft: draft,
            create: { _ in throw CancellationError() },
            onClose: {}
        )
        let view = try Self.themed(sheet, mode: .followSystem, system: .light)
        Self.snapshot(view, style: .light, named: "task-light")
    }

    @Test("Create Meeting is a form with Cancel and Create in the navigation bar")
    func createMeeting() throws {
        let draft = try #require(MessageEventDraftBuilder.draft(
            for: Self.header(),
            accountID: "acct",
            referenceDate: Date(timeIntervalSince1970: 1_779_960_000)
        ))
        let sheet = MessageEventSheet(
            draft: draft,
            create: { _ in throw CancellationError() },
            onClose: {}
        )
        let view = try Self.themed(sheet, mode: .followSystem, system: .light)
        Self.snapshot(view, style: .light, named: "meeting-light")
    }

    @Test("View Source shows its mode as the title with Done in the navigation bar")
    func viewSource() throws {
        let sheet = MessageRawSourceSheet(
            header: Self.header(),
            mode: .fullSource,
            loadSource: {
                try await Task.sleep(for: .seconds(60))
                return ""
            },
            onClose: {}
        )
        let view = try Self.themed(sheet, mode: .followSystem, system: .light)
        Self.snapshot(view, style: .light, named: "view-source-loading-light")
    }
}
#endif
