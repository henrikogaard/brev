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
    private var bodyLoadWaiters: [BodyLoadWaiter] = []
    private var bodyLoadWaiterSequence = 0

    private struct BodyLoadWaiter {
        let id: Int
        let continuation: CheckedContinuation<Bool, Never>
    }

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
    ///
    /// The wait is cancellation-aware: a card whose `.task` is cancelled
    /// while queued (collapse, thread switch, scroll off-screen) throws
    /// `CancellationError` instead of suspending forever with its loading
    /// state stuck on — the stuck-spinner defect from #51.
    func withBodyLoadPermit<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        if activeBodyLoads < bodyLoadPermitCount {
            activeBodyLoads += 1
        } else {
            let acquired = await waitForBodyLoadPermit()
            if !acquired {
                throw CancellationError()
            }
        }
        defer { releaseBodyLoadPermit() }
        return try await operation()
    }

    /// Suspends until a permit is handed over by a releaser, or returns
    /// `false` when the calling task is cancelled while still queued.
    /// A waiter already resumed by a releaser ignores late cancellation —
    /// it owns the transferred permit and must run and release it.
    private func waitForBodyLoadPermit() async -> Bool {
        let waiterID = nextBodyLoadWaiterID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                bodyLoadWaiters.append(
                    BodyLoadWaiter(id: waiterID, continuation: continuation)
                )
            }
        } onCancel: {
            Task { @MainActor in
                cancelBodyLoadWaiter(id: waiterID)
            }
        }
    }

    private func nextBodyLoadWaiterID() -> Int {
        bodyLoadWaiterSequence += 1
        return bodyLoadWaiterSequence
    }

    private func cancelBodyLoadWaiter(id: Int) {
        guard let index = bodyLoadWaiters.firstIndex(where: { $0.id == id })
        else { return }
        let waiter = bodyLoadWaiters.remove(at: index)
        // Resume with `false`: the caller never acquired a permit, so it
        // throws CancellationError without touching the permit count.
        waiter.continuation.resume(returning: false)
    }

    private func touch(_ messageID: MessageHeader.ID) {
        checkoutOrder.removeAll { $0 == messageID }
        checkoutOrder.append(messageID)
    }

    private func releaseBodyLoadPermit() {
        if let next = bodyLoadWaiters.first {
            bodyLoadWaiters.removeFirst()
            next.continuation.resume(returning: true)
        } else {
            activeBodyLoads -= 1
        }
    }
}
