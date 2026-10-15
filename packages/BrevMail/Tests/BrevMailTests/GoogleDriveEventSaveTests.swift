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
import BrevCalendar
@testable import BrevMail
import Foundation
import Testing

@Suite("GoogleDriveEventSave")
@MainActor
struct GoogleDriveEventSaveTests {
    @Test("only the allowlisted Drive and Workspace URLs yield a file ID")
    func parsesAllowlistedLinks() {
        let accepted = [
            "https://drive.google.com/file/d/file_1-2/view",
            "https://drive.google.com/file/d/file_1-2",
            "https://drive.google.com/open?id=file_1-2",
            "https://docs.google.com/document/d/doc-1/edit",
            "https://docs.google.com/spreadsheets/d/sheet_1/preview",
            "https://docs.google.com/presentation/d/slides-1",
        ]
        for link in accepted {
            #expect(GoogleDriveEventSaveModel.fileID(in: link) != nil)
        }
    }

    @Test("unsafe or ambiguous attachment URLs are rejected")
    func rejectsUnsafeLinks() {
        let rejected = [
            "http://drive.google.com/file/d/file/view",
            "https://evil.drive.google.com/file/d/file/view",
            "https://drive.google.com:444/file/d/file/view",
            "https://user:pass@drive.google.com/file/d/file/view",
            "https://drive.google.com/file/d/file/view/extra",
            "https://drive.google.com/file/d/file_1/view/",
            "https://drive.google.com//file/d/file_1",
            "https://drive.google.com/open?id=file&id=other",
            "https://docs.google.com/document/d/not-valid!.view",
        ]
        for link in rejected {
            #expect(GoogleDriveEventSaveModel.fileID(in: link) == nil)
        }
        #expect(!GoogleDriveEventSaveModel.authorizesPickerID(nil, for: "https://drive.google.com/file/d/file_1"))
        #expect(!GoogleDriveEventSaveModel.authorizesPickerID("other", for: "https://drive.google.com/file/d/file_1"))
        #expect(GoogleDriveEventSaveModel.authorizesPickerID("file_1", for: "https://drive.google.com/file/d/file_1"))
    }

    @Test("preparation reads only the parsed ID and downloads the metadata file")
    func preparesBinaryFromDrive() async throws {
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "file_1",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            )
        )
        let feature = enabledFeature()
        let model = GoogleDriveEventSaveModel(
            attachment: PIMEventAttachment(
                url: "https://drive.google.com/file/d/file_1/view",
                title: "Stale title",
                mimeType: "text/plain"
            ),
            accountID: "acct1",
            feature: feature,
            files: files
        )

        #expect(await files.counts().metadata == 0)
        let prepared = try await model.prepare()
        let counts = await files.counts()
        #expect(prepared.filename == "Agenda.pdf")
        #expect(prepared.mimeType == "application/pdf")
        #expect(prepared.data == Data([1, 2, 3]))
        #expect(prepared.originalFileID == "file_1")
        #expect(counts.metadata == 1)
        #expect(counts.download == 1)
        #expect(counts.export == 0)
        #expect(counts.lastAccountID == "acct1")
        #expect(counts.lastFileID == "file_1")
    }

    @Test("Workspace files require one supported explicit export choice")
    func exportsWorkspaceFile() async throws {
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "doc_1",
                name: "Plan",
                mimeType: "application/vnd.google-apps.document"
            )
        )
        let model = GoogleDriveEventSaveModel(
            attachment: PIMEventAttachment(
                url: "https://docs.google.com/document/d/doc_1/edit"
            ),
            accountID: "acct1",
            feature: enabledFeature(),
            files: files
        )
        let format = try #require(
            GoogleDriveExportFormats.options(
                for: "application/vnd.google-apps.document"
            ).first
        )
        await #expect(throws: GoogleDriveEventSaveError.exportChoiceRequired) {
            try await model.prepare()
        }
        let prepared = try await model.prepare(exportFormat: format)
        let counts = await files.counts()
        #expect(prepared.filename == "Plan.pdf")
        #expect(prepared.mimeType == format.mimeType)
        #expect(counts.download == 0)
        #expect(counts.export == 1)
    }

    @Test("an authoritative metadata ID mismatch stops before downloading")
    func rejectsMetadataMismatch() async {
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "other",
                name: "Other.pdf",
                mimeType: "application/pdf"
            )
        )
        let model = GoogleDriveEventSaveModel(
            attachment: PIMEventAttachment(
                url: "https://drive.google.com/file/d/file_1/view"
            ),
            accountID: "acct1",
            feature: enabledFeature(),
            files: files
        )
        await #expect(throws: GoogleDriveEventSaveError.mismatchedFile) {
            try await model.prepare()
        }
        let counts = await files.counts()
        #expect(counts.download == 0)
        #expect(counts.export == 0)
    }

    @Test("folders, shortcuts and unsupported Workspace files are rejected")
    func rejectsUnsupportedMetadata() async {
        for mimeType in [
            "application/vnd.google-apps.folder",
            "application/vnd.google-apps.shortcut",
            "application/vnd.google-apps.form",
        ] {
            let files = RecordingDriveFiles(
                metadata: GoogleDriveClient.File(
                    id: "file_1",
                    name: "Unsupported",
                    mimeType: mimeType
                )
            )
            let model = GoogleDriveEventSaveModel(
                attachment: PIMEventAttachment(
                    url: "https://drive.google.com/file/d/file_1"
                ),
                accountID: "acct1",
                feature: enabledFeature(),
                files: files
            )
            await #expect(throws: GoogleDriveEventSaveError.unsupportedFile) {
                try await model.prepare()
            }
            let counts = await files.counts()
            #expect(counts.download == 0)
            #expect(counts.export == 0)
        }
    }

    @Test("source removal while metadata is in flight prevents downloading")
    func invalidationDuringMetadata() async {
        let gate = GoogleDriveSaveTestGate()
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "file_1",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            ),
            metadataGate: gate
        )
        var sourceIsValid = true
        let model = GoogleDriveEventSaveModel(
            attachment: PIMEventAttachment(
                url: "https://drive.google.com/file/d/file_1"
            ),
            accountID: "acct1",
            feature: enabledFeature(),
            files: files,
            isValid: { sourceIsValid }
        )
        let pending = Task { try await model.prepare() }
        await gate.waitUntilEntered()
        sourceIsValid = false
        await gate.release()
        await #expect(throws: GoogleDriveEventSaveError.sourceUnavailable) {
            try await pending.value
        }
        #expect(await files.counts().download == 0)
    }

    private func enabledFeature() -> GoogleDriveFeature {
        GoogleDriveFeature { _ in
            GoogleOAuthAccountConfiguration(
                subject: "subject",
                email: "user@gmail.com",
                grantedScopes: [GoogleDriveClient.scope],
                platform: .macOS
            )
        }
    }
}

