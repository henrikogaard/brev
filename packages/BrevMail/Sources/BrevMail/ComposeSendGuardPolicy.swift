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

struct ComposeSendGuardPreferences: Equatable, Sendable {
    static let attachmentReminderKey = "compose.attachmentReminderEnabled"
    static let externalRecipientWarningKey = "compose.externalRecipientWarningEnabled"

    var attachmentReminderEnabled: Bool
    var externalRecipientWarningEnabled: Bool

    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(
            attachmentReminderEnabled: bool(
                for: attachmentReminderKey,
                defaultValue: true,
                defaults: defaults
            ),
            externalRecipientWarningEnabled: bool(
                for: externalRecipientWarningKey,
                defaultValue: true,
                defaults: defaults
            )
        )
    }

    private static func bool(
        for key: String,
        defaultValue: Bool,
        defaults: UserDefaults
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }
}

struct ComposeSendGuardSnapshot: Equatable, Sendable {
    var fromEmail: String
    var to: [String]
    var cc: [String]
    var bcc: [String]
    var subject: String
    var bodyText: String
    var hasAttachments: Bool
}

enum ComposeSendGuardWarning: String, Identifiable, Equatable, Sendable {
    case missingAttachment
    case externalRecipients

    var id: String { rawValue }

    var title: String {
        switch self {
        case .missingAttachment:
            return "Send without attachment?"
        case .externalRecipients:
            return "Send to external recipients?"
        }
    }

    var message: String {
        switch self {
        case .missingAttachment:
            return "This draft mentions an attachment, but no file is attached."
        case .externalRecipients:
            return "Some recipients are outside this account's email domain."
        }
    }
}

enum ComposeSendGuardPolicy {
    static func warning(
        for snapshot: ComposeSendGuardSnapshot,
        preferences: ComposeSendGuardPreferences
    ) -> ComposeSendGuardWarning? {
        if preferences.attachmentReminderEnabled,
           !snapshot.hasAttachments,
           mentionsAttachment(subject: snapshot.subject, bodyText: snapshot.bodyText) {
            return .missingAttachment
        }

        if preferences.externalRecipientWarningEnabled,
           hasExternalRecipient(snapshot) {
            return .externalRecipients
        }

        return nil
    }

    private static func mentionsAttachment(subject: String, bodyText: String) -> Bool {
        let text = "\(subject)\n\(bodyText)".lowercased()
        let keywords = [
            "attach",
            "attached",
            "attachment",
            "attachments",
            "enclosed",
            "enclosing"
        ]
        return keywords.contains { text.contains($0) }
    }

    private static func hasExternalRecipient(_ snapshot: ComposeSendGuardSnapshot) -> Bool {
        guard let senderDomain = domain(from: snapshot.fromEmail) else { return false }
        let recipients = snapshot.to + snapshot.cc + snapshot.bcc
        return recipients.contains { recipient in
            guard let recipientDomain = domain(from: recipient) else { return false }
            return recipientDomain != senderDomain
        }
    }

    private static func domain(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let address: String
        if let start = trimmed.lastIndex(of: "<"),
           let end = trimmed[start...].firstIndex(of: ">") {
            address = String(trimmed[trimmed.index(after: start) ..< end])
        } else {
            address = trimmed
        }

        guard let atIndex = address.lastIndex(of: "@") else { return nil }
        let domain = address[address.index(after: atIndex)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return domain.isEmpty ? nil : domain
    }
}
