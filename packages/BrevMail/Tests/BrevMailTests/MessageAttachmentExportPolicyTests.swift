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
@testable import BrevMail
import Foundation
import Testing

@Suite("MessageAttachmentExportPolicy")
struct MessageAttachmentExportPolicyTests {
    private func attachment(
        _ name: String,
        id: String? = nil,
        resource: String? = "res",
        size: Int = 1024
    ) -> BrevBackend.Attachment {
        BrevBackend.Attachment(
            id: id ?? name,
            name: name,
            mimeType: "application/pdf",
            sizeBytes: size,
            resource: resource
        )
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MessageAttachmentExportPolicyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: - Which attachments qualify

    @Test("only attachments with a downloadable resource are exportable")
    func exportableRequiresResource() {
        let items = [
            attachment("a.pdf"),
            attachment("b.pdf", resource: nil),
            attachment("c.pdf")
        ]

        #expect(MessageAttachmentExportPolicy.exportable(items).map(\.name) == ["a.pdf", "c.pdf"])
    }

    @Test("Save All appears from two exportable attachments")
    func saveAllNeedsTwoExportable() {
        #expect(!MessageAttachmentExportPolicy.showsSaveAll(for: []))
        #expect(!MessageAttachmentExportPolicy.showsSaveAll(for: [attachment("a.pdf")]))
        #expect(!MessageAttachmentExportPolicy.showsSaveAll(
            for: [attachment("a.pdf"), attachment("b.pdf", resource: nil)]
        ))
        #expect(MessageAttachmentExportPolicy.showsSaveAll(
            for: [attachment("a.pdf"), attachment("b.pdf")]
        ))
    }

    @Test("Save All disables while downloading or work is blocked")
    func saveAllDisabledStates() {
        #expect(!MessageAttachmentExportPolicy.isSaveAllDisabled(isDownloading: false, isWorkBlocked: false))
        #expect(MessageAttachmentExportPolicy.isSaveAllDisabled(isDownloading: true, isWorkBlocked: false))
        #expect(MessageAttachmentExportPolicy.isSaveAllDisabled(isDownloading: false, isWorkBlocked: true))
    }

    @Test("dragging needs a resource and unblocked work")
    func dragAvailability() {
        #expect(MessageAttachmentExportPolicy.canDrag(attachment("a.pdf"), isWorkBlocked: false))
        #expect(!MessageAttachmentExportPolicy.canDrag(attachment("a.pdf"), isWorkBlocked: true))
        #expect(!MessageAttachmentExportPolicy.canDrag(attachment("a.pdf", resource: nil), isWorkBlocked: false))
    }

    // MARK: - Destination names

    @Test("destination names are sanitized")
    func destinationNamesAreSanitized() {
        let names = MessageAttachmentExportPolicy.destinationNames(
            for: [attachment("../evil/report.pdf"), attachment("   ")],
            existsInDestination: { _ in false }
        )

        #expect(names == [".._evil_report.pdf", "attachment"])
    }

    @Test("destination names never reuse a name already on disk")
    func destinationNamesAvoidExistingFiles() {
        let names = MessageAttachmentExportPolicy.destinationNames(
            for: [attachment("report.pdf")],
            existsInDestination: { $0 == "report.pdf" }
        )

        #expect(names == ["report (1).pdf"])
    }

    @Test("destination names de-duplicate within the batch")
    func destinationNamesDeduplicateWithinBatch() {
        let names = MessageAttachmentExportPolicy.destinationNames(
            for: [
                attachment("report.pdf", id: "1"),
                attachment("report.pdf", id: "2"),
                attachment("report.pdf", id: "3"),
                attachment("notes.txt", id: "4")
            ],
            existsInDestination: { $0 == "report (1).pdf" }
        )

        #expect(names == ["report.pdf", "report (2).pdf", "report (3).pdf", "notes.txt"])
    }

    // MARK: - Help text

    @Test("help text combines the display name and size")
    func helpTextIncludesNameAndSize() {
        let help = MessageAttachmentExportPolicy.helpText(
            for: attachment("report.pdf", size: 2048)
        )

        #expect(help.hasPrefix("report.pdf"))
        #expect(help.contains(ByteCountFormatter.string(fromByteCount: 2048, countStyle: .file)))
    }

    // MARK: - Drag staging

    @Test("drag staging keeps the original filename inside a unique folder")
    func dragStagingKeepsFilename() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try MessageAttachmentExportPolicy.stageForDrag(
            data: Data("one".utf8),
            filename: "Invoice 2026.pdf",
            stagingRoot: root
        )
        let second = try MessageAttachmentExportPolicy.stageForDrag(
            data: Data("two".utf8),
            filename: "Invoice 2026.pdf",
            stagingRoot: root
        )

        #expect(first.lastPathComponent == "Invoice 2026.pdf")
        #expect(second.lastPathComponent == "Invoice 2026.pdf")
        #expect(first.deletingLastPathComponent() != second.deletingLastPathComponent())
        #expect(first.path.hasPrefix(root.path))
        #expect(try Data(contentsOf: first) == Data("one".utf8))
        #expect(try Data(contentsOf: second) == Data("two".utf8))
    }

    @Test("drag staging sanitizes path separators in the filename")
    func dragStagingSanitizesFilename() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let url = try MessageAttachmentExportPolicy.stageForDrag(
            data: Data("x".utf8),
            filename: "../../escape.txt",
            stagingRoot: root
        )

        #expect(url.path.hasPrefix(root.path))
        #expect(url.lastPathComponent == ".._.._escape.txt")
    }

    @Test("pruning removes only stale staging folders")
    func pruningRemovesOnlyStaleFolders() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let stale = root.appendingPathComponent("stale", isDirectory: true)
        let fresh = root.appendingPathComponent("fresh", isDirectory: true)
        for directory in [stale, fresh] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-7200)],
            ofItemAtPath: stale.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-60)],
            ofItemAtPath: fresh.path
        )

        MessageAttachmentExportPolicy.pruneStaleDragStaging(
            stagingRoot: root,
            olderThan: 3600,
            now: now
        )

        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
    }

    @Test("pruning a missing staging root is a no-op")
    func pruningMissingRootIsNoOp() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)", isDirectory: true)

        MessageAttachmentExportPolicy.pruneStaleDragStaging(
            stagingRoot: missing,
            olderThan: 3600,
            now: Date()
        )

        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }
}
