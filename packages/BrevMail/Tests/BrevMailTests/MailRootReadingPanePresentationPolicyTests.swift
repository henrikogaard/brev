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

import BrevBackend
import BrevDesign
@testable import BrevMail
import Foundation
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

    @Test("unfolding from compact reader clears compactReaderHeader and keeps selection intact")
    func unfoldingFromCompactReaderClearsCompactHeaderAndPreservesSelection() {
        let header = Self.sampleHeader(id: "msg-1")

        let alreadySelected = MailRootSizeClassTransitionPolicy.transition(
            from: .compact,
            to: .regular,
            compactReaderHeader: header,
            selectedHeader: header,
            selectedMessageID: header.id,
            hasSelectedMessageDestination: true,
            readingPanePresentation: .splitDetailColumn
        )
        #expect(alreadySelected == MailRootSizeClassTransitionOutcome(
            selectedMessageIDToPreserve: nil,
            compactReaderHeader: nil,
            preferredCompactColumn: nil,
            splitViewVisibility: nil
        ))

        let selectionCleared = MailRootSizeClassTransitionPolicy.transition(
            from: .compact,
            to: .regular,
            compactReaderHeader: header,
            selectedHeader: nil,
            selectedMessageID: nil,
            hasSelectedMessageDestination: true,
            readingPanePresentation: .splitDetailColumn
        )
        #expect(selectionCleared == MailRootSizeClassTransitionOutcome(
            selectedMessageIDToPreserve: "msg-1",
            compactReaderHeader: nil,
            preferredCompactColumn: nil,
            splitViewVisibility: nil
        ))

        let restoredHeader = Self.sampleHeader(id: "msg-restored")
        let undoRestored = MailRootSizeClassTransitionPolicy.transition(
            from: .compact,
            to: .regular,
            compactReaderHeader: header,
            selectedHeader: restoredHeader,
            selectedMessageID: restoredHeader.id,
            hasSelectedMessageDestination: true,
            readingPanePresentation: .splitDetailColumn
        )
        #expect(undoRestored == MailRootSizeClassTransitionOutcome(
            selectedMessageIDToPreserve: nil,
            compactReaderHeader: nil,
            preferredCompactColumn: nil,
            splitViewVisibility: nil
        ))

        let restoredFromDetailOnly = MailRootSizeClassTransitionPolicy.transition(
            from: .compact,
            to: .regular,
            compactReaderHeader: nil,
            selectedHeader: header,
            selectedMessageID: header.id,
            hasSelectedMessageDestination: true,
            readingPanePresentation: .splitDetailColumn,
            currentSplitViewVisibility: .detailOnly
        )
        #expect(restoredFromDetailOnly == MailRootSizeClassTransitionOutcome(
            selectedMessageIDToPreserve: nil,
            compactReaderHeader: nil,
            preferredCompactColumn: nil,
            splitViewVisibility: .doubleColumn
        ))

        let nothingOpen = MailRootSizeClassTransitionPolicy.transition(
            from: .compact,
            to: .regular,
            compactReaderHeader: nil,
            selectedHeader: header,
            selectedMessageID: header.id,
            hasSelectedMessageDestination: true,
            readingPanePresentation: .splitDetailColumn
        )
        #expect(nothingOpen == nil)
    }

    @Test("folding from regular split preserves an actively read message in the compact reader")
    func foldingFromRegularSplitPreservesActiveMessage() {
        let header = Self.sampleHeader(id: "msg-2")

        let outcome = MailRootSizeClassTransitionPolicy.transition(
            from: .regular,
            to: .compact,
            compactReaderHeader: nil,
            selectedHeader: header,
            selectedMessageID: header.id,
            hasSelectedMessageDestination: true,
            readingPanePresentation: .splitDetailColumn
        )
        #expect(outcome == MailRootSizeClassTransitionOutcome(
            selectedMessageIDToPreserve: nil,
            compactReaderHeader: header,
            preferredCompactColumn: .detail,
            splitViewVisibility: nil
        ))

        let bottomStackOutcome = MailRootSizeClassTransitionPolicy.transition(
            from: .regular,
            to: .compact,
            compactReaderHeader: nil,
            selectedHeader: header,
            selectedMessageID: header.id,
            hasSelectedMessageDestination: true,
            readingPanePresentation: .bottomStack
        )
        #expect(bottomStackOutcome == MailRootSizeClassTransitionOutcome(
            selectedMessageIDToPreserve: nil,
            compactReaderHeader: nil,
            preferredCompactColumn: .detail,
            splitViewVisibility: nil
        ))
    }

    @Test("folding with no selected message lands cleanly on the message list or sidebar")
    func foldingWithNoSelectedMessageLandsOnListOrSidebar() {
        let withMailbox = MailRootSizeClassTransitionPolicy.transition(
            from: .regular,
            to: .compact,
            compactReaderHeader: nil,
            selectedHeader: nil,
            selectedMessageID: nil,
            hasSelectedMessageDestination: true,
            readingPanePresentation: .splitDetailColumn
        )
        #expect(withMailbox == MailRootSizeClassTransitionOutcome(
            selectedMessageIDToPreserve: nil,
            compactReaderHeader: nil,
            preferredCompactColumn: .content,
            splitViewVisibility: nil
        ))

        let withoutMailbox = MailRootSizeClassTransitionPolicy.transition(
            from: .regular,
            to: .compact,
            compactReaderHeader: nil,
            selectedHeader: nil,
            selectedMessageID: nil,
            hasSelectedMessageDestination: false,
            readingPanePresentation: .splitDetailColumn
        )
        #expect(withoutMailbox == MailRootSizeClassTransitionOutcome(
            selectedMessageIDToPreserve: nil,
            compactReaderHeader: nil,
            preferredCompactColumn: .sidebar,
            splitViewVisibility: nil
        ))
    }

    @Test("unchanged or nil size-class updates produce no transition")
    func unchangedOrNilSizeClassIsNoOp() {
        let header = Self.sampleHeader(id: "msg-3")

        #expect(MailRootSizeClassTransitionPolicy.transition(
            from: .compact,
            to: .compact,
            compactReaderHeader: header,
            selectedHeader: header,
            selectedMessageID: header.id,
            hasSelectedMessageDestination: true,
            readingPanePresentation: .splitDetailColumn
        ) == nil)
        #expect(MailRootSizeClassTransitionPolicy.transition(
            from: .regular,
            to: nil,
            compactReaderHeader: nil,
            selectedHeader: header,
            selectedMessageID: header.id,
            hasSelectedMessageDestination: true,
            readingPanePresentation: .splitDetailColumn
        ) == nil)
    }

    private static func sampleHeader(id: String) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: "inbox",
            from: Correspondent(name: "Sigrid Moen", email: "sigrid@example.org"),
            to: [Correspondent(name: "Henrik", email: "henrik@example.org")],
            subject: "Fold transition test",
            snippet: "Continuity across fold and unfold.",
            date: Date(timeIntervalSince1970: 1_779_960_600)
        )
    }
}
