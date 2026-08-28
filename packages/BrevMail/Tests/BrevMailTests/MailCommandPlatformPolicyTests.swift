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

@testable import BrevMail
import Testing

@Suite("MailCommandPlatformPolicy")
struct MailCommandPlatformPolicyTests {
    @Test("message, compose, and print commands are cross-platform")
    func sharedGroups() {
        for platform in [MailCommandPlatformPolicy.Platform.macOS, .iOS] {
            let policy = MailCommandPlatformPolicy.forPlatform(platform)
            #expect(policy.includesMessageCommands)
            #expect(policy.includesComposeCommands)
            #expect(policy.includesPrintCommands)
        }
    }

    @Test("import/export, updates, and keyboard-shortcuts window are macOS-only")
    func macOSOnlyGroups() {
        let mac = MailCommandPlatformPolicy.forPlatform(.macOS)
        #expect(mac.includesImportExportCommands)
        #expect(mac.includesKeyboardShortcutsWindowCommand)

        let ios = MailCommandPlatformPolicy.forPlatform(.iOS)
        #expect(!ios.includesImportExportCommands)
        #expect(!ios.includesKeyboardShortcutsWindowCommand)
    }

    @Test("folder MBOX export stays unavailable until full message bodies are available")
    func folderMBOXExportRequiresFullBodies() {
        let mac = MailCommandPlatformPolicy.forPlatform(.macOS)

        #expect(!mac.includesFolderMBOXExportCommand)
    }
}
