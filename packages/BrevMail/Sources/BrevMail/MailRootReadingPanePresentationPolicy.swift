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
