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

/// Represents an inline image staged for compose.
struct ComposeInlineImage: Equatable {
    /// The Content-ID used in the message body to reference this image.
    let contentID: String
    /// The filename of the image.
    let filename: String
    /// The MIME type of the image.
    let mimeType: String
    /// The image data.
    let data: Data
}

/// Policy for inline image staging.
enum ComposeInlineImagePolicy {
    /// Allowed MIME types for inline images.
    static let allowedMIMETypes: Set<String> = ["image/png", "image/jpeg", "image/gif"]
    /// Maximum size in bytes for an inline image.
    static let maxBytes = 10 * 1024 * 1024
}

/// A registry for staging inline images in compose.
final class ComposeInlineImageRegistry {
    /// Images currently staged for composition.
    private(set) var staged: [ComposeInlineImage] = []

    /// Stages an image for composition if it passes validation.
    /// - Parameters:
    ///   - data: The image data.
    ///   - mimeType: The MIME type of the image.
    ///   - makeID: A closure that generates a Content-ID for the image.
    /// - Returns: The staged image, or nil if the MIME type is not allowed or the data exceeds maxBytes.
    func stage(data: Data, mimeType: String, makeID: () -> String) -> ComposeInlineImage? {
        guard ComposeInlineImagePolicy.allowedMIMETypes.contains(mimeType) else {
            return nil
        }
        guard data.count <= ComposeInlineImagePolicy.maxBytes else {
            return nil
        }
        let contentID = makeID()
        let image = ComposeInlineImage(
            contentID: contentID,
            filename: "image.\(Self.filenameExtension(for: mimeType))",
            mimeType: mimeType,
            data: data
        )
        staged.append(image)
        return image
    }

    private static func filenameExtension(for mimeType: String) -> String {
        switch mimeType {
        case "image/jpeg": return "jpg"
        case "image/gif": return "gif"
        default: return "png"
        }
    }

    /// Removes images whose Content-IDs are not in the provided set.
    /// - Parameter keepingContentIDs: A set of Content-IDs to keep.
    func reconcile(keepingContentIDs: Set<String>) {
        staged.removeAll { !keepingContentIDs.contains($0.contentID) }
    }

    /// Extracts all Content-IDs referenced via `<img src="cid:…">` in an
    /// HTML body string.
    ///
    /// Returns the bare CID values (no `cid:` prefix, no angle brackets).
    /// Used to reconcile the registry before send so images deleted from the
    /// body are not attached to the outgoing message.
    static func contentIDs(inHTML html: String) -> Set<String> {
        // Match src="cid:..." with single or double quotes, case-insensitive.
        let pattern = #"(?i)src\s*=\s*["']cid:([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsString = html as NSString
        let range = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: html, range: range)
        var result = Set<String>()
        for match in matches {
            guard match.numberOfRanges > 1,
                  match.range(at: 1).location != NSNotFound else { continue }
            result.insert(nsString.substring(with: match.range(at: 1)))
        }
        return result
    }
}
