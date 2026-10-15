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

/// The live calendar state a Drive save is qualified against (#14).
struct CalendarDriveSaveState: Hashable {
    let event: PIMEvent
    let collection: PIMCollection
    let source: PIMSource
}

/// Resolves whether one event attachment can be saved to Drive (#14).
///
/// Eligibility is a property of the event's own source and its linked
/// account — read-only events qualify, and no writable target is
/// consulted. The resolver reads live state through `state`, awaits the
/// feature's eligibility check, then re-reads that state: a source,
/// collection, account, or attachment that changed across the await
/// cannot enable the action.
enum CalendarDriveSaveEligibility {
    /// A resolved, still-current save target.
    struct Resolved: Equatable, Hashable {
        let eventID: PIMEvent.ID
        let sourceID: PIMSource.ID
        let collectionID: PIMCollection.ID
        let accountID: BrevAccount.ID
        let attachment: PIMEventAttachment
        let state: CalendarDriveSaveState

        func isCurrent(_ current: CalendarDriveSaveState?) -> Bool {
            current == state
        }
    }

    static func resolve(
        eventID: PIMEvent.ID,
        attachment: PIMEventAttachment,
        feature: GoogleDriveFeature,
        state: @escaping @MainActor () -> CalendarDriveSaveState?
    ) async -> Resolved? {
        guard let initialIdentity = await identity(
            eventID: eventID,
            attachment: attachment,
            state: state
        ) else { return nil }
        guard !Task.isCancelled else { return nil }
        guard await feature.isEligible(accountID: initialIdentity.accountID) else {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        let resolved = await identity(
            eventID: eventID,
            attachment: attachment,
            state: state
        )
        guard !Task.isCancelled, resolved == initialIdentity else { return nil }
        return resolved
    }

    @MainActor
    private static func identity(
        eventID: PIMEvent.ID,
        attachment: PIMEventAttachment,
        state: @MainActor () -> CalendarDriveSaveState?
    ) -> Resolved? {
        guard let state = state(),
              state.event.id == eventID,
              state.event.sourceID == state.source.id,
              state.event.collectionID == state.collection.id,
              state.collection.sourceID == state.source.id,
              state.event.attachments.contains(attachment),
              GoogleDriveEventSaveModel.fileID(in: attachment.url) != nil,
              let accountID = state.source.linkedAccountID,
              !accountID.isEmpty
        else { return nil }
        return Resolved(
            eventID: eventID,
            sourceID: state.source.id,
            collectionID: state.collection.id,
            accountID: accountID,
            attachment: attachment,
            state: state
        )
    }
}
