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
import Foundation
import Testing

@Suite("CompactReaderChromePolicy")
struct CompactReaderChromePolicyTests {
    // MARK: After-removal navigation

    @Test("removing the shown message advances to the survivor that inherited selection")
    func removalShowsNextMessage() {
        let outcome = CompactReaderRemovalPolicy.outcome(
            shownMessageID: "b",
            removedMessageIDs: ["b"],
            selectionAfterRemoval: "c"
        )
        #expect(outcome == .show("c"))
    }

    @Test("removing the last message returns to the list")
    func removalOfLastMessagePops() {
        let outcome = CompactReaderRemovalPolicy.outcome(
            shownMessageID: "a",
            removedMessageIDs: ["a"],
            selectionAfterRemoval: nil
        )
        #expect(outcome == .returnToList)
    }

    @Test("a selection that is itself being removed is not shown")
    func removedSelectionIsNeverShown() {
        let outcome = CompactReaderRemovalPolicy.outcome(
            shownMessageID: "a",
            removedMessageIDs: ["a", "b"],
            selectionAfterRemoval: "b"
        )
        #expect(outcome == .returnToList)
    }

    @Test("removing some other message leaves the reader alone")
    func unrelatedRemovalStays() {
        let outcome = CompactReaderRemovalPolicy.outcome(
            shownMessageID: "a",
            removedMessageIDs: ["z"],
            selectionAfterRemoval: "a"
        )
        #expect(outcome == .stay)
    }

    @Test("the return-to-list behaviour pops even when a next message exists")
    func returnToListBehaviour() {
        let outcome = CompactReaderRemovalPolicy.outcome(
            shownMessageID: "a",
            removedMessageIDs: ["a"],
            selectionAfterRemoval: "b",
            behavior: .returnToList
        )
        #expect(outcome == .returnToList)
    }

    // MARK: Bars and menu inventory

    @Test("the bottom bar mirrors iOS Mail: dismiss, move, reply menu, compose")
    func bottomBarInventory() {
        #expect(CompactReaderChromePolicy.bottomBarActions(hasArchiveFolder: true, hasMoveTargets: true)
            == [.archive, .move, .replyMenu, .compose])
        #expect(CompactReaderChromePolicy.bottomBarActions(hasArchiveFolder: false, hasMoveTargets: true)
            == [.trash, .move, .replyMenu, .compose])
        #expect(CompactReaderChromePolicy.bottomBarActions(hasArchiveFolder: true, hasMoveTargets: false)
            == [.archive, .replyMenu, .compose])
    }

    @Test("the reply menu offers reply, reply all and forward")
    func replyMenuInventory() {
        #expect(CompactReaderChromePolicy.replyMenuActions == [.reply, .replyAll, .forward])
    }

    @Test("the navigation bar carries previous, next and exactly one overflow menu")
    func navigationBarInventory() {
        #expect(CompactReaderChromePolicy.navigationBarActions == [.previousMessage, .nextMessage, .overflow])
    }

    @Test("the overflow menu exists once across both bars")
    func overflowIsNotDuplicated() {
        let bottom = CompactReaderChromePolicy.bottomBarActions(hasArchiveFolder: true, hasMoveTargets: true)
        #expect(bottom.contains(.overflow) == false)
        #expect(CompactReaderChromePolicy.navigationBarActions.filter { $0 == .overflow }.count == 1)
    }

    @Test("the merged overflow menu keeps related mail and Original, then actions, then Ask AI")
    func overflowInventory() {
        #expect(CompactReaderChromePolicy.overflowSections(
            hasRelatedMail: true, showsRenderingToggle: true, canAskAI: true
        ) == [.relatedMail, .renderingToggle, .messageActions, .askAI])
        #expect(CompactReaderChromePolicy.overflowSections(
            hasRelatedMail: false, showsRenderingToggle: false, canAskAI: false
        ) == [.messageActions])
    }
}
