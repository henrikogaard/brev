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
import BrevDesign
import BrevThemes
import SwiftUI

/// Routes "Create Event from Message" to the shared calendar editor
/// (#10, ADR-0072) when the session has writable PIM calendars, and to
/// the local EventKit sheet otherwise.
///
/// The decision needs the writable-target list, which loads
/// asynchronously, so the sheet shows a brief progress state while
/// the editing model resolves its targets. A session without event
/// authoring, or one whose load returns no writable calendar, keeps
/// the previous EventKit behavior unchanged.
struct MessageCreateEventSheet: View {
    @Environment(\.brevTheme) private var theme

    /// Writable-calendar owner for the shared editor; nil when the
    /// session has no event write service.
    let editing: CalendarEditingModel?
    /// The message the draft is built from.
    let header: MessageHeader
    /// Account the deep link is scoped to.
    let accountID: String
    /// Dismisses the sheet.
    let onClose: () -> Void

    /// nil = still resolving targets; true = shared editor; false =
    /// EventKit fallback.
    @State private var useSharedEditor: Bool?

    var body: some View {
        Group {
            switch useSharedEditor {
            case .some(true):
                if let editing,
                   let draft = MessageEventDraftBuilder.calendarDraft(
                       for: header,
                       accountID: accountID,
                       referenceDate: Date()
                   ) {
                    CalendarEventEditorView(
                        editing: editing,
                        draft: draft,
                        onSaved: {}
                    )
                } else {
                    MessageEventUnavailableSheet(onClose: onClose)
                }
            case .some(false):
                fallbackSheet
            case nil:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.bgPrimary.color)
            }
        }
        .task { await resolve() }
    }

    private var fallbackSheet: some View {
        let draft = MessageEventDraftBuilder.draft(
            for: header,
            accountID: accountID,
            referenceDate: Date()
        )
        return Group {
            if let draft {
                MessageEventSheet(
                    draft: draft,
                    create: {
                        try await AppleCalendarEventCreator()
                            .createEvent(from: $0)
                    },
                    onClose: onClose
                )
            } else {
                MessageEventUnavailableSheet(onClose: onClose)
            }
        }
    }

    /// Loads writable targets once, then picks the editor. Authoring
    /// disabled or zero writable calendars keep the EventKit fallback.
    @MainActor
    private func resolve() async {
        guard useSharedEditor == nil else { return }
        if let editing {
            await editing.load()
        }
        useSharedEditor = MessageCreateEventRouting.usesSharedEditor(
            editing: editing
        )
    }
}

/// Pure routing decision for Create Event from Message (#10): the
/// shared editor only when the session can author events and at least
/// one writable calendar target resolved; the EventKit sheet
/// otherwise. Kept separate from the view so the policy is unit
/// testable without rendering.
@MainActor
enum MessageCreateEventRouting {
    static func usesSharedEditor(
        editing: CalendarEditingModel?
    ) -> Bool {
        guard let editing, editing.canAuthor else { return false }
        return !editing.targets.isEmpty
    }
}
