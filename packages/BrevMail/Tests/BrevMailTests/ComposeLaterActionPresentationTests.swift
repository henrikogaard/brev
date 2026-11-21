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

@Suite("Compose Later action presentation")
struct ComposeLaterActionPresentationTests {
    @Test("Later is a primary action adjacent to Send on both platforms")
    func laterIsAdjacentToSend() throws {
        for platform: ComposeLayoutPlatform in [.compactIOS, .compactIOSAccessibility, .regularIOS, .macOS] {
            let layout = ComposePresentation.toolbarActionLayout(for: platform)
            let laterIndex = try #require(layout.primaryActions.firstIndex(of: .scheduleSend))
            let sendIndex = try #require(layout.primaryActions.firstIndex(of: .send))

            #expect(abs(laterIndex - sendIndex) == 1)
            #expect(layout.overflowActions.contains(.scheduleSend))
        }
    }

    @Test("Later requires scheduling capability and an unblocked composer")
    func laterRequiresCapabilityAndIdleComposer() {
        #expect(ComposePresentation.canPresentScheduleSend(
            hasCapability: true,
            isInteractionBlocked: false
        ))
        #expect(!ComposePresentation.canPresentScheduleSend(
            hasCapability: false,
            isInteractionBlocked: false
        ))
        #expect(!ComposePresentation.canPresentScheduleSend(
            hasCapability: true,
            isInteractionBlocked: true
        ))
        #expect(!ComposePresentation.canPresentScheduleSend(
            hasCapability: false,
            isInteractionBlocked: true
        ))
    }
}
