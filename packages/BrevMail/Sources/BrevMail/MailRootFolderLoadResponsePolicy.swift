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

struct MailRootFolderLoadRequest: Equatable, Sendable {
    let id: Int
}

enum MailRootFolderLoadStartPolicy {
    static func canStartLoad(
        activeRequest: MailRootFolderLoadRequest?,
        activeMailboxSwitchRequest: MailRootMailboxSwitchRequest?,
        supersedingActiveRequest: Bool = false
    ) -> Bool {
        (activeRequest == nil || supersedingActiveRequest)
            && activeMailboxSwitchRequest == nil
    }
}

enum MailRootFolderLoadResponsePolicy {
    static func canApplyResponse(
        request: MailRootFolderLoadRequest,
        activeRequest: MailRootFolderLoadRequest?
    ) -> Bool {
        activeRequest == request
    }
}

/// Decides how to reconcile the displayed folder list when the selected mail
/// source changes (#193). The bug it guards against: selecting a source whose
/// per-account section has not loaded yet (e.g. a just-added account during
/// multi-account restore) would otherwise leave the sidebar showing the
/// *previous* account's folders until the new section arrives.
enum MailRootSelectedSourceSyncPolicy {
    enum Action: Equatable {
        /// A loaded section matches the selected source — apply its folders.
        case applySection
        /// A specific source is selected but its section has not loaded yet —
        /// clear the stale folders so no other account's folders show through.
        /// `applyLoadedSourceSections` re-populates once the section arrives.
        case clearStaleFolders
        /// No specific source is selected (single-account / unified inbox /
        /// smart view); that load path owns the folder list — leave it.
        case keep
    }

    static func action(
        hasMatchingSection: Bool,
        isSpecificSourceSelected: Bool
    ) -> Action {
        if hasMatchingSection { return .applySection }
        return isSpecificSourceSelected ? .clearStaleFolders : .keep
    }
}
