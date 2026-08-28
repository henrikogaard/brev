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
        case .regularIOS, .macOS:
            ComposeFrameMetrics(minWidth: 680, minHeight: 560)
        }
    }

    static func toolbarMetrics(for platform: ComposeLayoutPlatform) -> ComposeToolbarMetrics {
        switch platform {
        case .compactIOS, .compactIOSAccessibility, .regularIOS:
            ComposeToolbarMetrics(buttonSize: 26, hitTargetSize: 36, height: 42, leadingInset: 0, topInset: 0)
        case .macOS:
            ComposeToolbarMetrics(buttonSize: 26, hitTargetSize: 36, height: 42, leadingInset: 76, topInset: 0)
        }
    }
}

enum ComposeToolbarAction: Equatable, Sendable, Hashable {
    case close
    case attach
    case signature
    case templates
    case security
    case aiWriter
    case saveDraft
    case scheduleSend
    case send
    case moreActions

    var accessibilityLabel: String {
        switch self {
        case .close:
            return String(localized: "Close", bundle: .module)
        case .attach:
            return String(localized: "Attach", bundle: .module)
        case .signature:
            return String(localized: "Signature", bundle: .module)
        case .templates:
            return String(localized: "Templates", bundle: .module)
        case .security:
            return String(localized: "Message Security", bundle: .module)
        case .aiWriter:
            return String(localized: "AI Writer", bundle: .module)
        case .saveDraft:
            return String(localized: "Save Draft", bundle: .module)
        case .scheduleSend:
            return String(localized: "Schedule send", bundle: .module)
        case .send:
            return String(localized: "Send", bundle: .module)
        case .moreActions:
            return String(localized: "Compose actions", bundle: .module)
        }
    }
}

struct ComposeToolbarActionLayout: Equatable, Sendable {
    let directActions: [ComposeToolbarAction]
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
    let toolbarClusterTreatment: ComposeToolbarClusterTreatment
    let fieldPanelTreatment: ComposeFieldPanelTreatment
    let fieldRows: [ComposeFieldRow]
}

/// How primary-toolbar control clusters are drawn on the shared surface.
enum ComposeToolbarClusterTreatment: Equatable, Sendable {
    /// Borderless icon/menu buttons with no pill background.
    case borderless
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

enum ComposeCarbonCopyField: Equatable, Sendable, Hashable, Identifiable {
    case cc
    case bcc

    var id: Self { self }

    var label: String {
        switch self {
        case .cc: return String(localized: "Cc", bundle: .module)
        case .bcc: return String(localized: "Bcc", bundle: .module)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .cc: return String(localized: "Add Cc", bundle: .module)
        case .bcc: return String(localized: "Add Bcc", bundle: .module)
        }
    }
}

enum ComposePresentation {
    static let aiShortcutStaleResponseMessage = "The draft changed before AI Writer finished. Try again with the current text."

    static let chrome = ComposeChromePresentation(
        toolbarClusterTreatment: .borderless,
        fieldPanelTreatment: .flatHairline,
        fieldRows: [.recipients, .subject, .sender]
    )

    static func isInteractionBusy(
        isSending: Bool,
        isSavingDraft: Bool,
        isAIWorking: Bool
    ) -> Bool {
        isSending || isSavingDraft || isAIWorking
    }

    static func hiddenCarbonCopyFields(
        isCcVisible: Bool,
        isBccVisible: Bool
    ) -> [ComposeCarbonCopyField] {
        var fields: [ComposeCarbonCopyField] = []
        if !isCcVisible {
            fields.append(.cc)
        }
        if !isBccVisible {
            fields.append(.bcc)
        }
        return fields
    }

    static func toolbarActionLayout(for platform: ComposeLayoutPlatform) -> ComposeToolbarActionLayout {
        switch platform {
        case .compactIOSAccessibility:
            ComposeToolbarActionLayout(
                directActions: [.close, .send, .moreActions],
                overflowActions: [
                    .attach,
                    .templates,
                    .signature,
                    .security,
                    .aiWriter,
                    .saveDraft,
                    .scheduleSend
                ]
            )
        case .compactIOS, .regularIOS, .macOS:
            ComposeToolbarActionLayout(
                directActions: [
                    .close,
                    .attach,
                    .signature,
                    .templates,
                    .security,
                    .aiWriter,
                    .saveDraft,
                    .scheduleSend,
                    .send
                ],
                overflowActions: []
            )
        }
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
            prefix: "Couldn't send:",
            fallback: "Couldn't send your message.",
            error: error
        )
    }

    static func saveDraftErrorMessage(for error: any Error) -> String {
        prefixedErrorMessage(
            prefix: "Couldn't save draft:",
            fallback: "Couldn't save your draft.",
            error: error
        )
    }

    static func aiShortcutErrorMessage(for error: any Error) -> String {
        prefixedErrorMessage(
            prefix: "Couldn't update with AI Writer:",
            fallback: "Couldn't update with AI Writer.",
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
