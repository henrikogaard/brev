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

struct MessageListMutationRollback {
    struct RestoredState {
        let headers: [MessageHeader]
        let loadedFolderHeaders: [MessageHeader]
    }

    private let visibleHeaders: [MessageHeader]
    private let loadedFolderHeaders: [MessageHeader]
    private let currentFolderHeaders: [MessageHeader]
    private let selectedMessageID: MessageHeader.ID?
    private let bulkSelection: Set<MessageHeader.ID>

    @MainActor
    init(
        visibleHeaders: [MessageHeader],
        loadedFolderHeaders: [MessageHeader],
        navigation: MailNavigationState
    ) {
        self.visibleHeaders = visibleHeaders
        self.loadedFolderHeaders = loadedFolderHeaders
        currentFolderHeaders = navigation.currentFolderHeaders
        selectedMessageID = navigation.selectedMessageID
        bulkSelection = navigation.bulkSelection
    }

    @MainActor
    func restore(navigation: MailNavigationState, excludingRemovedIDs: Set<MessageHeader.ID> = []) -> RestoredState {
        navigation.currentFolderHeaders = currentFolderHeaders.filter { !excludingRemovedIDs.contains($0.id) }
        navigation.selectedMessageID = selectedMessageID.flatMap { excludingRemovedIDs.contains($0) ? nil : $0 }
        navigation.bulkSelection = bulkSelection.subtracting(excludingRemovedIDs)
        return RestoredState(
            headers: visibleHeaders.filter { !excludingRemovedIDs.contains($0.id) },
            loadedFolderHeaders: loadedFolderHeaders.filter { !excludingRemovedIDs.contains($0.id) }
        )
    }
}

struct UnifiedInboxMutationRollback {
    struct RestoredState {
        let items: [UnifiedInboxItem]
        let selectedItemIDs: Set<UnifiedInboxItem.ID>
    }

    private let sourceID: MailSourceID?
    private let folderID: Folder.ID?
    private let collectionID: Folder.ID?
    private let items: [UnifiedInboxItem]
    private let selectedItemIDs: Set<UnifiedInboxItem.ID>
    private let currentFolderHeaders: [MessageHeader]
    private let selectedMessageID: MessageHeader.ID?
    private let bulkSelection: Set<MessageHeader.ID>

    @MainActor
    init(
        items: [UnifiedInboxItem],
        selectedItemIDs: Set<UnifiedInboxItem.ID>,
        navigation: MailNavigationState
    ) {
        sourceID = navigation.selectedSourceID
        folderID = navigation.selectedFolderID
        collectionID = navigation.selectedCollectionFolderID
        self.items = items
        self.selectedItemIDs = selectedItemIDs
        currentFolderHeaders = navigation.currentFolderHeaders
        selectedMessageID = navigation.selectedMessageID
        bulkSelection = navigation.bulkSelection
    }

    func restoring(failedItemIDs: Set<UnifiedInboxItem.ID>, in currentItems: [UnifiedInboxItem]) -> RestoredState {
        let currentByID = Dictionary(currentItems.map { ($0.id, $0) }) { _, latest in latest }
        let restored = items.compactMap { item in
            failedItemIDs.contains(item.id) ? item : currentByID[item.id]
        }
        let failedIDs = failedItemIDs
        return RestoredState(items: restored, selectedItemIDs: selectedItemIDs.intersection(failedIDs))
    }

    @MainActor
    func restoreFailedReader(
        in navigation: MailNavigationState,
        failedItemIDs: Set<UnifiedInboxItem.ID>,
        expectedSelectionRevision: Int
    ) {
        guard navigation.readerSelectionRevision == expectedSelectionRevision,
              let sourceID,
              let selectedItem = items.first(where: { $0.sourceID == sourceID && $0.header.id == selectedMessageID }),
              failedItemIDs.contains(selectedItem.id) else { return }
        let header = selectedItem.header
        if let collectionID {
            navigation.selectSmartView(folderID: collectionID)
        } else {
            navigation.selectFolder(folderID, in: sourceID)
        }
        navigation.selectMessage(header, in: sourceID, headers: currentFolderHeaders)
    }

    @MainActor
    func restore(navigation: MailNavigationState) -> RestoredState {
        navigation.currentFolderHeaders = currentFolderHeaders
        navigation.selectedMessageID = selectedMessageID
        navigation.bulkSelection = bulkSelection
        return RestoredState(items: items, selectedItemIDs: selectedItemIDs)
    }
}
