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
import Testing

@Suite("MailStartupPhase")
struct MailStartupPhaseTests {
    @Test("phase controller advances only forward")
    @MainActor
    func phaseControllerAdvancesOnlyForward() {
        let controller = MailStartupPhaseController()
        #expect(controller.phase == .cold)
        #expect(controller.advance(to: .cachedUsable))
        #expect(controller.phase == .cachedUsable)
        #expect(!controller.advance(to: .cold))
        #expect(controller.phase == .cachedUsable)
        #expect(controller.advance(to: .interactive))
        #expect(controller.allows(.cachedUsable))
        #expect(controller.advance(to: .background))
        #expect(controller.allows(.background))
    }
}
