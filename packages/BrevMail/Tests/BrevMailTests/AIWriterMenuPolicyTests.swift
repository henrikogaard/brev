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

@Suite("AIWriterMenuPolicy")
struct AIWriterMenuPolicyTests {
    @Test("blank compose text keeps the menu available for first-use consent")
    func blankComposeTextKeepsMenuAvailableForConsent() {
        #expect(AIWriterMenuPolicy.isMenuDisabled(
            isBusy: false,
            isAIWorking: false
        ) == false)
    }

    @Test("busy compose disables the whole menu")
    func busyComposeDisablesWholeMenu() {
        #expect(AIWriterMenuPolicy.isMenuDisabled(
            isBusy: true,
            isAIWorking: false
        ))
        #expect(AIWriterMenuPolicy.isMenuDisabled(
            isBusy: false,
            isAIWorking: true
        ))
    }

    @Test("blank compose text disables AI shortcut actions")
    func blankComposeTextDisablesShortcutActions() {
        #expect(AIWriterMenuPolicy.areShortcutsDisabled(bodyText: " \n\t "))
    }

    @Test("nonblank compose text enables AI shortcut actions")
    func nonblankComposeTextEnablesShortcutActions() {
        #expect(AIWriterMenuPolicy.areShortcutsDisabled(bodyText: "Draft this nicer") == false)
    }

    @Test("matching active request and unchanged body can apply AI shortcut response")
    func matchingActiveRequestAndUnchangedBodyCanApplyAIShortcutResponse() {
        #expect(ComposeAIShortcutResponsePolicy.canApplyResponse(
            request: ComposeAIShortcutRequest(
                action: .formal,
                inputText: "Please ship the build."
            ),
            activeRequest: ComposeAIShortcutRequest(
                action: .formal,
                inputText: "Please ship the build."
            ),
            currentBodyText: "Please ship the build."
        ))
    }

    @Test("changed request or edited body rejects stale AI shortcut response")
    func changedRequestOrEditedBodyRejectsStaleAIShortcutResponse() {
        let request = ComposeAIShortcutRequest(
            action: .formal,
            inputText: "Please ship the build."
        )

        #expect(!ComposeAIShortcutResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: ComposeAIShortcutRequest(
                action: .shorten,
                inputText: "Please ship the build."
            ),
            currentBodyText: "Please ship the build."
        ))
        #expect(!ComposeAIShortcutResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: ComposeAIShortcutRequest(
                action: .formal,
                inputText: "Different draft."
            ),
            currentBodyText: "Please ship the build."
        ))
        #expect(!ComposeAIShortcutResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentBodyText: "Please ship the build. Also, thanks."
        ))
        #expect(!ComposeAIShortcutResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: nil,
            currentBodyText: "Please ship the build."
        ))
    }
}
