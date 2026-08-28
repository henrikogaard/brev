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
import BrevSettings
import Foundation
import Testing

@Suite("ComposeTemplateBodyPolicy")
struct ComposeTemplateBodyPolicyTests {
    @Test("applying a template inserts subject and body into an empty draft")
    func applyingTemplateInsertsSubjectAndBodyIntoEmptyDraft() {
        let template = MessageTemplate(
            name: "Intro",
            body: "Hello team",
            subject: "Quick update"
        )

        let body = ComposeTemplateBodyPolicy.body(
            applying: template,
            to: "",
            selection: nil,
            insertionPoint: nil,
            currentSignatureBody: nil,
            previousSignatureBody: nil
        )

        #expect(body == "Hello team")
        #expect(ComposeTemplateBodyPolicy.subject(applying: template, to: "Old subject") == "Quick update")
    }

    @Test("applying a template replaces the selected text")
    func applyingTemplateReplacesSelectedText() {
        let template = MessageTemplate(
            name: "Replace",
            body: "Thank you",
            subject: nil
        )
        let selection = ComposeBodyTextSelection(
            bodyText: "Hello world",
            nsRange: NSRange(location: 6, length: 5)
        )

        let body = ComposeTemplateBodyPolicy.body(
            applying: template,
            to: "Hello world",
            selection: selection,
            insertionPoint: nil,
            currentSignatureBody: nil,
            previousSignatureBody: nil
        )

        #expect(body == "Hello Thank you")
    }

    @Test("applying a template inserts at the cursor and keeps the signature at the end")
    func applyingTemplateInsertsAtCursorAndKeepsSignatureAtEnd() {
        let template = MessageTemplate(
            name: "Snippet",
            body: "One line",
            subject: nil
        )
        let insertionPoint = ComposeBodyInsertionPoint(
            bodyText: "Hello",
            nsRange: NSRange(location: 5, length: 0)
        )

        let body = ComposeTemplateBodyPolicy.body(
            applying: template,
            to: "Hello\n\n-- \nHenrik",
            selection: nil,
            insertionPoint: insertionPoint,
            currentSignatureBody: "Henrik",
            previousSignatureBody: "Henrik"
        )

        #expect(body == "Hello\n\nOne line\n\n-- \nHenrik")
    }

    @Test("blank template bodies leave the draft body unchanged")
    func blankTemplateBodiesLeaveTheDraftBodyUnchanged() {
        let template = MessageTemplate(
            name: "Blank",
            body: "   ",
            subject: nil
        )

        let body = ComposeTemplateBodyPolicy.body(
            applying: template,
            to: "Hello",
            selection: nil,
            insertionPoint: nil,
            currentSignatureBody: nil,
            previousSignatureBody: nil
        )

        #expect(body == "Hello")
    }
}
