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
import Testing

@Suite("Export filename suggestions")
struct MailExportFilenameTests {
    @Test("archive suggestions remove path separators and reserved characters")
    func safeArchiveSuggestion() {
        let name = MailFolderExporter.suggestedArchiveName(for: #"../../a:b/c\d?e%f*g|h"i<j>k"#)
        #expect(!name.contains("/"))
        #expect(!name.contains("\\"))
        #expect(!name.hasPrefix("."))
        #expect(name.hasSuffix(".mbox"))
    }

    @Test("archive suggestions respect filesystem byte limits with Unicode names")
    func unicodeNamesAreBounded() {
        let name = MailFolderExporter.suggestedArchiveName(for: String(repeating: "👨‍👩‍👧‍👦", count: 100))
        #expect(name.utf8.count <= 255)
        #expect(!name.contains("�"))
        #expect(name.hasSuffix(".mbox"))
    }

    @Test("empty and dot-only folder names have a safe archive name")
    func emptyNamesHaveFallback() {
        #expect(MailFolderExporter.suggestedArchiveName(for: "   ") == "Mailbox.mbox")
        #expect(MailFolderExporter.suggestedArchiveName(for: "..") == "Mailbox.mbox")
    }
}
