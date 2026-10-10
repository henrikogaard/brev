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

@Suite("MessageListSelectionMath")
struct MessageListSelectionMathTests {
    private static let order = ["a", "b", "c", "d", "e", "f"]

    // MARK: Click modifiers

    @Test("held modifier keys map to a selection click")
    func clickModifierMapping() {
        #expect(MessageListClickModifier(command: false, shift: false) == nil)
        #expect(MessageListClickModifier(command: true, shift: false) == .toggle)
        #expect(MessageListClickModifier(command: false, shift: true) == .range)
        #expect(MessageListClickModifier(command: true, shift: true) == .toggle)
    }

    // MARK: Plain click

    @Test("a plain click selects one row, clears the checked set and anchors there")
    func plainClick() {
        let result = MessageListSelectionMath.plain("c")
        #expect(result.checkedIDs.isEmpty)
        #expect(result.anchorID == "c")
        #expect(result.cursorID == "c")
    }

    // MARK: Command-click

    @Test("command-click on a row adds it to the currently selected row")
    func commandClickStartsFromSelectedRow() {
        let result = MessageListSelectionMath.toggling("d", checked: [], selectedID: "b")
        #expect(result.checkedIDs == ["b", "d"])
        #expect(result.anchorID == "d")
        #expect(result.cursorID == "d")
    }

    @Test("command-click on a checked row removes it")
    func commandClickRemoves() {
        let result = MessageListSelectionMath.toggling("d", checked: ["b", "d", "f"], selectedID: "b")
        #expect(result.checkedIDs == ["b", "f"])
    }

    @Test("command-click on the only selected row leaves nothing checked")
    func commandClickOnSelectedRow() {
        let result = MessageListSelectionMath.toggling("b", checked: [], selectedID: "b")
        #expect(result.checkedIDs.isEmpty)
    }

    @Test("command-click with nothing selected checks just that row")
    func commandClickWithoutSelection() {
        let result = MessageListSelectionMath.toggling("c", checked: [], selectedID: nil)
        #expect(result.checkedIDs == ["c"])
    }

    // MARK: Shift-click

    @Test("shift-click selects the contiguous range from the selected row, forwards")
    func shiftClickForwards() {
        let result = MessageListSelectionMath.range(
            to: "d", anchorID: nil, selectedID: "b", order: Self.order
        )
        #expect(result.checkedIDs == ["b", "c", "d"])
        #expect(result.anchorID == "b")
        #expect(result.cursorID == "d")
    }

    @Test("shift-click selects the range backwards in visible order")
    func shiftClickBackwards() {
        let result = MessageListSelectionMath.range(
            to: "a", anchorID: nil, selectedID: "c", order: Self.order
        )
        #expect(result.checkedIDs == ["a", "b", "c"])
    }

    @Test("a second shift-click re-ranges from the same anchor instead of growing")
    func shiftClickKeepsAnchor() {
        let first = MessageListSelectionMath.range(
            to: "e", anchorID: nil, selectedID: "b", order: Self.order
        )
        let second = MessageListSelectionMath.range(
            to: "c", anchorID: first.anchorID, selectedID: "b", order: Self.order
        )
        #expect(second.checkedIDs == ["b", "c"])
        #expect(second.anchorID == "b")
    }

    @Test("shift-click on the anchor row collapses back to a single selection")
    func shiftClickOnAnchor() {
        let result = MessageListSelectionMath.range(
            to: "b", anchorID: "b", selectedID: "b", order: Self.order
        )
        #expect(result.checkedIDs.isEmpty)
    }

    @Test("shift-click with no anchor or selection checks only the clicked row's range of one")
    func shiftClickWithoutAnchor() {
        let result = MessageListSelectionMath.range(
            to: "c", anchorID: nil, selectedID: nil, order: Self.order
        )
        #expect(result.checkedIDs.isEmpty)
        #expect(result.anchorID == "c")
    }

