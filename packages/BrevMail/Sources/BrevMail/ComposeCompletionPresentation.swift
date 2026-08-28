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

/// Where compose completion feedback should appear in the mail chrome.
enum ComposeCompletionFeedback: Equatable, Sendable {
    /// Sticky/actionable top rail via `MailRootStatus`.
    case topStatus(MailRootStatus)
    /// Ephemeral bottom toast (benign success).
    case toast(message: String, tone: MailRootStatus.Tone)
}

enum ComposeCompletionPresentation {
    /// Maps a compose completion to rail or toast feedback.
    static func feedback(for completion: ComposeCompletion) -> ComposeCompletionFeedback? {
        switch completion {
        case .savedDraft:
            return .toast(message: "Draft saved.", tone: .success)
        case .sentMessage(_, let result, _):
            if result.warnings.contains(.sentCopyAppendFailed) {
                return .topStatus(MailRootStatus(
                    message: "Message sent, but Brev couldn't save a copy to Sent.",
                    tone: .warning
                ))
            }
            if result.warnings.contains(.remoteDraftCleanupFailed) {
                return .topStatus(MailRootStatus(
                    message: "Message sent, but Brev couldn't remove the saved draft.",
                    tone: .warning
                ))
            }
            if result.warnings.contains(.queuedForRetry) {
                return .topStatus(MailRootStatus(
                    message: "Message queued in Outbox and will retry when the account is online.",
                    tone: .warning
                ))
            }
            guard let scheduledFor = result.scheduledFor else { return nil }
            return .toast(
                message: "Message scheduled for \(ScheduleSendDateResolver.formattedScheduleDate(scheduledFor)).",
                tone: .success
            )
        }
    }

    /// Top-rail statuses only (warnings). Prefer `feedback(for:)` at call sites.
    static func status(for completion: ComposeCompletion) -> MailRootStatus? {
        guard case .topStatus(let status) = feedback(for: completion) else {
            return nil
        }
        return status
    }
}
