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

import BrevMail
import Testing

/// Explicit selection mode for the phone list (audit L1): the mode is entered with a
/// nav-bar button and only ends with Cancel, so unticking the last row must not end it.
@Suite("MailNavigationState selection mode")
@MainActor
struct MailNavigationSelectionModeTests {
    @Test("selection mode starts off")
    func startsOff() {
        let state = MailNavigationState()
        #expect(!state.isInSelectionMode)
        #expect(!state.isSelecting)
    }

    @Test("beginSelection enters the mode with an empty selection")
    func beginSelectionEntersModeEmpty() {
        let state = MailNavigationState()
        state.beginSelection()
        #expect(state.isInSelectionMode)
        #expect(state.bulkSelection.isEmpty)
    }

    @Test("beginSelection can seed the first row, as the long-press menu does")
    func beginSelectionSeedsRow() {
        let state = MailNavigationState()
        state.beginSelection(selecting: "message-1")
        #expect(state.isInSelectionMode)
        #expect(state.bulkSelection == ["message-1"])
    }

    @Test("unticking the last row keeps the mode until Cancel")
    func unselectingLastRowKeepsMode() {
        let state = MailNavigationState()
        state.beginSelection(selecting: "message-1")
        state.bulkSelection.remove("message-1")
        #expect(state.isInSelectionMode)
    }

    @Test("endSelection leaves the mode and clears the selection")
    func endSelectionClears() {
        let state = MailNavigationState()
        state.beginSelection(selecting: "message-1")
        state.endSelection()
        #expect(!state.isInSelectionMode)
        #expect(state.bulkSelection.isEmpty)
    }

    @Test("a non-empty bulk selection alone still counts as selection mode (macOS keyboard path)")
    func bulkSelectionAloneIsSelectionMode() {
        let state = MailNavigationState()
        state.bulkSelection = ["message-1"]
        #expect(state.isInSelectionMode)
        #expect(!state.isSelecting)
    }

    @Test("switching folder, unified inbox or mailbox ends selection mode")
    func scopeChangesEndSelectionMode() {
        let state = MailNavigationState()
        state.beginSelection(selecting: "message-1")
        state.selectFolder("archive", in: nil)
        #expect(!state.isInSelectionMode)

        state.beginSelection()
        state.selectUnifiedInbox()
        #expect(!state.isInSelectionMode)

        state.beginSelection()
        state.resetForMailboxSwitch()
        #expect(!state.isInSelectionMode)
    }
}
