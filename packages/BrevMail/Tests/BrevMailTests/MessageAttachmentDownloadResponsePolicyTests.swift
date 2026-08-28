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

@Suite("MessageAttachmentDownloadResponsePolicy")
struct MessageAttachmentDownloadResponsePolicyTests {
    @Test("attachment download can start when no download is active")
    func attachmentDownloadCanStartWhenNoDownloadIsActive() {
        #expect(MessageAttachmentDownloadStartPolicy.canStartDownload(
            activeRequest: nil,
            isBlocked: false
        ))
    }

    @Test("attachment download cannot start while another download is active")
    func attachmentDownloadCannotStartWhileAnotherDownloadIsActive() {
        #expect(!MessageAttachmentDownloadStartPolicy.canStartDownload(
            activeRequest: MessageAttachmentDownloadRequest(messageID: "message-1", attachmentID: "a1"),
            isBlocked: false
        ))
    }

    @Test("attachment download cannot start while root work is active")
    func attachmentDownloadCannotStartWhileRootWorkIsActive() {
        #expect(!MessageAttachmentDownloadStartPolicy.canStartDownload(
            activeRequest: nil,
            isBlocked: true
        ))
    }

    @Test("matching active message and attachment can apply a download response")
    func matchingActiveMessageAndAttachmentCanApplyDownloadResponse() {
        #expect(MessageAttachmentDownloadResponsePolicy.canApplyResponse(
            request: MessageAttachmentDownloadRequest(messageID: "message-1", attachmentID: "a1"),
            activeRequest: MessageAttachmentDownloadRequest(messageID: "message-1", attachmentID: "a1"),
            currentMessageID: "message-1"
        ))
    }

    @Test("message attachment or request changes reject a stale download response")
    func messageAttachmentOrRequestChangesRejectStaleDownloadResponse() {
        let request = MessageAttachmentDownloadRequest(messageID: "message-1", attachmentID: "a1")

        #expect(!MessageAttachmentDownloadResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: MessageAttachmentDownloadRequest(messageID: "message-2", attachmentID: "a1"),
            currentMessageID: "message-1"
        ))
        #expect(!MessageAttachmentDownloadResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: MessageAttachmentDownloadRequest(messageID: "message-1", attachmentID: "a2"),
            currentMessageID: "message-1"
        ))
        #expect(!MessageAttachmentDownloadResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentMessageID: "message-2"
        ))
        #expect(!MessageAttachmentDownloadResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentMessageID: nil
        ))
    }

    @Test("safe download filenames preserve readable names")
    func safeDownloadFilenamesPreserveReadableNames() {
        #expect(MessageAttachmentDownloadFilenamePolicy.safeFilename(
            suggestedName: "Board notes.pdf"
        ) == "Board notes.pdf")
    }

    @Test("safe download filenames replace path and control characters")
    func safeDownloadFilenamesReplacePathAndControlCharacters() {
        #expect(MessageAttachmentDownloadFilenamePolicy.safeFilename(
            suggestedName: "reports/May:final\ncopy.txt"
        ) == "reports_May_final_copy.txt")
    }

    @Test("safe download filenames fall back for blank or directory names")
    func safeDownloadFilenamesFallbackForBlankOrDirectoryNames() {
        #expect(MessageAttachmentDownloadFilenamePolicy.safeFilename(
            suggestedName: ""
        ) == "attachment")
        #expect(MessageAttachmentDownloadFilenamePolicy.safeFilename(
            suggestedName: "   "
        ) == "attachment")
        #expect(MessageAttachmentDownloadFilenamePolicy.safeFilename(
            suggestedName: "."
        ) == "attachment")
        #expect(MessageAttachmentDownloadFilenamePolicy.safeFilename(
            suggestedName: ".."
        ) == "attachment")
    }

    @Test("safe download filenames are bounded and preserve extensions")
    func safeDownloadFilenamesAreBoundedAndPreserveExtensions() {
        let longStem = String(repeating: "a", count: 260)

        let safeName = MessageAttachmentDownloadFilenamePolicy.safeFilename(
            suggestedName: "\(longStem).pdf"
        )

        #expect(safeName.count <= 180)
        #expect(safeName.hasSuffix(".pdf"))
    }

    @Test("safe download filenames without extensions are bounded")
    func safeDownloadFilenamesWithoutExtensionsAreBounded() {
        let safeName = MessageAttachmentDownloadFilenamePolicy.safeFilename(
            suggestedName: String(repeating: "b", count: 260)
        )

        #expect(safeName.count <= 180)
    }

    @Test("duplicate safe filenames stay bounded and preserve extensions")
    func duplicateSafeFilenamesStayBoundedAndPreserveExtensions() {
        let safeBaseName = MessageAttachmentDownloadFilenamePolicy.safeFilename(
            suggestedName: "\(String(repeating: "c", count: 260)).pdf"
        )

        let duplicateName = MessageAttachmentDownloadFilenamePolicy.uniqueFilename(
            baseName: safeBaseName
        ) { candidate in
            candidate == safeBaseName
        }

        #expect(duplicateName.count <= 180)
        #expect(duplicateName.hasSuffix(".pdf"))
        #expect(duplicateName.contains(" (1)."))
    }

    @Test("duplicate extensionless safe filenames stay bounded")
    func duplicateExtensionlessSafeFilenamesStayBounded() {
        let safeBaseName = MessageAttachmentDownloadFilenamePolicy.safeFilename(
            suggestedName: String(repeating: "d", count: 260)
        )

        let duplicateName = MessageAttachmentDownloadFilenamePolicy.uniqueFilename(
            baseName: safeBaseName
        ) { candidate in
            candidate == safeBaseName
        }

        #expect(duplicateName.count <= 180)
        #expect(duplicateName.hasSuffix(" (1)"))
    }

    @Test("duplicate safe filenames with long extensions still change names")
    func duplicateSafeFilenamesWithLongExtensionsStillChangeNames() {
        let safeBaseName = MessageAttachmentDownloadFilenamePolicy.safeFilename(
            suggestedName: "a.\(String(repeating: "e", count: 300))"
        )
        var baseChecks = 0

        let duplicateName = MessageAttachmentDownloadFilenamePolicy.uniqueFilename(
            baseName: safeBaseName
        ) { candidate in
            if candidate == safeBaseName {
                baseChecks += 1
                return baseChecks == 1
            }
            return false
        }

        #expect(duplicateName.count <= 180)
        #expect(duplicateName != safeBaseName)
        #expect(duplicateName.hasSuffix(" (1)"))
    }

    @Test("attachment downloads stage in temporary storage instead of Downloads")
    func attachmentDownloadsStageInTemporaryStorageInsteadOfDownloads() {
        let temporary = URL(fileURLWithPath: "/tmp/brev-attachments", isDirectory: true)

        #expect(MessageAttachmentDownloadStoragePolicy.directory(
            purpose: .previewOrOpen,
            temporaryDirectory: temporary
        ) == temporary)
        #expect(MessageAttachmentDownloadStoragePolicy.directory(
            purpose: .savePanelStaging,
            temporaryDirectory: temporary
        ) == temporary)
    }

    @Test("cached staged attachment URLs are reused only while the file exists")
    func cachedStagedAttachmentURLsAreReusedOnlyWhileFileExists() {
        let cached = URL(fileURLWithPath: "/tmp/brev-attachments/invoice.pdf")

        #expect(MessageAttachmentDownloadedFilePolicy.reusableCachedURL(
            cached,
            fileExists: { $0 == cached }
        ) == cached)
        #expect(MessageAttachmentDownloadedFilePolicy.reusableCachedURL(
            cached,
            fileExists: { _ in false }
        ) == nil)
        #expect(MessageAttachmentDownloadedFilePolicy.reusableCachedURL(
            nil,
            fileExists: { _ in true }
        ) == nil)
    }
}
