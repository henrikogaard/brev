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

import Foundation

/// Account-scoped index adapter; the legacy cache is read only during migration.
actor IndexedIMAPMailboxHeaderCache: IMAPMailboxHeaderCache {
    let index: any IMAPHeaderPageIndex
    let account: BrevAccount
    private let legacy: (any IMAPMailboxHeaderCache)?
    private var migrations: [Folder.ID: Task<Void, Error>] = [:]

    init(index: any IMAPHeaderPageIndex, account: BrevAccount, legacy: (any IMAPMailboxHeaderCache)?) {
        self.index = index
        self.account = account
        self.legacy = legacy
    }

    func prepare(folderID: Folder.ID) async throws {
        if let migration = migrations[folderID] { return try await migration.value }
        let task = Task { [index, account, legacy] in
            if let snapshot = await legacy?.snapshot(accountID: account.id, folderID: folderID) {
                try await index.storeIMAPSnapshot(snapshot, folderID: folderID, account: account, importingLegacy: true)
                await legacy?.clear(accountID: account.id, folderID: folderID)
            }
        }
        migrations[folderID] = task
        do { try await task.value } catch {
            migrations.removeValue(forKey: folderID)
            throw error
        }
    }

    func metadata(folderID: Folder.ID) async throws -> IMAPHeaderMetadata? {
        try await prepare(folderID: folderID)
        return try await index.imapHeaderMetadata(folderID: folderID, account: account)
    }

    func snapshot(accountID: BrevAccount.ID, folderID: Folder.ID) async -> IMAPMailboxHeaderCacheSnapshot? {
        guard accountID == account.id else { return nil }
        do {
            try await prepare(folderID: folderID)
            return try await index.imapHeaderSnapshot(folderID: folderID, account: account)
        } catch { return nil }
    }

    func setSnapshot(_ snapshot: IMAPMailboxHeaderCacheSnapshot, accountID: BrevAccount.ID, folderID: Folder.ID) async {
        guard accountID == account.id else { return }
        do {
            try await prepare(folderID: folderID)
            try await index.storeIMAPSnapshot(snapshot, folderID: folderID, account: account, importingLegacy: false)
        } catch { return }
    }

    func clear(accountID: BrevAccount.ID, folderID: Folder.ID) async {
        guard accountID == account.id else { return }
        if let migration = migrations[folderID] { _ = try? await migration.value }
        await index.clearFolder(folderID: folderID, account: account)
        await legacy?.clear(accountID: accountID, folderID: folderID)
        migrations.removeValue(forKey: folderID)
    }

    func clear(accountID: BrevAccount.ID) async {
        guard accountID == account.id else { return }
        for migration in migrations.values {
            _ = try? await migration.value
        }
        await index.clearIMAPCache(account: account)
        await legacy?.clear(accountID: accountID)
        migrations.removeAll()
    }
}
