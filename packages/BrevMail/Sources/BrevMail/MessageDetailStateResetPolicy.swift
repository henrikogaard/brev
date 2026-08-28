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

enum MessageDetailTransientField: CaseIterable, Hashable, Sendable {
    case messageBody
    case renderedHTML
    case bodyLoadError
    case loading
    case readStatus
    case downloadingAttachment
    case attachmentError
    case recipientsExpansion
    case parsedInvite
    case inviteLoadStatus
    case remoteContentOverride
    case calendarResponse
    case inviteResponseConfirmation
    case inviteResponseStatus
    case failedInviteResponse
    case inviteResponseProgress
    case listUnsubscribeConfirmation
    case quickLookPreview
}

enum MessageDetailStateResetReason: Sendable {
    case messageUnavailable
    case messageLoadStarted
    case bodyLoadFailed
}

enum MessageDetailStateResetPolicy {
    static func clearedFields(
        for reason: MessageDetailStateResetReason
    ) -> Set<MessageDetailTransientField> {
        switch reason {
        case .messageUnavailable:
            return Set(MessageDetailTransientField.allCases)
        case .messageLoadStarted:
            return messageScopedFields
        case .bodyLoadFailed:
            return messageScopedFields.subtracting([.bodyLoadError])
        }
    }

    private static let messageScopedFields: Set<MessageDetailTransientField> = [
        .messageBody,
        .renderedHTML,
        .bodyLoadError,
        .readStatus,
        .downloadingAttachment,
        .attachmentError,
        .recipientsExpansion,
        .parsedInvite,
        .inviteLoadStatus,
        .remoteContentOverride,
        .calendarResponse,
        .inviteResponseConfirmation,
        .inviteResponseStatus,
        .failedInviteResponse,
        .inviteResponseProgress,
        .listUnsubscribeConfirmation,
        .quickLookPreview,
    ]
}
