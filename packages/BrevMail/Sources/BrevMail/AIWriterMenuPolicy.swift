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

enum AIWriterMenuPolicy {
    static func isMenuDisabled(isBusy: Bool, isAIWorking: Bool) -> Bool {
        isBusy || isAIWorking
    }

    static func areShortcutsDisabled(bodyText: String) -> Bool {
        ComposeAIActionAvailability.disabledReason(
            for: .shortcut(.improveWriting, scope: .wholeDraft),
            in: ComposeAIActionContext(
                hasBackend: true,
                isEnabled: true,
                hasConsent: true,
                supportsAI: true,
                isBusy: false,
                hasActiveRequest: false,
                bodyText: bodyText,
                selectedText: nil,
                promptText: nil,
                hasReplyContext: true,
                hasSubjectTarget: true
            )
        ) != nil
    }
}
