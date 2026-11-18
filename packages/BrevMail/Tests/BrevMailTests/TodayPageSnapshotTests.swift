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

/// The Today page in the empty reader (#292).
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh the baseline.
@Suite("Today page snapshots")
@MainActor
struct TodayPageSnapshotTests {
    @Test("Today shows the greeting, the summary and both lists", arguments: ["light", "dark"])
    func todayPage(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 20, minute: 30))!
        let source = MailSourceID(accountID: "acct", mailboxID: "box")
        func row(_ id: String, _ name: String, _ email: String, _ subject: String, hoursAgo: Double,
                 isRead: Bool = false) -> TodayDigest.Row {
            let person = Correspondent(name: name, email: email)
            return TodayDigest.Row(
                sourceID: source,
                header: MessageHeader(id: id, threadID: id, folderID: "inbox", from: person,
                                      subject: subject, snippet: "",
                                      date: now.addingTimeInterval(-hoursAgo * 3600), isRead: isRead),
                person: person
            )
        }
        var digest = TodayDigest()
        digest.waitingOnYou = [
            row("1", "Maya Okafor", "maya@northwind.example", "Q4 roadmap: final review before Thursday", hoursAgo: 1),
            row("2", "Daniel Reyes", "daniel@example.com", "Onboarding copy", hoursAgo: 3),
            row("3", "Priya Natarajan", "priya@example.com", "Dinner on Saturday?", hoursAgo: 72, isRead: true),
        ]
        digest.waitingOnYouCount = 25
        digest.youreWaitingOn = [
            row("4", "Lena Fischer", "lena@example.com", "Re: Contract draft", hoursAgo: 30, isRead: true),
        ]
        digest.youreWaitingOnCount = 4
        digest.unreadUpdatesCount = 43
        let view = TodayPageView(
            displayName: "Alex Chen",
            refreshKey: 0,
            load: { digest },
            onOpen: { _ in },
            onAsk: {},
            now: now,
            preloaded: digest
        )
        .frame(width: 720, height: 640)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 720, height: 640)), named: "today-" + mode,
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

    @Test("summary sentence reads naturally for empty and busy days")
    func summary() {
        var digest = TodayDigest()
        #expect(TodayPageView.summary(digest) == "Nothing from people needs you.")
        digest.waitingOnYouCount = 1
        digest.unreadUpdatesCount = 43
        #expect(TodayPageView.summary(digest)
            == "1 conversation from people needs you. 43 updates are unread.")
    }
}
#endif
