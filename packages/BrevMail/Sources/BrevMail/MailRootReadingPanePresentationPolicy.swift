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
import SwiftUI

enum MailRootReadingPanePresentation: Equatable, Sendable {
    case splitDetailColumn
    case bottomStack
}

enum MailRootMessageSelectionPresentation: Equatable, Sendable {
    case compactOverlay
    case splitInPlace
}

/// Pure state update produced when an iOS scene transitions between compact and
/// regular horizontal size classes (for example, folding or unfolding iPhone Duo
/// or resizing iPad Slide Over / Split View).
struct MailRootSizeClassTransitionOutcome: Equatable, Sendable {
    /// Message ID to write back into `MailNavigationState.selectedMessageID` if
    /// needed to preserve the message shown before unfolding, or `nil` when
    /// selection is already intact.
    let selectedMessageIDToPreserve: MessageHeader.ID?
    /// Next value for `compactReaderHeader`.
    let compactReaderHeader: MessageHeader?
    /// Preferred compact column to activate on fold, or `nil` when unchanged.
    let preferredCompactColumn: NavigationSplitViewColumn?
    /// Split visibility update on unfold (restores `.doubleColumn` when compact
    /// folder navigation had previously set `.detailOnly`), or `nil` when unchanged.
    let splitViewVisibility: NavigationSplitViewVisibility?
}

/// Keeps reading continuity across live `.compact` <-> `.regular` horizontal
/// size-class transitions so unfolding never strands the split detail pane on
/// an empty view and folding never drops an actively read message.
enum MailRootSizeClassTransitionPolicy {
    static func transition(
        from oldSizeClass: UserInterfaceSizeClass?,
        to newSizeClass: UserInterfaceSizeClass?,
        compactReaderHeader: MessageHeader?,
        selectedHeader: MessageHeader?,
        selectedMessageID: MessageHeader.ID?,
        hasSelectedMessageDestination: Bool,
        readingPanePresentation: MailRootReadingPanePresentation,
        currentSplitViewVisibility: NavigationSplitViewVisibility = .automatic
    ) -> MailRootSizeClassTransitionOutcome? {
        guard let newSizeClass, oldSizeClass != newSizeClass else { return nil }

        switch newSizeClass {
        case .regular:
            let nextSplitVisibility: NavigationSplitViewVisibility? =
                currentSplitViewVisibility == .detailOnly ? .doubleColumn : nil
            guard compactReaderHeader != nil || nextSplitVisibility != nil else { return nil }
            // Match the compact reader's own priority (`selectedHeader ?? fallbackHeader`):
            // keep a live selection (e.g. restored by Undo) and fall back to
            // `compactReaderHeader` only when no live header is selected.
            let preservedMessageID: MessageHeader.ID? =
                if let compactReaderHeader,
                selectedHeader == nil,
                selectedMessageID != compactReaderHeader.id {
                    compactReaderHeader.id
                } else {
                    nil
                }
            return MailRootSizeClassTransitionOutcome(
                selectedMessageIDToPreserve: preservedMessageID,
                compactReaderHeader: nil,
                preferredCompactColumn: nil,
                splitViewVisibility: nextSplitVisibility
            )

        case .compact:
            // Bottom-stack layouts render `bottomReadingPane` directly instead of
            // `splitDetailPane`; leaving `compactReaderHeader` nil keeps its reader
            // mounted rather than collapsing `backgroundReadingPaneContent` to clear.
            if readingPanePresentation == .bottomStack {
                return MailRootSizeClassTransitionOutcome(
                    selectedMessageIDToPreserve: nil,
                    compactReaderHeader: nil,
                    preferredCompactColumn: hasSelectedMessageDestination ? .detail : .sidebar,
                    splitViewVisibility: nil
                )
            }
            if let selectedHeader {
                return MailRootSizeClassTransitionOutcome(
                    selectedMessageIDToPreserve: nil,
                    compactReaderHeader: selectedHeader,
                    preferredCompactColumn: .detail,
                    splitViewVisibility: nil
                )
            }
            let targetColumn: NavigationSplitViewColumn = hasSelectedMessageDestination
                ? MailRootReadingPanePresentationPolicy.compactColumnAfterSelectingFolder(
                    presentation: readingPanePresentation
                )
                : .sidebar
            return MailRootSizeClassTransitionOutcome(
                selectedMessageIDToPreserve: nil,
                compactReaderHeader: nil,
                preferredCompactColumn: targetColumn,
                splitViewVisibility: nil
            )

        @unknown default:
            return nil
        }
    }
}

enum MailRootReadingPanePresentationPolicy {
    static func presentation(for storedValue: String) -> MailRootReadingPanePresentation {
        presentation(for: MailboxReadingPanePlacement(rawValue: storedValue) ?? .side)
    }

    private static func presentation(
        for placement: MailboxReadingPanePlacement
    ) -> MailRootReadingPanePresentation {
        switch placement {
        case .side:
            return .splitDetailColumn
        case .bottom:
            return .bottomStack
        }
    }

    static func compactColumnAfterSelectingFolder(
        presentation: MailRootReadingPanePresentation
    ) -> NavigationSplitViewColumn {
        switch presentation {
        case .splitDetailColumn:
            return .content
        case .bottomStack:
            return .detail
        }
    }

    static func usesCompactReaderPresentation(
        horizontalSizeClass: UserInterfaceSizeClass?
    ) -> Bool {
        horizontalSizeClass != .regular
    }

    static func messageSelectionPresentation(
        horizontalSizeClass: UserInterfaceSizeClass?
    ) -> MailRootMessageSelectionPresentation {
        usesCompactReaderPresentation(horizontalSizeClass: horizontalSizeClass)
            ? .compactOverlay
            : .splitInPlace
    }
}
