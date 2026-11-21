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
import BrevSettings
import Foundation

/// What the Today page shows when no message is open (#292): conversations
/// from people that wait on you, and your sent mail that still waits on
/// someone else. Built only from locally cached headers, with fixed rules and
/// no AI or network (ADR-0006, ADR-0027).
struct TodayDigest: Equatable, Sendable {
    /// One conversation row; `header` is the conversation's newest message.
    struct Row: Identifiable, Equatable, Sendable {
        let sourceID: MailSourceID
        let header: MessageHeader
        let dueAt: Date?
        /// The other person: the sender of received mail, the first other
        /// recipient of sent mail.
        let person: Correspondent

        init(sourceID: MailSourceID, header: MessageHeader, dueAt: Date? = nil, person: Correspondent) {
            self.sourceID = sourceID
            self.header = header
            self.dueAt = dueAt
            self.person = person
        }

        var id: SourceMessageID { SourceMessageID(sourceID: sourceID, messageID: header.id) }
    }

    var waitingOnYou: [Row] = []
    var waitingOnYouCount = 0
    var youreWaitingOn: [Row] = []
    var youreWaitingOnCount = 0
    var unreadUpdatesCount = 0

    static let empty = TodayDigest()

    /// True when there is nothing to show beyond the greeting.
    var isEmpty: Bool {
        waitingOnYouCount == 0 && youreWaitingOnCount == 0 && unreadUpdatesCount == 0
    }
}

/// Builds a `TodayDigest` from cached Inbox and Sent headers.
enum TodayDigestBuilder {
    /// Rows per list; the counts above each list stay exact.
    static let rowLimit = 5
    /// Only mail from the last two weeks is "today" business.
    static let window: TimeInterval = 14 * 24 * 3600
    /// Sent mail gets a day before it counts as waiting on someone.
    static let replyGrace: TimeInterval = 24 * 3600

