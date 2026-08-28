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

import BrevAvatars
import BrevSettings
import Foundation

/// Decides whether Brev may reach for the local Contacts database at all.
///
/// Contacts is the only local source that raises a system permission prompt.
/// The demo mailbox's senders and recipients are invented, so a Contacts match
/// is impossible there and the prompt is pure interruption for whoever is
/// testing. Keeping the decision in one place means both consumers — avatar
/// resolution and compose autocomplete — stay in agreement about it.
public enum ContactsAccessPolicy {
    /// `false` while the demo mailbox is in use, `true` otherwise.
    ///
    /// Release builds have no demo mode, so this is a constant `true` there and
    /// both parameters go unread.
    public static func isEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> Bool {
        #if DEBUG
        AvatarPermissionPolicy.allowsSystemContactsAccess && !DeveloperSettings.isDemoModeRequested(
            environment: environment,
            defaults: defaults,
            isDeveloperBuild: true
        )
        #else
        true
        #endif
    }

    /// Applies the launch-time decision to everything that would reach for
    /// Contacts on its own. Call from the app's `init()`: it returns before any
    /// scene body is evaluated, so nothing can have resolved an avatar yet. See
    /// ADR-0055 for the separate normal-launch-to-demo transition gate.
    public static func applyProcessWidePolicy(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) {
        #if DEBUG
        AvatarPermissionPolicy.allowsSystemContactsAccess = !DeveloperSettings.isDemoModeRequested(
            environment: environment,
            defaults: defaults,
            isDeveloperBuild: true
        )
        #else
        AvatarPermissionPolicy.allowsSystemContactsAccess = true
        #endif
    }

    /// Disables every system Contacts consumer before a demo backend is
    /// installed from the normal sign-in screen.
    public static func disableForDemoMailbox() {
        AvatarPermissionPolicy.allowsSystemContactsAccess = false
    }

    /// Re-applies the launch policy after the last demo backend leaves the
    /// session. Direct mock launches remain disabled because their environment
    /// or persisted developer setting still requests demo mode.
    public static func restoreAfterDemoMailbox() {
        applyProcessWidePolicy()
    }
}
