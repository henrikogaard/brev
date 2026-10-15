/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the conditions in the LICENSE file.
 */

import BrevBackend
@testable import BrevMail
import Foundation
import Testing

@Suite("GoogleDriveSave")
@MainActor
struct GoogleDriveSaveTests {
    @Test("folder picks must be non-empty folders")
    func folderValidation() {
        #expect(
            GoogleDriveSaveModel.isValidFolder(
                GoogleDrivePick(
                    id: "folder",
                    name: "Folder",
                    mimeType: "application/vnd.google-apps.folder",
                    isFolder: true
                )
            )
        )
        #expect(
            !GoogleDriveSaveModel.isValidFolder(
                GoogleDrivePick(
                    id: "",
                    name: "Folder",
                    mimeType: "application/vnd.google-apps.folder",
                    isFolder: true
                )
            )
        )
        #expect(
            !GoogleDriveSaveModel.isValidFolder(
                GoogleDrivePick(
                    id: "../root",
                    name: "Folder",
                    mimeType: "application/vnd.google-apps.folder",
                    isFolder: true
                )
            )
        )
        #expect(
            !GoogleDriveSaveModel.isValidFolder(
                GoogleDrivePick(
                    id: "file",
                    name: "File",
                    mimeType: "application/pdf"
                )
            )
        )
    }

    @Test("the original event file can never be replaced")
    func originalFileCannotBeReplaced() {
        #expect(
            !GoogleDriveSaveModel.canReplace(
                conflictID: "source",
                originalFileID: "source"
            )
        )
        #expect(
            GoogleDriveSaveModel.canReplace(
                conflictID: "other",
                originalFileID: "source"
            )
        )
    }

    @Test("a validated folder gets a new copy under that folder ID")
    func createInSelectedFolder() async throws {
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "new",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            )
        )
        let model = GoogleDriveSaveModel(
            accountID: "acct1",
            filename: "Agenda.pdf",
            mimeType: "application/pdf",
            data: Data([1]),
            files: files
        )
        let folder = GoogleDrivePick(
            id: "folder-1",
            name: "Events",
            mimeType: "application/vnd.google-apps.folder",
            isFolder: true
        )
        #expect(try await model.inspectFolder(folder) == nil)
        _ = try await model.upload(folderID: folder.id, replacing: nil)
        let counts = await files.counts()
        #expect(counts.create == 1)
        #expect(counts.update == 0)
        #expect(counts.lastAccountID == "acct1")
        #expect(counts.lastFolderID == "folder-1")
    }

    @Test("replacing the source file is rejected by the model")
    func sourceFileCannotBeOverwritten() async {
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "source",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            )
        )
        let model = GoogleDriveSaveModel(
            accountID: "acct1",
            filename: "Agenda.pdf",
            mimeType: "application/pdf",
            data: Data([1]),
            originalFileID: "source",
            files: files
        )
        await #expect(throws: GoogleDriveSaveError.cannotReplaceSource) {
            try await model.upload(folderID: "folder-1", replacing: "source")
        }
        let counts = await files.counts()
        #expect(counts.update == 0)
        #expect(counts.lastReplacedID == nil)
    }

    @Test("ordinary conflicts can be replaced explicitly")
    func replacesBrevCopy() async throws {
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "replacement",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            ),
            conflict: GoogleDriveClient.File(
                id: "brev-copy",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            )
        )
        let model = GoogleDriveSaveModel(
            accountID: "acct1",
            filename: "Agenda.pdf",
            mimeType: "application/pdf",
            data: Data([1]),
            files: files
        )
        let folder = GoogleDrivePick(
            id: "folder-1",
            name: "Events",
            mimeType: "application/vnd.google-apps.folder",
            isFolder: true
        )
        let found = try await model.inspectFolder(folder)
        let conflict = try #require(found)
        _ = try await model.upload(folderID: folder.id, replacing: conflict.id)
        let counts = await files.counts()
        #expect(counts.update == 1)
        #expect(counts.lastReplacedID == "brev-copy")
        #expect(model.progress == 1)
    }

    @Test("Keep Both creates rather than replacing a conflict")
    func keepsBothFiles() async throws {
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "new",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            ),
            conflict: GoogleDriveClient.File(
                id: "brev-copy",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            )
        )
        let model = GoogleDriveSaveModel(
            accountID: "acct1",
            filename: "Agenda.pdf",
            mimeType: "application/pdf",
            data: Data([1]),
            files: files
        )
        _ = try await model.inspectFolder(
            GoogleDrivePick(
                id: "folder-1",
                name: "Events",
                mimeType: "application/vnd.google-apps.folder",
                isFolder: true
            )
        )
        _ = try await model.upload(folderID: "folder-1", replacing: nil)
        let counts = await files.counts()
        #expect(counts.create == 1)
        #expect(counts.update == 0)
    }

    @Test("provider errors remain retryable")
    func retriesAfterUploadError() async throws {
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "new",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            ),
            createFailures: 1
        )
        let model = GoogleDriveSaveModel(
            accountID: "acct1",
            filename: "Agenda.pdf",
            mimeType: "application/pdf",
            data: Data([1]),
            files: files
        )
        await #expect(throws: GoogleDriveSaveTestFailure.failed) {
            try await model.upload(folderID: "folder-1", replacing: nil)
        }
        _ = try await model.upload(folderID: "folder-1", replacing: nil)
        #expect(await files.counts().create == 2)
    }

    @Test("late upload completion after cancellation cannot be accepted")
    func cancelledLateCompletionAndRetry() async throws {
        let gate = GoogleDriveSaveTestGate()
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "new",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            ),
            createGate: gate
        )
        let model = GoogleDriveSaveModel(
            accountID: "acct1",
            filename: "Agenda.pdf",
            mimeType: "application/pdf",
            data: Data([1]),
            files: files
        )
        let pending = Task {
            try await model.upload(folderID: "folder-1", replacing: nil)
        }
        await gate.waitUntilEntered()
        model.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) {
            try await pending.value
        }
        let retried = try await model.upload(folderID: "folder-1", replacing: nil)
        #expect(retried.id == "new")
        #expect(await files.counts().create == 2)
    }
}
