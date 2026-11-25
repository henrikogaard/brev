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

/// Inputs needed to resolve mailbox chat scope chips and search behavior.
struct MailboxChatScopeContext: Equatable, Sendable {
    var senderEmail: String?
    var folder: Folder?
    var accountLabel: String?
    var sourceID: MailSourceID?
    /// The sender's display name, when the message carries one; the sender chip
    /// shows it instead of the address's local part.
    var senderName: String?

    var defaultChipKind: MailboxChatScopeChipKind {
        if senderEmail != nil {
            return .sender
        }
        if folder != nil {
            return .folder
        }
        if sourceID != nil {
            return .account
        }
        return .sender
    }

    func isChipEnabled(_ kind: MailboxChatScopeChipKind) -> Bool {
        switch kind {
        case .sender:
            return senderEmail != nil
        case .folder:
            return folder != nil
        case .account:
            return sourceID != nil
        }
    }

    func scope(for chip: MailboxChatScopeChipKind) -> MailboxChatScope? {
        switch chip {
        case .sender:
            guard let senderEmail else { return nil }
            return .sender(email: senderEmail)
        case .folder:
            guard folder != nil else { return nil }
            return .folder
        case .account:
            guard sourceID != nil else { return nil }
            return .account
        }
    }

    func chipTitle(for kind: MailboxChatScopeChipKind) -> String {
        switch kind {
        case .sender:
            senderEmail ?? String(localized: "Sender", bundle: .module)
        case .folder:
            folder?.name ?? String(localized: "Folder", bundle: .module)
        case .account:
            String(localized: "All folders", bundle: .module)
        }
    }

    /// Compact chip caption: full addresses get clipped mid-domain in the
    /// narrow column, so the sender chip carries the display name (or the local
    /// part when there is none) while the complete address stays on the
    /// accessibility label.
    func chipShortTitle(for kind: MailboxChatScopeChipKind) -> String {
        switch kind {
        case .sender:
            guard let senderEmail else { return chipTitle(for: kind) }
            if let name = senderName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return name
            }
            return senderEmail.split(separator: "@").first.map(String.init)
                ?? senderEmail
        case .folder, .account:
            return chipTitle(for: kind)
        }
    }

    func chipAccessibilityLabel(for kind: MailboxChatScopeChipKind) -> String {
        switch kind {
        case .sender, .folder:
            return chipTitle(for: kind)
        case .account:
            if let accountLabel {
                return String(localized: "All folders in \(accountLabel)", bundle: .module)
            }
            return String(localized: "All folders", bundle: .module)
        }
    }

    /// Tooltip on a disabled chip explaining what unlocks it — without it the
    /// dimming reads as broken rather than as "not applicable here".
    func chipDisabledHelp(for kind: MailboxChatScopeChipKind) -> String {
        switch kind {
        case .sender:
            String(localized: "Select a message to search its sender.", bundle: .module)
        case .folder:
            String(localized: "Open a single folder to scope the search.", bundle: .module)
        case .account:
            String(localized: "View a single account to search all its folders.", bundle: .module)
        }
    }
}

/// Explicit retrieval intent for built-in Assistant starter prompts so clicking
/// a starter queries cached mailbox metadata (date range, attachments) instead
/// of searching FTS5 for the localized card wording (#294, #370).
enum MailboxChatStarterIntent: String, Equatable, Sendable {
    case needsMeToday
    case whoHasntReplied
    case summarizeRecentThreads
    case findRecentAttachments
}

/// Builds cache-only search queries for mailbox chat Q&A by scope.
enum MailboxChatScopeSearchPolicy {
    private static let dayInterval: TimeInterval = 24 * 60 * 60

