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

import CoreGraphics

/// Room for the AI Writer preview in the reply docked under the reader
/// (#302). The dock has a fixed height, so with the fields, starters and body
/// all shown the preview text was squeezed to nothing.
enum InlineReplyPreviewLayout {
    /// While a preview is open in the dock, the From/To/Subject fields and
    /// the starters step aside; they come back on apply or cancel. The reply
    /// window has room for both and keeps its fields.
    static func showsFieldsAndStarters(isInline: Bool, isPreviewing: Bool) -> Bool {
        !(isInline && isPreviewing)
    }

    /// The least height the docked preview text gets, so it stays readable;
    /// nil in the reply window, where the text sizes to its content.
    static func previewTextMinHeight(isInline: Bool) -> CGFloat? {
        isInline ? 80 : nil
    }
}
