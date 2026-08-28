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
import BrevSettings
import Foundation

struct NewMailNotificationDecision: Equatable, Sendable {
    let shouldDeliver: Bool
    let showPreviews: Bool
    let playSound: Bool
}

struct NewMailNotificationContentPayload: Equatable, Sendable {
    let title: String
    let body: String
    let threadIdentifier: String
    let categoryIdentifier: String
    let userInfo: [String: String]
    let playSound: Bool
}

struct NewMailNotificationMessagePreview: Equatable, Sendable {
    let correspondent: Correspondent
    let subject: String
    let snippet: String
    let receivedAt: Date
}

enum NewMailNotificationPolicy {
    static func decision(
        settings: NotificationSettings,
        accountID: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> NewMailNotificationDecision {
        guard settings.notificationsEnabled else {
            return suppressed(settings: settings)
        }

        let override = settings.accountOverride(for: accountID)
        guard override.notificationsEnabled else {
            return suppressed(settings: settings)
        }

        guard !isQuietHour(settings: settings, now: now, calendar: calendar) else {
            return suppressed(settings: settings)
        }

        return NewMailNotificationDecision(
            shouldDeliver: true,
            showPreviews: settings.showPreviews,
            playSound: settings.soundEnabled && override.soundEnabled
        )
    }

    private static func suppressed(settings: NotificationSettings) -> NewMailNotificationDecision {
        NewMailNotificationDecision(
            shouldDeliver: false,
            showPreviews: settings.showPreviews,
            playSound: false
        )
    }

    private static func isQuietHour(
        settings: NotificationSettings,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard settings.quietHoursEnabled else { return false }

        let start = normalizedHour(settings.quietHoursStart)
        let end = normalizedHour(settings.quietHoursEnd)
        let current = calendar.component(.hour, from: now)

        if start == end {
            return true
        }
        if start < end {
            return current >= start && current < end
        }
        return current >= start || current < end
    }

    private static func normalizedHour(_ hour: Int) -> Int {
        ((hour % 24) + 24) % 24
    }

    static func contentPayload(
        correspondent: Correspondent,
        subject: String,
        snippet: String,
        receivedAt: Date,
        messageID: String,
        accountID: String,
        folderID: String? = nil,
        sourceID: MailSourceID? = nil,
        folderName: String?,
        showPreviews: Bool,
        playSound: Bool,
        allowsInlineReply: Bool = false
    ) -> NewMailNotificationContentPayload {
        var userInfo = NotificationRoutingPolicy.userInfo(
            accountID: accountID,
            folderID: folderID,
            messageID: messageID,
            sourceID: sourceID
        )
        let categoryIdentifier = allowsInlineReply
            ? BrevLocalNotificationCenter.newMailReplyCategoryIdentifier
            : BrevLocalNotificationCenter.newMailCategoryIdentifier

        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSnippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)

        if showPreviews {
            let senderName = correspondent.displayName
            let visibleSubject = trimmedSubject.isEmpty ? "New message" : trimmedSubject

            userInfo["senderName"] = senderName
            userInfo["subject"] = visibleSubject
            if !trimmedSnippet.isEmpty {
                userInfo["snippet"] = trimmedSnippet
            }
            userInfo["date"] = iso8601Formatter.string(from: receivedAt)

            return NewMailNotificationContentPayload(
                title: senderName,
                body: visibleSubject,
                threadIdentifier: threadIdentifier(for: accountID),
                categoryIdentifier: categoryIdentifier,
                userInfo: userInfo,
                playSound: playSound
            )
        }

        return NewMailNotificationContentPayload(
            title: "New mail",
            body: folderName.map { "In \($0)" } ?? "Inbox has new mail",
            threadIdentifier: threadIdentifier(for: accountID),
            categoryIdentifier: categoryIdentifier,
            userInfo: userInfo,
            playSound: playSound
        )
    }

    static func messagePreview(
        messageID: MessageHeader.ID,
        visibleHeaders: [MessageHeader],
        cachedHeaders: [MessageHeader] = [],
        fallbackDate: Date
    ) -> NewMailNotificationMessagePreview {
        guard let header = visibleHeaders.first(where: { $0.id == messageID })
            ?? cachedHeaders.first(where: { $0.id == messageID }) else {
            return NewMailNotificationMessagePreview(
                correspondent: Correspondent(name: nil, email: ""),
                subject: "",
                snippet: "",
                receivedAt: fallbackDate
            )
        }

        return NewMailNotificationMessagePreview(
            correspondent: header.from,
            subject: header.subject,
            snippet: header.snippet,
            receivedAt: header.date
        )
    }

    private static func threadIdentifier(for accountID: String) -> String {
        "brev.newMail.\(accountID)"
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
