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

import BrevDesign
@testable import BrevMail
import Testing

@Suite("MailPaneSurfacePolicy")
struct MailPaneSurfacePolicyTests {
    @Test("split view panes use full-height themed backgrounds")
    func splitViewPanesUseFullHeightThemedBackgrounds() {
        #expect(MailPaneSurfacePolicy.sidebar.role == .sidebar)
        #expect(MailPaneSurfacePolicy.sidebar.fillsPane)
        #expect(MailPaneSurfacePolicy.sidebar.ignoresTitlebarSafeArea)
        #expect(MailPaneSurfacePolicy.sidebar.navigationTitleStyle == .inline)
        #expect(MailPaneSurfacePolicy.sidebar.navigationBarBackgroundRole == .sidebar)
        #expect(MailPaneSurfacePolicy.content.role == .content)
        #expect(MailPaneSurfacePolicy.content.fillsPane)
        #expect(MailPaneSurfacePolicy.content.ignoresTitlebarSafeArea)
        #expect(MailPaneSurfacePolicy.content.navigationTitleStyle == .inline)
        #expect(MailPaneSurfacePolicy.content.navigationBarBackgroundRole == .content)
    }

    @Test("iPad message list column has readable split width")
    func iPadMessageListColumnHasReadableSplitWidth() throws {
        let width = try #require(MailPaneColumnWidthPolicy.messageList(platform: .iPad))

        #expect(width.minimum >= 320)
        #expect(width.ideal >= 380)
        #expect(width.maximum >= width.ideal)
    }

    @Test("phone message list column leaves compact split automatic")
    func phoneMessageListColumnLeavesCompactSplitAutomatic() {
        #expect(MailPaneColumnWidthPolicy.messageList(platform: .iPhone) == nil)
    }

    @Test("macOS message list gives mail identity a readable preferred width")
    func macOSMessageListColumnLeavesDesktopSplitAutomatic() throws {
        let width = try #require(MailPaneColumnWidthPolicy.messageList(platform: .macOS))
        #expect(width.minimum == 320)
        #expect(width.ideal == 420)
        #expect(width.maximum >= width.ideal)
    }

    @Test("macOS folder sidebar declares split-view column bounds")
    func macOSFolderSidebarDeclaresSplitViewColumnBounds() throws {
        let width = try #require(MailPaneColumnWidthPolicy.folderSidebar(platform: .macOS))

        // The bounds have to reach the split view itself rather than the
        // hosted content: a content-only frame leaves AppKit resolving the
        // column against the hosting view every drag step, which lags the
        // sidebar's layout behind the divider.
        #expect(width.minimum == 200)
        #expect(width.ideal == 240)
        #expect(width.maximum > width.ideal)
    }

    @Test("iPad folder sidebar keeps the same bounds as macOS")
    func iPadFolderSidebarKeepsTheSameBoundsAsMacOS() throws {
        let mac = try #require(MailPaneColumnWidthPolicy.folderSidebar(platform: .macOS))
        let pad = try #require(MailPaneColumnWidthPolicy.folderSidebar(platform: .iPad))

        #expect(pad == mac)
    }

    @Test("phone folder sidebar leaves compact split automatic")
    func phoneFolderSidebarLeavesCompactSplitAutomatic() {
        #expect(MailPaneColumnWidthPolicy.folderSidebar(platform: .iPhone) == nil)
    }

    @Test("macOS reader keeps a floor wide enough for its toolbar cluster")
    func macOSReaderKeepsFloorWideEnoughForItsToolbarCluster() throws {
        let minimum = try #require(MailPaneColumnWidthPolicy.readerMinimumWidth(platform: .macOS))

        #expect(minimum == 420)
        // The window's own minimum is the sum across columns, so the floor has
        // to leave the 960pt default width resizable.
        #expect(minimum < 480)
    }

    @Test("touch platforms leave the reader floor to the split view")
    func touchPlatformsLeaveReaderFloorToSplitView() {
        #expect(MailPaneColumnWidthPolicy.readerMinimumWidth(platform: .iPad) == nil)
        #expect(MailPaneColumnWidthPolicy.readerMinimumWidth(platform: .iPhone) == nil)
    }

    @Test("desktop reader uses a bounded canvas with density-aware gutters")
    func desktopReaderUsesBoundedDensityAwareCanvas() {
        let compact = MessageReaderLayoutPolicy.layout(
            platform: .macOS,
            density: .compact
        )
        let spacious = MessageReaderLayoutPolicy.layout(
            platform: .macOS,
            density: .spacious
        )

        #expect(compact.maximumContentWidth == 760)
        #expect(!compact.usesCardSurface)
        #expect(compact.outerHorizontalPadding == 12)
        #expect(spacious.outerHorizontalPadding == 24)
        #expect(spacious.contentPadding > compact.contentPadding)
    }

    @Test("phone reader stays edge efficient")
    func phoneReaderStaysEdgeEfficient() {
        let layout = MessageReaderLayoutPolicy.layout(
            platform: .iPhone,
            density: .spacious
        )

        #expect(layout.maximumContentWidth == nil)
        #expect(!layout.usesCardSurface)
        #expect(layout.outerHorizontalPadding == 0)
        #expect(layout.contentPadding == 16)
    }
}
