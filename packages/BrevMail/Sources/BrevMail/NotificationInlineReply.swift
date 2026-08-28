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

enum NotificationInlineReplyComposer {
    /// Builds the same plain-text reply draft as the compose surface, without
    /// adding a quote that the user cannot see or edit from the notification.
    static func draft(
        id: String,
        userText: String,
        header: MessageHeader,
        accountEmail: String,
        signatureBody: String?,
        securityMode: OutboundMessageSecurityMode
    ) -> Draft? {
        let normalizedText = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return nil }

        let recipients = ComposeReplyResolver.recipients(
            for: header,
            mode: .sender,
            accountEmail: accountEmail
        )
        guard !recipients.isEmpty else { return nil }

        return ComposeDraftBuilder.draft(
            id: id,
            replyingTo: header,
            forwardingFrom: nil,
            to: recipients,
            cc: [],
            bcc: [],
            subject: ComposeReplyFormatter.subject(for: header.subject),
            bodyText: normalizedText,
            signatureBody: signatureBody,
            securityMode: securityMode
        )
    }
}

enum NotificationInlineReplyAvailabilityPolicy {
    /// Notification actions cannot expose Brev's in-app Undo Send affordance,
    /// so only offer immediate reply when no cancellation delay is configured.
    static func allows(undoSendDelaySeconds: Int) -> Bool {
        undoSendDelaySeconds == 0
    }
}

enum NotificationInlineReplyOutcome: Equatable, Sendable {
    case sent
    case failed(draftWasSaved: Bool)
}

enum NotificationInlineReplyPipeline {
    /// Saves first because a notification reply has no open compose surface to
    /// retain the text if SMTP delivery fails. Sending the persisted value also
    /// preserves any backend-assigned remote draft identifier.
    static func deliver(
        draft: Draft,
        save: (Draft) async throws -> Draft,
        send: (Draft) async throws -> Void
    ) async -> NotificationInlineReplyOutcome {
        let saved: Draft
        do {
            saved = try await save(draft)
        } catch {
            return .failed(draftWasSaved: false)
        }

        do {
            try await send(saved)
            return .sent
        } catch {
            return .failed(draftWasSaved: true)
        }
    }
}

struct NotificationReplyFailurePayload: Equatable, Sendable {
    let title: String
    let body: String
    let threadIdentifier: String
    let userInfo: [String: String]
}

enum NotificationReplyFailurePolicy {
    static func payload(
        route: NotificationMailRoute,
        draftWasSaved: Bool
    ) -> NotificationReplyFailurePayload {
        return NotificationReplyFailurePayload(
            title: String(localized: "Reply not sent", bundle: .module),
            body: draftWasSaved
                ? String(localized: "Your reply is saved in Drafts. Open Brev to try again.", bundle: .module)
                : String(localized: "Open Brev to review the message and try again.", bundle: .module),
            threadIdentifier: "\(route.accountID):\(route.folderID)",
            userInfo: NotificationRoutingPolicy.userInfo(for: route)
        )
    }
}
