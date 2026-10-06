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
                label: responseLabel(for: localResponse.response),
                showsActions: false
            )
        }

        if header.isAnswered {
            return CalendarInviteResponsePresentation(
                label: String(localized: "Responded", bundle: .module),
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
                message: String(
                    localized:
                    "\(confirmationMessagePrefix(for: response)), but Brev couldn't save a copy to Sent.",
                    bundle: .module
                ),
                tone: .warning
            )
        }
        return MailRootStatus(
            message: confirmationMessagePrefix(for: response) + ".",
            tone: .success
        )
    }

    /// The confirmation shown after the mail reply succeeded and the
    /// shared-calendar reconciliation ran (#10). The mail outcome is
    /// always stated first; the calendar outcome follows so a partial
    /// failure never reads as a full success.
    static func confirmationStatus(
        for response: AttendeeState,
        sendResult: SendResult? = nil,
        reconciliation: CalendarInviteReconciliation
    ) -> MailRootStatus {
        let base = confirmationStatus(
            for: response,
            sendResult: sendResult
        )
        switch reconciliation {
        case .updated(let sourceName):
            return MailRootStatus(
                message: base.message + " " + String(
                    localized: "Calendar updated on \(sourceName).",
                    bundle: .module
                ),
                tone: .success
            )
        case .notSynced:
            return MailRootStatus(
                message: base.message + " " + String(
                    localized:
                    "The event is not synced to a Brev calendar, so only the reply was sent.",
                    bundle: .module
                ),
                tone: .info
            )
        case .notWritable(let sourceName):
            return MailRootStatus(
                message: base.message + " " + String(
                    localized:
                    "The \(sourceName) calendar is read-only, so the event's attendee list was not updated.",
                    bundle: .module
                ),
                tone: .warning
            )
        case .noMatchingAttendee:
            return MailRootStatus(
                message: base.message + " " + String(
                    localized:
                    "Brev could not match you to an attendee on the synced event, so only the reply was sent.",
                    bundle: .module
                ),
                tone: .info
            )
        case .failed(let sourceName, let message):
            return MailRootStatus(
                message: base.message + " " + String(
                    localized: "Updating the \(sourceName) calendar failed: \(message)",
                    bundle: .module
                ),
                tone: .warning
            )
        }
    }

    /// The RSVP badge for the locally-recorded reply — `AttendeeState`
    /// lives in BrevBackend, so its English `displayLabel` stays a
    /// model token and this layer owns the localized words.
    private static func responseLabel(for response: AttendeeState) -> String {
        switch response {
        case .accepted:
            String(localized: "Accepted", bundle: .module)
        case .tentative:
            String(localized: "Tentative", bundle: .module)
        case .declined:
            String(localized: "Declined", bundle: .module)
        case .needsAction:
            String(localized: "Needs action", bundle: .module)
        }
    }

    private static func confirmationMessagePrefix(for response: AttendeeState) -> String {
        switch response {
        case .accepted:
            return String(localized: "Invite accepted", bundle: .module)
        case .tentative:
            return String(localized: "Tentative response sent", bundle: .module)
        case .declined:
            return String(localized: "Invite declined", bundle: .module)
        case .needsAction:
            return String(localized: "Invite response updated", bundle: .module)
        }
    }
}
