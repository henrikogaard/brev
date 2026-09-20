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

import Foundation

/// Shared presentation model for source states (ADR-0072).
///
/// One mapping used by every surface that reports a source — settings,
/// pickers, browsing chrome — so a state always reads the same way. Values
/// only: colors and layout belong to the consuming view.
public struct PIMSourceStatusPresentation: Sendable, Hashable {
    /// User-facing state label.
    public let title: String
    /// SF Symbol for the state.
    public let symbolName: String
    /// Whether the state offers a direct remedy action (reconnect, review
    /// permissions) rather than being informational.
    public let isActionable: Bool
    /// Whether cached content may still be readable in this state.
    public let cacheMayRemainReadable: Bool

    public init(
        title: String,
        symbolName: String,
        isActionable: Bool,
        cacheMayRemainReadable: Bool
    ) {
        self.title = title
        self.symbolName = symbolName
        self.isActionable = isActionable
        self.cacheMayRemainReadable = cacheMayRemainReadable
    }
}

public enum PIMSourceStatusPresenter {
    /// The presentation for a source status.
    public static func presentation(
        for status: PIMSourceStatus
    ) -> PIMSourceStatusPresentation {
        switch status {
        case .disconnected:
            return PIMSourceStatusPresentation(
                title: String(localized: "Disconnected", bundle: .module),
                symbolName: "cable.connector.horizontal",
                isActionable: true,
                cacheMayRemainReadable: true
            )
        case .connecting:
            return PIMSourceStatusPresentation(
                title: String(localized: "Connecting…", bundle: .module),
                symbolName: "arrow.triangle.2.circlepath",
                isActionable: false,
                cacheMayRemainReadable: true
            )
        case .ready:
            return PIMSourceStatusPresentation(
                title: String(localized: "Ready", bundle: .module),
                symbolName: "checkmark.circle",
                isActionable: false,
                cacheMayRemainReadable: true
            )
        case .syncing:
            return PIMSourceStatusPresentation(
                title: String(localized: "Syncing…", bundle: .module),
                symbolName: "arrow.triangle.2.circlepath.circle",
                isActionable: false,
                cacheMayRemainReadable: true
            )
        case .permissionLimited:
            return PIMSourceStatusPresentation(
                title: String(localized: "Limited permissions", bundle: .module),
                symbolName: "exclamationmark.shield",
                isActionable: true,
                cacheMayRemainReadable: true
            )
        case .authenticationRequired:
            return PIMSourceStatusPresentation(
                title: String(localized: "Sign-in required", bundle: .module),
                symbolName: "person.badge.key",
                isActionable: true,
                cacheMayRemainReadable: true
            )
        case .failed:
            return PIMSourceStatusPresentation(
                title: String(localized: "Failed", bundle: .module),
                symbolName: "exclamationmark.triangle",
                isActionable: true,
                cacheMayRemainReadable: false
            )
        }
    }
}
