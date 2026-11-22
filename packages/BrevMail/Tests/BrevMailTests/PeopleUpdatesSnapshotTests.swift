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

/// Snapshots for the People / Updates pill bar, bundled Updates rows, and Subscriptions view (#295).
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh the baseline.
@Suite("People, Updates, and Subscriptions snapshots")
@MainActor
struct PeopleUpdatesSnapshotTests {
    @Test("People/Updates pill bar and collapsed Updates bundle render cleanly", arguments: ["light", "dark"])
    func peopleUpdatesAndBundle(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let source = MailSourceID(accountID: "acct", mailboxID: "box")
        let now = Date(timeIntervalSince1970: 1_794_500_000)
        let h1 = MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Linear", email: "notifications@linear.app"),
            subject: "BREV-42 assigned to you",
            snippet: "Assigned in Q4 sprint",
            date: now.addingTimeInterval(-600),
            isRead: false
        )
        let h2 = MessageHeader(
            id: "m2",
            threadID: "t2",
            folderID: "inbox",
            from: Correspondent(name: "Linear", email: "notifications@linear.app"),
            subject: "BREV-39 commented on",
            snippet: "Maya commented on your issue",
            date: now.addingTimeInterval(-3600),
            isRead: false
        )
        let bundle = UpdatesSenderBundle(
            id: "notifications@linear.app",
            senderName: "Linear",
            senderEmail: "notifications@linear.app",
            sourceID: source,
            headers: [h1, h2]
        )

        let view = VStack(alignment: .leading, spacing: 0) {
            PeopleUpdatesTabBar(
                activeTab: .constant(.updates),
                counts: PeopleUpdatesCounts(peopleCount: 24, updatesCount: 43, allCount: 67)
            )
            UpdatesBundleRowView(
                bundle: bundle,
                isExpanded: false,
                canArchive: true,
                onToggleExpanded: {},
                onArchiveBundle: {},
                onMoveSenderToPeople: {}
            ) {
                EmptyView()
            }
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.xs)
            Spacer()
        }
        .frame(width: 480, height: 140)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 480, height: 140)),
            named: "people-updates-bundle-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("Expanded Updates bundle renders flat selectable child rows", arguments: ["light", "dark"])
    func peopleUpdatesExpandedBundle(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let source = MailSourceID(accountID: "acct", mailboxID: "box")
        let now = Date(timeIntervalSince1970: 1_794_500_000)
        let h1 = MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Linear", email: "notifications@linear.app"),
            subject: "BREV-42 assigned to you",
            snippet: "Assigned in Q4 sprint",
            date: now.addingTimeInterval(-600),
            isRead: false
        )
        let h2 = MessageHeader(
            id: "m2",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Linear", email: "notifications@linear.app"),
            subject: "Re: BREV-42 assigned to you",
            snippet: "Maya commented on your issue",
            date: now.addingTimeInterval(-3600),
            isRead: true
        )
        let bundle = UpdatesSenderBundle(
            id: "notifications@linear.app",
            senderName: "Linear",
            senderEmail: "notifications@linear.app",
            sourceID: source,
            headers: [h1, h2]
        )

        let view = VStack(alignment: .leading, spacing: 0) {
            UpdatesBundleRowView(
                bundle: bundle,
                isExpanded: true,
                canArchive: true,
                onToggleExpanded: {},
                onArchiveBundle: {},
                onMoveSenderToPeople: {}
            ) {
                ForEach(bundle.headers) { header in
                    MessageListRow(
                        header: header,
                        threadCount: 1,
                        isSelected: header.id == h1.id,
                        isChecked: false,
                        isInSelectionMode: false,
                        isPinned: false,
                        isThreadExpanded: false,
                        showAvatar: true,
                        previewLineCount: 1,
                        fontFamily: .system,
                        textSize: .medium,
                        density: .comfortable,
                        showsAbsoluteArrivalTime: true,
                        sourceContext: nil,
                        isBlockedSender: false,
                        hasFollowUp: false,
                        onActivate: {},
                        onToggleCheck: {},
                        onToggleThread: {}
                    )
                }
            }
            .padding(.horizontal, BrevSpacing.md)
            .padding(.vertical, BrevSpacing.xs)
            Spacer()
        }
        .frame(width: 480, height: 260)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 480, height: 260)),
            named: "people-updates-expanded-bundle-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("Subscriptions list shows sender count, last received, Unsubscribe, and Archive all", arguments: ["light", "dark"])
    func subscriptionsView(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let source = MailSourceID(accountID: "acct", mailboxID: "box")
        let now = Date(timeIntervalSince1970: 1_794_500_000)
        let header1 = MessageHeader(
            id: "n1",
            threadID: "n1",
            folderID: "inbox",
            from: Correspondent(name: "The Coastal Post", email: "editors@coastal-post.example"),
            subject: "Weekend edition",
            snippet: "Stories from the north",
            date: now.addingTimeInterval(-3600),
            isRead: false
        )
        let header2 = MessageHeader(
            id: "n2",
            threadID: "n2",
            folderID: "inbox",
            from: Correspondent(name: "Northwind Digest", email: "news@northwind.example"),
            subject: "Weekly market brief",
            snippet: "Wind capacity report",
            date: now.addingTimeInterval(-86400 * 3),
            isRead: true
        )
        let options = ListUnsubscribeOptions.parse(
            listUnsubscribe: "<https://coastal-post.example/unsubscribe>",
            listUnsubscribePost: "List-Unsubscribe=One-Click"
        )
        let groups = [
            SubscriptionSenderGroup(
                id: "g1",
                sourceID: source,
                senderName: "The Coastal Post",
                senderEmail: "editors@coastal-post.example",
                headers: [header1, header1],
                lastReceived: header1.date,
                unsubscribeOptions: options
            ),
            SubscriptionSenderGroup(
                id: "g2",
                sourceID: source,
                senderName: "Northwind Digest",
                senderEmail: "news@northwind.example",
                headers: [header2],
                lastReceived: header2.date,
                unsubscribeOptions: options
            ),
        ]

        let view = SubscriptionsView(
            refreshKey: 0,
            load: { groups },
            canArchive: { _ in true },
            onArchiveAll: { _ in true },
            onConfirmedUnsubscribe: { _, _ in },
            onSelectMessage: { _, _ in },
            preloaded: groups
        )
        .frame(width: 560, height: 260)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 560, height: 260)),
            named: "subscriptions-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
