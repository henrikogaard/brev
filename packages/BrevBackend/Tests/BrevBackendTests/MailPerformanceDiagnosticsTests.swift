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

@testable import BrevBackend
import Foundation
import Testing

@Suite("MailPerformanceDiagnostics")
struct MailPerformanceDiagnosticsTests {
    @Test("search snapshots describe query shape without raw search content")
    func searchSnapshotsDescribeShapeWithoutRawSearchContent() {
        let query = SearchQuery(
            text: "secret launch alice@example.com",
            folderID: "private-folder-id",
            from: "boss@example.com",
            to: "me@example.com",
            hasAttachments: true,
            isUnread: false,
            isFlagged: true,
            subject: "Confidential roadmap",
            execution: .cacheThenServer
        )

        let snapshot = MailPerformanceDiagnostics.searchSnapshot(
            for: query,
            searchedFolderCount: 3
        )

        #expect(snapshot.execution == .cacheThenServer)
        #expect(snapshot.scope == .singleFolder)
        #expect(snapshot.searchedFolderCount == 3)
        #expect(snapshot.shape == "text,from,to,subject,attachment,read,flag")

        let publicDescription = snapshot.publicDescription
        #expect(publicDescription.contains("execution=cacheThenServer"))
        #expect(publicDescription.contains("scope=singleFolder"))
        #expect(publicDescription.contains("shape=text,from,to,subject,attachment,read,flag"))
        #expect(!publicDescription.contains("secret"))
        #expect(!publicDescription.contains("alice@example.com"))
        #expect(!publicDescription.contains("boss@example.com"))
        #expect(!publicDescription.contains("me@example.com"))
        #expect(!publicDescription.contains("Confidential"))
        #expect(!publicDescription.contains("private-folder-id"))
    }

    @Test("search snapshots expose explicit server all folders evidence")
    func searchSnapshotsExposeExplicitServerAllFoldersEvidence() {
        let query = SearchQuery(
            text: "quarterly budget",
            folderID: nil,
            execution: .serverOnly
        )

        let snapshot = MailPerformanceDiagnostics.searchSnapshot(
            for: query,
            searchedFolderCount: 7
        )

        #expect(snapshot.execution == .serverOnly)
        #expect(snapshot.scope == .allFolders)
        #expect(snapshot.searchedFolderCount == 7)
        #expect(snapshot.shape == "text")
        #expect(snapshot.publicDescription.contains("execution=serverOnly"))
        #expect(snapshot.publicDescription.contains("scope=allFolders"))
        #expect(snapshot.publicDescription.contains("folders=7"))
        #expect(snapshot.publicDescription.contains("shape=text"))
        #expect(!snapshot.publicDescription.contains("quarterly budget"))
    }

    @Test("error categories omit provider responses and addresses")
    func errorCategoriesOmitProviderResponsesAndAddresses() {
        let error = IMAPClientError.commandFailed(
            command: "UID SEARCH",
            response: "BAD cannot parse alice@example.com secret launch"
        )

        let category = MailPerformanceDiagnostics.errorCategory(for: error)

        #expect(category == "imap.commandFailed")
        #expect(!category.contains("UID SEARCH"))
        #expect(!category.contains("alice@example.com"))
        #expect(!category.contains("secret"))
    }
}