    /// - Parameters:
    ///   - inbox: Cached Inbox headers per source.
    ///   - sent: Cached Sent headers per source.
    ///   - myAddresses: The user's own addresses, any case.
    ///   - classify: The local inbox category of a header (ADR-0035);
    ///     only `.primary` mail counts as from a person.
    static func build(
        inbox: [(MailSourceID, [MessageHeader])],
        sent: [(MailSourceID, [MessageHeader])],
        myAddresses: Set<String>,
        now: Date,
        noReplyReminders: [FollowUpReminder] = [],
        classify: (MessageHeader, MailSourceID) -> InboxCategory
    ) -> TodayDigest {
        let mine = Set(myAddresses.map { $0.lowercased() })
        let since = now.addingTimeInterval(-window)
        func isMine(_ person: Correspondent) -> Bool { mine.contains(person.email.lowercased()) }

        var sentByThread: [ThreadKey: Date] = [:]
        var sentMessageIDs: Set<String> = []
        var sentLatest: [ThreadKey: (MailSourceID, MessageHeader)] = [:]
        var sentByCanonicalID: [SourceMessageID: [MessageHeader]] = [:]
        var trackedNoReplyMessages = Set<SourceMessageID>()
        for reminder in noReplyReminders where reminder.isAutomaticNoReply {
            guard let metadata = reminder.noReplyMetadata,
                  let identifier = NoReplyFollowUpReconciler.singleMessageIdentifier(metadata.expectedMessageID)
            else { continue }
            trackedNoReplyMessages.insert(SourceMessageID(sourceID: metadata.sourceID, messageID: identifier))
        }
        // Message ID -> when I last replied to it. IMAP threads each folder
        // on its own, so Inbox and Sent rarely share a thread ID; the reply
        // headers are what tie my answer to the conversation.
        var myReplyDates: [String: Date] = [:]
        for (sourceID, headers) in sent {
            for header in headers {
                if let identifier = NoReplyFollowUpReconciler.singleMessageIdentifier(header.messageID) {
                    sentByCanonicalID[SourceMessageID(sourceID: sourceID, messageID: identifier), default: []]
                        .append(header)
                }
                guard header.date >= since else { continue }
                let key = ThreadKey(sourceID: sourceID, threadID: header.threadID)
                sentByThread[key] = max(sentByThread[key] ?? .distantPast, header.date)
                if let id = header.messageID { sentMessageIDs.insert(id) }
                for id in Self.referencedIDs(header) {
                    myReplyDates[id] = max(myReplyDates[id] ?? .distantPast, header.date)
                }
                if header.date > (sentLatest[key]?.1.date ?? .distantPast) { sentLatest[key] = (sourceID, header) }
            }
        }

        var inboxLatest: [ThreadKey: (MailSourceID, MessageHeader)] = [:]
        var repliedSentIDs: Set<String> = []
        var inboxByThread: [ThreadKey: Date] = [:]
        var inboxThreadMessageIDs: [ThreadKey: Set<String>] = [:]
        for (sourceID, headers) in inbox {
            for header in headers where header.date >= since && !isMine(header.from) {
                // An Inbox copy of a message in Sent (an alias, a Bcc to self)
                // is my own mail, whatever address it came from.
                if let id = header.messageID, sentMessageIDs.contains(id) { continue }
                let key = ThreadKey(sourceID: sourceID, threadID: header.threadID)
                inboxByThread[key] = max(inboxByThread[key] ?? .distantPast, header.date)
                if let id = header.messageID { inboxThreadMessageIDs[key, default: []].insert(id) }
                repliedSentIDs.formUnion(Self.referencedIDs(header).filter { sentMessageIDs.contains($0) })
                if header.date > (inboxLatest[key]?.1.date ?? .distantPast) { inboxLatest[key] = (sourceID, header) }
            }
        }

        var digest = TodayDigest()
        var waiting: [TodayDigest.Row] = []
        for (key, (sourceID, header)) in inboxLatest {
            guard classify(header, sourceID) == .primary else {
                if !header.isRead { digest.unreadUpdatesCount += 1 }
                continue
            }
            let answeredLater = (sentByThread[key] ?? .distantPast) > header.date
                || (inboxThreadMessageIDs[key] ?? []).contains { (myReplyDates[$0] ?? .distantPast) > header.date }
            if !header.isAnswered, !answeredLater {
                waiting.append(TodayDigest.Row(sourceID: sourceID, header: header, person: header.from))
            }
        }

        var waitingOn: [TodayDigest.Row] = []
        for (key, (sourceID, header)) in sentLatest {
            let canonicalID = NoReplyFollowUpReconciler.singleMessageIdentifier(header.messageID)
            if let canonicalID,
               trackedNoReplyMessages.contains(SourceMessageID(sourceID: sourceID, messageID: canonicalID)) { continue }
            let other = (header.to + header.cc).first { !isMine($0) }
            let oldEnough = now.timeIntervalSince(header.date) >= replyGrace
            let replied = (inboxByThread[key] ?? .distantPast) > header.date
                || header.messageID.map(repliedSentIDs.contains) == true
            if let other, oldEnough, !replied {
                waitingOn.append(TodayDigest.Row(sourceID: sourceID, header: header, person: other))
            }
        }

        for reminder in noReplyReminders where reminder.isAutomaticNoReply
            && !reminder.isDismissed && !reminder.isCompleted && reminder.dueAt <= now {
            guard let metadata = reminder.noReplyMetadata,
                  let expectedIdentifier = NoReplyFollowUpReconciler.singleMessageIdentifier(metadata.expectedMessageID),
                  let header = NoReplyFollowUpReconciler.resolveSentCopy(
                      sentByCanonicalID[SourceMessageID(sourceID: metadata.sourceID, messageID: expectedIdentifier)] ?? []
                  ),
                  let other = (header.to + header.cc).first(where: { !isMine($0) })
            else { continue }
            waitingOn.append(TodayDigest.Row(
                sourceID: metadata.sourceID,
                header: header,
                dueAt: reminder.dueAt,
                person: other
            ))
        }

        let newestFirst: (TodayDigest.Row, TodayDigest.Row)
            -> Bool = { ($0.dueAt ?? $0.header.date) > ($1.dueAt ?? $1.header.date) }
        digest.waitingOnYouCount = waiting.count
        digest.waitingOnYou = Array(waiting.sorted(by: newestFirst).prefix(rowLimit))
        digest.youreWaitingOnCount = waitingOn.count
        digest.youreWaitingOn = Array(waitingOn.sorted(by: newestFirst).prefix(rowLimit))
        return digest
    }

    /// The message IDs a header answers: In-Reply-To plus References.
    private static func referencedIDs(_ header: MessageHeader) -> [String] {
        ([header.inReplyTo] + (header.references ?? []).map(Optional.some)).compactMap { $0 }
    }

    private struct ThreadKey: Hashable {
        let sourceID: MailSourceID
        let threadID: String
    }
}

/// The Today page greeting: part of day plus the user's first name.
enum TodayGreeting {
    enum Period: Equatable {
        case morning
        case afternoon
        case evening
    }

    /// Morning 5–11, afternoon 12–17, evening otherwise.
    static func period(at date: Date, calendar: Calendar = .current) -> Period {
        switch calendar.component(.hour, from: date) {
        case 5 ..< 12: .morning
        case 12 ..< 18: .afternoon
        default: .evening
        }
    }

    /// The first word of a display name; nil for a blank name or an address.
    static func firstName(from displayName: String) -> String? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("@") else { return nil }
        return trimmed.split(separator: " ").first.map(String.init)
    }

    /// The localized greeting line.
    static func text(period: Period, firstName: String?) -> String {
        switch (period, firstName) {
        case (.morning, let name?): String(localized: "Good morning, \(name)", bundle: .module)
        case (.afternoon, let name?): String(localized: "Good afternoon, \(name)", bundle: .module)
        case (.evening, let name?): String(localized: "Good evening, \(name)", bundle: .module)
        case (.morning, nil): String(localized: "Good morning", bundle: .module)
        case (.afternoon, nil): String(localized: "Good afternoon", bundle: .module)
        case (.evening, nil): String(localized: "Good evening", bundle: .module)
        }
    }
}
