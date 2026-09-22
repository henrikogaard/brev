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

import BrevCalendar
import Foundation

/// Editable form state for the task editor (ADR-0072 #12).
///
/// The draft owns every field the editor renders and converts to and
/// from PIMTask. Provider identity fields (uid, providerItemKey,
/// providerVersion, rawPayload) ride along untouched so an edit
/// round-trips the record the provider owns while the user-facing
/// fields carry the edits.
public struct TaskDraft: Sendable, Hashable {
    public var title = ""
    public var notes = ""
    /// Due date; nil clears it. Google stores the date only.
    public var due: Date?
    public var status: PIMTaskStatus = .needsAction
    /// The write target: a collection ID on the source being edited.
    public var targetID: String?

    // Provider identity carried through edits; always nil on create.
    var uid: String?
    var providerItemKey: String?
    var providerVersion: String?
    var rawPayload: String?
    var providerUpdatedAt: Date?
    var position: String?
    var parentKey: String?
    var links: [String] = []
    var completedAt: Date?
    /// The collection the edited task belongs to, for move detection.
    var originalCollectionID: PIMCollection.ID?

    /// A blank draft for a new task.
    public init() {}

    /// A draft pre-filled from a cached task for editing.
    public init(task: PIMTask) {
        title = task.title ?? ""
        notes = task.notes ?? ""
        due = task.due
        status = task.status
        targetID = task.collectionID
        originalCollectionID = task.collectionID
        uid = task.uid
        providerItemKey = task.providerItemKey
        providerVersion = task.providerVersion
        rawPayload = task.rawPayload
        providerUpdatedAt = task.providerUpdatedAt
        position = task.position
        parentKey = task.parentKey
        links = task.links
        completedAt = task.completedAt
    }

    /// Whether the draft has enough to save — a non-empty title.
    public var isSaveEnabled: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Folds the draft into a PIMTask for the write path. On create the
    /// caller supplies the target collection; identity fields are nil
    /// and the service assigns provider keys.
    public func task(
        sourceID: PIMSource.ID,
        collectionID: PIMCollection.ID
    ) -> PIMTask {
        PIMTask(
            id: providerItemKey.map {
                PIMTask.makeID(
                    collectionID: collectionID,
                    providerItemKey: $0
                )
            } ?? "draft",
            sourceID: sourceID,
            collectionID: collectionID,
            providerItemKey: providerItemKey ?? "",
            providerVersion: providerVersion,
            uid: uid,
            title: title,
            notes: notes.isEmpty ? nil : notes,
            due: due,
            completedAt: status == .completed
                ? (completedAt ?? Date())
                : nil,
            status: status,
            position: position,
            parentKey: parentKey,
            links: links,
            rawPayload: rawPayload,
            providerUpdatedAt: providerUpdatedAt
        )
    }
}
