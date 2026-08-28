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

struct ComposeAttachmentRowPresentation: Equatable {
    let filename: String
    let formattedSize: String
    let statusText: String?
    let retryButtonTitle: String?
    let removeAccessibilityLabel: String

    static func presentation(for attachment: PendingAttachment) -> ComposeAttachmentRowPresentation {
        ComposeAttachmentRowPresentation(
            filename: attachment.filename,
            formattedSize: attachment.formattedSize,
            statusText: statusText(for: attachment),
            retryButtonTitle: ComposeAttachmentUploadState.retryActionTitle(for: attachment),
            removeAccessibilityLabel: "Remove \(attachment.filename)"
        )
    }

    private static func statusText(for attachment: PendingAttachment) -> String? {
        if let statusText = ComposeAttachmentUploadState.statusText(for: attachment) {
            return statusText
        }
        if attachment.uploadedAttachmentID != nil {
            return "Ready to send"
        }
        return nil
    }
}
