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

@Suite("MailRootSelectedSourceSyncPolicy")
struct MailRootSelectedSourceSyncPolicyTests {
    @Test("applies the matching section regardless of how the source was selected")
    func appliesMatchingSection() {
        #expect(
            MailRootSelectedSourceSyncPolicy.action(
                hasMatchingSection: true,
                isSpecificSourceSelected: true
            ) == .applySection
        )
        #expect(
            MailRootSelectedSourceSyncPolicy.action(
                hasMatchingSection: true,
                isSpecificSourceSelected: false
            ) == .applySection
        )
    }

    @Test("clears stale folders when a specific source is selected but its section has not loaded")
    func clearsStaleWhenSourceUnloaded() {
        // The #193 cross-account flash: a just-added account is selected before
        // its per-account section exists, so the previous account's folders
        // must not show through.
        #expect(
            MailRootSelectedSourceSyncPolicy.action(
                hasMatchingSection: false,
                isSpecificSourceSelected: true
            ) == .clearStaleFolders
        )
    }

    @Test("keeps folders when no specific source is selected (single-account / unified / smart view)")
    func keepsWhenNoSpecificSource() {
        // Here the single-account loadFolders path owns the list, so the sync
        // must not clobber it.
        #expect(
            MailRootSelectedSourceSyncPolicy.action(
                hasMatchingSection: false,
                isSpecificSourceSelected: false
            ) == .keep
        )
    }
}
