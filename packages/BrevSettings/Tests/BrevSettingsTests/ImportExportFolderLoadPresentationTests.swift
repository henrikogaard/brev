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

@testable import BrevSettings
import Testing

@Suite("Import/Export folder loading")
struct ImportExportFolderLoadPresentationTests {
    @Test("no signed-in account explains why folders are unavailable")
    func noAccountExplainsUnavailability() {
        let status = ImportExportFolderLoadPresentation.status(
            hasBackend: false,
            isLoading: false,
            folderCount: 0,
            errorMessage: nil
        )
        #expect(status == .unavailable("Sign in to an account to import into or export from a folder."))
    }

    @Test("loading is reported while folders are being fetched")
    func loadingIsReported() {
        let status = ImportExportFolderLoadPresentation.status(
            hasBackend: true,
            isLoading: true,
            folderCount: 0,
            errorMessage: nil
        )
        #expect(status == .loading)
    }

    @Test("a load failure surfaces the underlying reason")
    func loadFailureSurfacesReason() {
        let status = ImportExportFolderLoadPresentation.status(
            hasBackend: true,
            isLoading: false,
            folderCount: 0,
            errorMessage: "Connection refused"
        )
        #expect(status == .failed("Couldn't load folders: Connection refused"))
    }

    /// A stale error must not keep showing once a retry has produced folders.
    @Test("folders present clears the status even after an earlier failure")
    func foldersPresentClearsStatus() {
        let status = ImportExportFolderLoadPresentation.status(
            hasBackend: true,
            isLoading: false,
            folderCount: 3,
            errorMessage: "Connection refused"
        )
        #expect(status == .ready)
    }

    @Test("an account with no folders is reported as empty, not failed")
    func emptyAccountIsReportedAsEmpty() {
        let status = ImportExportFolderLoadPresentation.status(
            hasBackend: true,
            isLoading: false,
            folderCount: 0,
            errorMessage: nil
        )
        #expect(status == .unavailable("No folders found for this account."))
    }
}
