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

@Suite("Cross-account search options snapshots")
@MainActor
struct CrossAccountSearchOptionsSnapshotTests {
    @Test("cross-account All mailboxes scope bar and chips render cleanly in light and dark mode",
          arguments: [false, true])
    func crossAccountOptionsBar(dark: Bool) {
        let theme = dark ? BrevTheme.brevMonoDark : .brevMonoLight
        let chips = UnifiedInboxSearchChipsCache().chips(
            text: "invoice from Maya pdf in Sent",
            isSavedSearch: false,
            searchAllFolders: true,
            inboxFolderID: nil,
            execution: .cacheThenServer
        )
        let view = VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            MailSearchOptionsBar(
                execution: .constant(.cacheThenServer),
                availableExecutions: [.cacheOnly, .cacheThenServer, .serverOnly],
                folderScope: .constant(true),
                fieldScope: .constant(.from)
            )
            ScrollView(.horizontal) {
                HStack(spacing: BrevSpacing.xs) {
                    NaturalLanguageSearchChipStrip(chips: chips, onRemove: { _ in })
                }
            }
            .frame(height: 28)
            .scrollIndicators(.hidden)
            .padding(.horizontal, BrevSpacing.md)
        }
        .frame(width: 380, height: 76, alignment: .topLeading)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.view.frame = CGRect(x: 0, y: 0, width: 380, height: 76)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 380, height: 76)),
            named: dark ? "cross-account-options-dark" : "cross-account-options-light",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
