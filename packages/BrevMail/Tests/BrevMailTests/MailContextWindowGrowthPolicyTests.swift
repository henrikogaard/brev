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

@testable import BrevMail
import Testing

@Suite("AI Sidebar window growth")
struct MailContextWindowGrowthPolicyTests {
    @Test("opening the sidebar grows the window by the column")
    func openingTheSidebarGrowsTheWindowByTheColumn() throws {
        // The shipped default: 960pt window, 320pt column. Without growth the
        // reader is left at ~160pt, which is one word per line.
        let width = try #require(MailContextWindowGrowthPolicy.widthOnOpen(
            currentWidth: 960,
            columnWidth: 320,
            maximumWidth: 3440
        ))

        #expect(width == 1280)
    }

    @Test("growth stops at the screen")
    func growthStopsAtTheScreen() throws {
        let width = try #require(MailContextWindowGrowthPolicy.widthOnOpen(
            currentWidth: 1200,
            columnWidth: 320,
            maximumWidth: 1440
        ))

        #expect(width == 1440)
    }

    @Test("a window already filling the screen is left alone")
    func aWindowAlreadyFillingTheScreenIsLeftAlone() {
        #expect(MailContextWindowGrowthPolicy.widthOnOpen(
            currentWidth: 1440,
            columnWidth: 320,
            maximumWidth: 1440
        ) == nil)
    }

    @Test("closing gives back the width the policy took")
    func closingGivesBackTheWidthThePolicyTook() throws {
        let width = try #require(MailContextWindowGrowthPolicy.widthOnClose(
            currentWidth: 1280,
            widthBeforeOpen: 960
        ))

        #expect(width == 960)
    }

    @Test("closing leaves a window the user narrowed by hand")
    func closingLeavesAWindowTheUserNarrowedByHand() {
        // Grew 960 -> 1280, then the user dragged it down to 900. Restoring 960
        // would widen a window they had just made smaller.
        #expect(MailContextWindowGrowthPolicy.widthOnClose(
            currentWidth: 900,
            widthBeforeOpen: 960
        ) == nil)
    }

    @Test("closing a window the policy never grew leaves it be")
    func closingAWindowThePolicyNeverGrewLeavesItBe() {
        #expect(MailContextWindowGrowthPolicy.widthOnClose(
            currentWidth: 1280,
            widthBeforeOpen: nil
        ) == nil)
    }

    @Test("a window that would overhang the screen slides left")
    func aWindowThatWouldOverhangTheScreenSlidesLeft() {
        // Origin 800, growing to 1280 on a 1440-wide screen: the right edge would
        // land at 2080, so the window moves left by the 640pt overhang.
        #expect(MailContextWindowGrowthPolicy.originX(
            currentOriginX: 800,
            newWidth: 1280,
            screenMinX: 0,
            screenMaxX: 1440
        ) == 160)
    }

    @Test("sliding left stops at the screen edge")
    func slidingLeftStopsAtTheScreenEdge() {
        #expect(MailContextWindowGrowthPolicy.originX(
            currentOriginX: 100,
            newWidth: 1600,
            screenMinX: 0,
            screenMaxX: 1440
        ) == 0)
    }

    @Test("a window that already fits does not move")
    func aWindowThatAlreadyFitsDoesNotMove() {
        #expect(MailContextWindowGrowthPolicy.originX(
            currentOriginX: 100,
            newWidth: 1280,
            screenMinX: 0,
            screenMaxX: 1440
        ) == 100)
    }
}

#if os(macOS)
@Suite("AI Sidebar column width")
struct MailContextColumnWidthPolicyTests {
    private let bounds = MailPaneColumnWidth(minimum: 280, ideal: 320, maximum: 420)

    @Test("a stored width inside the bounds is used as-is")
    func aStoredWidthInsideTheBoundsIsUsedAsIs() {
        #expect(MailContextColumnWidthPolicy.width(preferred: 360, bounds: bounds) == 360)
    }

    @Test("the column cannot be dragged past its bounds")
    func theColumnCannotBeDraggedPastItsBounds() {
        #expect(MailContextColumnWidthPolicy.width(preferred: 120, bounds: bounds) == 280)
        #expect(MailContextColumnWidthPolicy.width(preferred: 900, bounds: bounds) == 420)
    }

    @Test("dragging the leading edge left widens the column")
    func draggingTheLeadingEdgeLeftWidensTheColumn() {
        // The handle is on the column's leading edge, so a negative translation
        // (pointer moving left) has to make the column bigger, not smaller.
        #expect(MailContextColumnWidthPolicy.width(
            dragStartWidth: 320,
            translation: -60,
            bounds: bounds
        ) == 380)
    }

    @Test("dragging the leading edge right narrows the column")
    func draggingTheLeadingEdgeRightNarrowsTheColumn() {
        #expect(MailContextColumnWidthPolicy.width(
            dragStartWidth: 320,
            translation: 30,
            bounds: bounds
        ) == 290)
    }
}
#endif
