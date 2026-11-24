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

import Foundation

/// Custom `NSAttributedString` attribute keys that carry Brev's rich-compose
/// semantic structures (headings, inline code, code blocks, and tables)
/// identically across AppKit and UIKit without conflating them with the user's
/// chosen mailbox reading font.
enum ComposeRichTextAttribute {
    /// Marks an inline `<code>` run (`Bool` / `NSNumber`).
    static let inlineCode = NSAttributedString.Key("brevInlineCode")
    /// Groups consecutive paragraphs belonging to one `<pre><code>` block (`String`).
    static let codeBlockID = NSAttributedString.Key("brevCodeBlockID")
    /// Semantic heading level (`Int`: `1`, `2`, or `3`) for `<h1>`–`<h3>`.
    static let headingLevel = NSAttributedString.Key("brevHeadingLevel")
    /// Semantic table cell identity (`ComposeTableCellMetadata`) for `<table>` cells.
    static let tableCell = NSAttributedString.Key("brevTableCell")
}

/// Identifies a single cell inside a rich-compose semantic HTML table.
///
/// Subclasses `NSObject` and implements `NSCopying`, `isEqual(_:)`, and `hash`
/// so AppKit/UIKit `NSTextStorage`, undo, and `NSAttributedString.isEqual(to:)`
/// preserve cell metadata across edits and round-trips.
final class ComposeTableCellMetadata: NSObject, NSCopying, @unchecked Sendable {
    let tableID: String
    let row: Int
    let column: Int
    let isHeader: Bool

    init(tableID: String, row: Int, column: Int, isHeader: Bool) {
        self.tableID = tableID
        self.row = row
        self.column = column
        self.isHeader = isHeader
        super.init()
    }

    func copy(with _: NSZone? = nil) -> Any {
        ComposeTableCellMetadata(tableID: tableID, row: row, column: column, isHeader: isHeader)
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ComposeTableCellMetadata else { return false }
        return tableID == other.tableID
            && row == other.row
            && column == other.column
            && isHeader == other.isHeader
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(tableID)
        hasher.combine(row)
        hasher.combine(column)
        hasher.combine(isHeader)
        return hasher.finalize()
    }
}
