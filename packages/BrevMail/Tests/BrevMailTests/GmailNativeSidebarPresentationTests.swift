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
@testable import BrevMail
import Testing

@Suite("Gmail-native sidebar presentation")
struct GmailNativeSidebarPresentationTests {
    @Test("native label sources reveal All Mail without changing persisted preferences")
    func nativeSourceRevealsAllMailByDefault() {
        let persisted = FolderSidebarVisibilityPreferences.defaults
        let effective = FolderSidebarPresentation.effectiveVisibility(
            capabilities: [.providerAPI, .labels, .serverSideThreading],
            persisted: persisted
        )

        #expect(effective.showAllMail)
        #expect(persisted.showAllMail == false)
    }

    @Test("generic sources retain the persisted folder visibility byte-for-byte")
    func genericSourceRetainsPersistedVisibility() {
        let persisted = FolderSidebarVisibilityPreferences(
            showStarred: false,
            showSnoozed: true,
            showScheduled: false,
            showAllMail: false,
            showSpam: true,
            showTrash: false,
            showArchive: true
        )

        let effective = FolderSidebarPresentation.effectiveVisibility(
            capabilities: [.providerAPI, .labels],
            persisted: persisted
        )

        #expect(effective == persisted)
    }

    @Test("multi-account source capabilities resolve sidebar visibility independently")
    func sourceCapabilitiesRemainIndependent() {
        let persisted = FolderSidebarVisibilityPreferences.defaults
        let nativeSource = FolderSidebarPresentation.effectiveVisibility(
            capabilities: [.providerAPI, .labels, .serverSideThreading],
            persisted: persisted
        )
        let genericSource = FolderSidebarPresentation.effectiveVisibility(
            capabilities: [.serverSideSearch],
            persisted: persisted
        )

        #expect(nativeSource.showAllMail)
        #expect(genericSource.showAllMail == persisted.showAllMail)
    }

    @Test("native system labels keep provider names while generic aliases remain unchanged")
    func nativeNamesPreserveProviderLabels() {
        let sourceID = MailSourceID(accountID: "gmail-account", mailboxID: "primary")
        let aliasPreferences = FolderAliasPreferences(
            aliases: [
                FolderAliasPreference(
                    folderID: SourceFolderID(sourceID: sourceID, folderID: "STARRED"),
                    name: "Pinned"
                ),
                FolderAliasPreference(
                    folderID: SourceFolderID(sourceID: sourceID, folderID: "IMPORTANT"),
                    name: "Priority"
                ),
            ]
        )
        let starred = Folder(id: "STARRED", name: "Starred", role: .starred)
        let important = Folder(id: "IMPORTANT", name: "Important", role: .custom)
        let nativeCapabilities: BackendCapabilities = [.providerAPI, .labels, .serverSideThreading]

        #expect(
            FolderSidebarPresentation.displayName(
                for: starred,
                sourceID: sourceID,
                aliasPreferences: aliasPreferences,
                capabilities: nativeCapabilities
            ) == "Starred"
        )
        #expect(
            FolderSidebarPresentation.displayName(
                for: important,
                sourceID: sourceID,
                aliasPreferences: aliasPreferences,
                capabilities: nativeCapabilities
            ) == "Important"
        )
        #expect(
            FolderSidebarPresentation.displayName(
                for: starred,
                sourceID: sourceID,
                aliasPreferences: aliasPreferences
            ) == "Pinned"
        )
        #expect(
            FolderSidebarPresentation.displayName(
                for: important,
                sourceID: sourceID,
                aliasPreferences: aliasPreferences
            ) == "Priority"
        )
    }
}
