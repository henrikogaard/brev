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
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

/// Snapshot coverage for the pushed iPhone reader's conversation card and
/// quick-reply bar. Set `RECORD_SNAPSHOTS=YES` to record.
@Suite("Compact reader snapshots")
@MainActor
struct CompactReaderSnapshotTests {
    private static let header = MessageHeader(
        id: "m1",
        threadID: "thread-snapshot",
        folderID: "inbox",
        from: Correspondent(name: "Sigrid Moen", email: "sigrid.moen@example.org"),
        to: [Correspondent(name: "Henrik", email: "henrik@ogard.example")],
        subject: "Hytte weekend in Hemsedal",
        snippet: "Booked the cabin for three nights.",
        date: Date(timeIntervalSince1970: 1_779_960_600),
        isRead: true
    )

    @Test("expanded conversation card shows to-line, not the raw address", arguments: [false, true])
    func expandedCard(dark: Bool) {
        let theme = dark ? BrevTheme.brevMonoDark : BrevTheme.brevMonoLight
        let view = ThreadMessageCard(
            header: Self.header,
            isExpanded: true,
            isSelected: false,
            backend: MockBackend(),
            sourceID: nil,
            dateTextOverride: "12:00",
            initialRenderedBody: RenderedBody(html: nil, plainText: "Deterministic preview body.", attachments: [])
        ) {}
            .frame(width: 390, height: 170)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
            .htmlBodyRenderTarget(.staticSnapshot)
            .environment(\.colorScheme, dark ? .dark : .light)
        assertSnapshot(
            of: host(view, width: 390, height: 170, dark: dark),
            as: .image(size: CGSize(width: 390, height: 170), traits: .init(displayScale: 2)),
            named: dark ? "card-dark" : "card-light",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("collapsed conversation card at accessibility text size")
    func collapsedCardAccessibility() {
        let theme = BrevTheme.brevMonoLight
        let view = ThreadMessageCard(
            header: Self.header,
            isExpanded: false,
            isSelected: false,
            backend: MockBackend(),
            sourceID: nil,
            dateTextOverride: "12:00"
        ) {}
            .frame(width: 390, height: 260)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
            .htmlBodyRenderTarget(.staticSnapshot)
            .dynamicTypeSize(.accessibility3)
        assertSnapshot(
            of: host(view, width: 390, height: 260, dark: false),
            as: .image(size: CGSize(width: 390, height: 260), traits: .init(displayScale: 2)),
            named: "card-collapsed-accessibility",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("quick reply bar keeps 44 pt buttons in both themes", arguments: [false, true])
    func quickReplyBar(dark: Bool) {
        let theme = dark ? BrevTheme.brevMonoDark : BrevTheme.brevMonoLight
        let view = ReaderQuickReplyBar(
            recipientName: "Sigrid Moen",
            onSend: { _ in true },
            onExpand: { _ in },
            isDisabled: false
        )
        .frame(width: 390, height: 70)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, dark ? .dark : .light)
        assertSnapshot(
            of: host(view, width: 390, height: 70, dark: dark),
            as: .image(size: CGSize(width: 390, height: 70), traits: .init(displayScale: 2)),
            named: dark ? "quick-reply-dark" : "quick-reply-light",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("undo toast keeps 44 pt Undo and Dismiss targets")
    func undoToast() {
        let theme = BrevTheme.brevMonoLight
        let queue = UndoQueue(timeout: 600)
        queue.push(UndoableMutation(description: "Archived") {})
        let view = MailUndoToast(queue: queue, isBlocked: false, onUndo: {}, onRetry: {})
            .padding(16)
            .frame(width: 390, height: 90)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
        assertSnapshot(
            of: host(view, width: 390, height: 90, dark: false),
            as: .image(size: CGSize(width: 390, height: 90), traits: .init(displayScale: 2)),
            named: "undo-toast",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    private func host(_ view: some View, width: CGFloat, height: CGFloat, dark: Bool) -> UIViewController {
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = dark ? .dark : .light
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        return host
    }
}
#endif
