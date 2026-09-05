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

/// Restores the reader only within the view where the reversed action began.
@MainActor
final class MailUndoSelectionRestorer {
    private weak var navigation: MailNavigationState?
    private let header: MessageHeader
    private let sourceID: MailSourceID?
    private let folderID: Folder.ID?
    private let collectionID: Folder.ID?
    private let searchText: String

    init?(navigation: MailNavigationState) {
        guard let header = navigation.selectedHeader else { return nil }
        self.navigation = navigation
        self.header = header
        sourceID = navigation.selectedSourceID
        folderID = navigation.selectedFolderID
        collectionID = navigation.isUnifiedInboxSelected || navigation.isSmartViewSelected ? navigation.browsingFolderID : nil
        searchText = navigation.searchText
    }

    func restore(using receipt: MailMoveUndo) async throws {
        let revision = navigation.flatMap { matchesLocation($0) ? $0.readerSelectionRevision : nil }
        let mapping = try await receipt.restore()
        try Task.checkCancellation()
        guard let navigation, let revision, navigation.readerSelectionRevision == revision,
              matchesLocation(navigation), sourceID == nil || sourceID == receipt.sourceID,
              receipt.originalFolder.id == header.folderID, let restoredID = mapping[header.id] else { return }
        let restored = header.withIdentity(restoredID, folderID: receipt.originalFolder.id)
        let current = navigation.selectedSourceID == sourceID ? navigation.currentFolderHeaders : []
        let headers = current.filter { $0.id != header.id && $0.id != restoredID } + [restored]
        navigation.restoreMovedSelection(restored, in: sourceID != nil || collectionID != nil ? receipt.sourceID : nil,
                                         headers: headers)
    }

    private func matchesLocation(_ navigation: MailNavigationState) -> Bool {
        guard navigation.searchText == searchText else { return false }
        if let collectionID { return navigation.browsingFolderID == collectionID }
        return navigation.selectedSourceID == sourceID && navigation.selectedFolderID == folderID
    }
}
