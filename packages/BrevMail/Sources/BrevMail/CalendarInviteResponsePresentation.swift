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

struct CalendarInviteLocalResponse: Equatable {
    let messageID: MessageHeader.ID
    let response: AttendeeState
}

struct CalendarInviteResponseRequest: Equatable, Sendable {
    let messageID: MessageHeader.ID
    let sourceID: MailSourceID?
    let response: AttendeeState

    init(
        messageID: MessageHeader.ID,
        sourceID: MailSourceID? = nil,
        response: AttendeeState
    ) {
        self.messageID = messageID
        self.sourceID = sourceID
        self.response = response
    }
}

enum CalendarInviteResponseStartPolicy {
    static func canStartResponse(
        activeRequest: CalendarInviteResponseRequest?,
        isBlocked: Bool
    ) -> Bool {
        !isBlocked && activeRequest == nil
    }
}

enum CalendarInviteResponsePolicy {
    static func canApplyResponse(
        request: CalendarInviteResponseRequest,
        activeRequest: CalendarInviteResponseRequest?,
        currentSourceID: MailSourceID? = nil,
        currentMessageID: MessageHeader.ID?
    ) -> Bool {
        activeRequest == request
            && currentSourceID == request.sourceID
            && currentMessageID == request.messageID
    }
}

struct CalendarInviteResponsePresentation: Equatable {
    let label: String?
    let showsActions: Bool

    static func resolve(
        header: MessageHeader,
        localResponse: CalendarInviteLocalResponse?
    ) -> CalendarInviteResponsePresentation? {
        if let localResponse, localResponse.messageID == header.id {
            return CalendarInviteResponsePresentation(
                label: localResponse.response.displayLabel,
                showsActions: false
            )
        }

        if header.isAnswered {
            return CalendarInviteResponsePresentation(
                label: "Responded",
                showsActions: false
            )
        }

        return CalendarInviteResponsePresentation(
            label: nil,
            showsActions: true
        )
    }

    static func confirmationMessage(for response: AttendeeState) -> String {
        confirmationStatus(for: response).message
    }

    static func confirmationStatus(
        for response: AttendeeState,
        sendResult: SendResult? = nil
    ) -> MailRootStatus {
        if sendResult?.warnings.contains(.sentCopyAppendFailed) == true {
            return MailRootStatus(
                message: "\(confirmationMessagePrefix(for: response)), but Brev couldn't save a copy to Sent.",
                tone: .warning
            )
        }
        return MailRootStatus(
            message: confirmationMessagePrefix(for: response) + ".",
            tone: .success
        )
    }

    private static func confirmationMessagePrefix(for response: AttendeeState) -> String {
        switch response {
        case .accepted:
            return "Invite accepted"
        case .tentative:
            return "Tentative response sent"
        case .declined:
            return "Invite declined"
        case .needsAction:
            return "Invite response updated"
        }
    }
}
