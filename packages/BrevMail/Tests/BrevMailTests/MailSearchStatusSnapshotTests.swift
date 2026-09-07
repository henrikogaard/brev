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
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

@Suite("Mail search status snapshots")
@MainActor
struct MailSearchStatusSnapshotTests {
    @Test("search progress and coverage stay compact in both themes", arguments: [false, true])
    func states(dark: Bool) {
        let theme = dark ? BrevTheme.brevMonoDark : .brevMonoLight
        let source = MailSourceID(accountID: "one", mailboxID: "one")
        var searching = MailSearchProgressState()
        let searchingID = searching.begin(sources: [source])
        searching.apply(MailSearchUpdate(headers: [], coverage: .cached), source: source, request: searchingID)
        var cached = MailSearchProgressState()
        let cachedID = cached.begin(sources: [source])
        cached.apply(MailSearchUpdate(headers: [], coverage: .cached, isComplete: true), source: source, request: cachedID)
        var failed = MailSearchProgressState()
        let failedID = failed.begin(sources: [source])
        failed.fail(source: source, request: failedID)
        var complete = MailSearchProgressState()
        let completeID = complete.begin(sources: [source])
        complete.apply(MailSearchUpdate(headers: [], coverage: .server, isComplete: true), source: source, request: completeID)
        var mixed = MailSearchProgressState()
        let mixedID = mixed.begin(sources: [source, MailSourceID(accountID: "two", mailboxID: "two")])
        mixed.fail(source: source, request: mixedID)
        let view = VStack(spacing: 16) {
            MailSearchStatusView(progress: searching, checksAttachments: true, retry: {})
            MailSearchStatusView(progress: cached, checksAttachments: false, retry: {})
            MailSearchStatusView(progress: failed, checksAttachments: false, retry: {})
            MailSearchStatusView(progress: complete, checksAttachments: false, retry: {})
            MailSearchStatusView(progress: mixed, checksAttachments: true, retry: {})
        }
        .padding(12).frame(width: 360, height: 440)
        .background(theme.bgPrimary.color).brevTheme(theme)
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.locale, Locale(identifier: "en_US"))
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.view.frame = CGRect(x: 0, y: 0, width: 360, height: 440)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 360, height: 440)), named: dark ? "search-dark" : "search-light",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }
}
#endif
