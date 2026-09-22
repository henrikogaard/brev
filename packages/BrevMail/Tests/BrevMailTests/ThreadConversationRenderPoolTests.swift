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

@testable import BrevMail
import Foundation
import Testing

@Suite("Thread conversation render pool")
struct ThreadConversationRenderPoolTests {
    @Test("checkout returns the same store for a message and evicts LRU")
    @MainActor
    func checkoutReusesAndEvictsLRU() {
        let pool = ThreadConversationRenderPool(webViewStoreCapacity: 2)
        let first = pool.checkoutWebViewStore(for: "a")
        let second = pool.checkoutWebViewStore(for: "b")

        #expect(pool.checkoutWebViewStore(for: "a") === first)
        #expect(pool.pooledStoreCount == 2)

        // "a" was just touched, so "b" is the eviction candidate.
        _ = pool.checkoutWebViewStore(for: "c")
        #expect(pool.pooledStoreCount == 2)
        #expect(pool.checkoutWebViewStore(for: "b") !== second)
    }

    @Test("release frees the pool slot")
    @MainActor
    func releaseFreesSlot() {
        let pool = ThreadConversationRenderPool(webViewStoreCapacity: 1)
        _ = pool.checkoutWebViewStore(for: "a")
        pool.releaseWebViewStore(for: "a")

        #expect(pool.pooledStoreCount == 0)

        let store = pool.checkoutWebViewStore(for: "b")
        #expect(pool.pooledStoreCount == 1)
        #expect(pool.checkoutWebViewStore(for: "b") === store)
    }

    @Test("body-load permits bound concurrency to the pool budget")
    @MainActor
    func bodyLoadPermitsBoundConcurrency() async {
        let permits = 2
        let pool = ThreadConversationRenderPool(bodyLoadPermits: permits)
        var active = 0
        var maxActive = 0

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 6 {
                // Main-actor children keep the counter mutations race-free;
                // Task.yield still lets waiters interleave inside a permit.
                group.addTask { @MainActor in
                    try? await pool.withBodyLoadPermit {
                        active += 1
                        maxActive = max(maxActive, active)
                        await Task.yield()
                        active -= 1
                    }
                }
            }
        }

        #expect(maxActive <= permits)
        #expect(maxActive > 0)
    }

    @Test("a cancelled permit waiter stops waiting and frees the queue")
    @MainActor
    func cancelledWaiterStopsWaiting() async throws {
        let pool = ThreadConversationRenderPool(bodyLoadPermits: 1)
        var releaseHolder: CheckedContinuation<Void, Never>?
        await withCheckedContinuation { holderReady in
            Task { @MainActor in
                try? await pool.withBodyLoadPermit {
                    await withCheckedContinuation { done in
                        releaseHolder = done
                        holderReady.resume()
                    }
                }
            }
        }

        // Occupy the only permit, then queue a waiter and cancel it while
        // it is suspended — this is the collapse/thread-switch path from
        // #51 that used to leave the card loading forever.
        let waiter = Task { @MainActor in
            try await pool.withBodyLoadPermit {
                "acquired"
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        waiter.cancel()

        let outcome = await waiter.result
        #expect(throws: CancellationError.self) {
            try outcome.get()
        }

        // The queue must stay healthy: releasing the holder lets a fresh
        // caller acquire the permit.
        releaseHolder?.resume()
        let next = try await pool.withBodyLoadPermit { "acquired" }
        #expect(next == "acquired")
    }
}
