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

@Suite("MessageListRowIndicator")
struct MessageListRowIndicatorTests {
    @Test("headers without reply or forward state have no indicators")
    func headersWithoutReplyOrForwardStateHaveNoIndicators() {
        let header = Self.makeHeader()

        #expect(MessageListRowIndicator.indicators(for: header) == [])
    }

    @Test("answered and forwarded headers expose indicators in stable order")
    func answeredAndForwardedHeadersExposeIndicatorsInStableOrder() {
        let header = Self.makeHeader(isAnswered: true, isForwarded: true)

        #expect(MessageListRowIndicator.indicators(for: header) == [.answered, .forwarded])
    }

    @Test("indicators expose symbol names and accessibility labels")
    func indicatorsExposeSymbolNamesAndAccessibilityLabels() {
        #expect(MessageListRowIndicator.answered.symbolName == "arrowshape.turn.up.left.fill")
        #expect(MessageListRowIndicator.answered.accessibilityLabel == "Answered")
        #expect(MessageListRowIndicator.forwarded.symbolName == "arrowshape.turn.up.right.fill")
        #expect(MessageListRowIndicator.forwarded.accessibilityLabel == "Forwarded")
    }

    private static func makeHeader(
        isAnswered: Bool = false,
        isForwarded: Bool = false
    ) -> MessageHeader {
        MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            subject: "Hello",
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600),
            isAnswered: isAnswered,
            isForwarded: isForwarded
        )
    }
}
