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

@Suite("MailRootWorkspaceLoader")
struct MailRootWorkspaceLoaderTests {
    @Test("loads source sections before mailbox fallback and retention")
    @MainActor
    func loadsSourceSectionsBeforeMailboxFallbackAndRetention() async {
        var steps: [String] = []
        var sourceEmpty = true

        await MailRootWorkspaceLoader.load(
            loadSourceSections: {
                steps.append("sources")
                sourceEmpty = true
            },
            loadMailboxes: {
                steps.append("mailboxes")
            },
            loadFolders: {
                steps.append("folders")
            },
            sourceSectionsEmpty: { sourceEmpty },
            runInitialRetentionIfNeeded: {
                steps.append("retention")
            }
        )

        #expect(steps == ["sources", "mailboxes", "folders", "retention"])
    }

    @Test("skips mailbox fallback when source sections already exist")
    @MainActor
    func skipsMailboxFallbackWhenSourceSectionsExist() async {
        var steps: [String] = []

        await MailRootWorkspaceLoader.load(
            loadSourceSections: {
                steps.append("sources")
            },
            loadMailboxes: {
                steps.append("mailboxes")
            },
            loadFolders: {
                steps.append("folders")
            },
            sourceSectionsEmpty: { false },
            runInitialRetentionIfNeeded: {
                steps.append("retention")
            }
        )

        #expect(steps == ["sources", "retention"])
    }
}
