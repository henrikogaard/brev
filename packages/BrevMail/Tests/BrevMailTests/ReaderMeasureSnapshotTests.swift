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
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

@Suite("Reader measure snapshots")
@MainActor
struct ReaderMeasureSnapshotTests {
    @Test("plain reading column stays leading aligned at narrow and wide widths", arguments: [0, 1, 2, 3])
    func readingColumn(variant: Int) {
        let width: CGFloat = variant == 0 ? 320 : 1200
        let dark = variant == 2
        let theme = dark ? BrevTheme.brevMonoDark : .brevMonoLight
        let style = MessageBodyStyle.resolve(theme: theme, fontFamily: .system, textSize: .medium,
                                             renderingMode: .original, bodyInsetPoints: 0, bodyScale: variant == 3 ? 2 : 1)
        let text = String(repeating: "A clear reading column keeps each line comfortable without changing the sender's words. ", count: 10)
        let view = ScrollView {
            Text(text).font(style.swiftUIBodyFont).foregroundStyle(theme.textPrimary.color)
                .modifier(MessageReadingColumn(style: style)).padding(24)
        }
        .frame(width: width, height: 480)
        .background(theme.bgPrimary.color).brevTheme(theme)
        .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingController(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: width, height: 480)), named: "readable-\(variant)",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }
}
#endif
