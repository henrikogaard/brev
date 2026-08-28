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

#if os(macOS)
import AppKit
#endif

/// Attribute keys for tagging inline-image `NSTextAttachment` runs.
///
/// Set `ComposeInlineImageAttribute.contentID` on the attachment character run so the
/// HTML serializer can emit `<img src="cid:…">` instead of embedding raw image bytes.
enum ComposeInlineImageAttribute {
    /// The MIME Content-ID string for an inline image attachment run.
    static let contentID = NSAttributedString.Key("brevInlineContentID")
}

/// Detects supported inline-image formats from their file signatures.
enum ComposeInlineImageData {
    /// Returns the MIME type for supported PNG, JPEG, and GIF data.
    /// - Parameter data: The transferred image bytes to inspect.
    /// - Returns: A supported image MIME type, or `nil` for unknown data.
    static func mimeType(for data: Data) -> String? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "image/png"
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }
        if data.starts(with: Data("GIF87a".utf8)) || data.starts(with: Data("GIF89a".utf8)) {
            return "image/gif"
        }
        return nil
    }
}

/// Maps pasteboard UTI type strings to image (data, mimeType) payloads.
///
/// This is a pure, platform-neutral helper: it accepts UTI strings and a data-
/// retrieval closure instead of an `NSPasteboard` directly so it can be unit-tested
/// without an AppKit dependency.
enum ComposePasteboardImage {
    /// Preferred UTI order: png → jpeg → gif. Anything else is ignored.
    private static let preferenceOrder: [(uti: String, mimeType: String)] = [
        ("public.png", "image/png"),
        ("public.jpeg", "image/jpeg"),
        ("com.compuserve.gif", "image/gif"),
    ]

    /// Returns the highest-priority (data, mimeType) pair found in `types`, or `nil`
    /// if none of the preferred types are present or the data closure returns `nil`.
    ///
    /// - Parameters:
    ///   - types: The UTI strings advertised by the pasteboard or drag source.
    ///   - data: Closure that retrieves raw data for a given UTI string; returns `nil`
    ///           when no data is available for that type.
    /// - Returns: A named tuple `(data: Data, mimeType: String)` for the best available
    ///            image format, or `nil` when no supported image type is present.
    static func imagePayload(
        types: [String],
        data: (String) -> Data?
    ) -> (data: Data, mimeType: String)? {
        for candidate in preferenceOrder {
            guard types.contains(candidate.uti) else { continue }
            guard let imageData = data(candidate.uti) else { continue }
            return (data: imageData, mimeType: candidate.mimeType)
        }
        return nil
    }
}
