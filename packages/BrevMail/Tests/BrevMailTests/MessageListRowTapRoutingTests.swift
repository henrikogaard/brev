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
import CoreGraphics
import Testing

@Suite("MessageListRowTapRouting")
struct MessageListRowTapRoutingTests {
    private static let chevron = CGRect(x: 120, y: 8, width: 18, height: 18)

    @Test("a tap inside the thread chevron toggles the thread")
    func tapInsideChevronTogglesThread() {
        let destination = MessageListRowTapRouting.destination(
            for: CGPoint(x: 128, y: 16),
            threadToggleFrame: Self.chevron
        )

        #expect(destination == .toggleThread)
    }

    @Test("a tap just outside the chevron still toggles it within the slop margin")
    func tapWithinSlopMarginTogglesThread() {
        let destination = MessageListRowTapRouting.destination(
            for: CGPoint(x: 118, y: 6),
            threadToggleFrame: Self.chevron
        )

        #expect(destination == .toggleThread)
    }

    @Test("a tap on the row body activates the message")
    func tapOnRowBodyActivatesMessage() {
        let destination = MessageListRowTapRouting.destination(
            for: CGPoint(x: 40, y: 16),
            threadToggleFrame: Self.chevron
        )

        #expect(destination == .activate)
    }

    @Test("a row without a thread chevron always activates the message")
    func rowWithoutChevronActivates() {
        let destination = MessageListRowTapRouting.destination(
            for: .zero,
            threadToggleFrame: .zero
        )

        #expect(destination == .activate)
    }
}
