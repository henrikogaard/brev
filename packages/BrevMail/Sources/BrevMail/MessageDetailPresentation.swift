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

struct MessageDetailStatus: Equatable, Sendable {
    let title: String
    let icon: String
    let subtitle: String
    let actionTitle: String?
}

struct MessageDetailInlineStatus: Equatable, Sendable {
    enum Tone: Equatable, Sendable {
        case danger
    }

    let message: String
    let tone: Tone
    let isDismissible: Bool
    let lineLimit: Int?
}

struct MessageReadReceiptPrompt: Equatable, Sendable {
    let title: String
    let subtitle: String
    let sendTitle: String
    let declineTitle: String
}

struct MessageReadReceiptNotificationPresentation: Equatable, Sendable {
    let title: String
    let subtitle: String
    let icon: String
}

enum MessageDetailBodyPresentation: Equatable {
    case loading
    case error(String)
    case richHTML(String)
    case remoteBlocked(html: String, plainText: String?)
    case plainText(String)
    case attributedHTML(String)
    case htmlFallback(String)
    case empty

    struct Context {
        let isLoading: Bool
        let errorMessage: String?
        let html: String?
        let plainText: String?
        let renderedHTML: AttributedString?
        let useRichRenderer: Bool
        let isRemoteContentBlocked: Bool
    }

