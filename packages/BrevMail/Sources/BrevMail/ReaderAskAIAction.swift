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

/// Opens the mailbox chat for the message in the reader.
///
/// Always compares equal: the closure only flips root-owned `@State`, so a
/// freshly built copy is equivalent. Without this, a new closure in the
/// environment on every root body pass would invalidate the whole reader
/// subtree each time.
struct ReaderAskAIAction: Equatable {
    let perform: @MainActor () -> Void

    static func == (lhs: ReaderAskAIAction, rhs: ReaderAskAIAction) -> Bool { true }
}

private struct ReaderAskAIActionKey: EnvironmentKey {
    static let defaultValue: ReaderAskAIAction? = nil
}

extension EnvironmentValues {
    /// The pushed iPhone reader offers it from its single ••• menu; `nil` hides the item.
    var readerAskAIAction: ReaderAskAIAction? {
        get { self[ReaderAskAIActionKey.self] }
        set { self[ReaderAskAIActionKey.self] = newValue }
    }
}

/// The ••• menu entry that hands the open message to the AI mailbox chat.
struct ReaderAskAIMenuButton: View {
    let action: ReaderAskAIAction

    var body: some View {
        Button(action: action.perform) {
            Label(
                String(localized: "Ask AI", bundle: .module),
                systemImage: MailContextColumnVisibility.toolbarSymbolName
            )
        }
    }
}
