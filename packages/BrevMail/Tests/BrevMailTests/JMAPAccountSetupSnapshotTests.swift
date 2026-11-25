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
import BrevBackend
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

@Suite("JMAP account setup snapshots")
@MainActor
struct JMAPAccountSetupSnapshotTests {
    @Test("JMAP account setup renders Fastmail preset in light and dark themes", arguments: [
        ("jmap-setup-light", BrevTheme.brevMonoLight),
        ("jmap-setup-dark", BrevTheme.brevMonoDark)
    ])
    func jmapAccountSetupRenders(name: String, theme: BrevTheme) {
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: JMAPSnapshotTokenStore(),
            jmapAccountSetupCoordinator: { _ in
                fatalError("not called by the snapshot")
            }
        )
        let view = JMAPAccountSetupView(
            session: session,
            initialPreset: .fastmail,
            onClose: {}
        )
        .frame(width: 560, height: 640)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode == .dark ? .dark : .light)

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: theme.mode == .dark ? .darkAqua : .aqua)
        host.view.frame = CGRect(x: 0, y: 0, width: 560, height: 640)

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 560, height: 640)),
            named: name,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}

private actor JMAPSnapshotTokenStore: TokenStore {
    func token(for _: String) async -> Token? { nil }
    func setToken(_: Token, for _: String) async throws {}
    func clearToken(for _: String) async {}
}
#endif
