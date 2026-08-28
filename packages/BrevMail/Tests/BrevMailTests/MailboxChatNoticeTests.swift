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

@Suite("Mailbox chat notice")
struct MailboxChatNoticeTests {
    private let reasons: [MailboxChatDisabledReason] = [.missingBackend, .notEnabled, .consentRequired]

    @Test("every blocked state offers a way out")
    func everyBlockedStateOffersAWayOut() {
        // The missing-provider notice used to state the problem and stop there:
        // the only actionable control was gated behind `reason != .missingBackend`,
        // so the state a new install lands in was the one dead end.
        for reason in reasons {
            let notice = MailboxChatNotice(reason: reason)
            #expect(!notice.actionTitle.isEmpty)
        }
    }

    @Test("a missing provider is a warning and sends you to Settings")
    func missingProviderIsAWarningThatSendsYouToSettings() {
        let notice = MailboxChatNotice(reason: .missingBackend)

        #expect(notice.tone == .warning)
        #expect(notice.action == .openSettings)
        #expect(notice.actionTitle == "Set Up Provider…")
    }

    @Test("a provider that only needs turning on asks for consent, not Settings")
    func aProviderThatOnlyNeedsTurningOnAsksForConsent() {
        for reason in [MailboxChatDisabledReason.notEnabled, .consentRequired] {
            let notice = MailboxChatNotice(reason: reason)

            #expect(notice.tone == .info)
            #expect(notice.action == .showConsent)
            #expect(notice.actionTitle == "Enable AI Writer…")
        }
    }

    @Test("the notice never repeats the reason it already shows")
    func theNoticeNeverRepeatsTheReasonItAlreadyShows() {
        for reason in reasons {
            let notice = MailboxChatNotice(reason: reason)
            #expect(notice.message == reason.title)
            #expect(notice.actionTitle != reason.title)
        }
    }

    @Test("the ask field reads as a text area, not a search box")
    func theAskFieldReadsAsATextArea() {
        // At one line it read as a search box in a column this narrow. Two is
        // enough to say "type a sentence here" without crowding the transcript
        // above it, which the column is much shorter than.
        #expect(MailboxChatComposerPolicy.visibleLineLimit.lowerBound >= 2)
        #expect(MailboxChatComposerPolicy.visibleLineLimit.upperBound
            > MailboxChatComposerPolicy.visibleLineLimit.lowerBound)
    }

    @Test("send is a bare arrow, and the circle comes from the button")
    func sendIsABareArrow() {
        let symbol = MailboxChatComposerPolicy.sendSymbolName

        #expect(symbol == "arrow.up")
        // Same trap as the mailbox filter glyph: a `.circle` variant inside a
        // button that already draws a circular container is a circle in a circle.
        #expect(!symbol.contains("circle"))
    }

    @Test("a blocked composer says it is blocked instead of inviting a question")
    func aBlockedComposerSaysItIsBlocked() {
        let inviting = MailboxChatComposerPolicy.placeholder(
            subject: "all folders",
            disabledReason: nil
        )
        #expect(inviting == "Ask about all folders…")

        for reason in reasons {
            let blocked = MailboxChatComposerPolicy.placeholder(
                subject: "all folders",
                disabledReason: reason
            )
            #expect(blocked != inviting)
            #expect(blocked == "Unavailable")
        }
    }
}
