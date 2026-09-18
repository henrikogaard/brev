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

@testable import BrevIOS
import Foundation
import Testing

@Suite("OneShotBGCompletion")
struct OneShotBGCompletionTests {
    @Test("only the first completion is forwarded")
    func firstCompletionWins() {
        var results: [Bool] = []
        let completion = OneShotBGCompletion { results.append($0) }

        completion.complete(success: true)
        completion.complete(success: false)
        completion.complete(success: true)

        #expect(results == [true])
    }

    @Test("a failing first completion is the result that sticks")
    func firstFailureWins() {
        var results: [Bool] = []
        let completion = OneShotBGCompletion { results.append($0) }

        completion.complete(success: false)
        completion.complete(success: true)

        #expect(results == [false])
    }

    @Test("concurrent completions resolve exactly once")
    func concurrentCompletionResolvesOnce() {
        let lock = NSLock()
        var completions = 0
        let completion = OneShotBGCompletion { _ in
            lock.lock()
            completions += 1
            lock.unlock()
        }

        // The work task and the expiration handler race to complete; only one
        // may win or the app crashes with "task completed multiple times".
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            completion.complete(success: index.isMultiple(of: 2))
        }

        #expect(completions == 1)
    }
}
