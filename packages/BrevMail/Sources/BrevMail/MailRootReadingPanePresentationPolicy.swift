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
        readingPanePresentation: MailRootReadingPanePresentation
    ) -> MailRootSizeClassTransitionOutcome? {
        guard let newSizeClass, oldSizeClass != newSizeClass else { return nil }

        switch newSizeClass {
        case .regular:
            guard let compactReaderHeader else { return nil }
            return MailRootSizeClassTransitionOutcome(
                selectedMessageIDToPreserve: selectedMessageID == compactReaderHeader.id
                    ? nil
                    : compactReaderHeader.id,
                compactReaderHeader: nil,
                preferredCompactColumn: nil
            )

        case .compact:
            if let selectedHeader {
                return MailRootSizeClassTransitionOutcome(
                    selectedMessageIDToPreserve: nil,
                    compactReaderHeader: selectedHeader,
                    preferredCompactColumn: .detail
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
                preferredCompactColumn: targetColumn
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
