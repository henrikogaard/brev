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

extension Notification.Name {
    static let brevNoReplyFollowUpCacheDidChange = Notification.Name("brev.noReplyFollowUpCacheDidChange")
}

struct NoReplyFollowUpCacheSnapshot: Sendable {
    let sourceID: MailSourceID
    let headers: [MessageHeader]
    let sentFolderIDs: Set<Folder.ID>
    let ownAddresses: Set<String>
    let isComplete: Bool
}

struct NoReplyFollowUpReconciliationResult: Sendable {
    var settings: FollowUpSettings
    var created: [FollowUpReminder]
    var completed: [FollowUpReminder]
}

enum NoReplyFollowUpReconciler {
    static func reconcile(
        settings initialSettings: FollowUpSettings,
        snapshots: [NoReplyFollowUpCacheSnapshot]
    ) -> NoReplyFollowUpReconciliationResult {
        var settings = initialSettings
        var created: [FollowUpReminder] = []
        var completed: [FollowUpReminder] = []

        for snapshot in snapshots where snapshot.isComplete {
            let sourceHeaders = snapshot.headers
            let sentHeaders = sourceHeaders.filter { snapshot.sentFolderIDs.contains($0.folderID) }
            var sentByID: [String: [MessageHeader]] = [:]
            var sentByLocator: [String: MessageHeader] = [:]
            for header in sentHeaders {
                if let identifier = Self.singleMessageIdentifier(header.messageID) {
                    sentByID[identifier, default: []].append(header)
                }
                if sentByLocator[header.id] == nil { sentByLocator[header.id] = header }
            }
            let sentIdentifiers = Set(sentByID.keys)
            var replyDates: [String: Date] = [:]
            let ownAddresses = Set(snapshot.ownAddresses.map { $0.lowercased() })
            for header in sourceHeaders where !snapshot.sentFolderIDs.contains(header.folderID)
                && !ownAddresses.contains(header.from.email.lowercased()) {
                if Self.messageIdentifiers(header.messageID).contains(where: sentIdentifiers.contains) { continue }
                for identifier in Self.referencedIdentifiers(in: header) {
                    replyDates[identifier] = max(replyDates[identifier] ?? .distantPast, header.date)
                }
            }

            let pending = settings.pendingNoReplyIntents.filter { $0.sourceID == snapshot.sourceID }
            for intent in pending {
                guard let expectedIdentifier = Self.singleMessageIdentifier(intent.expectedMessageID) else { continue }
                let expected = Set([expectedIdentifier])
                let hinted = intent.sentMessageIDHint.flatMap { sentByLocator[$0] }
                let sent = hinted.flatMap { header in
                    Self.singleMessageIdentifier(header.messageID) == expectedIdentifier ? header : nil
                } ?? sentByID[expectedIdentifier]?.first
                guard let sent else { continue }
                let alreadyExists = settings.reminders.contains { $0.id == intent.id }
                if expected.contains(where: { (replyDates[$0] ?? .distantPast) > sent.date }) {
                    if let reminder = settings.reminders.first(where: { $0.id == intent.id }),
                       !reminder.isDismissed, !reminder.isCompleted {
                        settings.complete(id: reminder.id)
                        completed.append(reminder)
                    }
                    settings.pendingNoReplyIntents.removeAll { $0.id == intent.id }
                    continue
                }
                if !alreadyExists {
                    let reminder = FollowUpReminder(
                        id: intent.id,
                        messageID: sent.id,
                        threadID: sent.threadID,
                        accountID: snapshot.sourceID.accountID,
                        mailboxID: snapshot.sourceID.mailboxID,
                        folderID: sent.folderID,
                        dueAt: sent.date.addingTimeInterval(intent.delay),
                        noReplyMetadata: NoReplyFollowUpMetadata(
                            sourceID: snapshot.sourceID,
                            draftID: intent.draftID,
                            expectedMessageID: intent.expectedMessageID,
                            sentAt: sent.date
                        )
                    )
                    settings.reminders.append(reminder)
                    created.append(reminder)
                }
                settings.pendingNoReplyIntents.removeAll { $0.id == intent.id }
            }

            for reminder in settings.reminders where reminder.isAutomaticNoReply
                && reminder.noReplyMetadata?.sourceID == snapshot.sourceID
                && !reminder.isDismissed && !reminder.isCompleted {
                guard let metadata = reminder.noReplyMetadata,
                      let expectedIdentifier = Self.singleMessageIdentifier(metadata.expectedMessageID),
                      (replyDates[expectedIdentifier] ?? .distantPast) > metadata.sentAt else { continue }
                settings.complete(id: reminder.id)
                completed.append(reminder)
            }
        }

        return NoReplyFollowUpReconciliationResult(settings: settings, created: created, completed: completed)
    }

    private static func messageIdentifiers(_ value: String?) -> [String] {
        (try? ConversationMembershipResolver.identifiers(in: value)) ?? []
    }

    static func singleMessageIdentifier(_ value: String?) -> String? {
        let identifiers = messageIdentifiers(value)
        return identifiers.count == 1 ? identifiers.first : nil
    }

    private static func referencedIdentifiers(in header: MessageHeader) -> [String] {
        let references = (header.references ?? []).joined(separator: " ")
        return messageIdentifiers(header.inReplyTo) + messageIdentifiers(references)
    }
}

enum NoReplyFollowUpWaitingProjection {
    static func headers(
        sourceID: MailSourceID,
        sentFolderIDs: Set<Folder.ID>,
        cachedHeaders: [MessageHeader],
        reminders: [FollowUpReminder]
    ) -> [MessageHeader] {
        let byMessageID = Dictionary(
            reminders.compactMap { reminder -> (String, FollowUpReminder)? in
                guard reminder.isAutomaticNoReply, !reminder.isDismissed, !reminder.isCompleted,
                      reminder.noReplyMetadata?.sourceID == sourceID
                else { return nil }
                return (reminder.messageID, reminder)
            },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<String>()
        return cachedHeaders.compactMap { header in
            guard sentFolderIDs.contains(header.folderID),
                  let reminder = byMessageID[header.id],
                  let expectedMessageID = reminder.noReplyMetadata?.expectedMessageID,
                  let expectedIdentifier = NoReplyFollowUpReconciler.singleMessageIdentifier(expectedMessageID),
                  NoReplyFollowUpReconciler.singleMessageIdentifier(header.messageID) == expectedIdentifier
            else { return nil }
            return seen.insert(expectedIdentifier).inserted ? header : nil
        }
    }
}
