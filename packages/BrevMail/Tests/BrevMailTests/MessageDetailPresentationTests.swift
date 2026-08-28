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

@Suite("MessageDetailPresentation")
struct MessageDetailPresentationTests {
    @Test("rich HTML completes message-open timing only after WebKit finishes")
    func richHTMLWaitsForWebKitVisibility() {
        #expect(
            MessageOpenRenderCompletionPolicy.stage(hasHTML: true, usesRichRenderer: true)
                == .webView
        )
        #expect(
            MessageOpenRenderCompletionPolicy.stage(hasHTML: true, usesRichRenderer: false)
                == .bodyState
        )
        #expect(
            MessageOpenRenderCompletionPolicy.stage(hasHTML: false, usesRichRenderer: true)
                == .bodyState
        )
    }

    @Test("read receipt prompt asks before sending")
    func readReceiptPromptAsksBeforeSending() {
        let prompt = MessageDetailPresentation.readReceiptPrompt(
            for: ReadReceiptRequest(notificationTo: "sender@example.org")
        )

        #expect(prompt == MessageReadReceiptPrompt(
            title: "Read receipt requested",
            subtitle: "The sender asked to be notified that you opened this message. Brev will only send a receipt if you choose to.",
            sendTitle: "Send Receipt",
            declineTitle: "Decline"
        ))
    }

    @Test("received read receipt explains the original message")
    func receivedReadReceiptExplainsOriginalMessage() {
        let presentation = MessageDetailPresentation.readReceiptNotification(
            ReadReceiptNotification(
                finalRecipient: "reader@example.com",
                originalMessageID: "<original@example.org>",
                disposition: "manual-action/MDN-sent-manually; displayed"
            )
        )

        #expect(presentation == MessageReadReceiptNotificationPresentation(
            title: "Read receipt received",
            subtitle: "reader@example.com displayed <original@example.org>.",
            icon: "checkmark.seal"
        ))
    }

    @Test("sent message read receipt explains who displayed it")
    func sentMessageReadReceiptExplainsWhoDisplayedIt() {
        let presentation = MessageDetailPresentation.sentReadReceiptNotification([
            MessageReadReceiptNotificationRecord(
                originalMessageID: "<original@example.org>",
                finalRecipient: "reader@example.com",
                disposition: "manual-action/MDN-sent-manually; displayed",
                receiptMessageID: "INBOX:42",
                receivedAt: Date(timeIntervalSince1970: 1800)
            )
        ])

        #expect(presentation == MessageReadReceiptNotificationPresentation(
            title: "Read receipt received",
            subtitle: "reader@example.com displayed this message.",
            icon: "checkmark.seal"
        ))
    }

    @Test("display body preserves read receipt metadata from loaded message")
    func displayBodyPreservesReadReceiptMetadata() {
        let loaded = MessageBody(
            messageID: "receipt-message",
            html: "<p>Raw</p>",
            plainText: "Raw",
            readReceiptRequest: ReadReceiptRequest(notificationTo: "sender@example.org"),
            readReceiptNotification: ReadReceiptNotification(
                finalRecipient: "reader@example.com",
                originalMessageID: "<original@example.org>",
                disposition: "manual-action/MDN-sent-manually; displayed"
            ),
            authenticationResults: "mx.example.org; dmarc=pass"
        )
        let rendered = RenderedBody(
            html: "<p>Rendered</p>",
            plainText: "Rendered",
            attachments: []
        )

        let displayBody = MessageDetailPresentation.displayBody(
            loaded: loaded,
            rendered: rendered,
            fallbackSnippet: "Preview"
        )

        #expect(displayBody.html == "<p>Rendered</p>")
        #expect(displayBody.plainText == "Rendered")
        #expect(displayBody.readReceiptRequest == loaded.readReceiptRequest)
        #expect(displayBody.readReceiptNotification == loaded.readReceiptNotification)
        #expect(displayBody.authenticationResults == loaded.authenticationResults)
    }

    @Test("body load errors include a retry action")
    func bodyLoadErrorsIncludeRetryAction() {
        #expect(MessageDetailPresentation.bodyLoadErrorStatus(
            "The server timed out."
        ) == MessageDetailStatus(
            title: "Couldn't load message",
            icon: "exclamationmark.triangle",
            subtitle: "The server timed out.",
            actionTitle: "Try Again"
        ))
    }

    @Test("body load errors keep localized backend messages")
    func bodyLoadErrorsKeepLocalizedBackendMessages() {
        #expect(MessageDetailPresentation.bodyLoadErrorMessage(
            for: MailBackendError.network(underlying: "offline")
        ) == "Network error: offline")
    }

    @Test("empty body falls back to selected header snippet")
    func emptyBodyFallsBackToSelectedHeaderSnippet() {
        #expect(MessageDetailPresentation.displayPlainText(
            bodyPlainText: nil,
            fallbackSnippet: "ai\nhttps://t3.codes"
        ) == "ai\nhttps://t3.codes")
        #expect(MessageDetailPresentation.displayPlainText(
            bodyPlainText: "Full body",
            fallbackSnippet: "Preview"
        ) == "Full body")
        #expect(MessageDetailPresentation.displayPlainText(
            bodyPlainText: "  ",
            fallbackSnippet: "  "
        ) == nil)
    }

    @Test("preview fallback ignores blank snippets")
    func previewFallbackIgnoresBlankSnippets() {
        #expect(MessageDetailPresentation.previewFallbackPlainText("Preview copy") == "Preview copy")
        #expect(MessageDetailPresentation.previewFallbackPlainText("  \n ") == nil)
    }

    @Test("available preview text is shown while the full body loads")
    func availablePreviewTextIsShownWhileFullBodyLoads() {
        let presentation = MessageDetailBodyPresentation.resolve(
            MessageDetailBodyPresentation.Context(
                isLoading: true,
                errorMessage: nil,
                html: nil,
                plainText: "Cached preview",
                renderedHTML: nil,
                useRichRenderer: true,
                isRemoteContentBlocked: false
            )
        )

        #expect(presentation == .plainText("Cached preview"))
    }

    @Test("safe HTML body is preferred over plain alternative")
    func safeHTMLBodyIsPreferredOverPlainAlternative() {
        let presentation = MessageDetailBodyPresentation.resolve(
            MessageDetailBodyPresentation.Context(
                isLoading: false,
                errorMessage: nil,
                html: "<p><strong>Hello</strong> <em>Henrik</em></p>",
                plainText: "Hello Henrik",
                renderedHTML: AttributedString("Hello Henrik"),
                useRichRenderer: false,
                isRemoteContentBlocked: false
            )
        )

        #expect(presentation == .attributedHTML("<p><strong>Hello</strong> <em>Henrik</em></p>"))
    }

    @Test("attachment download errors include filename and localized backend message")
    func attachmentDownloadErrorsIncludeFilenameAndLocalizedBackendMessage() {
        #expect(MessageDetailPresentation.attachmentDownloadErrorMessage(
            filename: "invoice.pdf",
            error: MailBackendError.rateLimited(retryAfter: 4)
        ) == "Couldn't download \"invoice.pdf\": Rate limited. Try again in 4 seconds.")
    }

    @Test("attachment download errors use safe display filenames")
    func attachmentDownloadErrorsUseSafeDisplayFilenames() {
        #expect(MessageDetailPresentation.attachmentDownloadErrorMessage(
            filename: "reports/May:final\ncopy.pdf",
            error: MailBackendError.network(underlying: "offline")
        ) == "Couldn't download \"reports_May_final_copy.pdf\": Network error: offline")
    }

    @Test("attachment download errors fall back for blank display filenames")
    func attachmentDownloadErrorsFallbackForBlankDisplayFilenames() {
        #expect(MessageDetailPresentation.attachmentDownloadErrorMessage(
            filename: "   ",
            error: MailBackendError.network(underlying: "offline")
        ) == "Couldn't download \"attachment\": Network error: offline")
    }

    @Test("attachment rows use safe display filenames")
    func attachmentRowsUseSafeDisplayFilenames() {
        #expect(MessageDetailPresentation.attachmentDisplayName(
            "reports/May:final\ncopy.pdf"
        ) == "reports_May_final_copy.pdf")
        #expect(MessageDetailPresentation.attachmentDisplayName("   ") == "attachment")
    }

    @Test("attachment download errors render as dismissible danger inline status")
    func attachmentDownloadErrorsRenderAsDismissibleDangerInlineStatus() {
        let status = MessageDetailPresentation.attachmentDownloadErrorStatus(
            filename: "invoice.pdf",
            error: MailBackendError.network(underlying: "offline")
        )

        #expect(status == MessageDetailInlineStatus(
            message: "Couldn't download \"invoice.pdf\": Network error: offline",
            tone: .danger,
            isDismissible: true,
            lineLimit: nil
        ))
    }

    @Test("mark-read errors include a retry action and localized backend message")
    func markReadErrorsIncludeRetryActionAndLocalizedBackendMessage() {
        #expect(MessageDetailPresentation.markReadErrorStatus(
            for: MailBackendError.network(underlying: "offline")
        ) == MessageDetailStatus(
            title: "Couldn't mark as read",
            icon: "exclamationmark.triangle",
            subtitle: "Network error: offline",
            actionTitle: "Try Again"
        ))
    }

    @Test("mark-read errors fall back to a specific message")
    func markReadErrorsFallBackToSpecificMessage() {
        #expect(MessageDetailPresentation.markReadErrorStatus(
            for: NSError(domain: "BrevTests", code: 1, userInfo: [NSLocalizedDescriptionKey: " "])
        ).subtitle == "Couldn't mark this message as read.")
    }

    @Test("invite response errors include a retry action and localized backend message")
    func inviteResponseErrorsIncludeRetryActionAndLocalizedBackendMessage() {
        #expect(MessageDetailPresentation.inviteResponseErrorStatus(
            for: MailBackendError.network(underlying: "offline")
        ) == MessageDetailStatus(
            title: "Couldn't respond to invite",
            icon: "exclamationmark.triangle",
            subtitle: "Network error: offline",
            actionTitle: "Try Again"
        ))
    }

    @Test("invite response errors fall back to a specific message")
    func inviteResponseErrorsFallBackToSpecificMessage() {
        #expect(MessageDetailPresentation.inviteResponseErrorStatus(
            for: NSError(domain: "BrevTests", code: 1, userInfo: [NSLocalizedDescriptionKey: " "])
        ).subtitle == "Couldn't send your invite response.")
    }

    @Test("invite load errors include retry action and localized backend message")
    func inviteLoadErrorsIncludeRetryActionAndLocalizedBackendMessage() {
        #expect(MessageDetailPresentation.inviteLoadErrorStatus(
            for: MailBackendError.network(underlying: "offline")
        ) == MessageDetailStatus(
            title: "Couldn't load calendar invite",
            icon: "exclamationmark.triangle",
            subtitle: "Network error: offline",
            actionTitle: "Try Again"
        ))
    }

    @Test("invite parse errors mention the attachment filename")
    func inviteParseErrorsMentionTheAttachmentFilename() {
        #expect(MessageDetailPresentation.inviteParseErrorStatus(
            filename: "meeting.ics"
        ) == MessageDetailStatus(
            title: "Couldn't read calendar invite",
            icon: "exclamationmark.triangle",
            subtitle: "Brev couldn't parse \"meeting.ics\" as a calendar invite.",
            actionTitle: "Try Again"
        ))
    }

    @Test("invite parse errors use safe display filenames")
    func inviteParseErrorsUseSafeDisplayFilenames() {
        #expect(MessageDetailPresentation.inviteParseErrorStatus(
            filename: "calendar:reply\nmaybe.ics"
        ) == MessageDetailStatus(
            title: "Couldn't read calendar invite",
            icon: "exclamationmark.triangle",
            subtitle: "Brev couldn't parse \"calendar_reply_maybe.ics\" as a calendar invite.",
            actionTitle: "Try Again"
        ))
    }
}
