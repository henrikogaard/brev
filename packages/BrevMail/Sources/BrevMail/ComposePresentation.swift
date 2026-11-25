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

import CoreGraphics
import Foundation

struct ComposeFrameMetrics: Equatable, Sendable {
    let minWidth: CGFloat?
    let minHeight: CGFloat?
}

struct ComposeToolbarMetrics: Equatable, Sendable {
    let buttonSize: CGFloat
    let hitTargetSize: CGFloat
    let height: CGFloat
    let utilityHeight: CGFloat
    let leadingInset: CGFloat
    let topInset: CGFloat
}

enum ComposeLayoutPlatform: Equatable, Sendable {
    case compactIOS
    case compactIOSAccessibility
    case regularIOS
    case macOS
}

enum ComposeDeviceClass: Equatable, Sendable {
    case phone
    case pad
    case mac
}

enum ComposeLayoutPolicy {
    static func platform(
        horizontalSizeClassIsCompact: Bool,
        isAccessibilitySize: Bool,
        deviceClass: ComposeDeviceClass
    ) -> ComposeLayoutPlatform {
        switch deviceClass {
        case .phone:
            return isAccessibilitySize ? .compactIOSAccessibility : .compactIOS
        case .pad:
            if horizontalSizeClassIsCompact {
                return isAccessibilitySize ? .compactIOSAccessibility : .compactIOS
            }
            return .regularIOS
        case .mac:
            return .macOS
        }
    }

    static func frameMetrics(for platform: ComposeLayoutPlatform) -> ComposeFrameMetrics {
        switch platform {
        case .compactIOS, .compactIOSAccessibility:
            ComposeFrameMetrics(minWidth: nil, minHeight: nil)
        case .regularIOS:
            // ~660 fits the narrowest regular-width iPad scene (~678 pt).
            ComposeFrameMetrics(minWidth: 660, minHeight: 560)
        case .macOS:
            ComposeFrameMetrics(minWidth: 680, minHeight: 560)
        }
    }

    static func toolbarMetrics(
        for platform: ComposeLayoutPlatform,
        isCompactVertical: Bool = false
    ) -> ComposeToolbarMetrics {
        switch platform {
        case .compactIOS, .compactIOSAccessibility, .regularIOS:
            ComposeToolbarMetrics(
                buttonSize: 26,
                hitTargetSize: 44,
                height: isCompactVertical ? 44 : 52,
                utilityHeight: isCompactVertical ? 44 : 48,
                leadingInset: 0,
                topInset: 0
            )
        case .macOS:
            ComposeToolbarMetrics(
                buttonSize: 26,
                hitTargetSize: 36,
                height: 42,
                utilityHeight: 0,
                leadingInset: 76,
                topInset: 0
            )
        }
    }

    /// Visual diameter of the circular Send pill.
    ///
    /// On iOS, drawing the filled circle at the full 44 pt hit target makes the
    /// button oversized in portrait and nearly touch the sheet corner bezel in
    /// 44 pt landscape. A 34 pt visual circle centered inside the 44 pt tap
    /// target stays proportionate with Cancel, title, and Later.
    static func sendButtonVisualDiameter(for platform: ComposeLayoutPlatform) -> CGFloat {
        switch platform {
        case .compactIOS, .compactIOSAccessibility, .regularIOS:
            34
        case .macOS:
            36
        }
    }

    /// Whether header fields and the body share a scrollable column between the
    /// pinned top navigation bar and bottom utility bar (#362).
    ///
    /// True at iOS accessibility text sizes (stacked tall headers) and in
    /// compact vertical height (iPhone Landscape), where fixed headers plus the
    /// software keyboard otherwise push the top bar off-screen and occlude the
    /// body and formatting controls.
    static func usesScrollableFieldLayout(
        platform: ComposeLayoutPlatform,
        isCompactVertical: Bool
    ) -> Bool {
        switch platform {
        case .compactIOSAccessibility:
            true
        case .compactIOS, .regularIOS:
            isCompactVertical
        case .macOS:
            false
        }
    }

    /// Minimum body-editor height inside the scrollable iOS compose layout so
    /// the message body stays reachable below the header fields (#362).
    static func scrollableBodyMinHeight(
        platform: ComposeLayoutPlatform,
        isCompactVertical: Bool
    ) -> CGFloat? {
        switch platform {
        case .compactIOSAccessibility:
            240
        case .compactIOS, .regularIOS:
            isCompactVertical ? 160 : nil
        case .macOS:
            nil
        }
    }
}

enum ComposeToolbarAction: Equatable, Sendable, Hashable {
    case close
    case attach
    case format
    case signature
    case templates
    case messageOptions
    case security
    case aiWriter
    case editorAppearance
    case preview
    case saveDraft
    case scheduleSend
    case send
    case discardDraft
    case moreActions

    var accessibilityLabel: String {
        switch self {
        case .close:
            return String(localized: "Close", bundle: .module)
        case .attach:
            return String(localized: "Attach", bundle: .module)
        case .format:
            return String(localized: "Format", bundle: .module)
        case .signature:
            return String(localized: "Signature", bundle: .module)
        case .templates:
            return String(localized: "Templates", bundle: .module)
        case .messageOptions:
            return String(localized: "Message Options", bundle: .module)
        case .security:
            return String(localized: "Message Security", bundle: .module)
        case .aiWriter:
            return String(localized: "AI Writer", bundle: .module)
        case .editorAppearance:
            return String(localized: "Editor Appearance", bundle: .module)
        case .preview:
            return String(localized: "Preview", bundle: .module)
        case .saveDraft:
            return String(localized: "Save Draft", bundle: .module)
        case .scheduleSend:
            return String(localized: "Schedule send", bundle: .module)
        case .send:
            return String(localized: "Send", bundle: .module)
        case .discardDraft:
            return String(localized: "Discard Draft", bundle: .module)
        case .moreActions:
            return String(localized: "Compose actions", bundle: .module)
        }
    }
}

