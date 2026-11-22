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
        let activeCode = SignInCodeSurfaceMatch(
            code: "482913",
            sender: "Example Cloud",
            sentAt: now.addingTimeInterval(-90),
            messageID: "msg-code",
            folderID: "inbox",
            sourceID: nil
        )
        var digest = TodayDigest()
        digest.waitingOnYouCount = 1
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
        .frame(width: 560, height: 340)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 560, height: 340)),
            named: "today-active-signin-code-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
