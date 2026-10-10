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

@Suite("Compose focus policy")
struct ComposeFocusPolicyTests {
    @Test("a new message focuses To")
    func newMessageFocusesTo() {
        #expect(ComposeFocusPolicy.initialField(hasRecipients: false, hasSubject: false) == .to)
    }

    @Test("a forward with no recipient focuses To")
    func forwardFocusesTo() {
        #expect(ComposeFocusPolicy.initialField(hasRecipients: false, hasSubject: true) == .to)
    }

    @Test("a reply, with recipient and subject filled in, focuses the body")
    func replyFocusesBody() {
        #expect(ComposeFocusPolicy.initialField(hasRecipients: true, hasSubject: true) == .body)
    }

    @Test("a mailto: link with recipients but no subject focuses Subject")
    func recipientsWithoutSubjectFocusSubject() {
        #expect(ComposeFocusPolicy.initialField(hasRecipients: true, hasSubject: false) == .subject)
    }

    @Test("Return in To, Cc and Bcc moves to the next visible field, then Subject, then body")
    func returnChainsFields() {
        #expect(ComposeFocusPolicy.field(after: .to, isCcVisible: false, isBccVisible: false) == .subject)
        #expect(ComposeFocusPolicy.field(after: .to, isCcVisible: true, isBccVisible: true) == .cc)
        #expect(ComposeFocusPolicy.field(after: .cc, isCcVisible: true, isBccVisible: true) == .bcc)
        #expect(ComposeFocusPolicy.field(after: .cc, isCcVisible: true, isBccVisible: false) == .subject)
        #expect(ComposeFocusPolicy.field(after: .bcc, isCcVisible: true, isBccVisible: true) == .subject)
        #expect(ComposeFocusPolicy.field(after: .subject, isCcVisible: false, isBccVisible: false) == .body)
        #expect(ComposeFocusPolicy.field(after: .body, isCcVisible: false, isBccVisible: false) == nil)
    }

    @Test("a reply with the quote below puts the caret at the top of the typing zone")
    func caretAboveBottomQuote() {
        let marker = "On Jan 1, Ada wrote:"
        let body = "\n\n\(marker)\n> hi" as NSString
        let range = ComposeFocusPolicy.initialBodySelection(
            in: body,
            quoteProtection: ComposeQuoteProtection(marker: marker, edge: .bottom)
        )
        #expect(range == NSRange(location: 0, length: 0))
    }

    @Test("a reply with the quote above puts the caret right after the quote")
    func caretBelowTopQuote() {
        let marker = "On Jan 1, Ada wrote:"
        let body = "\(marker)\n> hi\n\n" as NSString
        let range = ComposeFocusPolicy.initialBodySelection(
            in: body,
            quoteProtection: ComposeQuoteProtection(marker: marker, edge: .top)
        )
        #expect(range == NSRange(location: ("\(marker)\n> hi" as NSString).length, length: 0))
    }

    @Test("without a quote the caret goes to the end of existing text")
    func caretAtEndWithoutQuote() {
        let body = "Draft text" as NSString
        let range = ComposeFocusPolicy.initialBodySelection(in: body, quoteProtection: nil)
        #expect(range == NSRange(location: body.length, length: 0))
    }
}
