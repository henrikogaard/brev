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

/// macOS sign-in code/link floating panel and reader card snapshots (#239, ADR-0088).
/// Uses synthetic placeholder values only; never real sign-in content.
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh the baseline.
@Suite("Sign-in code panel snapshots")
@MainActor
struct SignInCodePanelSnapshotTests {
    @Test("floating code panel renders grouped digits and Copy button", arguments: ["light", "dark"])
    func floatingCodePanel(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let presentation = SignInCodePresentation(
            accountID: "acct-1",
            messageID: "msg-1",
            sender: "Example Cloud",
            content: .code("525488"),
            timeout: 60
        )

        let view = SignInCodePanelView(
            presentation: presentation,
            didCopy: false,
            onCopy: {},
            onOpenLink: { _ in },
            onDismiss: {}
        )
        .padding(16)
        .frame(width: 400, height: 100)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 400, height: 100)),
            named: "signin-code-panel-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("floating link panel shows real destination host and Open button", arguments: ["light", "dark"])
    func floatingLinkPanel(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let presentation = SignInCodePresentation(
            accountID: "acct-1",
            messageID: "msg-2",
            sender: "Example Cloud",
            content: .link(destination: "https://auth.example.test/verify", host: "auth.example.test"),
            timeout: 60
        )

        let view = SignInCodePanelView(
            presentation: presentation,
            didCopy: false,
            onCopy: {},
            onOpenLink: { _ in },
            onDismiss: {}
        )
        .padding(16)
        .frame(width: 480, height: 100)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 480, height: 100)),
            named: "signin-link-panel-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("reader sign-in code card renders fresh and probably-expired states", arguments: ["light", "dark"])
    func readerSignInCodeCard(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 18, minute: 46))!
        let expiredMatch = SignInCodeSurfaceMatch(
            code: "482913",
            sender: "Example Cloud",
            sentAt: now.addingTimeInterval(-15 * 60),
            messageID: "msg-3",
            folderID: "inbox",
            sourceID: nil
        )

        let view = SignInCodeReaderCard(match: expiredMatch, now: now)
            .padding(16)
            .frame(width: 520, height: 132)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
            .environment(\.colorScheme, theme.mode.colorScheme)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 520, height: 132)),
            named: "signin-reader-card-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("Today page renders active sign-in code card alongside digest", arguments: ["light", "dark"])
    func todayPageWithActiveSignInCode(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 9, minute: 30))!
        let source = MailSourceID(accountID: "acct", mailboxID: "box")
        let activeCode = SignInCodeSurfaceMatch(
            code: "482913",
            sender: "Example Cloud",
            sentAt: now.addingTimeInterval(-90),
            messageID: "msg-code",
            folderID: "inbox",
            sourceID: source
        )
        let maya = Correspondent(name: "Maya Okafor", email: "maya@northwind.example")
        let lena = Correspondent(name: "Lena Fischer", email: "lena@example.com")
        var digest = TodayDigest()
        digest.waitingOnYou = [
            TodayDigest.Row(
                sourceID: source,
                header: MessageHeader(
                    id: "1",
                    threadID: "1",
                    folderID: "inbox",
                    from: maya,
                    subject: "Q4 roadmap: final review before Thursday",
                    snippet: "",
                    date: now.addingTimeInterval(-3600),
                    isRead: false
                ),
                person: maya
            ),
        ]
        digest.waitingOnYouCount = 1
        digest.youreWaitingOn = [
            TodayDigest.Row(
                sourceID: source,
                header: MessageHeader(
                    id: "2",
                    threadID: "2",
                    folderID: "inbox",
                    from: lena,
                    subject: "Re: Contract draft",
                    snippet: "",
                    date: now.addingTimeInterval(-30 * 3600),
                    isRead: true
                ),
                person: lena
            ),
        ]
        digest.youreWaitingOnCount = 1
        digest.unreadUpdatesCount = 12
        let view = TodayPageView(
            displayName: "Alex Chen",
            refreshKey: 0,
            load: { digest },
            onOpen: { _ in },
            onAsk: nil,
            activeSignInCode: activeCode,
            now: now,
            preloaded: digest
        )
        .frame(width: 640, height: 520)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 640, height: 520)),
            named: "today-active-signin-code-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("Message list row renders sign-in code chip for opted-in accounts", arguments: ["light", "dark"])
    func messageListRowWithSignInCodeChip(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 9, minute: 30))!
        let header = MessageHeader(
            id: "msg-code-row",
            threadID: "msg-code-row",
            folderID: "inbox",
            from: Correspondent(name: "Example Cloud", email: "noreply@example.test"),
            subject: "Your sign-in code is 482913",
            snippet: "Enter 482913 to finish signing in.",
            date: now.addingTimeInterval(-60),
            isRead: false
        )
        let view = MessageListRow(
            header: header,
            threadCount: 1,
            isSelected: false,
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
            signInCode: "482913",
            isBlockedSender: false,
            hasFollowUp: false,
            referenceDate: now,
            onActivate: {},
            onToggleCheck: {},
            onToggleThread: {}
        )
        .frame(width: 360)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 360, height: 104)),
            named: "message-list-row-signin-chip-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
