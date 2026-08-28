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

@Suite("ComposeTextCheckingPolicy")
struct ComposeTextCheckingPolicyTests {
    @Test("text checking defaults to native spell-checking and autocorrect")
    func defaultConfigurationEnablesNativeChecking() {
        let configuration = ComposeTextCheckingPolicy.configuration(isEnabled: true)

        #expect(configuration.spellChecking == .native)
        #expect(configuration.grammarChecking == .native)
        #expect(configuration.autocorrection == .native)
    }

    @Test("disabled text checking turns off native helpers")
    func disabledConfigurationDisablesNativeChecking() {
        let configuration = ComposeTextCheckingPolicy.configuration(isEnabled: false)

        #expect(configuration.spellChecking == .disabled)
        #expect(configuration.grammarChecking == .disabled)
        #expect(configuration.autocorrection == .disabled)
    }

    @Test("settings copy names live spell-checking without implying AI")
    func settingsCopyNamesNativeChecking() {
        #expect(ComposeTextCheckingPolicy.settingsTitle == "Check spelling while typing")
        #expect(ComposeTextCheckingPolicy.settingsSubtitle.contains("system spell-check"))
        #expect(ComposeTextCheckingPolicy.storageKey == "compose.textChecking.enabled")
    }
}
