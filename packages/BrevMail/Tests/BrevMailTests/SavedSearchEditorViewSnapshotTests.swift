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
@testable import BrevMail
import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@Suite("Saved Search editor snapshots")
@MainActor
struct SavedSearchEditorViewSnapshotTests {
    @Test("Create mode renders")
    func create() {
        let theme = BrevTheme.brevBuiltIns.first!
        let view = SavedSearchEditorView(onFinished: {})
            .frame(width: 390, height: 600)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        assertSnapshot(of: host, as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)), named: "create")
    }
}

#elseif os(macOS)
import AppKit
@testable import BrevMail
import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

@Suite("Smart View editor snapshots")
@MainActor
struct SavedSearchEditorViewSnapshotTests {
    @Test("Create mode exposes condition controls", arguments: [false, true])
    func create(dark: Bool) {
        let theme = dark ? BrevTheme.brevMonoDark : BrevTheme.brevMonoLight
        let view = SavedSearchEditorView(onFinished: {})
            .frame(width: 720, height: 381)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
            .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.view.frame = CGRect(x: 0, y: 0, width: 720, height: 381)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 720, height: 381)),
            named: dark ? "create-dark" : "create-light",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("Editing many conditions keeps the footer visible")
    func manyConditions() {
        let conditions: [SmartViewCondition] = [
            .init(field: .from, comparison: .doesNotContain, value: "newsletter"),
            .init(field: .subject, comparison: .beginsWith, value: "Project"),
            .init(field: .received, comparison: .inLastDays, value: "14"),
            .init(field: .isRead, comparison: .isFalse),
            .init(field: .isFlagged, comparison: .isTrue),
            .init(field: .hasAttachments, comparison: .isTrue),
            .init(field: .isAnswered, comparison: .isFalse),
            .init(field: .recipients, comparison: .endsWith, value: "example.com"),
            .init(field: .subject, comparison: .doesNotContain, value: "cancelled")
        ]
        let mailbox = SmartMailbox(id: "edit", name: "Project updates", query: .init(
            text: "", conditions: conditions, matchMode: .any, includeTrash: false, includeSent: true
        ), isEnabled: true)
        let view = SavedSearchEditorView(editing: mailbox, onFinished: {})
            .frame(width: 720, height: 640)
            .brevTheme(.brevMonoDark)
            .environment(\.colorScheme, .dark)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: .darkAqua)
        host.view.frame = CGRect(x: 0, y: 0, width: 720, height: 640)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 720, height: 640)), named: "many-dark",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

    @Test("Management shows hidden and mixed-order views", arguments: [false, true])
    func management(dark: Bool) throws {
        let defaults = UserDefaults(suiteName: "SmartViewSnapshot-" + UUID().uuidString)!
        let settings = SmartMailboxSettings(mailboxes: [
            .init(id: "invoices", name: "Invoices", query: .init(text: "invoice"), isEnabled: false)
        ], disabledBuiltInIDs: ["vip"], displayOrder: ["builtin:flagged", "custom:invoices"])
        settings.save(to: defaults)
        let theme = dark ? BrevTheme.brevMonoDark : BrevTheme.brevMonoLight
        let view = SmartViewsSection(settingsStore: .init(defaults: defaults))
            .frame(width: 680, height: 570)
            .brevTheme(theme)
            .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.view.frame = CGRect(x: 0, y: 0, width: 680, height: 570)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 680, height: 570)),
                       named: dark ? "management-dark" : "management-light",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }
}
#endif
