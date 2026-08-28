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

@Suite("Compose HTML publication")
struct ComposeHTMLPublicationTests {
    @Test("rapid editor updates coalesce to the newest pending snapshot")
    func rapidUpdatesCoalesceToNewestPendingSnapshot() {
        var state = ComposeDebouncedPublicationState<String>()

        let first = state.schedule("first")
        let latest = state.schedule("latest")

        #expect(state.takePending(for: first) == nil)
        #expect(state.takePending(for: latest) == "latest")
    }

    @Test("flush publishes the pending snapshot and invalidates delayed work")
    func flushPublishesPendingSnapshotAndInvalidatesDelayedWork() {
        var state = ComposeDebouncedPublicationState<String>()
        let generation = state.schedule("before send")

        #expect(state.flush() == "before send")
        #expect(state.takePending(for: generation) == nil)
        #expect(state.flush() == nil)
    }

    @Test("controller flush publishes before a delayed task can run")
    @MainActor
    func controllerFlushPublishesBeforeDelayedTaskCanRun() {
        var published: [String] = []
        let controller = ComposeHTMLPublicationController<String>(
            delayNanoseconds: .max,
            serialize: { "html:\($0)" },
            publish: { published.append($0) }
        )

        controller.schedule("latest")
        controller.flush()

        #expect(published == ["html:latest"])
    }

    @Test("publication debounce stays below one interactive frame budget")
    func publicationDebounceStaysBounded() {
        #expect(ComposeHTMLPublicationPolicy.debounceNanoseconds <= 100_000_000)
        #expect(ComposeHTMLPublicationPolicy.debounceNanoseconds > 0)
    }
}
