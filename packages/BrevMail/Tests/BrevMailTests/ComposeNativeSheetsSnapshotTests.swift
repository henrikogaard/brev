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

/// Phone-width snapshots of the compose sheets that became native iOS sheets
/// (Insert Link, Schedule Send, Templates, the Drive sheet chrome) and of the
/// compose header with Cc/Bcc revealed.
@Suite("Compose native sheet snapshots", .serialized)
@MainActor
struct ComposeNativeSheetsSnapshotTests {
    private static let phone = CGSize(width: 390, height: 844)
    private static let traits = UITraitCollection(displayScale: 2)

    private func snapshot(
        _ view: some View,
        named name: String,
        size: CGSize = phone,
        traits: UITraitCollection = ComposeNativeSheetsSnapshotTests.traits,
        theme: BrevTheme = .brevPaper,
        fileID: StaticString = #fileID,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let host = UIHostingController(rootView: view.environment(\.brevTheme, theme).htmlBodyRenderTarget(.staticSnapshot))
        // A real window gives navigation bars and the searchable drawer their
        // normal appearance; a detached hosting view renders them washed out.
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        assertSnapshot(
            of: host,
            as: .image(size: size, traits: traits),
            named: name,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil,
            fileID: fileID,
            file: file,
            testName: testName,
            line: line
        )
    }

    @Test("Insert Link sheet is a native form with Cancel and Insert in the navigation bar")
    func linkSheet() {
        snapshot(
            ComposeLinkSheet(
                input: ComposeLinkSheetInput(urlString: "", displayText: "Quarterly plan", hasExistingLink: false),
                onConfirm: { _, _ in },
                onRemove: {}
            ),
            named: "new-link"
        )
    }

    @Test("Insert Link sheet offers Remove Link when the selection already has a link")
    func linkSheetExistingLink() {
        snapshot(
            ComposeLinkSheet(
                input: ComposeLinkSheetInput(
                    urlString: "https://example.com/plan",
                    displayText: "Quarterly plan",
                    hasExistingLink: true
                ),
                onConfirm: { _, _ in },
                onRemove: {}
            ),
            named: "existing-link"
        )
    }

    @Test("Schedule Send sheet is a scrolling form with a custom date picker")
    func scheduleSendSheet() {
        let now = Date(timeIntervalSince1970: 1_779_960_600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        let locale = Locale(identifier: "en_US")
        snapshot(
            ScheduleSendSheet(
                initiallyScheduledDate: nil,
                now: { now },
                calendar: calendar,
                locale: locale,
                onConfirm: { _ in }
            ),
            named: "quick-picks"
        )
        snapshot(
            ScheduleSendSheet(
                initiallyScheduledDate: now.addingTimeInterval(60 * 60 * 30),
                now: { now },
                calendar: calendar,
                locale: locale,
                onConfirm: { _ in }
            ),
            named: "custom-date"
        )
    }

    @Test("Template picker is a searchable list with Done in the navigation bar")
    func templatePicker() {
        let settings = MessageTemplateSettings(templates: [
            MessageTemplate(
                id: "t1",
                name: "Meeting follow-up",
                body: "Thanks for your time today. Notes and next steps below.",
                subject: "Follow-up",
                isPinned: true,
                createdAt: Date(timeIntervalSince1970: 1_779_000_000)
            ),
            MessageTemplate(
                id: "t2",
                name: "Out of office",
                body: "I'm away until Monday and will reply when I'm back.",
                createdAt: Date(timeIntervalSince1970: 1_779_000_100)
            )
        ])
        snapshot(
            TemplatePickerView(
                templateSettings: .constant(settings),
                accountID: nil,
                currentSubject: "",
                currentBody: "",
                onInsert: { _ in },
                onSaveAsTemplate: { _ in }
            ),
            named: "templates"
        )
        snapshot(
            TemplatePickerView(
                templateSettings: .constant(.defaults),
                accountID: nil,
                currentSubject: "",
                currentBody: "",
                onInsert: { _ in },
                onSaveAsTemplate: { _ in }
            ),
            named: "templates-empty"
        )
    }

    @Test("Drive sheet chrome fits the phone instead of imposing a 560 pt minimum width")
    func driveSheetChrome() {
        snapshot(
            GoogleDriveSheetChrome(title: "Google Drive") {
                Text(verbatim: "Drive content")
            },
            named: "chrome"
        )
    }

    @Test("Cc and Bcc rows render with their recipients")
    func ccBccExpanded() {
        let backend = MockBackend()
        snapshot(
            ComposeView(
                backend: backend,
                from: backend.account,
                prefill: ComposePrefill(
                    to: ["ingrid.halvorsen@acme.example"],
                    cc: ["marte@example.org"],
                    bcc: ["archive@example.org"],
                    subject: "Stavanger rollout"
                )
            )
            .environment(\.horizontalSizeClass, .compact),
            named: "cc-bcc",
            theme: .brevMonoLight
        )
    }
}
#endif
