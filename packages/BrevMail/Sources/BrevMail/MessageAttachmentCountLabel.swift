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

/// The "N attachments" caption above a message's attachment list.
enum MessageAttachmentCountLabel {
    /// Plural-aware caption resolved through the String Catalog, so each
    /// language picks its own singular and plural forms.
    /// - Parameters:
    ///   - count: Number of attachments on the message.
    ///   - bundle: Bundle whose localization is used; tests pass a language
    ///     sub-bundle to check each translation.
    static func title(count: Int, bundle: Bundle = .module) -> String {
        String(localized: "\(count) attachments", bundle: bundle)
    }
}
