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

struct MessageCommandMutationRollback {
    private let currentFolderHeaders: [MessageHeader]
    private let selectedMessageID: MessageHeader.ID?
    private let bulkSelection: Set<MessageHeader.ID>

    @MainActor
    init(navigation: MailNavigationState) {
        currentFolderHeaders = navigation.currentFolderHeaders
        selectedMessageID = navigation.selectedMessageID
        bulkSelection = navigation.bulkSelection
    }

    @MainActor
    func restore(navigation: MailNavigationState) {
        navigation.currentFolderHeaders = currentFolderHeaders
        navigation.selectedMessageID = selectedMessageID
        navigation.bulkSelection = bulkSelection
    }
}
