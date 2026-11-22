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

enum LocalMessageWorkflowConversationCacheError: LocalizedError {
    case sourceUnavailable
    case noKnownFolders
    case incompleteCache
    case workflowChanged

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            String(localized: "The mailbox is no longer available.", bundle: .module)
        case .noKnownFolders:
            String(localized: "No cached folders are available to verify this conversation.", bundle: .module)
        case .incompleteCache:
            String(localized: "The cached conversation could not be verified. Try again when mail is available.", bundle: .module)
        case .workflowChanged:
            String(localized: "Snooze state changed in another window. Try again.", bundle: .module)
        }
    }
}

@MainActor
enum LocalMessageWorkflowConversationCache {
    static func loadExpiredInboxWakeCandidates(
        backend: any MailBackend,
        sourceID: MailSourceID,
        inboxFolder: Folder,
        folders: [Folder],
        loadedHeaders: [MessageHeader],
        snoozes: [LocalMessageSnooze],
        now: Date,
        isEligible: Bool,
        isCurrent: @MainActor () -> Bool
    ) async throws -> [MessageHeader] {
        guard isEligible,
              MessageListSnoozeWakePolicy.hasExpiredSourceOwnedSnooze(
                  in: snoozes,
                  sourceID: sourceID,
                  now: now
              ) else {
            return []
        }
        let candidates = try await candidates(
            backend: backend,
            sourceID: sourceID,
            folders: folders,
            anchors: loadedHeaders,
            isCurrent: isCurrent
        )
        guard isCurrent() else { throw CancellationError() }
        return MessageListSnoozeWakePolicy.expiredInboxWakeCandidates(
            from: candidates,
            sourceID: sourceID,
            inboxFolderID: inboxFolder.id,
            loadedHeaders: loadedHeaders,
            snoozes: snoozes,
            now: now
        )
    }

    static func candidates(
        backend: any MailBackend,
        sourceID: MailSourceID,
        folders: [Folder],
        anchors: [MessageHeader],
        isCurrent: @MainActor () -> Bool
    ) async throws -> [LocalMessageWorkflowCandidate] {
        guard backend.account.id == sourceID.accountID else {
            throw LocalMessageWorkflowConversationCacheError.sourceUnavailable
        }
        let knownFolderIDs = Set(folders.map(\.id))
        guard !knownFolderIDs.isEmpty,
              anchors.allSatisfy({ knownFolderIDs.contains($0.folderID) }) else {
            throw LocalMessageWorkflowConversationCacheError.noKnownFolders
        }

        var candidates: [LocalMessageWorkflowCandidate] = []
        for folder in folders {
            guard isCurrent() else { throw CancellationError() }
            let headers = try await backend.cachedMessageHeaders(in: folder, sourceID: sourceID)
            guard isCurrent() else { throw CancellationError() }
            guard headers.allSatisfy({ !$0.id.isEmpty && $0.folderID == folder.id }) else {
                throw LocalMessageWorkflowConversationCacheError.incompleteCache
            }
            candidates.append(contentsOf: headers.map { .init(sourceID: sourceID, header: $0) })
        }

        let cachedIDs = Set(candidates.map {
            "\($0.sourceID.accountID)\u{0}\($0.sourceID.mailboxID)\u{0}\($0.header.folderID)\u{0}\($0.header.id)"
        })
        candidates.append(contentsOf: anchors.compactMap { header -> LocalMessageWorkflowCandidate? in
            let key = "\(sourceID.accountID)\u{0}\(sourceID.mailboxID)\u{0}\(header.folderID)\u{0}\(header.id)"
            return cachedIDs.contains(key) ? nil : LocalMessageWorkflowCandidate(sourceID: sourceID, header: header)
        })
        guard isCurrent() else { throw CancellationError() }
        return candidates
    }
}
