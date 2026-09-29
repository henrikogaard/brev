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

/// Defers each mailbox construction stage until SwiftUI evaluates its body.
/// Computed `some View` properties alone still construct one deeply nested
/// value on the caller's stack. Release builds exceeded the iPhone's 1 MiB
/// stack at launch; a fixed-size boundary lets each stage unwind first.
struct MailRootRenderStage: View {
    private let content: () -> AnyView

    init(@ViewBuilder content: @escaping () -> some View) {
        self.content = { AnyView(content()) }
    }

    var body: some View { content() }
}