    static func answerSearchQuery(
        question: String,
        scope: MailboxChatScope,
        folderID: String?,
        starterIntent: MailboxChatStarterIntent? = nil,
        referenceDate: Date = Date()
    ) -> SearchQuery {
        let queryText: String
        let dateRange: ClosedRange<Date>?
        let hasAttachments: Bool?

        switch starterIntent {
        case .needsMeToday:
            queryText = ""
            dateRange = referenceDate.addingTimeInterval(-7 * dayInterval) ... referenceDate
            hasAttachments = nil
        case .whoHasntReplied:
            queryText = ""
            dateRange = referenceDate.addingTimeInterval(-30 * dayInterval) ... referenceDate
            hasAttachments = nil
        case .summarizeRecentThreads:
            queryText = ""
            dateRange = referenceDate.addingTimeInterval(-14 * dayInterval) ... referenceDate
            hasAttachments = nil
        case .findRecentAttachments:
            queryText = ""
            dateRange = referenceDate.addingTimeInterval(-30 * dayInterval) ... referenceDate
            hasAttachments = true
        case nil:
            queryText = question
            dateRange = nil
            hasAttachments = nil
        }

        switch scope {
        case .sender(let email):
            return SearchQuery(
                text: queryText,
                from: email,
                dateRange: dateRange,
                hasAttachments: hasAttachments,
                execution: .cacheOnly
            )
        case .folder:
            return SearchQuery(
                text: queryText,
                folderID: folderID,
                dateRange: dateRange,
                hasAttachments: hasAttachments,
                execution: .cacheOnly
            )
        case .account:
            return SearchQuery(
                text: queryText,
                dateRange: dateRange,
                hasAttachments: hasAttachments,
                execution: .cacheOnly
            )
        }
    }

    /// Returns the ordered set of cache-only queries needed to gather complete
    /// candidates for a starter intent before ranking and applying context limits
    /// (#370). Always stays strictly `.cacheOnly` and preserves scope constraints.
    static func answerSearchQueries(
        question: String,
        scope: MailboxChatScope,
        folderID: String?,
        sentFolderID: String? = nil,
        starterIntent: MailboxChatStarterIntent? = nil,
        referenceDate: Date = Date()
    ) -> [SearchQuery] {
        let base = answerSearchQuery(
            question: question,
            scope: scope,
            folderID: folderID,
            starterIntent: starterIntent,
            referenceDate: referenceDate
        )
        switch starterIntent {
        case .needsMeToday:
            var flagged = base
            flagged.isFlagged = true
            var unread = base
            unread.isUnread = true
            return [flagged, unread, base]
        case .whoHasntReplied:
            if scope == .account, let sentFolderID {
                var sentQuery = base
                sentQuery.folderID = sentFolderID
                return [sentQuery, base]
            }
            return [base]
        case .summarizeRecentThreads, .findRecentAttachments, nil:
            return [base]
        }
    }

    static func emptySearchMessage(
        scope: MailboxChatScope,
        folderName: String?
    ) -> String {
        switch scope {
        case .sender(let email):
            return String(
                localized: "I couldn't find cached messages from \(email) that answer that yet.",
                bundle: .module
            )
        case .folder:
            let name = folderName ?? String(localized: "thisFolder.lower", bundle: .module)
            return String(
                localized: "I couldn't find cached messages in \(name) that answer that yet.",
                bundle: .module
            )
        case .account:
            return String(
                localized: "I couldn't find cached messages across this account's folders that answer that yet.",
                bundle: .module
            )
        }
    }

    static func scopeDescription(
        scope: MailboxChatScope,
        folderName: String?,
        accountLabel: String?
    ) -> String {
        switch scope {
        case .sender(let email):
            email
        case .folder:
            folderName ?? String(localized: "currentFolder.lower", bundle: .module)
        case .account:
            // Prompt context only: this string is never rendered to the user,
            // so it stays in English with the rest of the system prompt.
            accountLabel.map { "all folders in \($0)" }
                ?? "all folders in the current account"
        }
    }
}

/// Ranks and filters cached mailbox headers for structured Assistant starters
/// before `MailboxChatAnswerContext` applies the message/byte budget (#370).
enum MailboxChatStarterCandidateSelector {
    static func select(
        headers: [MessageHeader],
        intent: MailboxChatStarterIntent?,
        sentFolderIDs: Set<String>,
        draftFolderIDs: Set<String> = [],
        myEmailAddress: String?,
        maxMessages: Int
    ) -> [MessageHeader] {
        // Freeform Q&A preserves the search backend's exact relevance/recency order.
        guard let intent else { return headers }

        // Deduplicate merged starter batches by message ID while keeping newest first.
        var seenIDs = Set<MessageHeader.ID>()
        let unique = headers
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.id < rhs.id
            }
            .filter { seenIDs.insert($0.id).inserted }

