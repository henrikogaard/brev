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

@Suite("Compose undo-send policy")
struct ComposeUndoSendPolicyTests {
    @Test("delay reads the shared compose settings key")
    func delayReadsSharedComposeSettingsKey() {
        let suiteName = "ComposeUndoSendPolicyTests.delayReads"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(10, forKey: ComposeUndoSendPolicy.delayKey)

        #expect(ComposeUndoSendPolicy.delaySeconds(defaults: defaults) == 10)
    }

    @Test("negative stored delay is treated as off")
    func negativeStoredDelayIsOff() {
        let suiteName = "ComposeUndoSendPolicyTests.negative"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(-5, forKey: ComposeUndoSendPolicy.delayKey)

        #expect(ComposeUndoSendPolicy.delaySeconds(defaults: defaults) == 0)
    }

    @Test("countdown emits every visible second before send")
    func countdownEmitsEveryVisibleSecondBeforeSend() {
        #expect(ComposeUndoSendPolicy.countdownValues(for: 5) == [5, 4, 3, 2, 1])
        #expect(ComposeUndoSendPolicy.countdownValues(for: 0).isEmpty)
    }
}
