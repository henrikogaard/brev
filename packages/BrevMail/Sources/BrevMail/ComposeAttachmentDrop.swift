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
import UniformTypeIdentifiers

/// Maps items dropped onto the compose window to attachment inputs.
///
/// The type-mapping and URL-decoding parts are pure so they can be tested
/// without an `NSItemProvider`; the item-provider loading lives in
/// `ComposeView` and feeds its results back through `importDroppedImages`
/// and `ComposeAttachmentImport.importFiles`.
enum ComposeAttachmentDrop {
    /// Content types the compose drop target advertises. File URLs become
    /// regular attachments; loose image data (e.g. an image dragged out of a
    /// browser) is written out and attached under a generated filename.
    static let acceptedContentTypes: [UTType] = [.fileURL, .image]

    /// How a single dropped item provider should be loaded.
    enum Source: Equatable {
        /// Load the item as a file URL and import the file at that path.
        case fileURL
        /// Load raw image data for the given concrete image type.
        case imageData(UTType)
    }

    /// Image data dropped without a backing file.
    struct DroppedImage: Sendable {
        let data: Data
        let type: UTType
    }

    /// Picks the representation to load for one provider, or `nil` when the
    /// provider offers nothing the compose window can attach.
    ///
    /// A file URL always wins over image data so the original filename is kept.
    static func source(forRegisteredTypeIdentifiers identifiers: [String]) -> Source? {
        let types = identifiers.compactMap { UTType($0) }
        if types.contains(where: { $0.conforms(to: .fileURL) }) {
            return .fileURL
        }
        if let image = types.first(where: { $0.conforms(to: .image) && $0.preferredFilenameExtension != nil }) {
            return .imageData(image)
        }
        return nil
    }

    /// Decodes the object an item provider hands back for the file-URL type.
    ///
    /// AppKit and UIKit variously return a `URL`, an `NSURL`, the URL's data
    /// representation, or an absolute-string; only file URLs are accepted.
    static func fileURL(fromLoadedItem item: Any?) -> URL? {
        let url: URL?
        switch item {
        case let value as URL:
            url = value
        case let value as Data:
            url = URL(dataRepresentation: value, relativeTo: nil)
        case let value as String:
            url = URL(string: value)
        default:
            url = nil
        }
        guard let url, url.isFileURL else { return nil }
        return url
    }

    /// Filename used for image data that has no backing file.
    static func imageFilename(for type: UTType) -> String {
        "Image.\(type.preferredFilenameExtension ?? "img")"
    }

    /// Writes dropped image data to a scratch directory and runs it through the
    /// regular file import so naming, size limits, and MIME detection match the
    /// file picker exactly.
    static func importDroppedImages(
        _ images: [DroppedImage],
        existingFilenames: Set<String>,
        existingByteCount: Int
    ) async -> ComposeAttachmentImportResult {
        guard !images.isEmpty else {
            return ComposeAttachmentImportResult(attachments: [], errorMessage: nil)
        }
        let scratchDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("brev-compose-drop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratchDirectory) }

        var urls: [URL] = []
        do {
            try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
            for (index, image) in images.enumerated() {
                let url = scratchDirectory
                    .appendingPathComponent("\(index)", isDirectory: true)
                    .appendingPathComponent(imageFilename(for: image.type))
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try image.data.write(to: url)
                urls.append(url)
            }
        } catch {
            return ComposeAttachmentImportResult(
                attachments: [],
                errorMessage: "Couldn't attach dropped image: \(error.localizedDescription)"
            )
        }

        return await ComposeAttachmentImport.importFiles(
            from: urls,
            existingFilenames: existingFilenames,
            existingByteCount: existingByteCount
        )
    }
}
