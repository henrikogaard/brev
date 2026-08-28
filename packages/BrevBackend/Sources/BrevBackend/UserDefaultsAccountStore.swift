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

/// `AccountStore` backed by `UserDefaults`.
///
/// This stores account identity and current-account selection only.
/// OAuth tokens remain in `TokenStore`/Keychain.
public actor UserDefaultsAccountStore: AccountStore {
    private struct Snapshot: Codable {
        var accounts: [BrevAccount]
        var currentID: String?
    }

    private let userDefaults: UserDefaults
    private let key: String
    private var snapshot: Snapshot
    private var continuations: [UUID: AsyncStream<[BrevAccount]>.Continuation] = [:]

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = "app.brev.accounts"
    ) {
        self.userDefaults = userDefaults
        self.key = key
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = decoded
            if Self.normalizeCurrentSelection(&snapshot) {
                Self.persist(snapshot, userDefaults: userDefaults, key: key)
            }
        } else {
            snapshot = Snapshot(accounts: [], currentID: nil)
        }
    }

    public var accounts: [BrevAccount] {
        snapshot.accounts
    }

    public var current: BrevAccount? {
        snapshot.accounts.first { $0.id == snapshot.currentID }
    }

    public func setCurrent(_ id: String) {
        guard snapshot.accounts.contains(where: { $0.id == id }) else { return }
        snapshot.currentID = id
        persistAndEmit()
    }

    public func add(_ account: BrevAccount) {
        if let index = snapshot.accounts.firstIndex(where: { $0.id == account.id }) {
            snapshot.accounts[index] = account
        } else {
            snapshot.accounts.append(account)
        }
        _ = Self.normalizeCurrentSelection(&snapshot)
        persistAndEmit()
    }

    public func remove(_ id: String) {
        snapshot.accounts.removeAll { $0.id == id }
        _ = Self.normalizeCurrentSelection(&snapshot)
        persistAndEmit()
    }

    public nonisolated func subscribe() -> AsyncStream<[BrevAccount]> {
        AsyncStream { continuation in
            let token = UUID()
            Task { [weak self] in
                await self?.register(token: token, continuation: continuation)
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.unregister(token: token) }
            }
        }
    }

    private func register(
        token: UUID,
        continuation: AsyncStream<[BrevAccount]>.Continuation
    ) {
        continuations[token] = continuation
        continuation.yield(snapshot.accounts)
    }

    private func unregister(token: UUID) {
        continuations.removeValue(forKey: token)
    }

    private static func normalizeCurrentSelection(_ snapshot: inout Snapshot) -> Bool {
        let normalizedCurrentID: String?
        if let currentID = snapshot.currentID,
           snapshot.accounts.contains(where: { $0.id == currentID }) {
            normalizedCurrentID = currentID
        } else {
            normalizedCurrentID = snapshot.accounts.first?.id
        }

        guard snapshot.currentID != normalizedCurrentID else { return false }
        snapshot.currentID = normalizedCurrentID
        return true
    }

    private static func persist(
        _ snapshot: Snapshot,
        userDefaults: UserDefaults,
        key: String
    ) {
        if let data = try? JSONEncoder().encode(snapshot) {
            userDefaults.set(data, forKey: key)
        }
    }

    private func persistAndEmit() {
        Self.persist(snapshot, userDefaults: userDefaults, key: key)
        for continuation in continuations.values {
            continuation.yield(snapshot.accounts)
        }
    }
}
