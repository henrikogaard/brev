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

/// Shared render resources for the cards of one `ThreadConversationView`.
///
/// "Expand All" on a long thread otherwise lets every card spin up its own
/// `WKWebView` and fire its body/CID fetches in parallel. The pool keeps a
/// small least-recently-used set of `HTMLBodyWebViewStore`s so cards that
/// remount while scrolling reuse a warm WebKit process, and it funnels body
/// and attachment loads through a fixed number of permits — the same budget
/// `MailConcurrentWork` gives mailbox fetches.
///
/// Every call site is view init/body/task code running on the main actor.
@MainActor
final class ThreadConversationRenderPool {
    /// Number of web-view stores kept warm for card (re)use — roughly one
    /// screenful of expanded cards.
    nonisolated static let defaultWebViewStoreCapacity = 8
    /// Matches `MailConcurrentWork`'s parallelism: enough to pipeline fetches
    /// without flooding the backend on mass expansion.
    nonisolated static let defaultBodyLoadPermits = 4

    private let webViewStoreCapacity: Int
    private let bodyLoadPermitCount: Int
    private var stores: [MessageHeader.ID: HTMLBodyWebViewStore] = [:]
    /// Checkout order, oldest first; the head is the eviction candidate.
    private var checkoutOrder: [MessageHeader.ID] = []
    private var activeBodyLoads = 0
    private var bodyLoadWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        webViewStoreCapacity: Int = ThreadConversationRenderPool.defaultWebViewStoreCapacity,
        bodyLoadPermits: Int = ThreadConversationRenderPool.defaultBodyLoadPermits
    ) {
        self.webViewStoreCapacity = max(1, webViewStoreCapacity)
        bodyLoadPermitCount = max(1, bodyLoadPermits)
    }

    /// Number of stores currently tracked by the pool (testing hook).
    var pooledStoreCount: Int { stores.count }

    /// Returns the pooled store for `messageID`, evicting and releasing the
    /// least-recently-used slot once the pool is full. The returned store
    /// belongs to the caller; eviction only drops the pool's own reference,
    /// so a still-visible card is never disrupted mid-render.
    func checkoutWebViewStore(for messageID: MessageHeader.ID) -> HTMLBodyWebViewStore {
        if let store = stores[messageID] {
            touch(messageID)
            return store
        }
        if stores.count >= webViewStoreCapacity, let evictedID = checkoutOrder.first {
            checkoutOrder.removeFirst()
            stores.removeValue(forKey: evictedID)?.releaseWebView()
        }
        let store = HTMLBodyWebViewStore()
        stores[messageID] = store
        checkoutOrder.append(messageID)
        return store
    }

    /// Drops the pool's reference for `messageID` and releases its WebKit
    /// instance, freeing the slot for another card. Callers that keep their
    /// own store reference keep rendering — the pool only loses track of it.
    func releaseWebViewStore(for messageID: MessageHeader.ID) {
        stores.removeValue(forKey: messageID)?.releaseWebView()
        checkoutOrder.removeAll { $0 == messageID }
    }

    /// Runs `operation` after acquiring a body-load permit, suspending while
    /// every permit is checked out. Permits transfer directly from a releaser
    /// to the next waiter — the same slot protocol `AvatarResolver` uses.
    func withBodyLoadPermit<T>(
        _ operation: () async throws -> T
    ) async rethrows -> T {
        if activeBodyLoads < bodyLoadPermitCount {
            activeBodyLoads += 1
        } else {
            await withCheckedContinuation { continuation in
                bodyLoadWaiters.append(continuation)
            }
        }
        defer { releaseBodyLoadPermit() }
        return try await operation()
    }

    private func touch(_ messageID: MessageHeader.ID) {
        checkoutOrder.removeAll { $0 == messageID }
        checkoutOrder.append(messageID)
    }

    private func releaseBodyLoadPermit() {
        if let next = bodyLoadWaiters.first {
            bodyLoadWaiters.removeFirst()
            next.resume()
        } else {
            activeBodyLoads -= 1
        }
    }
}
