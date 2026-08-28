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
import BrevSettings
import Foundation
import Observation

/// Mirrors the unread total to the platform's app-icon affordance
/// (macOS dock badge, iOS home-screen badge).
///
/// Wraps `MailBadgePresentation.apply(unreadCount:)` so the view layer
/// has a typed entry point that can be tested in isolation and so the
/// policy/side-effect split is explicit. The class is `@Observable`
/// because the settings view may want to read the last-applied count
/// for diagnostics.
@Observable
@MainActor
public final class UnreadBadgeUpdater {
    public private(set) var lastAppliedCount = 0

    public init() {}

    /// Apply a new unread count. A count of `0` clears the badge.
    public func updateBadge(totalUnread: Int) {
        let normalized = max(0, totalUnread)
        lastAppliedCount = normalized
        #if os(macOS)
        guard Self.canUseSystemBadgeInCurrentProcess else { return }
        #endif
        #if os(macOS) || os(iOS)
        MailBadgePresentation.apply(unreadCount: normalized)
        #else
        _ = normalized
        #endif
    }

    /// Compute the displayed count from the current folder snapshot
    /// honouring the user's `NotificationSettings.badgePolicy` and
    /// `badgeEnabled` toggle, then apply it.
    public func updateBadge(
        folders: [Folder],
        sourceSections: [MailSourceSection],
        settings: NotificationSettings
    ) {
        let count = MailBadgePresentation.unreadCount(
            folders: folders,
            sourceSections: sourceSections,
            settings: settings
        )
        updateBadge(totalUnread: count)
    }

    #if os(macOS)
    private static var canUseSystemBadgeInCurrentProcess: Bool {
        !Bundle.main.bundleURL.path.contains("/usr/libexec/swift/pm")
    }
    #endif
}
