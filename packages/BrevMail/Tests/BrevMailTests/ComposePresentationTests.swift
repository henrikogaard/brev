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

import BrevBackend
@testable import BrevMail
import Foundation
import Testing

@Suite("ComposePresentation")
struct ComposePresentationTests {
    @Test("compact iOS compose chrome does not force desktop minimum size")
    func compactIOSComposeChromeDoesNotForceDesktopMinimumSize() {
        let metrics = ComposeLayoutPolicy.frameMetrics(for: .compactIOS)

        #expect(metrics.minWidth == nil)
        #expect(metrics.minHeight == nil)
    }

    @Test("phone compose chrome stays compact even when the sheet reports regular width")
    func phoneComposeChromeStaysCompactForRegularSheetWidth() {
        #expect(ComposeLayoutPolicy.platform(
            horizontalSizeClassIsCompact: false,
            isAccessibilitySize: false,
            deviceClass: .phone
        ) == .compactIOS)
        #expect(ComposeLayoutPolicy.platform(
            horizontalSizeClassIsCompact: false,
            isAccessibilitySize: true,
            deviceClass: .phone
        ) == .compactIOSAccessibility)
    }

    @Test("regular compose chrome keeps roomy desktop minimum size")
    func regularComposeChromeKeepsRoomyDesktopMinimumSize() {
        #expect(ComposeLayoutPolicy.frameMetrics(for: .regularIOS) == ComposeFrameMetrics(
            minWidth: 680,
            minHeight: 560
        ))
        #expect(ComposeLayoutPolicy.frameMetrics(for: .macOS) == ComposeFrameMetrics(
            minWidth: 680,
            minHeight: 560
        ))
    }

    @Test("send errors keep readable backend messages")
    func sendErrorsKeepReadableBackendMessages() {
        #expect(ComposePresentation.sendErrorMessage(
            for: MailBackendError.network(underlying: "offline")
        ) == "Couldn't send: Network error: offline")
    }

    @Test("send errors fall back when localized message is blank")
    func sendErrorsFallBackWhenLocalizedMessageIsBlank() {
        let error = NSError(domain: "BrevTests", code: 1, userInfo: [NSLocalizedDescriptionKey: " "])

        #expect(ComposePresentation.sendErrorMessage(for: error) == "Couldn't send your message.")
    }

    @Test("save draft errors keep readable backend messages")
    func saveDraftErrorsKeepReadableBackendMessages() {
        #expect(ComposePresentation.saveDraftErrorMessage(
            for: MailBackendError.quotaExceeded
        ) == "Couldn't save draft: Mailbox quota exceeded.")
    }

    @Test("save draft errors fall back when localized message is blank")
    func saveDraftErrorsFallBackWhenLocalizedMessageIsBlank() {
        let error = NSError(domain: "BrevTests", code: 1, userInfo: [NSLocalizedDescriptionKey: " "])

        #expect(ComposePresentation.saveDraftErrorMessage(for: error) == "Couldn't save your draft.")
    }

    @Test("AI shortcut errors keep readable backend messages")
    func aiShortcutErrorsKeepReadableBackendMessages() {
        #expect(ComposePresentation.aiShortcutErrorMessage(
            for: MailBackendError.rateLimited(retryAfter: 12)
        ) == "Couldn't update with AI Writer: Rate limited. Try again in 12 seconds.")
    }

    @Test("AI shortcut errors fall back when localized message is blank")
    func aiShortcutErrorsFallBackWhenLocalizedMessageIsBlank() {
        let error = NSError(domain: "BrevTests", code: 1, userInfo: [NSLocalizedDescriptionKey: " "])

        #expect(ComposePresentation.aiShortcutErrorMessage(for: error) == "Couldn't update with AI Writer.")
    }

    @Test("compose errors render as dismissible danger inline status")
    func composeErrorsRenderAsDismissibleDangerInlineStatus() {
        let status = ComposePresentation.errorStatus("Couldn't send: offline")

        #expect(status == ComposeErrorStatus(
            message: "Couldn't send: offline",
            tone: .danger,
            isDismissible: true,
            lineLimit: nil
        ))
    }

    @Test("compose interaction is busy while sending, saving, or AI Writer is working")
    func composeInteractionIsBusyDuringMutatingWork() {
        #expect(ComposePresentation.isInteractionBusy(
            isSending: true,
            isSavingDraft: false,
            isAIWorking: false
        ))
        #expect(ComposePresentation.isInteractionBusy(
            isSending: false,
            isSavingDraft: true,
            isAIWorking: false
        ))
        #expect(ComposePresentation.isInteractionBusy(
            isSending: false,
            isSavingDraft: false,
            isAIWorking: true
        ))
        #expect(!ComposePresentation.isInteractionBusy(
            isSending: false,
            isSavingDraft: false,
            isAIWorking: false
        ))
    }

    @Test("compose body appearance falls back to system for unknown stored values")
    func composeBodyAppearanceFallsBackToSystemForUnknownStoredValues() {
        #expect(ComposeBodyAppearance.resolve("missing") == .system)
    }

    @Test("compose body appearance maps system light and dark to readable editor themes")
    func composeBodyAppearanceMapsToReadableEditorThemes() {
        #expect(ComposeBodyAppearance.system.resolved(for: .light) == .light)
        #expect(ComposeBodyAppearance.system.resolved(for: .dark) == .dark)
        #expect(ComposeBodyAppearance.light.editorTheme.id == "brev-mono-light")
        #expect(ComposeBodyAppearance.dark.editorTheme.id == "brev-mono-dark")
        #expect(ComposeBodyAppearance.light.editorTheme.textPrimary.hex != ComposeBodyAppearance.light.editorTheme.bgPrimary.hex)
        #expect(ComposeBodyAppearance.dark.editorTheme.textPrimary.hex != ComposeBodyAppearance.dark.editorTheme.bgPrimary.hex)
    }

    @Test("compose chrome uses flat hairline fields under the full-size titlebar")
    func composeChromeUsesFlatHairlineFieldsUnderFullSizeTitlebar() {
        let chrome = ComposePresentation.chrome

        #expect(chrome.fieldPanelTreatment == .flatHairline)
        #expect(chrome.toolbarClusterTreatment == .borderless)
        #expect(chrome.fieldRows == [.recipients, .subject, .sender])
    }

    @Test("accessibility compact toolbar keeps send direct and moves draft controls into actions")
    func accessibilityCompactToolbarKeepsSendDirectAndMovesDraftControlsIntoActions() {
        let layout = ComposePresentation.toolbarActionLayout(for: .compactIOSAccessibility)

        #expect(layout.directActions == [.close, .send, .moreActions])
        #expect(layout.overflowActions == [
            .attach,
            .templates,
            .signature,
            .security,
            .aiWriter,
            .saveDraft,
            .scheduleSend
        ])
        #expect(layout.moreActionsAccessibilityLabel == "Compose actions")
        #expect(layout.moreActionsAccessibilityValue == [
            "Attach",
            "Templates",
            "Signature",
            "Message Security",
            "AI Writer",
            "Save Draft",
            "Schedule send"
        ].joined(separator: ", "))
    }

    @Test("regular toolbar keeps secondary compose controls direct")
    func regularToolbarKeepsSecondaryComposeControlsDirect() {
        let layout = ComposePresentation.toolbarActionLayout(for: .regularIOS)

        #expect(layout.directActions == [
            .close,
            .attach,
            .signature,
            .templates,
            .security,
            .aiWriter,
            .saveDraft,
            .scheduleSend,
            .send
        ])
        #expect(layout.overflowActions.isEmpty)
    }

    @Test("macOS toolbar controls use an accessible hit target around compact icons")
    func macOSToolbarControlsUseAccessibleHitTargetAroundCompactIcons() {
        let metrics = ComposeLayoutPolicy.toolbarMetrics(for: .macOS)

        #expect(metrics.buttonSize == 26)
        #expect(metrics.hitTargetSize == 36)
        #expect(metrics.height == 42)
        #expect(metrics.leadingInset == 76)
        #expect(metrics.topInset == 0)
        #expect(metrics.hitTargetSize > metrics.buttonSize)
    }

    @Test("compose toolbar actions expose readable accessibility labels")
    func composeToolbarActionsExposeReadableAccessibilityLabels() {
        #expect(ComposeToolbarAction.aiWriter.accessibilityLabel == "AI Writer")
        #expect(ComposeToolbarAction.moreActions.accessibilityLabel == "Compose actions")
        #expect(ComposeToolbarAction.scheduleSend.accessibilityLabel == "Schedule send")
    }

    @Test("carbon copy controls expose only hidden recipient fields")
    func carbonCopyControlsExposeOnlyHiddenRecipientFields() {
        #expect(ComposePresentation.hiddenCarbonCopyFields(
            isCcVisible: false,
            isBccVisible: false
        ) == [.cc, .bcc])
        #expect(ComposePresentation.hiddenCarbonCopyFields(
            isCcVisible: true,
            isBccVisible: false
        ) == [.bcc])
        #expect(ComposePresentation.hiddenCarbonCopyFields(
            isCcVisible: false,
            isBccVisible: true
        ) == [.cc])
        #expect(ComposePresentation.hiddenCarbonCopyFields(
            isCcVisible: true,
            isBccVisible: true
        ).isEmpty)
        #expect(ComposeCarbonCopyField.cc.label == "Cc")
        #expect(ComposeCarbonCopyField.cc.accessibilityLabel == "Add Cc")
        #expect(ComposeCarbonCopyField.bcc.label == "Bcc")
        #expect(ComposeCarbonCopyField.bcc.accessibilityLabel == "Add Bcc")
    }
}
