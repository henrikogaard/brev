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

@Suite("MailRootReadingPanePresentationPolicy")
struct MailRootReadingPanePresentationPolicyTests {
    @Test("side preference keeps the reading pane in the split detail column")
    func sidePreferenceKeepsSplitDetailColumn() {
        #expect(MailRootReadingPanePresentationPolicy.presentation(
            for: MailboxReadingPanePlacement.side.rawValue
        ) == .splitDetailColumn)
    }

    @Test("bottom preference moves the reading pane below the message list")
    func bottomPreferenceUsesBottomStack() {
        #expect(MailRootReadingPanePresentationPolicy.presentation(
            for: MailboxReadingPanePlacement.bottom.rawValue
        ) == .bottomStack)
    }

    @Test("invalid stored values fall back to the side reading pane")
    func invalidPreferenceFallsBackToSide() {
        #expect(MailRootReadingPanePresentationPolicy.presentation(
            for: "overlay"
        ) == .splitDetailColumn)
    }

    @Test("compact folder selection advances to the list for side reading panes")
    func compactFolderSelectionAdvancesToListForSideReadingPanes() {
        #expect(MailRootReadingPanePresentationPolicy.compactColumnAfterSelectingFolder(
            presentation: .splitDetailColumn
        ) == .content)
    }

    @Test("the explicit reader presentation is limited to compact width")
    func compactReaderPresentationIsLimitedToCompactWidth() {
        #expect(MailRootReadingPanePresentationPolicy.usesCompactReaderPresentation(
            horizontalSizeClass: .compact
        ))
        #expect(!MailRootReadingPanePresentationPolicy.usesCompactReaderPresentation(
            horizontalSizeClass: .regular
        ))
    }

    @Test("message selection preserves regular width split columns")
    func messageSelectionPreservesRegularWidthSplitColumns() {
        #expect(MailRootReadingPanePresentationPolicy.messageSelectionPresentation(
            horizontalSizeClass: .compact
        ) == .compactOverlay)
        #expect(MailRootReadingPanePresentationPolicy.messageSelectionPresentation(
            horizontalSizeClass: .regular
        ) == .splitInPlace)
    }
}
