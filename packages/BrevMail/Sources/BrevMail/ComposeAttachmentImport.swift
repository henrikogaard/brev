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

struct ComposeAttachmentImportResult: Sendable {
    let attachments: [PendingAttachment]
    let errorMessage: String?
}

enum ComposeAttachmentImport {
    static func importFiles(
        from urls: [URL],
        existingFilenames: Set<String> = [],
        existingByteCount: Int = 0,
        maxByteCount: Int = maxAttachmentByteCount
    ) async -> ComposeAttachmentImportResult {
        await Task.detached(priority: .userInitiated) {
            importFilesOffMainActor(
                from: urls,
                existingFilenames: existingFilenames,
                existingByteCount: existingByteCount,
                maxByteCount: maxByteCount
            )
        }.value
    }

    private static func importFilesOffMainActor(
        from urls: [URL],
        existingFilenames: Set<String>,
        existingByteCount: Int,
        maxByteCount: Int
    ) -> ComposeAttachmentImportResult {
        var attachments: [PendingAttachment] = []
        var errors: [String] = []
        var usedFilenames = existingFilenames
        var remainingByteCount = max(0, maxByteCount - max(0, existingByteCount))

        for url in urls {
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                // Bound the read: a multi-gigabyte file would otherwise be read
                // fully into memory and could exhaust it. The cap also matches
                // the send limit most providers enforce.
                let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if fileSize > remainingByteCount {
                    errors.append(attachmentBudgetExceededMessage(filename: displayFilename(for: url)))
                    continue
                }
                let data = try coordinatedBoundedData(
                    from: url,
                    maxByteCount: remainingByteCount
                )
                let filename = safeFilename(
                    suggestedName: url.lastPathComponent,
                    usedFilenames: usedFilenames
                )
                usedFilenames.insert(filename)
                attachments.append(
                    PendingAttachment(
                        filename: filename,
                        mimeType: mimeType(for: url),
                        data: data
                    )
                )
                remainingByteCount -= data.count
            } catch is AttachmentReadLimitExceededError {
                errors.append(attachmentBudgetExceededMessage(filename: displayFilename(for: url)))
            } catch {
                errors.append(attachmentReadErrorMessage(
                    filename: displayFilename(for: url),
                    error: error
                ))
            }
        }

        return ComposeAttachmentImportResult(
            attachments: attachments,
            errorMessage: combinedErrorMessage(errors)
        )
    }

    private static func safeFilename(
        suggestedName: String,
        usedFilenames: Set<String>
    ) -> String {
        let safeName = MessageAttachmentDownloadFilenamePolicy.safeFilename(
            suggestedName: suggestedName
        )
        return MessageAttachmentDownloadFilenamePolicy.uniqueFilename(
            baseName: safeName
        ) { candidate in
            usedFilenames.contains(candidate)
        }
    }

    private static func displayFilename(for url: URL) -> String {
        MessageAttachmentDownloadFilenamePolicy.safeFilename(
            suggestedName: url.lastPathComponent
        )
    }

    static func filePickerErrorMessage(for error: any Error) -> String {
        "Couldn't choose attachment: \(localizedMessage(for: error, fallback: "Unknown error."))"
    }

    private static func attachmentReadErrorMessage(filename: String, error: any Error) -> String {
        "Couldn't attach \"\(filename)\": \(localizedMessage(for: error, fallback: "Unknown error."))"
    }

    /// Maximum attachment size accepted on import (25 MB), bounding memory use
    /// and matching the limit most mail providers enforce on send.
    static let maxAttachmentByteCount = 25 * 1024 * 1024

    private static func attachmentBudgetExceededMessage(filename: String) -> String {
        "Couldn't attach \"\(filename)\": the total attachments exceed the 25 MB limit."
    }

    private static func coordinatedBoundedData(
        from url: URL,
        maxByteCount: Int
    ) throws -> Data {
        var coordinationError: NSError?
        var readResult: Result<Data, any Error>?
        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            readResult = Result {
                try boundedData(from: coordinatedURL, maxByteCount: maxByteCount)
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let readResult else {
            throw CocoaError(.fileReadUnknown)
        }
        return try readResult.get()
    }

    private static func boundedData(
        from url: URL,
        maxByteCount: Int
    ) throws -> Data {
        guard maxByteCount >= 0 else {
            throw AttachmentReadLimitExceededError()
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }

        var data = Data()
        let chunkByteCount = 64 * 1024
        while data.count <= maxByteCount {
            let allowedRead = min(chunkByteCount, maxByteCount - data.count + 1)
            guard allowedRead > 0,
                  let chunk = try file.read(upToCount: allowedRead),
                  !chunk.isEmpty
            else {
                break
            }
            data.append(chunk)
            if data.count > maxByteCount {
                throw AttachmentReadLimitExceededError()
            }
        }
        return data
    }

    private static func combinedErrorMessage(_ errors: [String]) -> String? {
        guard let first = errors.first else { return nil }
        guard errors.count > 1 else { return first }

        let remaining = errors.count - 1
        let fileLabel = remaining == 1 ? "file" : "files"
        return "\(first) \(remaining) more \(fileLabel) couldn't be added."
    }

    private static func localizedMessage(for error: any Error, fallback: String) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? fallback : message
    }

    private static func mimeType(for url: URL) -> String {
        if let utType = UTType(filenameExtension: url.pathExtension),
           let mime = utType.preferredMIMEType {
            return mime
        }
        return mimeTypeFallbacks[url.pathExtension.lowercased()] ?? "application/octet-stream"
    }

    private static let mimeTypeFallbacks = [
        "txt": "text/plain",
        "text": "text/plain",
        "md": "text/markdown",
        "csv": "text/csv",
        "html": "text/html",
        "htm": "text/html",
        "json": "application/json",
        "xml": "application/xml"
    ]
}

private struct AttachmentReadLimitExceededError: Error {}
