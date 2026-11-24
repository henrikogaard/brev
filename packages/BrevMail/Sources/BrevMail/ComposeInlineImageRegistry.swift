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
    /// Allowed MIME types for inline images (PNG, JPEG, GIF, WebP).
    static let allowedMIMETypes: Set<String> = [
        "image/png",
        "image/jpeg",
        "image/gif",
        "image/webp"
    ]
    /// Maximum size in bytes for a single inline image (10 MiB).
    static let maxBytes = 10 * 1024 * 1024
    /// Maximum aggregate size in bytes for all inline images in one compose session (25 MiB).
    static let maxTotalBytes = ComposeAttachmentImport.maxAttachmentByteCount

    /// User-facing error shown when an inline image is rejected for unsupported format.
    static var unsupportedFormatMessage: String {
        String(
            localized: "Only PNG, JPEG, GIF, and WebP images can be inserted inline.",
            bundle: .module
        )
    }

    /// User-facing error shown when an inline image exceeds per-image or aggregate byte caps.
    static var sizeLimitExceededMessage: String {
        String(
            localized: "That image exceeds the inline image size limit.",
            bundle: .module
        )
    }
}

/// A registry for staging inline images in compose.
final class ComposeInlineImageRegistry {
    /// Images currently staged for composition.
    private(set) var staged: [ComposeInlineImage] = []

    /// Normalized Content-IDs referenced by read-only preserved quoted HTML
    /// outside the editable text storage. Protected IDs always count toward the
    /// aggregate inline byte cap and are never evicted as undo history.
    private(set) var protectedContentIDs: Set<String> = []

    /// Updates the set of Content-IDs protected by read-only preserved quoted HTML.
    func setProtectedContentIDs(_ contentIDs: Set<String>) {
        protectedContentIDs = Set(contentIDs.map(ComposeInlineImageData.normalizedContentID))
    }

    /// Clears all staged images and protected Content-IDs when ending or resetting a session.
    func clear() {
        staged = []
        protectedContentIDs = []
    }

    /// Total byte count across all currently staged inline images.
    var totalBytes: Int {
        staged.reduce(0) { $0 + $1.data.count }
    }

    /// Total byte count across staged inline images whose Content-IDs are active
    /// in `keepingContentIDs` or protected by preserved quoted HTML.
    func activeTotalBytes(keepingContentIDs: Set<String>) -> Int {
        referencedImages(keepingContentIDs: keepingContentIDs.union(protectedContentIDs))
            .reduce(0) { $0 + $1.data.count }
    }

    /// Stages an image for composition if it passes validation.
    /// - Parameters:
    ///   - data: The image data.
    ///   - mimeType: The MIME type of the image.
    ///   - activeContentIDs: Optional set of Content-IDs still referenced in the
    ///     body. When provided, aggregate byte caps are checked against active
    ///     images plus `protectedContentIDs` (pruning unreferenced undo-retained
    ///     entries only if needed to stay within `maxTotalBytes`, never evicting
    ///     `protectedContentIDs`).
    ///   - makeID: A closure that generates a Content-ID for the image.
    /// - Returns: The staged image, or nil if the MIME type is not allowed, empty, or exceeds byte caps.
    func stage(
        data: Data,
        mimeType: String,
        activeContentIDs: Set<String>? = nil,
        makeID: () -> String
    ) -> ComposeInlineImage? {
        let normalizedMIME = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !data.isEmpty,
              ComposeInlineImagePolicy.allowedMIMETypes.contains(normalizedMIME) else {
            return nil
        }
        guard data.count <= ComposeInlineImagePolicy.maxBytes else {
            return nil
        }
        let effectiveActiveIDs = activeContentIDs.map { $0.union(protectedContentIDs) }
        let currentBytes = effectiveActiveIDs.map { activeTotalBytes(keepingContentIDs: $0) } ?? totalBytes
        guard currentBytes + data.count <= ComposeInlineImagePolicy.maxTotalBytes else {
            return nil
        }
        if let effectiveActiveIDs, totalBytes + data.count > ComposeInlineImagePolicy.maxTotalBytes {
            reconcile(keepingContentIDs: effectiveActiveIDs)
        }
        let contentID = makeID()
        let image = ComposeInlineImage(
            contentID: contentID,
            filename: "image.\(Self.filenameExtension(for: normalizedMIME))",
            mimeType: normalizedMIME,
            data: data
        )
        staged.append(image)
        return image
    }

