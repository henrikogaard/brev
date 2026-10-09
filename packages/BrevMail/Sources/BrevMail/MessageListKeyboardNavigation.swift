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

import SwiftUI

/// A key command handled by the focused macOS message list, beyond the
/// arrow and Return handling that already lives on the list container.
enum MessageListKeyCommand: Equatable {
    /// Delete / Backspace: move the selection to Trash.
    case deleteSelection
    /// Escape: drop the bulk selection.
    case clearSelection
    case moveToStart
    case moveToEnd
    case pageUp
    case pageDown
}

/// Pure key-to-command mapping and selection-index math for the message
/// list's keyboard handling, kept out of the view so it can be tested.
enum MessageListKeyboardNavigation {
    /// Rows moved by Page Up / Page Down. The list does not report its
    /// visible row count, so a fixed step stands in for "one screen".
    static let pageStep = 10

    /// Modifiers the system adds to navigation keys without the user
    /// holding anything.
    private static let ignoredModifiers: EventModifiers = [.function, .numericPad, .capsLock]

    /// Maps a bare key press to a list command. Any real modifier (⌘, ⌥, ⌃,
    /// ⇧) returns nil so menu shortcuts such as ⌘⌫ keep their own path.
    static func command(for key: KeyEquivalent, modifiers: EventModifiers) -> MessageListKeyCommand? {
        guard modifiers.subtracting(ignoredModifiers).isEmpty else { return nil }
        switch key {
        case .delete, .deleteForward: return .deleteSelection
        case .escape: return .clearSelection
        case .home: return .moveToStart
        case .end: return .moveToEnd
        case .pageUp: return .pageUp
        case .pageDown: return .pageDown
        default: return nil
        }
    }

    /// The row index a movement command lands on, clamped to the list.
    /// Returns nil for an empty list and for non-movement commands.
    static func targetIndex(for command: MessageListKeyCommand, current: Int?, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let last = count - 1
        switch command {
        case .moveToStart:
            return 0
        case .moveToEnd:
            return last
        case .pageUp:
            guard let current else { return 0 }
            return min(max(current - pageStep, 0), last)
        case .pageDown:
            guard let current else { return 0 }
            return min(max(current + pageStep, 0), last)
        case .deleteSelection, .clearSelection:
            return nil
        }
    }
}
