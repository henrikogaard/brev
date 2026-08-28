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

/// Snapshot coverage for `MessageDetailView` — the reading pane that
/// shows a selected message's subject, sender, recipients, and body.
/// Locks in the no-selection placeholder and the header-present
/// (subject + sender visible, body loading) states in the default
/// theme so regressions in the reading pane layout are caught.
@Suite("MessageDetailView snapshots")
@MainActor
struct MessageDetailViewSnapshotTests {
    @Test("No-selection placeholder renders in default theme")
    func noSelectionPlaceholder() {
        let theme = BrevTheme.brevPaper
        let view = MessageDetailView(
            backend: MockBackend(),
            header: nil
        )
        .frame(width: 390, height: 844)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .htmlBodyRenderTarget(.staticSnapshot)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        #expect(MockBackend.previewMessages["inbox"]?.isEmpty == false)
        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: "no-selection"
        )
    }

    @Test("Header-present state renders subject and sender in default theme")
    func headerPresentRendersSubjectAndSender() {
        let theme = BrevTheme.brevPaper
        let header = MessageHeader(
            id: "m1",
            threadID: "thread-standup",
            folderID: "inbox",
            from: Correspondent(name: "Ingrid Halvorsen", email: "ingrid.halvorsen@acme.example"),
            to: [Correspondent(email: "henrik@ogard.example")],
            subject: "Stavanger rollout notes",
            snippet: "Quick recap from yesterday — three open threads, all triaged.",
            date: Date(timeIntervalSince1970: 1_779_960_600),
            isRead: true,
            isFlagged: false,
            hasAttachments: true
        )
        let view = MessageDetailView(
            backend: MockBackend(),
            header: header
        )
        .frame(width: 390, height: 844)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .htmlBodyRenderTarget(.staticSnapshot)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        #expect(header.subject == "Stavanger rollout notes")
        #expect(header.from.displayName == "Ingrid Halvorsen")
        #expect(header.snippet.contains("Quick recap from yesterday"))
        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: "header-present"
        )
    }

    @Test("Body load error state renders actionable message in default theme")
    func bodyLoadErrorState() {
        let theme = BrevTheme.brevPaper
        let view = MessageDetailStatusView(
            status: MessageDetailPresentation.bodyLoadErrorStatus(
                "Network error: offline"
            )
        ) {}
            .frame(width: 390, height: 200)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: "body-load-error"
        )
    }
}
#endif
