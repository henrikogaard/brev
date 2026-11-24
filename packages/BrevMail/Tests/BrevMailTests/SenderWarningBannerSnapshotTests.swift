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

/// macOS snapshot coverage for `SenderWarningBanner` in collapsed and expanded
/// disclosure states (#301).
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh baselines on macOS 26+.
@Suite("Sender warning banner snapshots")
@MainActor
struct SenderWarningBannerSnapshotTests {
    @Test("look-alike sender warning renders collapsed and expanded details", arguments: ["light", "dark"])
    func lookAlikeWarningStates(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let header = MessageHeader(
            id: "msg-spoof",
            threadID: "msg-spoof",
            folderID: "inbox",
            from: Correspondent(name: "PayPal Support", email: "alerts@paypa1.com"),
            subject: "Action required on your account",
            snippet: "Please confirm your details.",
            date: Date(timeIntervalSince1970: 1_760_000_000),
            isRead: false
        )
        #expect(MessageHeaderAnalyzer.warning(
            for: header,
            authenticationResults: nil,
            writtenAddresses: [],
            knownDomains: ["paypal.com"]
        ) == .lookAlikeDomain("paypal.com"))
        let view = VStack(alignment: .leading, spacing: 14) {
            SenderWarningBanner(header: header, authenticationResults: nil, initiallyExpanded: false)
            SenderWarningBanner(header: header, authenticationResults: nil, initiallyExpanded: true)
        }
        .padding(16)
        .frame(width: 560, height: 300, alignment: .topLeading)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.senderWarningHistory, SenderWarningHistory(written: [], knownDomains: ["paypal.com"]))
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 560, height: 300)),
            named: "sender-warning-lookalike-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    @Test("DMARC failure warning renders expanded explanation", arguments: ["light", "dark"])
    func dmarcFailureExpanded(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let header = MessageHeader(
            id: "msg-dmarc",
            threadID: "msg-dmarc",
            folderID: "inbox",
            from: Correspondent(name: "Billing Team", email: "billing@northwind.example"),
            subject: "Updated wire instructions",
            snippet: "Use the new account.",
            date: Date(timeIntervalSince1970: 1_760_000_000),
            isRead: false
        )
        let view = SenderWarningBanner(
            header: header,
            authenticationResults: "mx.example.org; dmarc=fail header.from=northwind.example",
            initiallyExpanded: true
        )
        .padding(16)
        .frame(width: 560, height: 150, alignment: .topLeading)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.senderWarningHistory, SenderWarningHistory(written: [], knownDomains: []))
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 560, height: 150)),
            named: "sender-warning-dmarc-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
