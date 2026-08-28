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
@testable import BrevMail
import Foundation
import Testing

@Suite("ThreadConversationExpansionPolicy")
struct ThreadConversationExpansionTests {
    private static let epoch = Date(timeIntervalSince1970: 0)

    private static func makeHeader(id: String, date: Date = epoch) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "t",
            folderID: "inbox",
            from: Correspondent(name: "Ada", email: "ada@example.org"),
            subject: "Subject",
            snippet: "",
            date: date,
            isRead: false
        )
    }

    @Test("default expanded ID is the newest header's ID")
    func defaultExpandedIDIsNewest() {
        let older = Self.makeHeader(id: "older", date: Self.epoch)
        let newer = Self.makeHeader(id: "newer", date: Self.epoch.addingTimeInterval(60))
        // Headers arrive oldest→newest (already sorted by ThreadMessageDerivation)
        let result = ThreadConversationExpansionPolicy.defaultExpandedID(in: [older, newer])
        #expect(result == "newer")
    }

    @Test("default expanded ID is nil for empty array")
    func defaultExpandedIDIsNilForEmpty() {
        let result = ThreadConversationExpansionPolicy.defaultExpandedID(in: [])
        #expect(result == nil)
    }

    @Test("default expanded ID is the only element for single-message thread")
    func defaultExpandedIDIsSingleElement() {
        let only = Self.makeHeader(id: "only")
        let result = ThreadConversationExpansionPolicy.defaultExpandedID(in: [only])
        #expect(result == "only")
    }

    @Test("selected header expands when it belongs to the thread")
    func selectedHeaderExpandsWhenItBelongsToThread() {
        let older = Self.makeHeader(id: "older")
        let newer = Self.makeHeader(id: "newer")

        let result = ThreadConversationExpansionPolicy.expandedID(
            selectedID: older.id,
            in: [older, newer]
        )

        #expect(result == older.id)
    }

    @Test("selected header falls back to newest when it is not in the thread")
    func selectedHeaderFallsBackToNewestWhenMissing() {
        let older = Self.makeHeader(id: "older", date: Self.epoch)
        let newer = Self.makeHeader(id: "newer", date: Self.epoch.addingTimeInterval(60))

        let result = ThreadConversationExpansionPolicy.expandedID(
            selectedID: "missing",
            in: [older, newer]
        )

        #expect(result == newer.id)
    }

    @Test("thread view preserves heading context at accessibility text sizes")
    func threadViewPreservesHeadingContextAtAccessibilityTextSizes() {
        let shouldScroll = ThreadConversationAccessibilityPolicy.shouldAutoScrollToExpandedMessage(
            autoScrollsToExpandedMessage: true,
            isAccessibilitySize: true
        )

        #expect(!shouldScroll)
    }

    @Test("thread view keeps normal expanded-message auto scroll at standard text sizes")
    func threadViewKeepsNormalExpandedMessageAutoScrollAtStandardTextSizes() {
        let shouldScroll = ThreadConversationAccessibilityPolicy.shouldAutoScrollToExpandedMessage(
            autoScrollsToExpandedMessage: true,
            isAccessibilitySize: false
        )

        #expect(shouldScroll)
    }

    @Test("thread view respects disabled auto scroll at every text size")
    func threadViewRespectsDisabledAutoScrollAtEveryTextSize() {
        #expect(!ThreadConversationAccessibilityPolicy.shouldAutoScrollToExpandedMessage(
            autoScrollsToExpandedMessage: false,
            isAccessibilitySize: false
        ))
        #expect(!ThreadConversationAccessibilityPolicy.shouldAutoScrollToExpandedMessage(
            autoScrollsToExpandedMessage: false,
            isAccessibilitySize: true
        ))
    }

    @Test("dense mail chrome caps dynamic type before accessibility sizes")
    func denseMailChromeCapsDynamicTypeBeforeAccessibilitySizes() {
        #expect(MailDenseChromeDynamicType.range.upperBound == .xxxLarge)
        #expect(!MailDenseChromeDynamicType.range.upperBound.isAccessibilitySize)
    }

    @Test("compact mail chrome stays at normal control scale")
    func compactMailChromeStaysAtNormalControlScale() {
        #expect(MailDenseChromeDynamicType.compactRange.upperBound == .large)
        #expect(!MailDenseChromeDynamicType.compactRange.upperBound.isAccessibilitySize)
    }
}
