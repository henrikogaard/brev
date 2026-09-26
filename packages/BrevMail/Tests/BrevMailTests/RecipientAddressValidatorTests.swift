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

@Suite("RecipientAddressValidator")
struct RecipientAddressValidatorTests {
    @Test(
        "accepts addresses that look like email",
        arguments: [
            "ada@example.org",
            "ada.lovelace+tag@mail.example.co.uk",
            "  henrik@ogard.no  "
        ]
    )
    func acceptsLikelyAddresses(_ address: String) {
        #expect(RecipientAddressValidator.isLikelyEmailAddress(address))
    }

    @Test(
        "rejects obvious non-addresses",
        arguments: [
            "",
            "ada",
            "ada@",
            "@example.org",
            "ada@example",
            "ada@.org",
            "ada@org.",
            "ada lovelace@example.org",
            "ada@@example.org"
        ]
    )
    func rejectsNonAddresses(_ address: String) {
        #expect(!RecipientAddressValidator.isLikelyEmailAddress(address))
    }
}

@Suite("RecipientChipFieldPresentation")
struct RecipientChipFieldPresentationTests {
    @Test("placeholder is hidden once a recipient chip exists")
    func placeholderIsHiddenOnceRecipientChipExists() {
        #expect(RecipientChipFieldPresentation.promptText(recipientCount: 0) == "name@example.com")
        #expect(RecipientChipFieldPresentation.promptText(recipientCount: 1) == nil)
        #expect(RecipientChipFieldPresentation.promptText(recipientCount: 3) == nil)
    }

    @Test("a space does not commit incomplete input")
    func spaceLeavesIncompleteInput() {
        #expect(RecipientChipFieldPresentation.commitAction(afterTyping: "he ") == .none)
        #expect(RecipientChipFieldPresentation.commitAction(afterTyping: "He ") == .none)
    }

    @Test("a space commits once the text looks like an address")
    func spaceCommitsValidAddress() {
        #expect(
            RecipientChipFieldPresentation.commitAction(afterTyping: "henrik@ex.com ")
                == .commit("henrik@ex.com")
        )
    }

    @Test("comma and semicolon always commit the preceding text")
    func separatorsCommitAnyText() {
        #expect(RecipientChipFieldPresentation.commitAction(afterTyping: "he,") == .commit("he"))
        #expect(RecipientChipFieldPresentation.commitAction(afterTyping: "he;") == .commit("he"))
    }

    @Test("ordinary keystrokes do nothing")
    func ordinaryKeystrokesDoNothing() {
        #expect(RecipientChipFieldPresentation.commitAction(afterTyping: "hen") == .none)
        #expect(RecipientChipFieldPresentation.commitAction(afterTyping: "") == .none)
    }
}