        switch intent {
        case .needsMeToday:
            return prioritizeAttentionItems(unique)
        case .summarizeRecentThreads:
            return diversifyByThread(unique, maxMessages: maxMessages)
        case .whoHasntReplied:
            return unansweredSentMessages(
                unique,
                sentFolderIDs: sentFolderIDs,
                draftFolderIDs: draftFolderIDs,
                myEmailAddress: myEmailAddress
            )
        case .findRecentAttachments:
            return unique.filter(\.hasAttachments)
        }
    }

    private static func prioritizeAttentionItems(_ headers: [MessageHeader]) -> [MessageHeader] {
        headers.sorted { lhs, rhs in
            let lhsRank = attentionRank(lhs)
            let rhsRank = attentionRank(rhs)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id < rhs.id
        }
    }

    private static func attentionRank(_ header: MessageHeader) -> Int {
        switch (header.isFlagged, !header.isRead) {
        case (true, true): 0
        case (true, false): 1
        case (false, true): 2
        case (false, false): 3
        }
    }

    /// Groups candidates by conversation using both native `threadID`s and
    /// `ConversationMembershipResolver` RFC link identifiers (so unthreaded
    /// IMAP replies with per-message `threadID`s still group into one
    /// conversation), then allocates slots round-robin across conversations (#370).
    private static func diversifyByThread(
        _ headers: [MessageHeader],
        maxMessages: Int
    ) -> [MessageHeader] {
        guard !headers.isEmpty else { return [] }

        var parent = Array(headers.indices)
        func find(_ index: Int) -> Int {
            var root = index
            while parent[root] != root {
                root = parent[root]
            }
            var current = index
            while parent[current] != root {
                let next = parent[current]
                parent[current] = root
                current = next
            }
            return root
        }
        func union(_ lhs: Int, _ rhs: Int) {
            let rootA = find(lhs)
            let rootB = find(rhs)
            if rootA != rootB {
                // Keep the smaller index (newest header) as canonical root.
                if rootA < rootB {
                    parent[rootB] = rootA
                } else {
                    parent[rootA] = rootB
                }
            }
        }

        // Track owners of each own Message-ID so duplicate/reused IDs across
        // unrelated messages do not bridge unrelated conversations.
        var ownIDFingerprints: [String: Set<String>] = [:]
        for header in headers {
            if let ownID = singleMessageIdentifier(header.rfcMessageID) {
                let fingerprint = "\(header.from.email.lowercased())|\(header.subject)|\(header.date.timeIntervalSinceReferenceDate)"
                ownIDFingerprints[ownID, default: []].insert(fingerprint)
            }
        }
        let unsafeIdentifiers = Set(ownIDFingerprints.filter { $0.value.count > 1 }.map(\.key))

        var firstIndexByThreadID: [String: Int] = [:]
        var firstIndexByLinkID: [String: Int] = [:]

        for (index, header) in headers.enumerated() {
            if !header.threadID.isEmpty {
                if let existing = firstIndexByThreadID[header.threadID] {
                    union(existing, index)
                } else {
                    firstIndexByThreadID[header.threadID] = index
                }
            }
            let linkIDs = (ConversationMembershipResolver.cachedLinkIdentifiers(for: header) ?? [])
                .map { $0.lowercased() }
            for linkID in linkIDs where !unsafeIdentifiers.contains(linkID) {
                if let existing = firstIndexByLinkID[linkID] {
                    union(existing, index)
                } else {
                    firstIndexByLinkID[linkID] = index
                }
            }
        }

        var buckets: [Int: [MessageHeader]] = [:]
        var orderedRoots: [Int] = []
        for (index, header) in headers.enumerated() {
            let root = find(index)
            if buckets[root] == nil {
                orderedRoots.append(root)
                buckets[root] = [header]
            } else {
                buckets[root, default: []].append(header)
            }
        }

        // Round-robin across recent conversations: every distinct conversation
        // gets its newest representative first before any busy thread consumes
        // additional context slots.
        var result: [MessageHeader] = []
        let limit = max(maxMessages, 0)
        var depth = 0
        while result.count < limit {
            var addedInRound = false
            for root in orderedRoots {
                guard result.count < limit else { break }
                if let members = buckets[root], depth < members.count {
                    result.append(members[depth])
                    addedInRound = true
                }
            }
            if !addedInRound { break }
            depth += 1
        }
        return result
    }

    private static func isDraftIdentifier(_ raw: String) -> Bool {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "draft"
            || normalized == "drafts"
            || normalized == "\\draft"
            || normalized == "\\drafts"
            || normalized == "[gmail]/drafts"
            || normalized.hasSuffix("/drafts")
            || normalized.hasSuffix(".drafts")
    }

    private static func isDraftHeader(
        _ header: MessageHeader,
        draftFolderIDs: Set<String>
    ) -> Bool {
        if draftFolderIDs.contains(header.folderID) || isDraftIdentifier(header.folderID) {
            return true
        }
        return header.labels.contains { draftFolderIDs.contains($0) || isDraftIdentifier($0) }
    }

    /// Matches `TodayDigestBuilder` and `NoReplyFollowUpReconciler`:
    /// excludes unsent drafts from both sent and reply scans, matches cached
    /// replies by thread timestamp or tokenized `In-Reply-To`/`References`
    /// identifiers, and returns sent messages with external recipients that have
    /// no known cached reply (#370).
    private static func unansweredSentMessages(
        _ headers: [MessageHeader],
        sentFolderIDs: Set<String>,
        draftFolderIDs: Set<String>,
        myEmailAddress: String?
    ) -> [MessageHeader] {
        let eligibleHeaders = headers.filter { !isDraftHeader($0, draftFolderIDs: draftFolderIDs) }

        var myAddresses = Set<String>()
        if let normalized = myEmailAddress?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !normalized.isEmpty {
            myAddresses.insert(normalized)
        }
        for header in eligibleHeaders where sentFolderIDs.contains(header.folderID) {
            let email = header.from.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !email.isEmpty {
                myAddresses.insert(email)
            }
        }

        func isMine(_ correspondent: Correspondent) -> Bool {
            let normalized = correspondent.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !normalized.isEmpty && myAddresses.contains(normalized)
        }

        func isSentHeader(_ header: MessageHeader) -> Bool {
            if sentFolderIDs.contains(header.folderID) { return true }
            if !myAddresses.isEmpty, isMine(header.from) { return true }
            return sentFolderIDs.isEmpty && header.folderID.lowercased().contains("sent")
        }

        var sentHeaders: [MessageHeader] = []
        var sentMessageIDs = Set<String>()
        for header in eligibleHeaders where isSentHeader(header) {
            sentHeaders.append(header)
            if let messageID = singleMessageIdentifier(header.rfcMessageID) {
                sentMessageIDs.insert(messageID)
            }
        }
        guard !sentHeaders.isEmpty else { return [] }

        // Keep newest sent message per thread so repeated follow-ups don't duplicate.
        var sentLatestByThread: [String: MessageHeader] = [:]
        for header in sentHeaders {
            let key = header.threadID.isEmpty ? header.id : header.threadID
            if let existing = sentLatestByThread[key] {
                if header.date > existing.date {
                    sentLatestByThread[key] = header
                }
            } else {
                sentLatestByThread[key] = header
            }
        }

        var incomingByThread: [String: Date] = [:]
        var repliedSentMessageIDs = Set<String>()
        for header in eligibleHeaders where !isSentHeader(header) {
            if let id = singleMessageIdentifier(header.rfcMessageID), sentMessageIDs.contains(id) {
                continue
            }
            if isMine(header.from) { continue }
            let threadKey = header.threadID.isEmpty ? header.id : header.threadID
            incomingByThread[threadKey] = max(incomingByThread[threadKey] ?? .distantPast, header.date)
            for ref in referencedMessageIDs(header) where sentMessageIDs.contains(ref) {
                repliedSentMessageIDs.insert(ref)
            }
        }

        return sentLatestByThread.values
            .filter { header in
                let externalRecipients = (header.to + header.cc).filter { !isMine($0) }
                guard !externalRecipients.isEmpty else { return false }
                let threadKey = header.threadID.isEmpty ? header.id : header.threadID
                let repliedInThread = (incomingByThread[threadKey] ?? .distantPast) > header.date
                let repliedByHeader = singleMessageIdentifier(header.rfcMessageID)
                    .map(repliedSentMessageIDs.contains) == true
                return !repliedInThread && !repliedByHeader
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.id < rhs.id
            }
    }

    private static func messageIdentifiers(_ value: String?) -> [String] {
        ((try? ConversationMembershipResolver.identifiers(in: value)) ?? [])
            .map { $0.lowercased() }
    }

    private static func singleMessageIdentifier(_ value: String?) -> String? {
        let identifiers = messageIdentifiers(value)
        return identifiers.count == 1 ? identifiers.first : nil
    }

    private static func referencedMessageIDs(_ header: MessageHeader) -> [String] {
        messageIdentifiers(header.inReplyTo)
            + (header.references ?? []).flatMap { messageIdentifiers($0) }
    }
}
