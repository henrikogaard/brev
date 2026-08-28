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

@testable import BrevMail
import Foundation
import Testing

@Suite("ComposeAttachmentImport")
struct ComposeAttachmentImportTests {
    @Test("readable files become pending attachments")
    func readableFilesBecomePendingAttachments() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        let data = Data("hello".utf8)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await ComposeAttachmentImport.importFiles(from: [url])

        #expect(result.attachments.count == 1)
        #expect(result.attachments.first?.filename == url.lastPathComponent)
        #expect(result.attachments.first?.mimeType == "text/plain")
        #expect(result.attachments.first?.data == data)
        #expect(result.errorMessage == nil)
    }

    @Test("files larger than the size limit are rejected, not read into memory")
    func filesLargerThanLimitAreRejected() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bin")
        try Data(repeating: 0, count: 200).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await ComposeAttachmentImport.importFiles(from: [url], maxByteCount: 100)

        #expect(result.attachments.isEmpty)
        #expect(result.errorMessage != nil)
    }

    @Test("multiple files share one total attachment budget")
    func multipleFilesShareOneTotalAttachmentBudget() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appendingPathComponent("first.bin")
        let second = directory.appendingPathComponent("second.bin")
        try Data(repeating: 1, count: 60).write(to: first)
        try Data(repeating: 2, count: 60).write(to: second)

        let result = await ComposeAttachmentImport.importFiles(
            from: [first, second],
            maxByteCount: 100
        )

        #expect(result.attachments.map(\.filename) == ["first.bin"])
        #expect(result.errorMessage != nil)
    }

    @Test("existing pending attachments count toward the total budget")
    func existingPendingAttachmentsCountTowardTotalBudget() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bin")
        try Data(repeating: 1, count: 40).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await ComposeAttachmentImport.importFiles(
            from: [url],
            existingByteCount: 70,
            maxByteCount: 100
        )

        #expect(result.attachments.isEmpty)
        #expect(result.errorMessage != nil)
    }

    @Test("readable files use safe pending attachment names")
    func readableFilesUseSafePendingAttachmentNames() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Board:notes\nfinal")
            .appendingPathExtension("txt")
        let data = Data("hello".utf8)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await ComposeAttachmentImport.importFiles(from: [url])

        #expect(result.attachments.first?.filename == "Board_notes_final.txt")
    }

    @Test("readable files with duplicate safe names are disambiguated")
    func readableFilesWithDuplicateSafeNamesAreDisambiguated() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appendingPathComponent("Budget:May.pdf")
        let second = directory.appendingPathComponent("Budget\nMay.pdf")
        try Data("one".utf8).write(to: first)
        try Data("two".utf8).write(to: second)

        let result = await ComposeAttachmentImport.importFiles(from: [first, second])

        #expect(result.attachments.map(\.filename) == [
            "Budget_May.pdf",
            "Budget_May (1).pdf"
        ])
    }

    @Test("readable files disambiguate against existing pending attachment names")
    func readableFilesDisambiguateAgainstExistingPendingAttachmentNames() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Budget\nMay")
            .appendingPathExtension("pdf")
        try Data("two".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await ComposeAttachmentImport.importFiles(
            from: [url],
            existingFilenames: ["Budget_May.pdf"]
        )

        #expect(result.attachments.map(\.filename) == ["Budget_May (1).pdf"])
    }

    @Test("readable files with blank names use attachment fallback")
    func readableFilesWithBlankNamesUseAttachmentFallback() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("   ")
        let data = Data("hello".utf8)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await ComposeAttachmentImport.importFiles(from: [url])

        #expect(result.attachments.first?.filename == "attachment")
    }

    @Test("unreadable files report a visible error")
    func unreadableFilesReportVisibleError() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")

        let result = await ComposeAttachmentImport.importFiles(from: [url])

        #expect(result.attachments.isEmpty)
        #expect(result.errorMessage?.hasPrefix("Couldn't attach \"\(url.lastPathComponent)\":") == true)
    }

    @Test("unreadable files use safe names in visible errors")
    func unreadableFilesUseSafeNamesInVisibleErrors() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Budget\nMay")
            .appendingPathExtension("pdf")

        let result = await ComposeAttachmentImport.importFiles(from: [url])

        #expect(result.attachments.isEmpty)
        #expect(result.errorMessage?.hasPrefix("Couldn't attach \"Budget_May.pdf\":") == true)
    }

    @Test("unreadable files with blank names use attachment fallback in errors")
    func unreadableFilesWithBlankNamesUseAttachmentFallbackInErrors() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("   ")

        let result = await ComposeAttachmentImport.importFiles(from: [url])

        #expect(result.attachments.isEmpty)
        #expect(result.errorMessage?.hasPrefix("Couldn't attach \"attachment\":") == true)
    }

    @Test("file picker failures report a visible error")
    func filePickerFailuresReportVisibleError() {
        let error = NSError(
            domain: "BrevTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Picker denied access."]
        )

        #expect(ComposeAttachmentImport.filePickerErrorMessage(for: error) == "Couldn't choose attachment: Picker denied access.")
    }
}
