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
import BrevDesign
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

/// macOS attachment cards (#306 slice 4, part 2): icon, name, "kind · size",
/// primary action and ••• menu, in the reader's adaptive grid. One card is
/// hovered and one is downloading. Set `RECORD_SNAPSHOTS=YES` to record.
@Suite("Message attachment card snapshots")
@MainActor
struct MessageAttachmentCardSnapshotTests {
    @Test("attachment cards across light and dark themes", arguments: [
        "brevMonoLight", "brevMonoDark", "solarizedLight", "solarizedDark", "gruvboxLight", "gruvboxDark",
    ])
    func cards(_ themeName: String) throws {
        let theme = try #require(Self.theme(named: themeName))
        let actions = MessageAttachmentActionPresentation.actions(
            resourceAvailable: true, isDownloading: false, isWorkBlocked: false
        )
        let files: [(String, String, String, Bool, Bool)] = [
            ("Q4 roadmap final review.pdf", "doc.richtext", "PDF · 240 KB", false, false),
            ("Team photo.jpeg", "photo", "JPEG · 2.1 MB", true, false),
            ("Budget.xlsx", "tablecells", "XLSX · 88 KB", false, true),
        ]
        let view = LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: BrevSpacing.sm)],
            alignment: .leading,
            spacing: BrevSpacing.sm
        ) {
            ForEach(files, id: \.0) { file in
                MessageAttachmentCard(
                    name: file.0, systemImage: file.1, subtitle: file.2,
                    isHovered: file.3, isDownloading: file.4,
                    primaryAction: MessageAttachmentActionPresentation.primaryAction(in: actions),
                    overflowActions: MessageAttachmentActionPresentation.overflowActions(in: actions),
                    onAction: { _ in }
                )
            }
        }
        .padding(BrevSpacing.md)
        .frame(width: 720, height: 150, alignment: .topLeading)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: theme.mode.colorScheme == .dark ? .darkAqua : .aqua)
        host.view.frame = CGRect(x: 0, y: 0, width: 720, height: 150)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 720, height: 150)), named: themeName,
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

    private static func theme(named name: String) -> BrevTheme? {
        switch name {
        case "brevMonoLight": .brevMonoLight
        case "brevMonoDark": .brevMonoDark
        case "solarizedLight": .solarizedLight
        case "solarizedDark": .solarizedDark
        case "gruvboxLight": .gruvboxLight
        case "gruvboxDark": .gruvboxDark
        default: nil
        }
    }
}
#endif
