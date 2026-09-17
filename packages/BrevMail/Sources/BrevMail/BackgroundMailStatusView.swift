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

#if os(macOS)
import BrevDesign
import BrevThemes
import SwiftUI

/// Immutable snapshot of the background-mail status shown in the menu bar
/// item (ADR-0075). Built from `BackgroundMailCoordinator` values only, so
/// the menu content is provider-neutral and snapshot-testable.
public struct BackgroundMailStatusPresentation: Equatable, Sendable {
    public var unreadCount: Int
    public var lastSuccessfulRefresh: Date?
    public var lastFailureSummary: String?
    public var isRefreshing: Bool
    public var isManualSchedule: Bool

    public init(
        unreadCount: Int = 0,
        lastSuccessfulRefresh: Date? = nil,
        lastFailureSummary: String? = nil,
        isRefreshing: Bool = false,
        isManualSchedule: Bool = false
    ) {
        self.unreadCount = unreadCount
        self.lastSuccessfulRefresh = lastSuccessfulRefresh
        self.lastFailureSummary = lastFailureSummary
        self.isRefreshing = isRefreshing
        self.isManualSchedule = isManualSchedule
    }

    @MainActor
    public init(coordinator: BackgroundMailCoordinator) {
        self.init(
            unreadCount: coordinator.unreadCount,
            lastSuccessfulRefresh: coordinator.lastSuccessfulRefresh,
            lastFailureSummary: coordinator.lastFailureSummary,
            isRefreshing: coordinator.isRefreshing,
            isManualSchedule: coordinator.isManualSchedule
        )
    }

    /// Single status line: in-flight check wins, then failures, then the
    /// manual-cadence disclosure, then the last check time.
    public var statusLine: String {
        if isRefreshing {
            return String(localized: "Checking…", bundle: .module)
        }
        if let lastFailureSummary {
            return String(localized: "Last check failed: \(lastFailureSummary)", bundle: .module)
        }
        if isManualSchedule {
            return String(
                localized: "Manual mode — listening for server pushes only",
                bundle: .module
            )
        }
        if let lastSuccessfulRefresh {
            let time = lastSuccessfulRefresh.formatted(.dateTime.hour().minute())
            return String(localized: "Last checked \(time)", bundle: .module)
        }
        return String(localized: "Not checked yet", bundle: .module)
    }

    /// Unread-count line, pluralized through the string catalog.
    public var unreadLine: String {
        String(localized: "\(unreadCount) unread", bundle: .module)
    }
}

/// Menu content for the macOS menu-bar extra (ADR-0075). Actions are
/// closures so the view stays platform- and app-agnostic.
public struct BackgroundMailStatusView: View {
    private let presentation: BackgroundMailStatusPresentation
    private let onCheckNow: () -> Void
    private let onOpenBrev: () -> Void
    private let onQuitBrev: () -> Void

    public init(
        presentation: BackgroundMailStatusPresentation,
        onCheckNow: @escaping () -> Void,
        onOpenBrev: @escaping () -> Void,
        onQuitBrev: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.onCheckNow = onCheckNow
        self.onOpenBrev = onOpenBrev
        self.onQuitBrev = onQuitBrev
    }

    public var body: some View {
        Text(presentation.statusLine)
        Text(presentation.unreadLine)
        Divider()
        Button(String(localized: "Check now", bundle: .module), action: onCheckNow)
        Button(String(localized: "Open Brev", bundle: .module), action: onOpenBrev)
        Divider()
        Button(String(localized: "Quit Brev", bundle: .module), action: onQuitBrev)
    }
}
#endif
