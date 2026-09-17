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
import Foundation
import ServiceManagement

/// Release-bundle gating for launch at login (ADR-0075, ADR-0080, Rule 7):
/// test builds (`Brev Test (…).app`, bundle id `eu.brevmail.brev.test.*`)
/// must never register as a login item, so the toggle is only offered for
/// the exact release identifiers of the two rings.
public enum LaunchAtLoginAvailability {
    /// Bundle identifiers allowed to register for launch at login: Stable
    /// and Nightly are separate apps (ADR-0080) and both are release builds.
    public static let releaseBundleIdentifiers: Set<String> = [
        "eu.brevmail.brev",
        "eu.brevmail.brev.nightly"
    ]

    /// Returns whether the current bundle may register for launch at login.
    public static func isAvailable(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return releaseBundleIdentifiers.contains(bundleIdentifier)
    }
}

/// Thin wrapper over `SMAppService.mainApp` so the settings UI renders the
/// system's true registration state (including `.requiresApproval`) rather
/// than Brev's own flag. Never registers in tests — only the settings
/// toggle calls `setEnabled`.
@MainActor
public final class LaunchAtLoginController {
    public init() {}

    /// The system's view of Brev's login-item registration.
    public var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// Registers or unregisters Brev as a login item. May throw (e.g. when
    /// the system requires user approval); the caller should re-read
    /// `status` afterwards rather than trusting the request.
    public func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Opens System Settings › Login Items for `.requiresApproval` follow-up.
    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
#endif
