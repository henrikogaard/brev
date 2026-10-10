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

import BrevBackend
import Foundation

/// Pure rules for getting reader attachments out of Brev: dragging a row to
/// Finder or another app, and the header's Save All action. Filename
/// sanitizing and de-duplication reuse `MessageAttachmentDownloadFilenamePolicy`
/// so every export path names files the same way.
enum MessageAttachmentExportPolicy {
    /// Seconds after which an abandoned drag staging folder is deleted.
    static let dragStagingMaxAge: TimeInterval = 3600

    /// Default folder under the app's temporary directory that holds drag staging folders.
    static var defaultDragStagingRoot: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BrevAttachmentDrag", isDirectory: true)
    }

    /// Attachments whose bytes can be fetched through the backend.
    static func exportable(_ attachments: [Attachment]) -> [Attachment] {
        attachments.filter { $0.resource != nil }
    }

    /// Save All is only useful when there is more than one file to save.
    static func showsSaveAll(for attachments: [Attachment]) -> Bool {
        exportable(attachments).count >= 2
    }

    /// Save All is disabled while another attachment download runs or message work is blocked.
    static func isSaveAllDisabled(isDownloading: Bool, isWorkBlocked: Bool) -> Bool {
        isDownloading || isWorkBlocked
    }

    /// A row can start a drag only when its bytes are fetchable and message work is not blocked.
    static func canDrag(_ attachment: Attachment, isWorkBlocked: Bool) -> Bool {
        attachment.resource != nil && !isWorkBlocked
    }

    /// Tooltip text for a row: display filename and formatted size.
    static func helpText(for attachment: Attachment) -> String {
        let size = ByteCountFormatter.string(
            fromByteCount: Int64(attachment.sizeBytes),
            countStyle: .file
        )
        return "\(MessageDetailPresentation.attachmentDisplayName(attachment.name)) — \(size)"
    }

    /// Sanitized, collision-free destination filenames, one per input attachment in order.
    /// - Parameters:
    ///   - attachments: The attachments to save into one folder.
    ///   - existsInDestination: Whether a file with that name is already in the folder.
    static func destinationNames(
        for attachments: [Attachment],
        existsInDestination: (String) -> Bool
    ) -> [String] {
        var reserved: Set<String> = []
        return attachments.map { attachment in
            let safeName = MessageAttachmentDownloadFilenamePolicy.safeFilename(
                suggestedName: attachment.name
            )
            // Lowercased: the default macOS volume format is case-insensitive.
            let name = MessageAttachmentDownloadFilenamePolicy.uniqueFilename(
                baseName: safeName
            ) { candidate in
                reserved.contains(candidate.lowercased()) || existsInDestination(candidate)
            }
            reserved.insert(name.lowercased())
            return name
        }
    }

    /// Writes attachment bytes to `<stagingRoot>/<uuid>/<sanitized filename>` so a drag
    /// delivers the original filename. Blocking file I/O: call off the main actor.
    static func stageForDrag(
        data: Data,
        filename: String,
        stagingRoot: URL = defaultDragStagingRoot
    ) throws -> URL {
        let directory = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(
            MessageAttachmentDownloadFilenamePolicy.safeFilename(suggestedName: filename)
        )
        try data.write(to: destination, options: .atomic)
        return destination
    }

    /// Deletes staging folders older than `olderThan` seconds. Best effort: errors are ignored.
    static func pruneStaleDragStaging(
        stagingRoot: URL = defaultDragStagingRoot,
        olderThan maxAge: TimeInterval = dragStagingMaxAge,
        now: Date = Date()
    ) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: stagingRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: []
        ) else {
            return
        }
        let cutoff = now.addingTimeInterval(-maxAge)
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let modified, modified < cutoff {
                try? fileManager.removeItem(at: entry)
            }
        }
    }
}
