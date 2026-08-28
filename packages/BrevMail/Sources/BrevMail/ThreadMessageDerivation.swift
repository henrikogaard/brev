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
import Foundation

/// Pure utilities for deriving thread message lists from in-memory headers.
///
/// Thread membership is resolved client-side — no backend fetch required.
/// Headers are already loaded into `MailNavigationState.currentFolderHeaders`.
enum ThreadMessageDerivation {
    /// Returns all headers sharing `threadID`, sorted oldest → newest.
    ///
    /// - Parameters:
    ///   - allHeaders: The full set of headers for the current folder.
    ///   - threadID: The thread to filter to.
    /// - Returns: Filtered and sorted headers, empty if none match.
    static func threadHeaders(
        from allHeaders: [MessageHeader],
        threadID: String
    ) -> [MessageHeader] {
        allHeaders
            .filter { $0.threadID == threadID }
            .sorted { $0.date < $1.date }
    }
}

/// Policy for which card starts expanded in ThreadConversationView.
enum ThreadConversationExpansionPolicy {
    /// Returns the ID of the newest (last) header — the default-expanded card.
    /// Assumes headers are sorted oldest → newest (as returned by ThreadMessageDerivation).
    static func defaultExpandedID(in headers: [MessageHeader]) -> MessageHeader.ID? {
        headers.last?.id
    }

    /// Returns the selected message when it belongs to this thread,
    /// otherwise falls back to the newest message.
    static func expandedID(
        selectedID: MessageHeader.ID?,
        in headers: [MessageHeader]
    ) -> MessageHeader.ID? {
        if let selectedID, headers.contains(where: { $0.id == selectedID }) {
            return selectedID
        }
        return defaultExpandedID(in: headers)
    }
}

enum ThreadConversationAccessibilityPolicy {
    static func shouldAutoScrollToExpandedMessage(
        autoScrollsToExpandedMessage: Bool,
        isAccessibilitySize: Bool
    ) -> Bool {
        autoScrollsToExpandedMessage && !isAccessibilitySize
    }
}

/// Helpers for inline thread expansion in MessageListView.
enum MessageListInlineExpansion {
    /// Toggles the presence of `threadID` in the expansion set.
    static func toggle(threadID: String, in set: inout Set<String>) {
        if set.contains(threadID) {
            set.remove(threadID)
        } else {
            set.insert(threadID)
        }
    }

    /// Expands a thread without collapsing it. Used when selecting a
    /// grouped parent row so child messages become selectable inline.
    static func expandIfNeeded(
        threadID: String,
        threadCount: Int,
        isThreadingEnabled: Bool,
        in set: inout Set<String>
    ) {
        guard isThreadingEnabled, threadCount > 1 else { return }
        set.insert(threadID)
    }

    /// Returns all headers belonging to `threadID`, sorted oldest → newest.
    static func childHeaders(
        for threadID: String,
        excludingParentID parentID: MessageHeader.ID,
        from allHeaders: [MessageHeader]
    ) -> [MessageHeader] {
        ThreadMessageDerivation.threadHeaders(from: allHeaders, threadID: threadID)
            .filter { $0.id != parentID }
    }
}
