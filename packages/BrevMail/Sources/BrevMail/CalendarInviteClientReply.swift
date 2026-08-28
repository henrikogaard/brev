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
import BrevCalendar
import Foundation

enum CalendarInviteReplyRoute: Equatable {
    case serverSide
    case clientSideIMIP
    case unsupported
}

enum CalendarInviteReplyRouting {
    static func route(for capabilities: BackendCapabilities) -> CalendarInviteReplyRoute {
        if capabilities.contains(.serverSideCalendarReply) { return .serverSide }
        if capabilities.contains(.smtpOAuth) { return .clientSideIMIP }
        return .unsupported
    }

    static func supportsActions(capabilities: BackendCapabilities) -> Bool {
        route(for: capabilities) != .unsupported
    }
}

struct CalendarInviteClientReplyPayload: Equatable {
    let draft: Draft
    let attachmentData: Data
    let filename: String
    let mimeType: String
}

enum CalendarInviteClientReplyComposer {
    enum ComposeError: Error, Equatable {
        case missingOrganizer
        case unsupportedResponse
    }

    static func compose(
        event: ICSParser.ParsedEvent,
        response: AttendeeState,
        account: BrevAccount,
        messageID: MessageHeader.ID,
        now: Date = Date()
    ) throws -> CalendarInviteClientReplyPayload {
        let status = try replyStatus(for: response)
        guard let organizer = event.organizer else {
            throw ComposeError.missingOrganizer
        }
        let attendee = event.attendees.first {
            $0.email.caseInsensitiveCompare(account.emailAddress) == .orderedSame
        } ?? ICSParser.ParsedPerson(name: account.displayName, email: account.emailAddress)
        let reply = try IMIPReplyComposer.compose(
            event: event,
            attendee: attendee,
            status: status,
            now: now
        )
        // The reply body is plain text that embeds the attacker-controlled event
        // SUMMARY; route it through the standard HTML-escaping path so a crafted
        // title (e.g. `<img src=x onerror=…>`) can't inject markup into the
        // outgoing HTML body.
        let replyText = reply.plainTextBody + "\n\nCalendar response attached as iMIP REPLY."
        let draft = Draft(
            id: "calendar-reply-\(messageID)-\(response.rawValue)",
            inReplyToMessageID: messageID,
            to: [Correspondent(name: organizer.name, email: organizer.email)],
            subject: reply.subject,
            htmlBody: ComposeHTMLBodyPolicy.html(fromEditorText: replyText)
        )
        return CalendarInviteClientReplyPayload(
            draft: draft,
            attachmentData: Data(reply.ics.utf8),
            filename: filename(for: event),
            mimeType: "text/calendar; method=REPLY"
        )
    }

    private static func replyStatus(for response: AttendeeState) throws -> IMIPReplyComposer.ReplyStatus {
        switch response {
        case .accepted:
            return .accepted
        case .tentative:
            return .tentative
        case .declined:
            return .declined
        case .needsAction:
            throw ComposeError.unsupportedResponse
        }
    }

    private static func filename(for event: ICSParser.ParsedEvent) -> String {
        let title = event.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = title?.isEmpty == false ? title! : "calendar-invite"
        let slug = base
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(slug.isEmpty ? "calendar-invite" : slug)-reply.ics"
    }
}
