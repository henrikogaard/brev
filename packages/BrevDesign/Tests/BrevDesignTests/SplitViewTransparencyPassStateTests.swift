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

#if os(macOS)
import AppKit
@testable import BrevDesign
import Testing

@Suite("Split-view transparency pass state")
struct SplitViewTransparencyPassStateTests {
    @Test("coalesces repeated layout requests in one run-loop turn")
    func coalescesRepeatedLayoutRequests() {
        var state = SplitViewTransparencyPassState()

        let firstRequest = state.requestImmediatePass()
        #expect(firstRequest)
        for _ in 0 ..< 100 {
            let repeatedRequest = state.requestImmediatePass()
            #expect(!repeatedRequest)
        }

        state.completeImmediatePass()
        let nextTurnRequest = state.requestImmediatePass()
        #expect(nextTurnRequest)
    }

    @Test("only the newest settled pass generation can run")
    func rejectsSupersededSettledPasses() {
        var state = SplitViewTransparencyPassState()

        let first = state.requestSettledPass()
        let second = state.requestSettledPass()

        #expect(!state.shouldRunSettledPass(first))
        #expect(state.shouldRunSettledPass(second))
    }

    @Test("coalesces passes across probes in the same split view")
    @MainActor
    func coalescesAcrossProbes() async throws {
        let splitView = NSSplitView()
        var applyCount = 0
        let coordinator = SplitViewTransparencyPassCoordinator(
            settledDelay: .milliseconds(20)
        ) { appliedSplitView in
            #expect(appliedSplitView === splitView)
            applyCount += 1
        }

        for _ in 0 ..< 100 {
            coordinator.requestPass(for: splitView)
        }

        // The stable contract is one immediate pass plus one settled pass.
        // Do not assert between their deadlines: a loaded executor can resume
        // this test after the settled deadline even when coalescing is correct.
        try await Task.sleep(for: .milliseconds(100))
        #expect(applyCount == 2)
    }
}
#endif
