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

import BrevAI
@testable import BrevMail
import Testing

@Suite("Mailbox chat availability")
struct MailboxChatAvailabilityTests {
    @Test("availability requires enabled consented AI backend")
    func availabilityRequiresEnabledConsentedAIBackend() {
        let base = MailboxChatAvailabilityState(
            settings: AIWriterSettings(isEnabled: true, consentGiven: true),
            hasProviderBackend: true
        )

        #expect(MailboxChatAvailability.disabledReason(in: base) == nil)
        #expect(MailboxChatAvailability.disabledReason(in: base.with(hasProviderBackend: false)) == .missingBackend)
        #expect(MailboxChatAvailability.disabledReason(in: base.with(settings: .defaults)) == .notEnabled)
        #expect(MailboxChatAvailability.disabledReason(
            in: base.with(settings: AIWriterSettings(isEnabled: true, consentGiven: false))
        ) == .consentRequired)
    }

    @Test("composer interactivity requires idle enabled chat")
    func composerInteractivityRequiresIdleEnabledChat() {
        #expect(MailboxChatComposerPolicy.isComposerInteractive(
            isSending: false,
            disabledReason: nil
        ))
        #expect(!MailboxChatComposerPolicy.isComposerInteractive(
            isSending: true,
            disabledReason: nil
        ))
        #expect(!MailboxChatComposerPolicy.isComposerInteractive(
            isSending: false,
            disabledReason: .missingBackend
        ))
        #expect(!MailboxChatComposerPolicy.isComposerInteractive(
            isSending: false,
            disabledReason: .notEnabled
        ))
        #expect(!MailboxChatComposerPolicy.isComposerInteractive(
            isSending: false,
            disabledReason: .consentRequired
        ))
    }

    @Test("disabled sends either show consent or ignore")
    func disabledSendsEitherShowConsentOrIgnore() {
        #expect(MailboxChatComposerPolicy.sendOutcome(disabledReason: nil) == .send)
        #expect(MailboxChatComposerPolicy.sendOutcome(disabledReason: .missingBackend) == .ignore)
        #expect(MailboxChatComposerPolicy.sendOutcome(disabledReason: .notEnabled) == .showConsent)
        #expect(MailboxChatComposerPolicy.sendOutcome(disabledReason: .consentRequired) == .showConsent)
    }
}

private extension MailboxChatAvailabilityState {
    func with(
        settings: AIWriterSettings? = nil,
        hasProviderBackend: Bool? = nil
    ) -> MailboxChatAvailabilityState {
        MailboxChatAvailabilityState(
            settings: settings ?? self.settings,
            hasProviderBackend: hasProviderBackend ?? self.hasProviderBackend
        )
    }
}

@Suite("MailboxChatEmptyTranscriptPolicy")
struct MailboxChatEmptyTranscriptPolicyTests {
    @Test("empty transcript describes the panel rather than repeating the disabled reason")
    func emptyTranscriptDoesNotRepeatDisabledReason() {
        let message = MailboxChatEmptyTranscriptPolicy.message

        // The composer callout is the one place a disabled reason appears.
        let reasons: [MailboxChatDisabledReason] = [.missingBackend, .notEnabled, .consentRequired]
        for reason in reasons {
            #expect(message != reason.title)
        }
    }

    @Test("empty transcript message adds to its title rather than restating it")
    func emptyTranscriptDoesNotRestateItsTitle() {
        let message = MailboxChatEmptyTranscriptPolicy.message

        // The title is already an invitation to ask; the message has to earn
        // its line by saying something the title does not.
        #expect(!message.lowercased().hasPrefix("ask "))
        #expect(message.contains("cached on this Mac"))
    }
}
