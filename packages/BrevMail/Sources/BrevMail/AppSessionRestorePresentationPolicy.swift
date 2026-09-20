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

public enum AppSessionRestorePresentationPolicy {
    /// Keep payload-bearing scenes available to consume their reader command.
    public static func shouldShowSettings(isRequested: Bool, hasReaderCommandHandoff: Bool) -> Bool {
        isRequested && !hasReaderCommandHandoff
    }

    /// Show the mailbox as soon as any account is connected or served from
    /// cache, even while other accounts are still restoring. The cache-first
    /// render must not wait for the slowest account to finish connecting, so
    /// `isRestoringSession` is intentionally *not* a gate here — remaining
    /// restore is surfaced as a non-blocking indicator instead.
    public static func shouldShowMailboxRoot(
        visibleBackendCount: Int,
        isRestoringSession _: Bool
    ) -> Bool {
        visibleBackendCount > 0
    }

    /// Only block the window with a full progress surface when nothing is
    /// showing yet — i.e. no account is visible and we're still restoring (or
    /// haven't attempted a restore). Once a backend is visible the mailbox root
    /// renders and this branch isn't reached.
    public static func shouldShowRestoreProgress(
        visibleBackendCount: Int,
        isRestoringSession: Bool,
        sessionRestoreAttempted: Bool
    ) -> Bool {
        visibleBackendCount == 0 && (isRestoringSession || !sessionRestoreAttempted)
    }

    /// Surface the restore-error alert whenever any account failed to restore,
    /// including the total-failure case where no backend is visible and the
    /// window shows the login screen. Gating this on `visibleBackendCount > 0`
    /// used to leave total failures silent — the user's accounts would vanish
    /// behind the login screen with no explanation.
    public static func shouldShowRestoreErrorAlert(
        accountRestoreErrorCount: Int
    ) -> Bool {
        accountRestoreErrorCount > 0
    }
}
