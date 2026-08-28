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

import BrevAI
import Foundation

enum MailboxActionAgentAvailabilityPolicy {
    static func isVisible(
        settings: MailboxActionAgentSettings,
        hasAIBackend: Bool,
        backendSupportsAIIntent: Bool
    ) -> Bool {
        settings.isAvailable
            && hasAIBackend
            && backendSupportsAIIntent
    }

    static func canPresent(
        settings: MailboxActionAgentSettings,
        hasAIBackend: Bool,
        backendSupportsAIIntent: Bool,
        hasSelectedFolder: Bool,
        hasActionFolders: Bool,
        hasActiveWork: Bool,
        hasPresentedSheet: Bool,
        isUnifiedInboxSelected: Bool,
        isSmartViewSelected: Bool
    ) -> Bool {
        isVisible(
            settings: settings,
            hasAIBackend: hasAIBackend,
            backendSupportsAIIntent: backendSupportsAIIntent
        )
            && hasSelectedFolder
            && hasActionFolders
            && !hasActiveWork
            && !hasPresentedSheet
            && !isUnifiedInboxSelected
            && !isSmartViewSelected
    }
}