    /// Returns staged inline images whose Content-IDs appear in `keepingContentIDs`
    /// without mutating `staged` (allowing Undo to restore recently deleted images).
    func referencedImages(keepingContentIDs: Set<String>) -> [ComposeInlineImage] {
        let normalizedKeeping = Set(keepingContentIDs.map(ComposeInlineImageData.normalizedContentID))
        return staged.filter {
            normalizedKeeping.contains(ComposeInlineImageData.normalizedContentID($0.contentID))
        }
    }

    /// Restores previously persisted inline images from a reopened draft without
    /// changing their Content-IDs or duplicating existing entries.
    func restore(_ images: [ComposeInlineImage]) {
        var existing = Set(staged.map { ComposeInlineImageData.normalizedContentID($0.contentID) })
        for image in images {
            let normalizedCID = ComposeInlineImageData.normalizedContentID(image.contentID)
            let normalizedMIME = image.mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedCID.isEmpty,
                  !image.data.isEmpty,
                  ComposeInlineImagePolicy.allowedMIMETypes.contains(normalizedMIME),
                  image.data.count <= ComposeInlineImagePolicy.maxBytes,
                  totalBytes + image.data.count <= ComposeInlineImagePolicy.maxTotalBytes,
                  existing.insert(normalizedCID).inserted else {
                continue
            }
            staged.append(ComposeInlineImage(
                contentID: image.contentID,
                filename: image.filename,
                mimeType: normalizedMIME,
                data: image.data
            ))
        }
    }

    private static func filenameExtension(for mimeType: String) -> String {
        switch mimeType {
        case "image/jpeg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        default: return "png"
        }
    }

    /// Removes images whose Content-IDs are not in the provided set.
    /// - Parameter keepingContentIDs: A set of Content-IDs to keep.
    func reconcile(keepingContentIDs: Set<String>) {
        let normalizedKeeping = Set(keepingContentIDs.map(ComposeInlineImageData.normalizedContentID))
        staged.removeAll { !normalizedKeeping.contains(ComposeInlineImageData.normalizedContentID($0.contentID)) }
    }

    /// Extracts all Content-IDs referenced via `<img src="cid:…">` in an
    /// HTML body string (handles double-quoted, single-quoted, and unquoted `src`).
    ///
    /// Returns the bare CID values (no `cid:` prefix, no angle brackets).
    /// Used to reconcile the registry before send so images deleted from the
    /// body are not attached to the outgoing message.
    static func contentIDs(inHTML html: String) -> Set<String> {
        let imgTagPattern = #"(?i)<\s*img\b[^>]*>"#
        guard let imgRegex = try? NSRegularExpression(pattern: imgTagPattern) else { return [] }
        let srcPattern = #"(?i)\bsrc\s*=\s*(?:"\s*cid:([^"]+)"|'\s*cid:([^']+)'|cid:([^\s/>]+))"#
        guard let srcRegex = try? NSRegularExpression(pattern: srcPattern) else { return [] }

        let nsString = html as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        var result = Set<String>()
        for imgMatch in imgRegex.matches(in: html, range: fullRange) {
            let tag = nsString.substring(with: imgMatch.range)
            let tagNS = tag as NSString
            guard let srcMatch = srcRegex.firstMatch(
                in: tag,
                range: NSRange(location: 0, length: tagNS.length)
            ) else {
                continue
            }
            for group in 1 ..< srcMatch.numberOfRanges {
                let range = srcMatch.range(at: group)
                guard range.location != NSNotFound else { continue }
                let raw = tagNS.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !raw.isEmpty {
                    result.insert(raw)
                }
                break
            }
        }
        return result
    }
}
