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
import SnapshotTesting
import SwiftUI
import Testing

/// Full-window sequential triage surface (#293).
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh the baseline.
@Suite("Triage view snapshots")
@MainActor
struct TriageViewSnapshotTests {
    @Test("Triage shows active conversation, progress line, and key hints", arguments: ["light", "dark"])
    func triageActive(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let source = MailSourceID(accountID: "acct", mailboxID: "box")
        let now = Date(timeIntervalSince1970: 1_794_500_000)
        let first = MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Maya Okafor", email: "maya@northwind.example"),
            subject: "Q4 roadmap: final review before Thursday",
            snippet: "Can you sign off on section 3 before noon?",
            date: now.addingTimeInterval(-3600),
            isRead: false
        )
        let second = MessageHeader(
            id: "m2",
            threadID: "t2",
            folderID: "inbox",
            from: Correspondent(name: "Daniel Reyes", email: "daniel@example.com"),
            subject: "Onboarding copy",
            snippet: "Draft is ready for a quick read.",
            date: now.addingTimeInterval(-7200),
            isRead: false
        )
        let session = TriageSession(
            items: [
                TriageItem(sourceID: source, header: first, threadHeaders: [first]),
                TriageItem(sourceID: source, header: second, threadHeaders: [second]),
            ],
            returnPosition: TriageReturnPosition(
                selectedSourceID: source,
                selectedFolderID: "inbox",
                selectedMessageID: "m1",
                isUnifiedInboxSelected: false,
                isSmartViewSelected: false
            )
        )

        let view = TriageView(
            session: session,
            canArchive: true,
            canSnooze: true,
            canReply: true,
            isKeyHandlingSuspended: true,
            onArchive: {},
            onSnooze: {},
            onReply: {},
            onSkip: {},
            onDone: {},
            onUndo: {},
            onPreloadNext: {}
        ) { item, _ in
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                Text(verbatim: item.header.subject)
                    .brevFont(.title)
                    .foregroundStyle(theme.textPrimary.color)
                Text(verbatim: item.header.from.name ?? item.header.from.email)
                    .brevFont(.callout)
                    .foregroundStyle(theme.textSecondary.color)
                Divider()
                Text(
                    verbatim: "Hi Alex,\n\nCan you sign off on section 3 of the Q4 roadmap before Thursday noon? Everything else is locked."
                )
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                Spacer()
            }
            .padding(BrevSpacing.xl)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 820, height: 560)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 820, height: 560)),
            named: "triage-active-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("Triage caught-up state shows completion summary", arguments: ["light", "dark"])
    func triageCaughtUp(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let session = TriageSession(
            items: [],
            returnPosition: TriageReturnPosition(
                selectedSourceID: nil,
                selectedFolderID: nil,
                selectedMessageID: nil,
                isUnifiedInboxSelected: false,
                isSmartViewSelected: false
            )
        )

        let view = TriageView(
            session: session,
            canArchive: false,
            canSnooze: false,
            canReply: false,
            isKeyHandlingSuspended: true,
            onArchive: {},
            onSnooze: {},
            onReply: {},
            onSkip: {},
            onDone: {},
            onUndo: {},
            onPreloadNext: {}
        ) { _, _ in
            EmptyView()
        }
        .frame(width: 820, height: 560)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 820, height: 560)),
            named: "triage-caught-up-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
