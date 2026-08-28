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

struct ComposeAIAvailabilityState: Equatable, Sendable {
    var settings: AIWriterSettings
    var hasProviderBackend: Bool
    var backendSupportsAIWriter: Bool
    var isBusy: Bool
    var hasActiveRequest: Bool

    var providerUnavailableReason: ComposeAIActionDisabledReason? {
        if !backendSupportsAIWriter { return .unsupportedAccount }
        if !hasProviderBackend { return .missingBackend }
        return nil
    }

    func context(
        bodyText: String,
        selectedText: String? = nil,
        promptText: String? = nil,
        hasReplyContext: Bool = true,
        hasSubjectTarget: Bool = true
    ) -> ComposeAIActionContext {
        ComposeAIActionContext(
            hasBackend: hasProviderBackend,
            isEnabled: settings.isEnabled,
            hasConsent: settings.consentGiven,
            supportsAI: backendSupportsAIWriter,
            isBusy: isBusy,
            hasActiveRequest: hasActiveRequest,
            bodyText: bodyText,
            selectedText: selectedText,
            promptText: promptText,
            hasReplyContext: hasReplyContext,
            hasSubjectTarget: hasSubjectTarget
        )
    }
}
