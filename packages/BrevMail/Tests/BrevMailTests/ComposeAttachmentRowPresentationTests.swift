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

@Suite("ComposeAttachmentRowPresentation")
struct ComposeAttachmentRowPresentationTests {
    @Test("failed attachment rows expose retry and remove affordances")
    func failedRowsExposeRetryAndRemove() {
        let attachment = ComposeAttachmentUploadState.markFailed(
            PendingAttachment(
                filename: "brief.pdf",
                mimeType: "application/pdf",
                data: Data("pdf".utf8)
            ),
            message: "Network error: offline"
        )

        let presentation = ComposeAttachmentRowPresentation.presentation(for: attachment)

        #expect(presentation.filename == "brief.pdf")
        #expect(presentation.statusText == "Upload failed: Network error: offline")
        #expect(presentation.retryButtonTitle == "Retry on Send")
        #expect(presentation.removeAccessibilityLabel == "Remove brief.pdf")
    }

    @Test("uploaded attachment rows show ready copy without retry")
    func uploadedRowsShowReadyWithoutRetry() {
        let attachment = ComposeAttachmentUploadState.markUploaded(
            PendingAttachment(
                filename: "sent.pdf",
                mimeType: "application/pdf",
                data: Data("pdf".utf8)
            ),
            remoteID: "remote-1"
        )

        let presentation = ComposeAttachmentRowPresentation.presentation(for: attachment)

        #expect(presentation.statusText == "Ready to send")
        #expect(presentation.retryButtonTitle == nil)
        #expect(presentation.removeAccessibilityLabel == "Remove sent.pdf")
    }
}
