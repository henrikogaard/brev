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
import Observation

/// How a mail RSVP reconciled with the shared calendar cache (#10).
public enum CalendarInviteReconciliation: Equatable, Sendable {
    /// The cached event's attendee state was updated remotely and in
    /// the cache.
    case updated(sourceName: String)
    /// The event is not in the shared cache — the mail reply stands
    /// alone.
    case notSynced
    /// The event is cached but its source/collection is not writable
    /// right now.
    case notWritable(sourceName: String)
    /// The event is cached but none of its attendees match the
    /// account or the invite's recipients — nothing to update.
    case noMatchingAttendee
    /// The write failed; the mail reply still succeeded.
    case failed(sourceName: String, message: String)
}

/// Reconciles a calendar-invite RSVP with the synced calendar event
/// (#10, ADR-0072).
///
/// After the mail reply is sent, the reconciler finds the cached
/// PIMEvent by the invite's UID across every calendar source, patches
/// the attendee whose address matches the account (or the invite's
/// recipient list when the account address is absent), and writes the
/// update through the shared write service so the provider sees the
/// same response the email carried. All reads are cache-only.
@Observable
@MainActor
public final class CalendarInviteReconciler {
    private let coordinator: PIMSourceCoordinator?
    private let eventSyncService: PIMEventSyncService?
    private let collectionService: PIMCollectionService?
    private let writeService: (any CalendarEventWriting)?

    public init(
        coordinator: PIMSourceCoordinator? = nil,
        eventSyncService: PIMEventSyncService? = nil,
        collectionService: PIMCollectionService? = nil,
        writeService: (any CalendarEventWriting)? = nil
    ) {
        self.coordinator = coordinator
        self.eventSyncService = eventSyncService
        self.collectionService = collectionService
        self.writeService = writeService
    }

    /// Whether reconciliation can run — needs the cache readers and a
    /// write service.
    public var isAvailable: Bool {
        coordinator != nil && eventSyncService != nil
            && collectionService != nil && writeService != nil
    }

    /// The cached event matching an invite UID, if one is synced (#10).
    ///
    /// Cache-only lookup in the same source order reconcile() uses, so
    /// an "Open in Calendar" deep link targets the exact record an RSVP
    /// would update. One unreadable source cache never fails the
    /// lookup — the remaining sources still answer.
    public func cachedEvent(forUID uid: String) async -> PIMEvent? {
        let trimmedUID = uid.trimmingCharacters(in: .whitespaces)
        guard !trimmedUID.isEmpty,
              let coordinator,
              let eventSyncService else {
            return nil
        }
        guard let sources = try? await coordinator.allSources()
            .filter({ $0.kind == .calendar }) else {
            return nil
        }
        for source in sources {
            guard let events = try? await eventSyncService.events(
                for: source.id
            ) else { continue }
            if let event = events.first(where: { $0.uid == trimmedUID }) {
                return event
            }
        }
        return nil
    }

    /// Applies the RSVP to the cached event matching the invite.
    /// - Parameters:
    ///   - invite: The parsed invite; its UID selects the event.
    ///   - response: The response the mail reply carried.
    ///   - accountEmail: The receiving account's address — the
    ///     attendee to update when it appears on the event.
    ///   - recipientEmails: The invite message's To/Cc addresses —
    ///     the fallback identity when the account address is absent.
    public func reconcile(
        invite: ICSParser.ParsedEvent,
        response: AttendeeState,
        accountEmail: String,
        recipientEmails: [String]
    ) async -> CalendarInviteReconciliation {
        guard let uid = invite.uid?.trimmingCharacters(in: .whitespaces),
              !uid.isEmpty,
              let coordinator,
              let eventSyncService,
              let collectionService,
              let writeService else {
            return .notSynced
        }
        guard let rsvp = Self.rsvp(for: response) else {
            return .notSynced
        }
        do {
            let sources = try await coordinator.allSources()
                .filter { $0.kind == .calendar }
            for source in sources {
                let events = try await eventSyncService.events(
                    for: source.id
                )
                guard let event = events.first(where: { $0.uid == uid })
                else { continue }
                let collections = try await collectionService.collections(
                    for: source.id
                )
                guard let collection = collections.first(where: {
                    $0.id == event.collectionID
                }) else {
                    return .notWritable(sourceName: source.displayName)
                }
                let identities = Self.identityOrder(
                    accountEmail: accountEmail,
                    recipientEmails: recipientEmails
                )
                guard let index = event.attendees.firstIndex(
                    where: { attendee in
                        identities.contains {
                            $0.caseInsensitiveCompare(attendee.email)
                                == .orderedSame
                        }
                    }
                ) else {
                    return .noMatchingAttendee
                }
                guard writeService.canWrite(
                    source: source,
                    collection: collection
                ) else {
                    return .notWritable(sourceName: source.displayName)
                }
                var updated = event
                updated.attendees[index].rsvp = rsvp
                do {
                    _ = try await writeService.update(
                        updated,
                        in: collection,
                        source: source
                    )
                    return .updated(sourceName: source.displayName)
                } catch {
                    return .failed(
                        sourceName: source.displayName,
                        message: (error as? LocalizedError)?
                            .errorDescription
                            ?? error.localizedDescription
                    )
                }
            }
            return .notSynced
        } catch {
            return .notSynced
        }
    }

    /// The RSVP value a mail AttendeeState maps to; needsAction has no
    /// write counterpart — it is only a display state.
    static func rsvp(for response: AttendeeState) -> PIMEventPerson.RSVP? {
        switch response {
        case .accepted: .accepted
        case .tentative: .tentative
        case .declined: .declined
        case .needsAction: nil
        }
    }

    /// Identity candidates in priority order: the account address
    /// first, then the invite's recipients, deduplicated. The first
    /// attendee match wins so a multi-source event never picks a
    /// different identity silently.
    static func identityOrder(
        accountEmail: String,
        recipientEmails: [String]
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in [accountEmail] + recipientEmails {
            let email = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !email.isEmpty,
                  seen.insert(email.lowercased()).inserted else {
                continue
            }
            result.append(email)
        }
        return result
    }
}