actor RecordingDriveFiles: DriveFileServing {
    struct Counts: Sendable {
        var metadata = 0
        var download = 0
        var export = 0
        var create = 0
        var update = 0
        var lastAccountID: String?
        var lastFileID: String?
        var lastFolderID: String?
        var lastReplacedID: String?
    }

    private let response: GoogleDriveClient.File
    private let createGate: GoogleDriveSaveTestGate?
    private let metadataGate: GoogleDriveSaveTestGate?
    private let conflictResponse: GoogleDriveClient.File?
    private var count = Counts()
    private var createFailuresRemaining: Int

    init(
        metadata: GoogleDriveClient.File,
        createGate: GoogleDriveSaveTestGate? = nil,
        metadataGate: GoogleDriveSaveTestGate? = nil,
        conflict: GoogleDriveClient.File? = nil,
        createFailures: Int = 0
    ) {
        response = metadata
        self.createGate = createGate
        self.metadataGate = metadataGate
        conflictResponse = conflict
        createFailuresRemaining = createFailures
    }

    func counts() -> Counts { count }

    func metadata(
        fileID: String,
        accountID: BrevAccount.ID
    ) async throws -> GoogleDriveClient.File {
        count.metadata += 1
        count.lastAccountID = accountID
        count.lastFileID = fileID
        if let metadataGate {
            await metadataGate.pause()
        }
        return response
    }

    func download(
        fileID: String,
        accountID: BrevAccount.ID
    ) async throws -> Data {
        count.download += 1
        count.lastAccountID = accountID
        return Data([1, 2, 3])
    }

    func export(
        fileID: String,
        mimeType: String,
        accountID: BrevAccount.ID
    ) async throws -> Data {
        count.export += 1
        count.lastAccountID = accountID
        return Data([4, 5])
    }

    func create(
        name: String,
        mimeType: String,
        data: Data,
        parentFolderID: String?,
        accountID: BrevAccount.ID,
        onProgress: (@Sendable (Int64, Int64) -> Void)?
    ) async throws -> GoogleDriveClient.File {
        count.create += 1
        count.lastAccountID = accountID
        count.lastFolderID = parentFolderID
        onProgress?(1, 1)
        if let createGate {
            await createGate.pause()
        }
        if createFailuresRemaining > 0 {
            createFailuresRemaining -= 1
            throw GoogleDriveSaveTestFailure.failed
        }
        return response
    }

    func existingFile(
        named name: String,
        inFolderID folderID: String?,
        accountID: BrevAccount.ID
    ) async throws -> GoogleDriveClient.File? {
        count.lastAccountID = accountID
        return conflictResponse
    }

    func update(
        fileID: String,
        mimeType: String,
        data: Data,
        accountID: BrevAccount.ID,
        onProgress: (@Sendable (Int64, Int64) -> Void)?
    ) async throws -> GoogleDriveClient.File {
        count.update += 1
        count.lastAccountID = accountID
        count.lastReplacedID = fileID
        onProgress?(1, 1)
        return response
    }
}

enum GoogleDriveSaveTestFailure: Error, Equatable {
    case failed
}

actor GoogleDriveSaveTestGate {
    private var entered = false
    private var pausesRemaining = 1
    private var enterWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func pause() async {
        guard pausesRemaining > 0 else { return }
        pausesRemaining -= 1
        entered = true
        enterWaiter?.resume()
        enterWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enterWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
