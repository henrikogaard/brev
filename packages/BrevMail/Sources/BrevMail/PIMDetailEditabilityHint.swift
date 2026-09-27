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

/// Explains why a PIM detail pane offers no Edit/Delete actions for a
/// synced item (UI/UX review 2026-09-27 M4/P1): a read-only detail with
/// no hint looks broken, and the "Allow editing" toggle lives in
/// Settings rather than on the pane itself.
enum PIMDetailEditabilityHint {
    /// - Parameters:
    ///   - source: The item's owning source; nil when unresolved.
    ///   - collection: The item's collection; nil when unresolved.
    ///   - editActionsAvailable: Whether the pane shows Edit or Delete.
    /// - Returns: A displayable hint, or nil when editing is available or
    ///   the reason cannot be diagnosed (e.g. a provider that never
    ///   supports writes).
    static func text(
        source: PIMSource?,
        collection: PIMCollection?,
        editActionsAvailable: Bool
    ) -> String? {
        guard !editActionsAvailable, let source else { return nil }
        if collection?.isReadOnly == true {
            return String(
                localized: "This collection is read-only on the server.",
                bundle: .module
            )
        }
        guard !source.enabledCapabilities.contains(.write)
        else { return nil }
        return String(
            localized:
            "Editing is turned off for this source. Turn on “Allow editing” in Settings to change or delete it.",
            bundle: .module
        )
    }
}
