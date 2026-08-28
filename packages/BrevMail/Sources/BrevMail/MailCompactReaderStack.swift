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

/// Layers the compact reader above a retained mailbox so Back restores its exact list state.
struct MailCompactReaderStack<Background: View>: View {
    private let isReaderPresented: Bool
    private let background: Background
    private let reader: AnyView?

    init(
        isReaderPresented: Bool,
        @ViewBuilder background: () -> Background,
        reader: AnyView?
    ) {
        self.isReaderPresented = isReaderPresented
        self.background = background()
        self.reader = reader
    }

    var body: some View {
        ZStack {
            background
                .allowsHitTesting(!isReaderPresented)
                .accessibilityHidden(isReaderPresented)

            if let reader {
                reader.zIndex(1)
            }
        }
    }
}
