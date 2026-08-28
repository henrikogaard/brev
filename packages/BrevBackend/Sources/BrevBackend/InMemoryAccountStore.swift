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

/// In-memory `AccountStore` used by previews, tests, and the mock
/// backend. Backed by an actor for safe concurrent access.
public actor InMemoryAccountStore: AccountStore {
    private var _accounts: [BrevAccount]
    private var _currentID: String?
    private var continuations: [UUID: AsyncStream<[BrevAccount]>.Continuation] = [:]

    public init(accounts: [BrevAccount] = [], current: BrevAccount? = nil) {
        _accounts = accounts
        _currentID = current?.id
    }

    public var accounts: [BrevAccount] { _accounts }
    public var current: BrevAccount? { _accounts.first { $0.id == _currentID } }

    public func setCurrent(_ id: String) {
        guard _accounts.contains(where: { $0.id == id }) else { return }
        _currentID = id
        emit()
    }

    public func add(_ account: BrevAccount) {
        if let idx = _accounts.firstIndex(where: { $0.id == account.id }) {
            _accounts[idx] = account
        } else {
            _accounts.append(account)
        }
        if _currentID == nil { _currentID = account.id }
        emit()
    }

    public func remove(_ id: String) {
        _accounts.removeAll { $0.id == id }
        if _currentID == id { _currentID = _accounts.first?.id }
        emit()
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
        continuation.yield(_accounts)
    }

    private func unregister(token: UUID) {
        continuations.removeValue(forKey: token)
    }

    private func emit() {
        for continuation in continuations.values {
            continuation.yield(_accounts)
        }
    }
}
