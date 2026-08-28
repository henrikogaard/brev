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

/// Gates send/save while reply/forward quote text is still upgrading from a
/// provisional listing snippet to a CTE-decoded `MessageBody`.
enum ComposeQuotedBodyUpgradePolicy {
    /// Reply/forward (not recovered drafts) start pending until upgrade finishes.
    static func initiallyPending(
        hasRecoveredDraft: Bool,
        isReplyOrForward: Bool
    ) -> Bool {
        !hasRecoveredDraft && isReplyOrForward
    }

    /// Send and save must wait while the upgrade task is outstanding.
    static func blocksSending(isUpgradePending: Bool) -> Bool {
        isUpgradePending
    }
}
