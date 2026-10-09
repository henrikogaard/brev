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

/// The compose fields that can hold keyboard focus. The body is a UIKit text
/// view, so SwiftUI focus state only mirrors it through a focus request.
enum ComposeFocusField: Hashable {
    case to
    case cc
    case bcc
    case subject
    case body
}

/// A one-shot request for the body text view to take keyboard focus. `id`
/// changes with every request so repeated requests are all honoured.
struct ComposeBodyFocusRequest: Equatable {
    let id: Int
    /// Where to put the caret; nil keeps the text view's own selection.
    let selection: NSRange?
}

/// Decides where the keyboard goes when compose opens and when Return is
/// pressed, matching iOS Mail: new mail starts in To, a reply starts in the
/// body above the quote.
enum ComposeFocusPolicy {
    /// The field to focus when compose appears.
    static func initialField(hasRecipients: Bool, hasSubject: Bool) -> ComposeFocusField {
        if !hasRecipients { return .to }
        if !hasSubject { return .subject }
        return .body
    }

    /// The field Return moves to; `nil` once the body has focus.
    static func field(
        after field: ComposeFocusField,
        isCcVisible: Bool,
        isBccVisible: Bool
    ) -> ComposeFocusField? {
        switch field {
        case .to:
            if isCcVisible { return .cc }
            if isBccVisible { return .bcc }
            return .subject
        case .cc:
            return isBccVisible ? .bcc : .subject
        case .bcc:
            return .subject
        case .subject:
            return .body
        case .body:
            return nil
        }
    }

    /// Where the caret lands when the body takes initial focus: inside the
    /// typing zone, never inside the read-only quote.
    static func initialBodySelection(
        in storage: NSString,
        quoteProtection: ComposeQuoteProtection?
    ) -> NSRange {
        guard let quoteProtection,
              let protected = ComposeQuoteEditGuard.protectedRange(in: storage, protection: quoteProtection)
        else {
            return NSRange(location: storage.length, length: 0)
        }
        switch quoteProtection.edge {
        case .bottom:
            return NSRange(location: 0, length: 0)
        case .top:
            return NSRange(location: NSMaxRange(protected), length: 0)
        }
    }
}
