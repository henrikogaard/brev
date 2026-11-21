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

enum NoReplyFollowUpOwnership {
    static func isCurrent(
        sourceID: MailSourceID,
        currentSourceIDs: Set<MailSourceID>,
        currentAccountID: String?,
        currentBackendIdentity: ObjectIdentifier?,
        expectedBackendIdentity: ObjectIdentifier
    ) -> Bool {
        currentSourceIDs.contains(sourceID)
            && currentAccountID == sourceID.accountID
            && currentBackendIdentity == expectedBackendIdentity
    }

    static func canApplyRefresh(
        generation: Int,
        currentGeneration: Int,
        sourceSectionsRevision: Int,
        currentSourceSectionsRevision: Int,
        sourceID: MailSourceID,
        currentSourceIDs: Set<MailSourceID>,
        currentAccountID: String?,
        currentBackendIdentity: ObjectIdentifier?,
        expectedBackendIdentity: ObjectIdentifier
    ) -> Bool {
        generation == currentGeneration
            && sourceSectionsRevision == currentSourceSectionsRevision
            && isCurrent(
                sourceID: sourceID,
                currentSourceIDs: currentSourceIDs,
                currentAccountID: currentAccountID,
                currentBackendIdentity: currentBackendIdentity,
                expectedBackendIdentity: expectedBackendIdentity
            )
    }
}

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
            var sentByLocator: [String: [MessageHeader]] = [:]
            for header in sentHeaders {
                if let identifier = Self.singleMessageIdentifier(header.messageID) {
                    sentByID[identifier, default: []].append(header)
                }
                sentByLocator[header.id, default: []].append(header)
            }
            let sentIdentifiers = Set(sentByID.keys)
            var replyIdentifiers = Set<String>()
            let ownAddresses = Set(snapshot.ownAddresses.map { $0.lowercased() })
            for header in sourceHeaders where !snapshot.sentFolderIDs.contains(header.folderID)
                && !ownAddresses.contains(header.from.email.lowercased()) {
                if Self.messageIdentifiers(header.messageID).contains(where: sentIdentifiers.contains) { continue }
                replyIdentifiers.formUnion(Self.referencedIdentifiers(in: header))
            }

            let pending = settings.pendingNoReplyIntents.filter { $0.sourceID == snapshot.sourceID }
            for intent in pending {
                guard let expectedIdentifier = Self.singleMessageIdentifier(intent.expectedMessageID) else { continue }
                let hinted = (intent.sentMessageIDHint.map { sentByLocator[$0] ?? [] } ?? [])
                    .filter { Self.singleMessageIdentifier($0.messageID) == expectedIdentifier }
                let sent = Self.resolveSentCopy(
                    hinted.isEmpty ? sentByID[expectedIdentifier] ?? [] : hinted
                )
                guard let sent else { continue }
                let alreadyExists = settings.reminders.contains { $0.id == intent.id }
                if replyIdentifiers.contains(expectedIdentifier) {
                    if let index = settings.reminders.firstIndex(where: { $0.id == intent.id }) {
                        if !settings.reminders[index].isDismissed && !settings.reminders[index].isCompleted {
                            settings.reminders[index].isCompleted = true
                            completed.append(settings.reminders[index])
                        }
                    } else {
                        var tombstone = Self.reminder(for: intent, sent: sent, sourceID: snapshot.sourceID)
                        tombstone.isCompleted = true
                        settings.reminders.append(tombstone)
                    }
                    settings.pendingNoReplyIntents.removeAll { $0.id == intent.id }
                    continue
                }
                if !alreadyExists {
                    let reminder = Self.reminder(for: intent, sent: sent, sourceID: snapshot.sourceID)
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
                      replyIdentifiers.contains(expectedIdentifier) else { continue }
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
        messageIdentifiers(header.inReplyTo)
            + (header.references ?? []).flatMap { messageIdentifiers($0) }
    }

    private static func reminder(
        for intent: PendingNoReplyFollowUpIntent,
        sent: MessageHeader,
        sourceID: MailSourceID
    ) -> FollowUpReminder {
        FollowUpReminder(
            id: intent.id,
            messageID: sent.id,
            threadID: sent.threadID,
            accountID: sourceID.accountID,
            mailboxID: sourceID.mailboxID,
            folderID: sent.folderID,
            dueAt: sent.date.addingTimeInterval(intent.delay),
            noReplyMetadata: NoReplyFollowUpMetadata(
                sourceID: sourceID,
                draftID: intent.draftID,
                expectedMessageID: intent.expectedMessageID,
                sentAt: sent.date
            )
        )
    }

    static func resolveSentCopy(_ candidates: [MessageHeader]) -> MessageHeader? {
        guard let first = candidates.sorted(by: sentCopyOrder).first else { return nil }
        guard candidates.allSatisfy({
            $0.date == first.date && $0.threadID == first.threadID && $0.subject == first.subject
                && $0.from == first.from && $0.to == first.to && $0.cc == first.cc
        }) else { return nil }
        return first
    }

    private static func sentCopyOrder(_ lhs: MessageHeader, _ rhs: MessageHeader) -> Bool {
        if lhs.folderID != rhs.folderID { return lhs.folderID < rhs.folderID }
        return lhs.id < rhs.id
    }
}

enum NoReplyFollowUpWaitingProjection {
    static func headers(
        sourceID: MailSourceID,
        sentFolderIDs: Set<Folder.ID>,
        cachedHeaders: [MessageHeader],
        reminders: [FollowUpReminder]
    ) -> [MessageHeader] {
        var result: [MessageHeader] = []
        var seen = Set<String>()
        let sentHeaders = cachedHeaders.filter { sentFolderIDs.contains($0.folderID) }
        for reminder in reminders where reminder.isAutomaticNoReply && !reminder.isDismissed
            && !reminder.isCompleted && reminder.noReplyMetadata?.sourceID == sourceID {
            guard let expectedMessageID = reminder.noReplyMetadata?.expectedMessageID,
                  let identifier = NoReplyFollowUpReconciler.singleMessageIdentifier(expectedMessageID),
                  seen.insert(identifier).inserted else { continue }
            let candidates = sentHeaders.filter {
                NoReplyFollowUpReconciler.singleMessageIdentifier($0.messageID) == identifier
            }
            if let sent = NoReplyFollowUpReconciler.resolveSentCopy(candidates) { result.append(sent) }
        }
        return result
    }
}
