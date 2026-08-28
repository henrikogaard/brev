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

@Suite("ComposeSignatureBodyPolicy")
struct ComposeSignatureBodyPolicyTests {
    @Test("selected signature appears in an empty compose body")
    func selectedSignatureAppearsInEmptyComposeBody() {
        let body = ComposeSignatureBodyPolicy.body(
            afterSelecting: "Henrik\nBrev",
            in: "",
            replacing: nil
        )

        #expect(body == "\n\n-- \nHenrik\nBrev")
    }

    @Test("selected signature is appended after user content")
    func selectedSignatureIsAppendedAfterUserContent() {
        let body = ComposeSignatureBodyPolicy.body(
            afterSelecting: "Henrik\nBrev",
            in: "Hello",
            replacing: nil
        )

        #expect(body == "Hello\n\n-- \nHenrik\nBrev")
    }

    @Test("switching signatures replaces the managed signature block")
    func switchingSignaturesReplacesManagedSignatureBlock() {
        let body = ComposeSignatureBodyPolicy.body(
            afterSelecting: "Personal",
            in: "\n\n-- \nWork",
            replacing: "Work"
        )

        #expect(body == "\n\n-- \nPersonal")
    }

    @Test("choosing no signature removes the managed signature block")
    func choosingNoSignatureRemovesManagedSignatureBlock() {
        let body = ComposeSignatureBodyPolicy.body(
            afterSelecting: nil,
            in: "Hello\n\n-- \nHenrik\nBrev",
            replacing: "Henrik\nBrev"
        )

        #expect(body == "Hello")
    }

    @Test("selecting an already visible signature does not duplicate it")
    func selectingAlreadyVisibleSignatureDoesNotDuplicateIt() {
        let currentBody = "Hello\n\n-- \nHenrik\nBrev"

        let body = ComposeSignatureBodyPolicy.body(
            afterSelecting: "Henrik\nBrev",
            in: currentBody,
            replacing: nil
        )

        #expect(body == currentBody)
    }

    @Test("reply signatures are inserted before the quoted original")
    func replySignaturesAreInsertedBeforeQuotedOriginal() {
        let replyBody = """


        On 28 May 2026 at 09:30 UTC, Alex Chen <alex@example.org> wrote:
        > Launch notes
        """

        let body = ComposeSignatureBodyPolicy.body(
            afterSelecting: "Henrik\nBrev",
            in: replyBody,
            replacing: nil
        )

        #expect(body == """


        -- 
        Henrik
        Brev

        On 28 May 2026 at 09:30 UTC, Alex Chen <alex@example.org> wrote:
        > Launch notes
        """)
    }

    @Test("switching reply signatures keeps the quoted original below the signature")
    func switchingReplySignaturesKeepsQuotedOriginalBelowSignature() {
        let replyBody = """
        Thanks

        -- 
        Work

        On 28 May 2026 at 09:30 UTC, Alex Chen <alex@example.org> wrote:
        > Launch notes
        """

        let body = ComposeSignatureBodyPolicy.body(
            afterSelecting: "Personal",
            in: replyBody,
            replacing: "Work"
        )

        #expect(body == """
        Thanks

        -- 
        Personal

        On 28 May 2026 at 09:30 UTC, Alex Chen <alex@example.org> wrote:
        > Launch notes
        """)
    }
}
