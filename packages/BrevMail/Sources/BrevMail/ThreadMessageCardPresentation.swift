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

enum ThreadMessageBodyPresentation: Equatable {
    case waiting
    case loading
    case error(String)
    case plainText(String)
    case attributedHTML(String)
    case richHTML(
        html: String,
        allowRemoteContent: Bool,
        showsRemoteContentBanner: Bool
    )
    case htmlFallback(String)
    case empty

    struct Context {
        let isLoading: Bool
        let errorMessage: String?
        let renderedBody: RenderedBody?
        let useRichRenderer: Bool
        let allowRemoteContent: Bool
        let showRemoteContent: Bool
    }

    static func resolve(_ context: Context) -> ThreadMessageBodyPresentation {
        if context.isLoading { return .loading }
        if let errorMessage = context.errorMessage { return .error(errorMessage) }
        guard let renderedBody = context.renderedBody else { return .waiting }

        if context.useRichRenderer, let html = renderedBody.html, !html.isEmpty {
            let remoteAllowed = context.allowRemoteContent || context.showRemoteContent
            return .richHTML(
                html: html,
                allowRemoteContent: remoteAllowed,
                showsRemoteContentBanner: !remoteAllowed && MessageRemoteContentDetector.hasRemoteAssets(html)
            )
        }

        if let html = renderedBody.html, !html.isEmpty {
            if MessageHTMLRenderPolicy.shouldImportAttributedHTML(
                html,
                useRichRenderer: context.useRichRenderer,
                allowRemoteContent: context.allowRemoteContent || context.showRemoteContent
            ) {
                return .attributedHTML(html)
            }
            if let text = renderedBody.plainText, !text.isEmpty {
                return .plainText(text)
            }
            return .htmlFallback(htmlFallback(html))
        }

        if let text = renderedBody.plainText, !text.isEmpty {
            return .plainText(text)
        }

        return .empty
    }

    static func htmlFallback(_ html: String) -> String {
        let stripped = html.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        return stripped
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ThreadCalendarInvitePresentation: Equatable {
    let attachment: Attachment
    let responseLabel: String?
    let showsActions: Bool
    let unsupportedMessage: String?

    static func resolve(
        header: MessageHeader,
        renderedBody: RenderedBody?,
        capabilities: BackendCapabilities,
        localResponse: CalendarInviteLocalResponse?
    ) -> ThreadCalendarInvitePresentation? {
        guard let attachment = renderedBody?.attachments.first(where: isCalendarInviteAttachment) else {
            return nil
        }

        let responsePresentation = CalendarInviteResponsePresentation.resolve(
            header: header,
            localResponse: localResponse
        )
        let supportsReplies = CalendarInviteReplyRouting.supportsActions(capabilities: capabilities)
        let showsActions = supportsReplies && responsePresentation?.showsActions == true

        return ThreadCalendarInvitePresentation(
            attachment: attachment,
            responseLabel: responsePresentation?.label,
            showsActions: showsActions,
            unsupportedMessage: supportsReplies ? nil : "Calendar replies require server support or an SMTP-capable account."
        )
    }

    static func isCalendarInviteAttachment(_ attachment: Attachment) -> Bool {
        attachment.mimeType.lowercased().hasPrefix("text/calendar")
            && attachment.resource != nil
    }
}
