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

enum MessageListReloadOperation: Equatable, Sendable {
    case folder
    case search(query: String)
}

enum MessageListReloadPolicy {
    static func operation(forSearchText searchText: String) -> MessageListReloadOperation {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .folder }
        return .search(query: query)
    }

    /// Whether a change to the search text or to a search option (scope,
    /// execution, all folders) needs a reload. Without search text the folder
    /// page does not depend on any search option, so an options-only change —
    /// such as the execution reset a folder switch performs — must not fetch
    /// the page the folder load already fetched.
    static func searchChangeNeedsReload(oldSearchText: String, newSearchText: String) -> Bool {
        operation(forSearchText: oldSearchText) != .folder || operation(forSearchText: newSearchText) != .folder
    }
}

enum MessageListWorkResumePolicy {
    static func shouldReloadVisibleMessages(
        wasBlocked: Bool,
        isBlocked: Bool,
        hasPendingReload: Bool
    ) -> Bool {
        wasBlocked && !isBlocked && hasPendingReload
    }
}
