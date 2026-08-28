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

@Suite("ComposeAIActionPresentation")
struct ComposeAIActionPresentationTests {
    @Test("toolbar actions have deterministic order and presentation")
    func toolbarActionsHaveDeterministicOrderAndPresentation() {
        let actions = ComposeAIAction.toolbarActions

        #expect(actions.map(\.id) == [
            "draftFromPrompt",
            "shortcut.improveWriting.wholeDraft",
            "shortcut.shorten.wholeDraft",
            "shortcut.expand.wholeDraft",
            "shortcut.formal.wholeDraft",
            "shortcut.casual.wholeDraft",
            "shortcut.friendly.wholeDraft",
            "shortcut.fixSpelling.wholeDraft",
            "shortcut.translate.wholeDraft",
            "suggestSubject"
        ])
        #expect(actions[0].title == "Draft from Prompt")
        #expect(actions[0].symbolName == "text.badge.plus")
        #expect(actions[1].title == AIShortcutAction.improveWriting.displayLabel)
        #expect(actions[1].symbolName == AIShortcutAction.improveWriting.symbolName)
    }

    @Test("selected text actions distinguish selection scope")
    func selectedTextActionsDistinguishSelectionScope() {
        let actions = ComposeAIAction.selectedTextActions

        #expect(actions.count == AIShortcutAction.allCases.count)
        #expect(actions.allSatisfy { $0.scope == .selection })
        #expect(actions.allSatisfy { $0.requirements.contains(.selectedText) })
        #expect(actions.first?.id == "shortcut.improveWriting.selection")
    }

    @Test("whole draft shortcuts require body text")
    func wholeDraftShortcutsRequireBodyText() {
        let action = ComposeAIAction.shortcut(.shorten, scope: .wholeDraft)

        #expect(action.scope == .wholeDraft)
        #expect(action.requirements.contains(.bodyText))
        #expect(!action.requirements.contains(.selectedText))
    }

    @Test("availability reports the first deterministic disabled reason")
    func availabilityReportsFirstDeterministicDisabledReason() {
        let action = ComposeAIAction.shortcut(.shorten, scope: .wholeDraft)

        #expect(ComposeAIActionAvailability.disabledReason(
            for: action,
            in: .available(bodyText: "Hello")
        ) == nil)
        #expect(ComposeAIActionAvailability.disabledReason(
            for: action,
            in: .available(bodyText: "Hello").with(hasBackend: false)
        ) == .missingBackend)
        #expect(ComposeAIActionAvailability.disabledReason(
            for: action,
            in: .available(bodyText: "Hello").with(isEnabled: false, hasConsent: true)
        ) == .notEnabled)
        #expect(ComposeAIActionAvailability.disabledReason(
            for: action,
            in: .available(bodyText: "Hello").with(isEnabled: true, hasConsent: false)
        ) == .consentRequired)
        #expect(ComposeAIActionAvailability.disabledReason(
            for: action,
            in: .available(bodyText: "Hello").with(supportsAI: false)
        ) == .unsupportedAccount)
        #expect(ComposeAIActionAvailability.disabledReason(
            for: action,
            in: .available(bodyText: "Hello").with(isBusy: true)
        ) == .busy)
        #expect(ComposeAIActionAvailability.disabledReason(
            for: action,
            in: .available(bodyText: "Hello").with(hasActiveRequest: true)
        ) == .requestInFlight)
        #expect(ComposeAIActionAvailability.disabledReason(
            for: action,
            in: .available(bodyText: " \n\t ")
        ) == .bodyTextRequired)
    }

    @Test("selection prompt reply and subject requirements are testable")
    func selectionPromptReplyAndSubjectRequirementsAreTestable() {
        #expect(ComposeAIActionAvailability.disabledReason(
            for: .shortcut(.formal, scope: .selection),
            in: .available(bodyText: "Body", selectedText: nil)
        ) == .selectedTextRequired)
        #expect(ComposeAIActionAvailability.disabledReason(
            for: .draftFromPrompt,
            in: .available(bodyText: "", promptText: nil)
        ) == .promptRequired)
        #expect(ComposeAIActionAvailability.disabledReason(
            for: .draftReply,
            in: .available(bodyText: "Body", hasReplyContext: false)
        ) == .replyContextRequired)
        #expect(ComposeAIActionAvailability.disabledReason(
            for: .suggestSubject,
            in: .available(bodyText: "Body", hasSubjectTarget: false)
        ) == .subjectTargetRequired)
    }
}

private extension ComposeAIActionContext {
    static func available(
        bodyText: String,
        selectedText: String? = nil,
        promptText: String? = nil,
        hasReplyContext: Bool = true,
        hasSubjectTarget: Bool = true
    ) -> ComposeAIActionContext {
        ComposeAIActionContext(
            hasBackend: true,
            isEnabled: true,
            hasConsent: true,
            supportsAI: true,
            isBusy: false,
            hasActiveRequest: false,
            bodyText: bodyText,
            selectedText: selectedText,
            promptText: promptText,
            hasReplyContext: hasReplyContext,
            hasSubjectTarget: hasSubjectTarget
        )
    }

    func with(
        hasBackend: Bool? = nil,
        isEnabled: Bool? = nil,
        hasConsent: Bool? = nil,
        supportsAI: Bool? = nil,
        isBusy: Bool? = nil,
        hasActiveRequest: Bool? = nil
    ) -> ComposeAIActionContext {
        ComposeAIActionContext(
            hasBackend: hasBackend ?? self.hasBackend,
            isEnabled: isEnabled ?? self.isEnabled,
            hasConsent: hasConsent ?? self.hasConsent,
            supportsAI: supportsAI ?? self.supportsAI,
            isBusy: isBusy ?? self.isBusy,
            hasActiveRequest: hasActiveRequest ?? self.hasActiveRequest,
            bodyText: bodyText,
            selectedText: selectedText,
            promptText: promptText,
            hasReplyContext: hasReplyContext,
            hasSubjectTarget: hasSubjectTarget
        )
    }
}