    @Test("an anchor that left the list falls back to the selected row")
    func shiftClickStaleAnchor() {
        let result = MessageListSelectionMath.range(
            to: "d", anchorID: "gone", selectedID: "c", order: Self.order
        )
        #expect(result.checkedIDs == ["c", "d"])
    }

    // MARK: Shift-arrow

    @Test("shift-down extends from the selected row one row at a time")
    func shiftDownExtends() {
        let first = MessageListSelectionMath.extending(
            by: 1, anchorID: nil, cursorID: nil, selectedID: "b", order: Self.order
        )
        #expect(first.checkedIDs == ["b", "c"])
        #expect(first.anchorID == "b")
        #expect(first.cursorID == "c")

        let second = MessageListSelectionMath.extending(
            by: 1, anchorID: first.anchorID, cursorID: first.cursorID, selectedID: "b", order: Self.order
        )
        #expect(second.checkedIDs == ["b", "c", "d"])
    }

    @Test("shift-up after shift-down shrinks the range and ends back at a single selection")
    func shiftUpShrinks() {
        let down = MessageListSelectionMath.extending(
            by: 1, anchorID: nil, cursorID: nil, selectedID: "b", order: Self.order
        )
        let up = MessageListSelectionMath.extending(
            by: -1, anchorID: down.anchorID, cursorID: down.cursorID, selectedID: "b", order: Self.order
        )
        #expect(up.checkedIDs.isEmpty)
        #expect(up.cursorID == "b")
    }

    @Test("shift-up past the anchor extends the other way")
    func shiftUpPastAnchor() {
        let first = MessageListSelectionMath.extending(
            by: -1, anchorID: nil, cursorID: nil, selectedID: "c", order: Self.order
        )
        #expect(first.checkedIDs == ["b", "c"])
        let second = MessageListSelectionMath.extending(
            by: -1, anchorID: first.anchorID, cursorID: first.cursorID, selectedID: "c", order: Self.order
        )
        #expect(second.checkedIDs == ["a", "b", "c"])
    }

    @Test("extending clamps at both ends of the list")
    func extendingClamps() {
        let atEnd = MessageListSelectionMath.extending(
            by: 1, anchorID: "e", cursorID: "f", selectedID: "e", order: Self.order
        )
        #expect(atEnd.cursorID == "f")
        #expect(atEnd.checkedIDs == ["e", "f"])

        let atStart = MessageListSelectionMath.extending(
            by: -1, anchorID: "b", cursorID: "a", selectedID: "b", order: Self.order
        )
        #expect(atStart.cursorID == "a")
        #expect(atStart.checkedIDs == ["a", "b"])
    }

    @Test("extending with no selection and no anchor changes nothing")
    func extendingWithoutAnchor() {
        let result = MessageListSelectionMath.extending(
            by: 1, anchorID: nil, cursorID: nil, selectedID: nil, order: Self.order
        )
        #expect(result.checkedIDs.isEmpty)
        #expect(result.anchorID == nil)
    }

    @Test("extending in an empty list changes nothing")
    func extendingEmptyList() {
        let result = MessageListSelectionMath.extending(
            by: 1, anchorID: "a", cursorID: "a", selectedID: "a", order: []
        )
        #expect(result.checkedIDs.isEmpty)
    }

    // MARK: Select all

    @Test("select all checks every visible row and keeps the selected row as the anchor")
    func selectAll() {
        let result = MessageListSelectionMath.selectingAll(order: Self.order, selectedID: "c")
        #expect(result.checkedIDs == Set(Self.order))
        #expect(result.anchorID == "c")
        #expect(result.cursorID == "f")
    }

    @Test("select all anchors on the first row when nothing is selected")
    func selectAllWithoutSelection() {
        let result = MessageListSelectionMath.selectingAll(order: Self.order, selectedID: nil)
        #expect(result.anchorID == "a")
    }

    @Test("select all in an empty list checks nothing")
    func selectAllEmpty() {
        let result = MessageListSelectionMath.selectingAll(order: [], selectedID: nil)
        #expect(result.checkedIDs.isEmpty)
        #expect(result.anchorID == nil)
    }
}