struct ComposeToolbarActionLayout: Equatable, Sendable {
    let primaryActions: [ComposeToolbarAction]
    let utilityActions: [ComposeToolbarAction]
    let overflowActions: [ComposeToolbarAction]

    var moreActionsAccessibilityLabel: String {
        ComposeToolbarAction.moreActions.accessibilityLabel
    }

    var moreActionsAccessibilityValue: String {
        overflowActions.map(\.accessibilityLabel).joined(separator: ", ")
    }
}

struct ComposeErrorStatus: Equatable, Sendable {
    enum Tone: Equatable, Sendable {
        case danger
    }

    let message: String
    let tone: Tone
    let isDismissible: Bool
    let lineLimit: Int?
}

struct ComposeChromePresentation: Equatable, Sendable {
    let fieldPanelTreatment: ComposeFieldPanelTreatment
    let fieldRows: [ComposeFieldRow]
}

enum ComposeFieldPanelTreatment: Equatable, Sendable {
    /// Flat rows with hairline dividers; no filled well / card.
    case flatHairline
}

enum ComposeFieldRow: Equatable, Sendable, Hashable {
    case recipients
    case subject
    case sender
}

enum ComposePresentation {
    static let aiShortcutStaleResponseMessage = String(
        localized: "The draft changed before AI Writer finished. Try again with the current text.",
        bundle: .module
    )

    static let chrome = ComposeChromePresentation(
        fieldPanelTreatment: .flatHairline,
        fieldRows: [.recipients, .sender, .subject]
    )

    static func isInteractionBusy(
        isSending: Bool,
        isSavingDraft: Bool,
        isAIWorking: Bool
    ) -> Bool {
        isSending || isSavingDraft || isAIWorking
    }

    static func canPresentScheduleSend(
        hasCapability: Bool,
        isInteractionBlocked: Bool
    ) -> Bool {
        hasCapability && !isInteractionBlocked
    }

    static func toolbarActionLayout(for platform: ComposeLayoutPlatform) -> ComposeToolbarActionLayout {
        switch platform {
        case .compactIOS, .compactIOSAccessibility, .regularIOS:
            ComposeToolbarActionLayout(
                primaryActions: [.close, .scheduleSend, .send],
                utilityActions: [.attach, .format, .moreActions],
                overflowActions: [
                    .templates,
                    .signature,
                    .messageOptions,
                    .format,
                    .security,
                    .aiWriter,
                    .saveDraft,
                    .scheduleSend,
                    .discardDraft
                ]
            )
        case .macOS:
            ComposeToolbarActionLayout(
                primaryActions: [.attach, .format, .send, .scheduleSend, .moreActions],
                utilityActions: [],
                overflowActions: [
                    .templates,
                    .signature,
                    .messageOptions,
                    .security,
                    .aiWriter,
                    .editorAppearance,
                    .preview,
                    .saveDraft,
                    .scheduleSend,
                    .discardDraft
                ],
            )
        }
    }

    static func title(isReplying: Bool, isForwarding: Bool) -> String {
        if isReplying {
            return String(localized: "Reply", bundle: .module)
        }
        if isForwarding {
            return String(localized: "Forward", bundle: .module)
        }
        return String(localized: "New Message", bundle: .module)
    }

    static func windowTitle(subject: String) -> String {
        let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return subject.isEmpty
            ? String(localized: "New Message", bundle: .module)
            : subject
    }

    /// The bottom error bar stays hidden while the body already shows the same
    /// restoration refusal next to its Close button.
    static func showsErrorBanner(errorMessage: String?, restorationError: String?) -> Bool {
        guard let errorMessage else { return false }
        return errorMessage != restorationError
    }

    static func errorStatus(_ message: String) -> ComposeErrorStatus {
        ComposeErrorStatus(
            message: message,
            tone: .danger,
            isDismissible: true,
            lineLimit: nil
        )
    }

    static func sendErrorMessage(for error: any Error) -> String {
        prefixedErrorMessage(
            prefix: String(localized: "Couldn't send:", bundle: .module),
            fallback: String(localized: "Couldn't send your message.", bundle: .module),
            error: error
        )
    }

    static func saveDraftErrorMessage(for error: any Error) -> String {
        prefixedErrorMessage(
            prefix: String(localized: "Couldn't save draft:", bundle: .module),
            fallback: String(localized: "Couldn't save your draft.", bundle: .module),
            error: error
        )
    }

    static func aiShortcutErrorMessage(for error: any Error) -> String {
        prefixedErrorMessage(
            prefix: String(localized: "Couldn't update with AI Writer:", bundle: .module),
            fallback: String(localized: "couldntUpdateAiWriter.period", bundle: .module),
            error: error
        )
    }

    private static func prefixedErrorMessage(
        prefix: String,
        fallback: String,
        error: any Error
    ) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? fallback : "\(prefix) \(message)"
    }
}
