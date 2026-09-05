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

extension UndoQueue {
    /// Registers only provider-confirmed reversals; retries skip completed batches.
    func registerMoves(_ receipts: [MailMoveUndo?], description: String, lease: UndoMutationLease? = nil) {
        registerBatch(receipts.map { receipt in
            receipt.map { receipt in
                UndoableMutation(description: description) { _ = try await receipt.restore() }
            }
        }, description: description, lease: lease)
    }

    /// Registers a flag change without replacing history for an unchanged selection.
    func registerFlag(_ flag: MailFlagUndo.Flag, originals: [MessageHeader], newValue: Bool,
                      sourceID: MailSourceID, backend: any MailBackend, lease: UndoMutationLease? = nil) {
        guard originals.contains(where: { (flag == .read ? $0.isRead : $0.isFlagged) != newValue }) else { return }
        push(MailFlagUndo.action(flag, originals: originals, newValue: newValue, sourceID: sourceID,
                                 backend: backend, description: MailFlagUndo.description(flag, value: newValue)), lease: lease)
    }

    /// Groups successful operations into one Undo without repeating successful reversals on retry.
    func registerBatch(_ actions: [UndoableMutation?], description: String, lease: UndoMutationLease? = nil) {
        guard !actions.isEmpty else { return }
        // A generic "Undo" must cover the entire command. A batch containing
        // permanent deletions cannot promise that every selected message returns.
        guard actions.allSatisfy({ $0 != nil }) else {
            discardPendingUndo(lease: lease)
            return
        }
        let batch = MailUndoBatch(actions: actions.compactMap { $0 })
        push(UndoableMutation(description: description) { try await batch.restore() }, lease: lease)
    }
}

private actor MailUndoBatch {
    let actions: [UndoableMutation]
    private var nextIndex = 0

    init(actions: [UndoableMutation]) { self.actions = actions }

    func restore() async throws {
        while nextIndex < actions.count {
            try Task.checkCancellation()
            try await actions[nextIndex].undoAction()
            nextIndex += 1
        }
    }
}

enum MailFlagUndo {
    enum Flag: Sendable { case read, flagged }

    static func description(_ flag: Flag, value: Bool) -> String {
        switch flag {
        case .read: return value ? String(localized: "Marked as Read", bundle: .module) : String(
                localized: "Marked as Unread",
                bundle: .module
            )
        case .flagged: return value ? String(localized: "Flagged", bundle: .module) : String(
                localized: "Unflagged",
                bundle: .module
            )
        }
    }

    static func action(_ flag: Flag, originals: [MessageHeader], newValue: Bool, sourceID: MailSourceID,
                       backend: any MailBackend, description: String) -> UndoableMutation {
        let ids = originals.filter { (flag == .read ? $0.isRead : $0.isFlagged) != newValue }.map(\.id)
        return UndoableMutation(description: description) {
            guard !ids.isEmpty else { return }
            if flag == .read {
                try await backend.setRead(!newValue, for: ids, sourceID: sourceID)
            } else {
                try await backend.setFlagged(!newValue, for: ids, sourceID: sourceID)
            }
        }
    }
}

/// Shared delete semantics for toolbar, row, and bulk actions.
enum MailUndoableDelete {
    static func perform(messageIDs: [MessageHeader.ID], from folder: Folder, folders: [Folder],
                        sourceID: MailSourceID, backend: any MailBackend) async throws -> MailMoveUndo? {
        if let trash = folders.first(where: { $0.role == .trash }), folder.id != trash.id {
            return try await backend.moveWithUndo(messageIDs: messageIDs, from: folder, to: trash, sourceID: sourceID)
        }
        try await backend.delete(messageIDs: messageIDs, sourceID: sourceID)
        return nil
    }
}

/// Junk classification uses a provider reversal or a source-owned fallback move.
enum MailJunkUndo {
    static func description(_ isJunk: Bool) -> String {
        isJunk ? String(localized: "Reported Junk", bundle: .module)
            : String(localized: "Marked Not Junk", bundle: .module)
    }

    static func perform(_ isJunk: Bool, header: MessageHeader, folders: [Folder],
                        sourceID: MailSourceID, backend: any MailBackend) async throws -> UndoableMutation? {
        let title = description(isJunk)
        let destination = MessageCommandPresentation.junkFallbackFolder(isJunk: isJunk, folders: folders)
        // Label backends change mailbox membership when classifying junk. Their
        // move receipt preserves the original label delta, including archived mail.
        if !backend.capabilities.contains(.labels) {
            do {
                try await backend.setJunk(isJunk, for: [header.id], sourceID: sourceID)
                return UndoableMutation(description: title) {
                    try await backend.setJunk(!isJunk, for: [header.id], sourceID: sourceID)
                }
            } catch MailBackendError.notSupported {
                // Standards-only servers fall back to moving into Spam/Inbox.
            }
        }
        guard let destination else { throw MailBackendError.notSupported(backend.capabilities) }
        let origin = folders.first { $0.id == header.folderID }
            ?? Folder(id: header.folderID, name: header.folderID, role: .custom)
        let receipt = try await backend.moveWithUndo(messageIDs: [header.id], from: origin, to: destination, sourceID: sourceID)
        return receipt.map { receipt in
            UndoableMutation(description: title) { _ = try await receipt.restore() }
        }
    }
}
