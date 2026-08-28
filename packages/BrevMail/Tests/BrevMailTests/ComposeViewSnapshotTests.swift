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
import BrevPlugins
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@MainActor
private final class ComposeToolbarMarkerPlugin: BrevUIExtension {
    let identifier = "com.brev.tests.compose-toolbar-marker"
    let displayName = "Compose toolbar marker"
    let author = "Brev tests"
    var isEnabled = true

    let contributions = [
        ContributionDefinition(
            id: "compose-toolbar-marker",
            kind: .composeToolbar,
            displayName: "Compose toolbar marker",
            sfSymbolName: "circle"
        )
    ]

    func view(for contributionID: String) -> AnyView {
        isEnabled ? AnyView(ComposeToolbarMarkerView()) : AnyView(EmptyView())
    }
}

private struct ComposeToolbarMarkerView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.accessibilityIdentifier = "brev-compose-toolbar-marker"
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Snapshot coverage for `ComposeView` — the message editor. Locks in
/// the empty compose state and the reply-prefilled state in the default
/// theme so regressions in the compose layout, header fields, and
/// toolbar are caught.
@Suite("ComposeView snapshots", .serialized)
@MainActor
struct ComposeViewSnapshotTests {
    @Test("Empty compose renders with header fields and toolbar in default theme")
    func emptyCompose() {
        let theme = BrevTheme.brevPaper
        let backend = MockBackend()
        #expect(backend.account.emailAddress == "henrik@ogard.example")
        let view = ComposeView(
            backend: backend,
            from: backend.account
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
        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: "empty-compose"
        )
    }

    @Test("Reply compose renders with prefilled subject and recipients in default theme")
    func replyCompose() {
        let theme = BrevTheme.brevPaper
        let backend = MockBackend()
        let header = MessageHeader(
            id: "m1",
            threadID: "thread-standup",
            folderID: "inbox",
            from: Correspondent(name: "Ingrid Halvorsen", email: "ingrid.halvorsen@acme.example"),
            to: [Correspondent(email: "henrik@ogard.example")],
            subject: "Stavanger rollout notes",
            snippet: "Quick recap from yesterday.",
            date: Date(timeIntervalSince1970: 1_779_960_600),
            isRead: true,
            isFlagged: false
        )
        #expect(header.subject == "Stavanger rollout notes")
        #expect(ComposeReplyResolver
            .recipients(for: header, mode: .sender, accountEmail: backend.account.emailAddress) ==
            ["ingrid.halvorsen@acme.example"])
        let view = ComposeView(
            backend: backend,
            from: backend.account,
            replyingTo: header
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
        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: "reply-compose"
        )
    }

    @Test("default compose toolbar renders each plugin contribution once")
    func defaultToolbarRendersPluginContributionOnce() {
        let plugin = ComposeToolbarMarkerPlugin()
        BrevPluginRegistry.shared.register(plugin)
        // The production registry intentionally has no unregister API. Keep
        // this suite serialized and disable the retained test plugin before
        // the next test so it contributes no marker outside this assertion.
        defer { plugin.isEnabled = false }

        let theme = BrevTheme.brevPaper
        let backend = MockBackend()
        let view = ComposeView(
            backend: backend,
            from: backend.account
        )
        .frame(width: 960, height: 780)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)

        let host = UIHostingController(rootView: view)
        host.loadViewIfNeeded()
        host.view.frame = CGRect(x: 0, y: 0, width: 960, height: 780)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        #expect(countMarkerViews(in: host.view) == 1)
    }

    private func countMarkerViews(in view: UIView) -> Int {
        let ownCount = view.accessibilityIdentifier == "brev-compose-toolbar-marker" ? 1 : 0
        return ownCount + view.subviews.reduce(0) { count, subview in
            count + countMarkerViews(in: subview)
        }
    }
}
#endif
