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

/// Coordinates what happens when a user accepts (or declines) a calendar
/// invite, honouring the optional CalDAV write target.
///
/// The contract is deliberately small:
/// 1. Always produce a local iMIP reply (`IMIPReplyComposer`) so the
///    organizer learns the response — this path never depends on CalDAV.
/// 2. *If* a CalDAV write target is configured and the response is an
///    acceptance, additionally PUT the event into the chosen calendar.
///
/// CalDAV failures never block the iMIP reply: the outcome reports the
/// reply plus an optional calendar-write result or error, and the caller
/// decides how loudly to surface a write failure.
public struct InviteAcceptanceCoordinator: Sendable {
    /// What the calendar-write step did, if anything.
    public enum CalendarWriteOutcome: Sendable {
        /// No target configured, or the response was not an acceptance —
        /// iMIP reply only, exactly as before CalDAV existed.
        case skipped
        /// Event was PUT into the configured calendar.
        case written(CalDAVWriteResult)
        /// The PUT failed. The iMIP reply is still valid and returned.
        case failed(CalDAVWriteError)
    }

    /// The combined result of handling an invite response.
    public struct Outcome: Sendable {
        /// The iMIP reply payload — always present.
        public let reply: IMIPReplyComposer.Reply
        public let calendarWrite: CalendarWriteOutcome
    }

    public init() {}

    /// Handles an invite response.
    ///
    /// - Parameters:
    ///   - event: The parsed invite.
    ///   - attendee: The responding user.
    ///   - status: Accept / tentative / decline.
    ///   - originalICS: The full `VCALENDAR` of the invite, stored as-is
    ///     when writing to CalDAV. Pass `nil` to derive a minimal event
    ///     from `event` is *not* supported — callers always have the raw
    ///     ICS from the message part.
    ///   - writer: A configured `CalDAVEventWriter`, or `nil` when the
    ///     feature is off / unconfigured. When `nil`, only iMIP runs.
    /// - Returns: The iMIP reply plus the calendar-write outcome.
    public func handle(
        event: ICSParser.ParsedEvent,
        attendee: ICSParser.ParsedPerson,
        status: IMIPReplyComposer.ReplyStatus,
        originalICS: String,
        writer: CalDAVEventWriter?
    ) async throws -> Outcome {
        // 1. iMIP reply — required, never gated on CalDAV.
        let reply = try IMIPReplyComposer.compose(
            event: event,
            attendee: attendee,
            status: status
        )

        // 2. CalDAV write — only on acceptance, only when configured.
        guard let writer, status != .declined else {
            return Outcome(reply: reply, calendarWrite: .skipped)
        }

        do {
            let result = try await writer.putEvent(event, ics: originalICS)
            return Outcome(reply: reply, calendarWrite: .written(result))
        } catch let error as CalDAVWriteError {
            return Outcome(reply: reply, calendarWrite: .failed(error))
        }
    }
}
