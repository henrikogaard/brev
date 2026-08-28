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

enum LocalRulesExecutionMode: Sendable, Equatable {
    case automatic
    case manualSafe
    case manualForced
}

struct LocalRulesMoveBatch: Sendable, Equatable {
    let folder: Folder
    let messageIDs: [MessageHeader.ID]
}

struct LocalRulesRuntimePlan: Sendable, Equatable {
    let readIDs: [MessageHeader.ID]
    let unreadIDs: [MessageHeader.ID]
    let flaggedIDs: [MessageHeader.ID]
    let deleteIDs: [MessageHeader.ID]
    let moveBatches: [LocalRulesMoveBatch]
    let executionResult: LocalRulesExecutionResult

    var totalExecutableActionCount: Int {
        readIDs.count
            + unreadIDs.count
            + flaggedIDs.count
            + deleteIDs.count
            + moveBatches.reduce(0) { $0 + $1.messageIDs.count }
    }
}

enum LocalRulesRuntime {
    static func plan(
        rules: [ServerRule],
        headers: [MessageHeader],
        folders: [Folder],
        capabilities: BackendCapabilities,
        archiveFolderID: Folder.ID?,
        trashFolderID: Folder.ID?,
        mode: LocalRulesExecutionMode
    ) -> LocalRulesRuntimePlan {
        let context = LocalRulesExecutionContext(
            capabilities: capabilities,
            destructiveActionPolicy: destructivePolicy(for: mode, trashFolderID: trashFolderID),
            archiveFolderID: archiveFolderID
        )
        let executionResult = LocalRulesEngine.execute(
            rules: rules,
            on: headers,
            context: context
        )
        // Failable-merge, not Dictionary(uniqueKeysWithValues:): a buggy/hostile
        // server can return two messages with the same UID (duplicate header id)
        // or two folders with the same path, which would otherwise trap here.
        let headersByID = Dictionary(headers.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
        let foldersByID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })

        var readIDs: [MessageHeader.ID] = []
        var unreadIDs: [MessageHeader.ID] = []
        var flaggedIDs: [MessageHeader.ID] = []
        var deleteIDs: [MessageHeader.ID] = []
        var moveIDsByFolderID: [Folder.ID: [MessageHeader.ID]] = [:]

        for applied in executionResult.appliedActions {
            guard let header = headersByID[applied.messageID] else { continue }
            switch applied.action {
            case .markRead:
                guard !header.isRead else { continue }
                readIDs.append(applied.messageID)
            case .markUnread:
                guard header.isRead else { continue }
                unreadIDs.append(applied.messageID)
            case .flag:
                guard !header.isFlagged else { continue }
                flaggedIDs.append(applied.messageID)
            case .delete:
                deleteIDs.append(applied.messageID)
            case .moveToFolder(let id):
                guard header.folderID != id,
                      foldersByID[id] != nil else { continue }
                moveIDsByFolderID[id, default: []].append(applied.messageID)
            case .archive, .forward, .providerAction:
                continue
            }
        }

        let moveBatches = moveIDsByFolderID
            .keys
            .sorted()
            .compactMap { folderID -> LocalRulesMoveBatch? in
                guard let folder = foldersByID[folderID],
                      let ids = moveIDsByFolderID[folderID] else { return nil }
                return LocalRulesMoveBatch(
                    folder: folder,
                    messageIDs: ids
                )
            }

        return LocalRulesRuntimePlan(
            readIDs: readIDs,
            unreadIDs: unreadIDs,
            flaggedIDs: flaggedIDs,
            deleteIDs: deleteIDs,
            moveBatches: moveBatches,
            executionResult: executionResult
        )
    }

    static func apply(
        plan: LocalRulesRuntimePlan,
        backend: any MailBackend,
        sourceID: MailSourceID?
    ) async throws {
        if !plan.readIDs.isEmpty {
            try await setRead(true, for: plan.readIDs, backend: backend, sourceID: sourceID)
        }
        if !plan.unreadIDs.isEmpty {
            try await setRead(false, for: plan.unreadIDs, backend: backend, sourceID: sourceID)
        }
        if !plan.flaggedIDs.isEmpty {
            try await setFlagged(true, for: plan.flaggedIDs, backend: backend, sourceID: sourceID)
        }
        for moveBatch in plan.moveBatches {
            try await move(
                messageIDs: moveBatch.messageIDs,
                to: moveBatch.folder,
                backend: backend,
                sourceID: sourceID
            )
        }
        if !plan.deleteIDs.isEmpty {
            try await delete(plan.deleteIDs, backend: backend, sourceID: sourceID)
        }
    }

    private static func destructivePolicy(
        for mode: LocalRulesExecutionMode,
        trashFolderID: Folder.ID?
    ) -> LocalRulesExecutionContext.DestructiveActionPolicy {
        switch mode {
        case .automatic:
            return .requireExplicitApproval
        case .manualSafe:
            if let trashFolderID {
                return .recoverDelete(toFolderID: trashFolderID)
            }
            return .requireExplicitApproval
        case .manualForced:
            return .allow
        }
    }

    private static func setRead(
        _ isRead: Bool,
        for messageIDs: [MessageHeader.ID],
        backend: any MailBackend,
        sourceID: MailSourceID?
    ) async throws {
        if let sourceID {
            try await backend.setRead(isRead, for: messageIDs, sourceID: sourceID)
        } else {
            try await backend.setRead(isRead, for: messageIDs)
        }
    }

    private static func setFlagged(
        _ isFlagged: Bool,
        for messageIDs: [MessageHeader.ID],
        backend: any MailBackend,
        sourceID: MailSourceID?
    ) async throws {
        if let sourceID {
            try await backend.setFlagged(isFlagged, for: messageIDs, sourceID: sourceID)
        } else {
            try await backend.setFlagged(isFlagged, for: messageIDs)
        }
    }

    private static func move(
        messageIDs: [MessageHeader.ID],
        to folder: Folder,
        backend: any MailBackend,
        sourceID: MailSourceID?
    ) async throws {
        if let sourceID {
            try await backend.move(messageIDs: messageIDs, to: folder, sourceID: sourceID)
        } else {
            try await backend.move(messageIDs: messageIDs, to: folder)
        }
    }

    private static func delete(
        _ messageIDs: [MessageHeader.ID],
        backend: any MailBackend,
        sourceID: MailSourceID?
    ) async throws {
        if let sourceID {
            try await backend.delete(messageIDs: messageIDs, sourceID: sourceID)
        } else {
            try await backend.delete(messageIDs: messageIDs)
        }
    }
}
