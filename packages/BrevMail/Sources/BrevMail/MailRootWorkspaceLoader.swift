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

/// Startup workspace load orchestration extracted from `BrevMailRootView`.
///
/// Keeps the root view thinner and makes the critical-path order explicit:
/// source sections first, then mailbox/folder fallback, then one-time retention.
enum MailRootWorkspaceLoader {
    @MainActor
    static func load(
        loadSourceSections: () async -> Void,
        loadMailboxes: () async -> Void,
        loadFolders: () async -> Void,
        sourceSectionsEmpty: () -> Bool,
        runInitialRetentionIfNeeded: () async -> Void
    ) async {
        await loadSourceSections()
        if sourceSectionsEmpty() {
            await loadMailboxes()
            await loadFolders()
        }
        await runInitialRetentionIfNeeded()
    }
}