    static func resolve(_ context: Context) -> MessageDetailBodyPresentation {
        if let errorMessage = context.errorMessage { return .error(errorMessage) }
        if context.isLoading,
           nonEmpty(context.html) == nil,
           nonEmpty(context.plainText) == nil {
            return .loading
        }

        if let html = nonEmpty(context.html) {
            if context.useRichRenderer {
                return .richHTML(html)
            }
            if context.isRemoteContentBlocked {
                if let text = nonEmpty(context.plainText) {
                    return .plainText(text)
                }
                return .remoteBlocked(html: html, plainText: nonEmpty(context.plainText))
            }
            if context.renderedHTML != nil {
                return .attributedHTML(html)
            }
        }

        if let text = nonEmpty(context.plainText) {
            return .plainText(text)
        }
        if let html = nonEmpty(context.html) {
            return .htmlFallback(html)
        }
        return .empty
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

enum MessageOpenVisibilityStage: Equatable {
    case bodyState
    case webView
}

enum MessageOpenRenderCompletionPolicy {
    static func stage(hasHTML: Bool, usesRichRenderer: Bool) -> MessageOpenVisibilityStage {
        hasHTML && usesRichRenderer ? .webView : .bodyState
    }
}

enum MessageDetailPresentation {
    static func readReceiptPrompt(for request: ReadReceiptRequest) -> MessageReadReceiptPrompt {
        _ = request
        return MessageReadReceiptPrompt(
            title: "Read receipt requested",
            subtitle: "The sender asked to be notified that you opened this message. Brev will only send a receipt if you choose to.",
            sendTitle: "Send Receipt",
            declineTitle: "Decline"
        )
    }

    static func readReceiptNotification(
        _ notification: ReadReceiptNotification
    ) -> MessageReadReceiptNotificationPresentation {
        MessageReadReceiptNotificationPresentation(
            title: "Read receipt received",
            subtitle: readReceiptNotificationSubtitle(notification),
            icon: "checkmark.seal"
        )
    }

    static func sentReadReceiptNotification(
        _ records: [MessageReadReceiptNotificationRecord]
    ) -> MessageReadReceiptNotificationPresentation {
        if records.count == 1, let record = records.first {
            return MessageReadReceiptNotificationPresentation(
                title: "Read receipt received",
                subtitle: sentReadReceiptNotificationSubtitle(record),
                icon: "checkmark.seal"
            )
        }
        return MessageReadReceiptNotificationPresentation(
            title: "Read receipts received",
            subtitle: "\(records.count) recipients sent read receipts for this message.",
            icon: "checkmark.seal"
        )
    }

    static func displayPlainText(bodyPlainText: String?, fallbackSnippet: String) -> String? {
        let body = bodyPlainText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let body, !body.isEmpty {
            return bodyPlainText
        }
        let snippet = fallbackSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        return snippet.isEmpty ? nil : fallbackSnippet
    }

    static func displayBody(
        loaded: MessageBody,
        rendered: RenderedBody,
        fallbackSnippet: String
    ) -> MessageBody {
        MessageBody(
            messageID: loaded.messageID,
            html: rendered.html,
            plainText: displayPlainText(
                bodyPlainText: rendered.plainText,
                fallbackSnippet: fallbackSnippet
            ),
            attachments: rendered.attachments,
            listUnsubscribe: loaded.listUnsubscribe,
            readReceiptRequest: loaded.readReceiptRequest,
            readReceiptNotification: loaded.readReceiptNotification,
            authenticationResults: loaded.authenticationResults
        )
    }

    static func previewFallbackPlainText(_ snippet: String) -> String? {
        let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : snippet
    }

    static func bodyLoadErrorMessage(for error: any Error) -> String {
        localizedMessage(for: error, fallback: "Couldn't load message body.")
    }

    static func attachmentDisplayName(_ filename: String) -> String {
        safeDisplayFilename(filename)
    }

    static func attachmentDownloadErrorMessage(filename: String, error: any Error) -> String {
        "Couldn't download \"\(attachmentDisplayName(filename))\": \(localizedMessage(for: error, fallback: "Unknown error."))"
    }

    static func attachmentDownloadErrorStatus(filename: String, error: any Error) -> MessageDetailInlineStatus {
        MessageDetailInlineStatus(
            message: attachmentDownloadErrorMessage(filename: filename, error: error),
            tone: .danger,
            isDismissible: true,
            lineLimit: nil
        )
    }

    static func bodyLoadErrorStatus(_ message: String) -> MessageDetailStatus {
        MessageDetailStatus(
            title: "Couldn't load message",
            icon: "exclamationmark.triangle",
            subtitle: message,
            actionTitle: "Try Again"
        )
    }

    static func markReadErrorStatus(for error: any Error) -> MessageDetailStatus {
        MessageDetailStatus(
            title: "Couldn't mark as read",
            icon: "exclamationmark.triangle",
            subtitle: localizedMessage(for: error, fallback: "Couldn't mark this message as read."),
            actionTitle: "Try Again"
        )
    }

    static func inviteResponseErrorStatus(for error: any Error) -> MessageDetailStatus {
        MessageDetailStatus(
            title: "Couldn't respond to invite",
            icon: "exclamationmark.triangle",
            subtitle: localizedMessage(for: error, fallback: "Couldn't send your invite response."),
            actionTitle: "Try Again"
        )
    }

    static func inviteLoadErrorStatus(for error: any Error) -> MessageDetailStatus {
        MessageDetailStatus(
            title: "Couldn't load calendar invite",
            icon: "exclamationmark.triangle",
            subtitle: localizedMessage(for: error, fallback: "Couldn't load the calendar invite."),
            actionTitle: "Try Again"
        )
    }

    static func inviteParseErrorStatus(filename: String) -> MessageDetailStatus {
        MessageDetailStatus(
            title: "Couldn't read calendar invite",
            icon: "exclamationmark.triangle",
            subtitle: "Brev couldn't parse \"\(attachmentDisplayName(filename))\" as a calendar invite.",
            actionTitle: "Try Again"
        )
    }

    private static func safeDisplayFilename(_ filename: String) -> String {
        MessageAttachmentDownloadFilenamePolicy.safeFilename(
            suggestedName: filename
        )
    }

    private static func readReceiptNotificationSubtitle(
        _ notification: ReadReceiptNotification
    ) -> String {
        let action = readReceiptDispositionAction(notification.disposition)
        let recipient = nonEmpty(notification.finalRecipient)
        let originalMessageID = nonEmpty(notification.originalMessageID)

        switch (recipient, originalMessageID) {
        case (let recipient?, let originalMessageID?):
            return "\(recipient) \(action) \(originalMessageID)."
        case (let recipient?, nil):
            return "\(recipient) \(action) the message."
        case (nil, let originalMessageID?):
            return "The recipient \(action) \(originalMessageID)."
        case (nil, nil):
            return "The recipient \(action) the message."
        }
    }

    private static func sentReadReceiptNotificationSubtitle(
        _ record: MessageReadReceiptNotificationRecord
    ) -> String {
        let action = readReceiptDispositionAction(record.disposition)
        if let recipient = nonEmpty(record.finalRecipient) {
            return "\(recipient) \(action) this message."
        }
        return "The recipient \(action) this message."
    }

    private static func readReceiptDispositionAction(_ disposition: String) -> String {
        let components = disposition
            .split(separator: ";", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let last = components.last, !last.isEmpty else {
            return "reported receipt for"
        }
        return last.lowercased()
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func localizedMessage(for error: any Error, fallback: String) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? fallback : message
    }
}
