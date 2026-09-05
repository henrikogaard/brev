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
@testable import BrevSettings
import Testing

@Suite("Folder Sync hierarchy")
struct FolderSyncRowsTests {
    @Test("children remain under their parent and malformed cycles appear only once")
    func hierarchy() {
        let folders = [
            Folder(id: "child", name: "Travel", role: .custom, parentID: "parent"),
            Folder(id: "inbox", name: "Inbox", role: .inbox),
            Folder(id: "parent", name: "Archive", role: .archive),
            Folder(id: "cycle", name: "Cycle", role: .custom, parentID: "cycle")
        ]
        let rows = FolderSyncRows.make(folders)
        #expect(rows.map(\.folder.id) == ["inbox", "parent", "child", "cycle"])
        #expect(rows.map(\.depth) == [0, 0, 1, 0])
    }
}
