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
import BrevDesign
import Foundation

/// Visual grouping for real conversation cards inside an Assistant answer (#294).
enum AssistantCardSectionKind: String, CaseIterable, Identifiable, Sendable {
    case needsYou
    case worthALook
    case updatesAndNewsletters

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsYou: String(localized: "Needs you", bundle: .module)
        case .worthALook: String(localized: "Worth a look", bundle: .module)
        case .updatesAndNewsletters: String(localized: "Updates & newsletters", bundle: .module)
        }
    }
}

/// Deterministic tags derived strictly from local message state (#294).
enum AssistantCardTag: String, Hashable, Identifiable, Sendable {
    case urgent
    case reply
    case read

    var id: String { rawValue }

    var title: String {
        switch self {
        case .urgent: String(localized: "Urgent", bundle: .module)
        case .reply: String(localized: "Reply", bundle: .module)
        case .read: String(localized: "Read", bundle: .module)
        }
    }
}

/// A real local conversation card shown inside an Assistant answer (#294, ADR-0047).
/// Every card traces directly back to a cached `MailboxChatCitation` from local search.
struct AssistantConversationCard: Identifiable, Equatable, Sendable {
    let messageID: MessageHeader.ID
    let folderID: Folder.ID
    let sourceID: MailSourceID?
    let senderName: String
    let senderEmail: String
    let subject: String
    let snippet: String
    let date: Date
    let section: AssistantCardSectionKind
    let tags: [AssistantCardTag]
    let citation: MailboxChatCitation

    var id: String {
        "\(sourceID?.accountID ?? "_")|\(sourceID?.mailboxID ?? "_")|\(folderID)|\(messageID)"
    }
}

/// A group of conversation cards sharing a section heading.
struct AssistantAnswerSection: Identifiable, Equatable, Sendable {
    let kind: AssistantCardSectionKind
    let cards: [AssistantConversationCard]

    var id: String { kind.id }
}

/// Follow-up and confirmed action chips shown below an Assistant answer (#294).
enum AssistantAnswerActionChip: Identifiable, Equatable, Sendable {
    case reply(senderName: String, card: AssistantConversationCard)
    case followUpPrompt(String)
    case archiveUpdates(count: Int, cards: [AssistantConversationCard])

    var id: String {
        switch self {
        case .reply(_, let card): "reply:\(card.id)"
        case .followUpPrompt(let prompt): "prompt:\(prompt)"
        case .archiveUpdates(let count, _): "archive-updates:\(count)"
        }
    }

    var title: String {
        switch self {
        case .reply(let senderName, _):
            String(format: String(localized: "Reply to %@…", bundle: .module), senderName)
        case .followUpPrompt(let prompt):
            prompt
        case .archiveUpdates(let count, _):
            String(format: String(localized: "Archive all %lld", bundle: .module), Int64(count))
        }
    }
}

/// Structured presentation of an Assistant answer's real conversation cards,
/// summary chips, and action chips (#294).
struct AssistantAnswerPresentation: Equatable, Sendable {
    let summaryChips: [String]
    let sections: [AssistantAnswerSection]
    let actionChips: [AssistantAnswerActionChip]
}

/// Pure local builder that turns grounded `MailboxChatCitation`s into structured
/// answer cards without inventing any messages (#294, ADR-0047).
enum AssistantAnswerCardsBuilder {
    static func build(
        citations: [MailboxChatCitation],
        locale: Locale = .current
    ) -> AssistantAnswerPresentation {
        var needsYou: [AssistantConversationCard] = []
        var worthALook: [AssistantConversationCard] = []
        var updates: [AssistantConversationCard] = []

        for citation in citations {
            let senderEmail = citation.senderEmail ?? ""
            let senderName = (citation.senderName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? (citation.senderName ?? senderEmail)
                : (senderEmail.isEmpty ? citation.subject : senderEmail)

            let syntheticHeader = MessageHeader(
                id: citation.id,
                threadID: citation.id,
                folderID: citation.folderID,
                from: Correspondent(name: citation.senderName, email: senderEmail),
                subject: citation.subject,
                snippet: citation.snippet ?? "",
                date: citation.date,
                isRead: citation.isRead,
                isFlagged: citation.isFlagged,
                isAnswered: citation.isAnswered
            )
            let category = InboxClassificationPolicy.classification(
                for: syntheticHeader,
                sourceID: citation.sourceID,
                overrideStore: .empty
            ).category

            let section: AssistantCardSectionKind
            var tags: [AssistantCardTag] = []

            if category != .primary {
                section = .updatesAndNewsletters
                if citation.isRead { tags.append(.read) }
            } else if citation.isFlagged || (!citation.isRead && !citation.isAnswered) {
                section = .needsYou
                if citation.isFlagged { tags.append(.urgent) }
                if !citation.isAnswered { tags.append(.reply) }
            } else {
                section = .worthALook
                if citation.isRead { tags.append(.read) }
            }

            let card = AssistantConversationCard(
                messageID: citation.id,
                folderID: citation.folderID,
                sourceID: citation.sourceID,
                senderName: senderName,
                senderEmail: senderEmail,
                subject: citation.subject,
                snippet: citation.snippet ?? "",
                date: citation.date,
                section: section,
                tags: tags,
                citation: citation
            )

            switch section {
            case .needsYou: needsYou.append(card)
            case .worthALook: worthALook.append(card)
            case .updatesAndNewsletters: updates.append(card)
            }
        }

        var sections: [AssistantAnswerSection] = []
        if !needsYou.isEmpty {
            sections.append(AssistantAnswerSection(kind: .needsYou, cards: needsYou))
        }
        if !worthALook.isEmpty {
            sections.append(AssistantAnswerSection(kind: .worthALook, cards: worthALook))
        }
        if !updates.isEmpty {
            sections.append(AssistantAnswerSection(kind: .updatesAndNewsletters, cards: updates))
        }

        var summaryChips: [String] = []
        if !needsYou.isEmpty {
            summaryChips.append(String(
                format: String(localized: "%lld need you", bundle: .module, locale: locale),
                locale: locale,
                Int64(needsYou.count)
            ))
        }
        if !worthALook.isEmpty {
            summaryChips.append(String(
                format: String(localized: "%lld worth a look", bundle: .module, locale: locale),
                locale: locale,
                Int64(worthALook.count)
            ))
        }
        if let earliest = citations.map(\.date).min(),
           let latest = citations.map(\.date).max() {
            let startText = earliest.formatted(.dateTime.day().month(.abbreviated).locale(locale))
            let endText = latest.formatted(.dateTime.day().month(.abbreviated).locale(locale))
            summaryChips.append(startText == endText ? startText : "\(startText) – \(endText)")
        }

        var actionChips: [AssistantAnswerActionChip] = []
        if let topNeed = needsYou.first {
            actionChips.append(.reply(senderName: topNeed.senderName, card: topNeed))
        }
        if !citations.isEmpty {
            actionChips.append(.followUpPrompt(String(localized: "Who hasn't replied to me?", bundle: .module, locale: locale)))
        }
        if !updates.isEmpty {
            actionChips.append(.archiveUpdates(count: updates.count, cards: updates))
        }

        return AssistantAnswerPresentation(
            summaryChips: summaryChips,
            sections: sections,
            actionChips: actionChips
        )
    }
}
