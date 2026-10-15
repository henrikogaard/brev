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
            payload: GoogleDriveStagedPayload(
                filename: "Agenda.pdf",
                mimeType: "application/pdf",
                bytes: Data([1])
            ),
            files: files,
            feature: Self.enabledFeature()
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
            payload: GoogleDriveStagedPayload(
                filename: "Agenda.pdf",
                mimeType: "application/pdf",
                bytes: Data([1]),
                sourceFileID: "source"
            ),
            files: files,
            feature: Self.enabledFeature()
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
            payload: GoogleDriveStagedPayload(
                filename: "Agenda.pdf",
                mimeType: "application/pdf",
                bytes: Data([1])
            ),
            files: files,
            feature: Self.enabledFeature()
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

    @Test("a picked conflict replacement survives alert dismissal")
    func pickedConflictReplacementCannotBeCancelledByDismissal() async throws {
        let conflict = GoogleDriveClient.File(
            id: "brev-copy",
            name: "Agenda.pdf",
            mimeType: "application/pdf"
        )
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "replacement",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            ),
            conflict: conflict
        )
        var savedFileID: String?
        let model = GoogleDriveSaveModel(
            accountID: "acct1",
            payload: GoogleDriveStagedPayload(
                filename: "Agenda.pdf",
                mimeType: "application/pdf",
                bytes: Data([1])
            ),
            files: files,
            feature: Self.enabledFeature(),
            onSaved: { savedFileID = $0.id }
        )
        let folder = GoogleDrivePick(
            id: "folder-1",
            name: "Events",
            mimeType: "application/vnd.google-apps.folder",
            isFolder: true
        )

        model.start()
        await waitUntil { model.pickerOperationToken != nil }
        model.pickedFolder(folder, pickerToken: model.pickerOperationToken)
        await waitUntil { model.phase == .conflict(conflict) }
        model.replaceConflict()
        model.cancelConflict()
        await waitUntil { model.phase == .finished }

        #expect(await files.counts().update == 1)
        #expect(savedFileID == "replacement")
        #expect(model.payload.bytes == nil)
    }

    @Test("Keep Both creates rather than replacing a conflict")
    func keepsBothFiles() async {
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
            payload: GoogleDriveStagedPayload(
                filename: "Agenda.pdf",
                mimeType: "application/pdf",
                bytes: Data([1])
            ),
            files: files,
            feature: Self.enabledFeature()
        )
        let folder = GoogleDrivePick(
            id: "folder-1",
            name: "Events",
            mimeType: "application/vnd.google-apps.folder",
            isFolder: true
        )
        model.start()
        await waitUntil { model.pickerOperationToken != nil }
        model.pickedFolder(folder, pickerToken: model.pickerOperationToken)
        await waitUntil {
            if case .conflict = model.phase { return true }
            return false
        }
        model.keepBoth()
        model.cancelConflict()
        await waitUntil { model.phase == .finished }

        let counts = await files.counts()
        #expect(counts.create == 1)
        #expect(counts.update == 0)
        #expect(model.payload.bytes == nil)
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
            payload: GoogleDriveStagedPayload(
                filename: "Agenda.pdf",
                mimeType: "application/pdf",
                bytes: Data([1])
            ),
            files: files,
            feature: Self.enabledFeature()
        )
        await #expect(throws: GoogleDriveSaveTestFailure.failed) {
            try await model.upload(folderID: "folder-1", replacing: nil)
        }
        _ = try await model.upload(folderID: "folder-1", replacing: nil)
        #expect(await files.counts().create == 2)
    }

    @Test("an upload error returns the shared flow to a retryable picker")
    func orchestratedUploadErrorIsRetryable() async {
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "new",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            ),
            createFailures: 1
        )
        let payload = GoogleDriveStagedPayload(
            filename: "Agenda.pdf",
            mimeType: "application/pdf",
            bytes: Data([1])
        )
        let model = GoogleDriveSaveModel(
            accountID: "acct1",
            payload: payload,
            files: files,
            feature: Self.enabledFeature()
        )
        let folder = GoogleDrivePick(
            id: "folder-1",
            name: "Events",
            mimeType: "application/vnd.google-apps.folder",
            isFolder: true
        )

        model.start()
        await waitUntil { model.pickerOperationToken != nil }
        model.pickedFolder(folder, pickerToken: model.pickerOperationToken)
        await waitUntil { model.errorMessage != nil }

        #expect(model.phase == .picking(accessToken: "token"))
        #expect(model.errorMessage == "Google Drive could not save this file. Try again.")
        #expect(model.pickerOperationToken != nil)
        #expect(payload.bytes == Data([1]))
        model.pickedFolder(folder, pickerToken: model.pickerOperationToken)
        await waitUntil { model.phase == .finished }

        #expect(payload.bytes == nil)
        #expect(payload.filename == nil)
        #expect(payload.mimeType == nil)
        #expect(model.errorMessage == nil)
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
        let payload = GoogleDriveStagedPayload(
            filename: "Agenda.pdf",
            mimeType: "application/pdf",
            bytes: Data([1])
        )
        let model = GoogleDriveSaveModel(
            accountID: "acct1",
            payload: payload,
            files: files,
            feature: Self.enabledFeature()
        )
        let progressCallbacks = GoogleDriveProgressCounter()
        let pending = Task {
            try await model.upload(
                folderID: "folder-1",
                replacing: nil,
                onProgress: { _, _ in progressCallbacks.increment() }
            )
        }
        await gate.waitUntilEntered()
        model.cancel()
        #expect(model.phase == .finished)
        #expect(model.progress == nil)
        #expect(payload.bytes == nil)
        #expect(payload.filename == nil)
        #expect(payload.mimeType == nil)
        await gate.release()
        await #expect(throws: CancellationError.self) {
            try await pending.value
        }
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        #expect(model.progress == nil)
        #expect(progressCallbacks.value == 0)
        await #expect(throws: GoogleDriveSaveError.sourceUnavailable) {
            try await model.upload(folderID: "folder-1", replacing: nil)
        }
        let freshModel = GoogleDriveSaveModel(
            accountID: "acct1",
            payload: GoogleDriveStagedPayload(
                filename: "Agenda.pdf",
                mimeType: "application/pdf",
                bytes: Data([2])
            ),
            files: files,
            feature: Self.enabledFeature()
        )
        let retried = try await freshModel.upload(
            folderID: "folder-1",
            replacing: nil
        )
        #expect(retried.id == "new")
        #expect(await files.counts().create == 2)
    }

    private static func enabledFeature() -> GoogleDriveFeature {
        GoogleDriveFeature(configuration: { _ in
            GoogleOAuthAccountConfiguration(
                subject: "subject",
                email: "user@gmail.com",
                grantedScopes: [GoogleDriveClient.scope],
                platform: .macOS
            )
        }, accessToken: { _ in "token" }, pickerDeveloperKey: "key", pickerAppID: "app")
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async {
        for _ in 0 ..< 1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for Drive save state")
    }
}

final class GoogleDriveProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }
}
