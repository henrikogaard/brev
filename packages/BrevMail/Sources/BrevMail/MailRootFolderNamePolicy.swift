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

/// Resolves a folder name without crossing account boundaries.
enum MailRootFolderNamePolicy {
    /// Finds the event folder in the event account's source sections, using
    /// the selected account's flat folder list only for that same account.
    static func resolve(
        folderID: Folder.ID,
        backendAccountID: BrevAccount.ID,
        selectedAccountID: BrevAccount.ID,
        selectedAccountFolders: [Folder],
        sourceSections: [MailSourceSection]
    ) -> String? {
        let accountSections = sourceSections.filter { $0.account.id == backendAccountID }
        if let match = accountSections
            .lazy
            .flatMap(\.folders)
            .first(where: { $0.id == folderID }) {
            return match.name
        }

        guard backendAccountID == selectedAccountID else { return nil }
        return selectedAccountFolders.first(where: { $0.id == folderID })?.name
    }
}
