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

/// How a modified click on a row changes the selection.
enum MessageListClickModifier: Equatable {
    /// Command-click: toggle the row in the checked set.
    case toggle
    /// Shift-click: select the range from the anchor.
    case range

    /// Maps held modifier keys to a selection click; nil for a plain click.
    /// Command wins when both are held, as in Finder.
    init?(command: Bool, shift: Bool) {
        if command {
            self = .toggle
        } else if shift {
            self = .range
        } else {
            return nil
        }
    }
}

/// Pure multi-selection rules for the macOS message list: Command-click,
/// Shift-click, Shift-arrow and Select All. The view owns the anchor and
/// cursor between calls and writes `checkedIDs` to
/// `MailNavigationState.bulkSelection`.
///
/// A range of one row is reported as an empty checked set: the list is then
/// in ordinary single-selection mode, which is what the reader pane shows.
enum MessageListSelectionMath {
    /// The selection after an interaction.
    struct Result: Equatable {
        /// Rows to put in the bulk selection.
        var checkedIDs: Set<MessageHeader.ID>
        /// The fixed end of a Shift range.
        var anchorID: MessageHeader.ID?
        /// The moving end of a Shift range.
        var cursorID: MessageHeader.ID?
    }

    /// A plain click: single selection, nothing checked.
    static func plain(_ id: MessageHeader.ID) -> Result {
        Result(checkedIDs: [], anchorID: id, cursorID: id)
    }

    /// Command-click: toggles `id`, starting from the currently selected row
    /// when nothing is checked yet so the first Command-click adds to it.
    /// - Parameters:
    ///   - id: The clicked row.
    ///   - checked: The current bulk selection.
    ///   - selectedID: The row shown in the reader, if any.
    static func toggling(
        _ id: MessageHeader.ID,
        checked: Set<MessageHeader.ID>,
        selectedID: MessageHeader.ID?
    ) -> Result {
        var next = checked
        if next.isEmpty, let selectedID {
            next.insert(selectedID)
        }
        if next.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        return Result(checkedIDs: next, anchorID: id, cursorID: id)
    }

    /// Shift-click: selects every row between the anchor and `id`, in
    /// visible order, replacing the checked set.
    /// - Parameters:
    ///   - id: The clicked row.
    ///   - anchorID: The fixed end of the range, if one is already set.
    ///   - selectedID: The reader's row, used when the anchor is unset or stale.
    ///   - order: Row IDs in the order they are shown.
    static func range(
        to id: MessageHeader.ID,
        anchorID: MessageHeader.ID?,
        selectedID: MessageHeader.ID?,
        order: [MessageHeader.ID]
    ) -> Result {
        let anchor = resolvedAnchor(anchorID, selectedID: selectedID, order: order) ?? id
        return Result(
            checkedIDs: checkedRange(from: anchor, to: id, order: order),
            anchorID: anchor,
            cursorID: id
        )
    }

    /// Shift-arrow: moves the cursor `delta` rows and re-selects the range
    /// from the anchor. Does nothing without an anchor or selection.
    /// - Parameters:
    ///   - delta: Rows to move; negative is up.
    ///   - anchorID: The fixed end of the range, if one is already set.
    ///   - cursorID: The moving end of the range, if one is already set.
    ///   - selectedID: The reader's row, used when the anchor is unset or stale.
    ///   - order: Row IDs in the order they are shown.
    static func extending(
        by delta: Int,
        anchorID: MessageHeader.ID?,
        cursorID: MessageHeader.ID?,
        selectedID: MessageHeader.ID?,
        order: [MessageHeader.ID]
    ) -> Result {
        guard let anchor = resolvedAnchor(anchorID, selectedID: selectedID, order: order),
              let anchorIndex = order.firstIndex(of: anchor)
        else {
            return Result(checkedIDs: [], anchorID: nil, cursorID: nil)
        }
        let cursorIndex = cursorID.flatMap { order.firstIndex(of: $0) } ?? anchorIndex
        let target = min(max(cursorIndex + delta, 0), order.count - 1)
        let cursor = order[target]
        return Result(
            checkedIDs: checkedRange(from: anchor, to: cursor, order: order),
            anchorID: anchor,
            cursorID: cursor
        )
    }

    /// Select All: checks every visible row.
    static func selectingAll(order: [MessageHeader.ID], selectedID: MessageHeader.ID?) -> Result {
        guard let first = order.first else {
            return Result(checkedIDs: [], anchorID: nil, cursorID: nil)
        }
        let anchor = selectedID.flatMap { order.contains($0) ? $0 : nil } ?? first
        return Result(checkedIDs: Set(order), anchorID: anchor, cursorID: order.last)
    }

    private static func resolvedAnchor(
        _ anchorID: MessageHeader.ID?,
        selectedID: MessageHeader.ID?,
        order: [MessageHeader.ID]
    ) -> MessageHeader.ID? {
        if let anchorID, order.contains(anchorID) { return anchorID }
        if let selectedID, order.contains(selectedID) { return selectedID }
        return nil
    }

    private static func checkedRange(
        from anchor: MessageHeader.ID,
        to cursor: MessageHeader.ID,
        order: [MessageHeader.ID]
    ) -> Set<MessageHeader.ID> {
        guard let a = order.firstIndex(of: anchor), let c = order.firstIndex(of: cursor), a != c else {
            return []
        }
        return Set(order[min(a, c) ... max(a, c)])
    }
}
