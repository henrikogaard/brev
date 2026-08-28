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

@Suite("ComposeAIAvailabilityState")
struct ComposeAIAvailabilityStateTests {
    @Test("shared settings drive compose action availability")
    func sharedSettingsDriveComposeActionAvailability() {
        let disabled = ComposeAIAvailabilityState(
            settings: .defaults,
            hasProviderBackend: true,
            backendSupportsAIWriter: true,
            isBusy: false,
            hasActiveRequest: false
        )

        #expect(disabled.context(bodyText: "Draft").isEnabled == false)
        #expect(ComposeAIActionAvailability.disabledReason(
            for: .shortcut(.improveWriting, scope: .wholeDraft),
            in: disabled.context(bodyText: "Draft")
        ) == .notEnabled)

        let enabled = disabled.with(settings: AIWriterSettings(isEnabled: true, consentGiven: true))

        #expect(enabled.context(bodyText: "Draft").isEnabled)
        #expect(enabled.context(bodyText: "Draft").hasConsent)
        #expect(ComposeAIActionAvailability.disabledReason(
            for: .shortcut(.improveWriting, scope: .wholeDraft),
            in: enabled.context(bodyText: "Draft")
        ) == nil)
    }

    @Test("unsupported account is distinct from provider construction failure")
    func unsupportedAccountIsDistinctFromProviderConstructionFailure() {
        let settings = AIWriterSettings(isEnabled: true, consentGiven: true)
        let unsupported = ComposeAIAvailabilityState(
            settings: settings,
            hasProviderBackend: false,
            backendSupportsAIWriter: false,
            isBusy: false,
            hasActiveRequest: false
        )
        let missingProvider = ComposeAIAvailabilityState(
            settings: settings,
            hasProviderBackend: false,
            backendSupportsAIWriter: true,
            isBusy: false,
            hasActiveRequest: false
        )

        #expect(ComposeAIActionAvailability.disabledReason(
            for: .draftFromPrompt,
            in: unsupported.context(bodyText: "", promptText: "Reply")
        ) == .unsupportedAccount)
        #expect(unsupported.providerUnavailableReason == .unsupportedAccount)
        #expect(ComposeAIActionAvailability.disabledReason(
            for: .draftFromPrompt,
            in: missingProvider.context(bodyText: "", promptText: "Reply")
        ) == .missingBackend)
        #expect(missingProvider.providerUnavailableReason == .missingBackend)
    }

    @Test("busy and active request states remain visible after settings are available")
    func busyAndActiveRequestStatesRemainVisibleAfterSettingsAreAvailable() {
        let base = ComposeAIAvailabilityState(
            settings: AIWriterSettings(isEnabled: true, consentGiven: true),
            hasProviderBackend: true,
            backendSupportsAIWriter: true,
            isBusy: false,
            hasActiveRequest: false
        )

        #expect(ComposeAIActionAvailability.disabledReason(
            for: .suggestSubject,
            in: base.with(isBusy: true).context(bodyText: "Draft")
        ) == .busy)
        #expect(ComposeAIActionAvailability.disabledReason(
            for: .suggestSubject,
            in: base.with(hasActiveRequest: true).context(bodyText: "Draft")
        ) == .requestInFlight)
    }
}

private extension ComposeAIAvailabilityState {
    func with(
        settings: AIWriterSettings? = nil,
        isBusy: Bool? = nil,
        hasActiveRequest: Bool? = nil
    ) -> ComposeAIAvailabilityState {
        ComposeAIAvailabilityState(
            settings: settings ?? self.settings,
            hasProviderBackend: hasProviderBackend,
            backendSupportsAIWriter: backendSupportsAIWriter,
            isBusy: isBusy ?? self.isBusy,
            hasActiveRequest: hasActiveRequest ?? self.hasActiveRequest
        )
    }
}
