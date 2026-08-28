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

enum MailboxChatScope: Equatable, Sendable {
    case sender(email: String)
    case folder
    case account
}

enum MailboxChatTurnKind: Equatable, Sendable {
    case user(String)
    case answer(text: String, citations: [MailboxChatCitation], providerLabel: String)
    case actionReview(MailboxActionAgentPlan, providerLabel: String)
    case clarification(text: String, providerLabel: String)
    case error(text: String, providerLabel: String)
}

struct MailboxChatCitation: Equatable, Identifiable, Sendable {
    var id: String
    var folderID: String
    var sourceID: MailSourceID?
    var subject: String
    var date: Date

    var recentItem: SenderContextRecentItem {
        SenderContextRecentItem(
            id: id,
            folderID: folderID,
            subject: subject,
            date: date,
            folderName: nil,
            sourceID: sourceID
        )
    }
}

enum MailboxChatRoute: Equatable, Sendable {
    case answer
    case action
}

enum MailboxChatIntentRouter {
    static func classify(_ userText: String) -> MailboxChatRoute {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .answer
        }

        let planner = MailboxActionAgentPlanner()
        let planningResult = planner.plan(
            request: trimmed,
            headers: [],
            folders: [],
            focusedFolder: nil
        )

        switch planningResult {
        case .clarificationRequired(.unsupportedRequest):
            return matchesActionVerb(in: trimmed) ? .action : .answer
        case .planned, .clarificationRequired:
            return .action
        }
    }

    private static func matchesActionVerb(in request: String) -> Bool {
        let lowercased = request.lowercased()
        if lowercased.contains("delete")
            || lowercased.contains("remove")
            || lowercased.contains("trash") {
            return true
        }
        if lowercased.contains("move") {
            return true
        }
        if lowercased.contains("archive") {
            return true
        }
        if lowercased.contains("mark"), lowercased.contains("unread") {
            return true
        }
        if lowercased.contains("mark"), lowercased.contains("read") {
            return true
        }
        if lowercased.contains("unflag") {
            return true
        }
        if lowercased.contains("flag") {
            return true
        }
        return false
    }
}
