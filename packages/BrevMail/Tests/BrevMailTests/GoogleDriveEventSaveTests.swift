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

    @Test("explicit intent reaches Picker before touching Drive files")
    func pickerAuthorizesBeforeMetadataAndDownload() async {
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "file_1",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            )
        )
        let payload = GoogleDriveStagedPayload()
        let model = GoogleDriveEventSaveModel(
            attachment: PIMEventAttachment(
                url: "https://drive.google.com/file/d/file_1"
            ),
            accountID: "acct1",
            feature: enabledFeature(),
            files: files,
            payload: payload
        )

        #expect(await files.counts().metadata == 0)
        model.start()
        await waitUntil { model.phase == .picking(accessToken: "token") }
        #expect(await files.counts().metadata == 0)

        model.picked([
            GoogleDrivePick(
                id: "other",
                name: "Other",
                mimeType: "application/pdf"
            ),
        ])
        await waitUntil { model.errorMessage != nil }
        let counts = await files.counts()
        #expect(counts.metadata == 0)
        #expect(counts.download == 0)
        #expect(counts.export == 0)
        #expect(model.authorizedFileID == nil)

        model.cancel()
        #expect(model.phase == .finished)
        #expect(payload.bytes == nil)
        #expect(payload.filename == nil)
        #expect(payload.mimeType == nil)
        #expect(model.authorizedFileID == nil)
    }

    @Test("a matching Picker event authorizes and stages only that file")
    func matchingPickerEventStagesTheAuthorizedFile() async {
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "file_1",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            )
        )
        let payload = GoogleDriveStagedPayload()
        let model = GoogleDriveEventSaveModel(
            attachment: PIMEventAttachment(
                url: "https://drive.google.com/file/d/file_1"
            ),
            accountID: "acct1",
            feature: enabledFeature(),
            files: files,
            payload: payload
        )
        model.start()
        await waitUntil { model.phase == .picking(accessToken: "token") }
        model.picked([
            GoogleDrivePick(id: "file_1", name: "Agenda.pdf", mimeType: "application/pdf"),
        ])
        await waitUntil { model.phase == .saving }

        #expect(model.authorizedFileID == "file_1")
        #expect(payload.filename == "Agenda.pdf")
        #expect(payload.bytes == Data([1, 2, 3]))
        #expect(await files.counts().metadata == 1)
        #expect(await files.counts().download == 1)
        model.cancel()
        #expect(payload.bytes == nil)
        #expect(model.authorizedFileID == nil)
    }

    @Test("no Drive grant leaves the flow at opt-in without file calls")
    func missingGrantDoesNotReadMetadata() async {
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "file_1",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            )
        )
        let model = GoogleDriveEventSaveModel(
            attachment: PIMEventAttachment(
                url: "https://drive.google.com/file/d/file_1"
            ),
            accountID: "acct1",
            feature: enabledFeature(scopes: ["openid"]),
            files: files
        )
        model.start()
        await waitUntil { model.phase == .optIn }
        let counts = await files.counts()
        #expect(counts.metadata == 0)
        #expect(counts.download == 0)
        #expect(counts.export == 0)
    }

    @Test("metadata and download require a matching Picker authorization")
    func metadataAndPreparationRequirePickerAuthorization() async {
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "file_1",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
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

        await #expect(throws: GoogleDriveEventSaveError.pickerAuthorizationRequired) {
            _ = try await model.loadMetadata()
        }
        await #expect(throws: GoogleDriveEventSaveError.pickerAuthorizationRequired) {
            try await model.prepare()
        }
        let counts = await files.counts()
        #expect(counts.metadata == 0)
        #expect(counts.download == 0)
        #expect(counts.export == 0)
    }

    @Test("superseded validation cannot publish late Picker state")
    func supersededValidationCannotPublishPickerState() async {
        let gate = GoogleDriveSaveTestGate()
        let grant = GoogleDriveSaveTestGrant(
            firstConfigurationGate: gate
        )
        await grant.enable()
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "file_1",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            )
        )
        let feature = GoogleDriveFeature(
            configuration: { _ in await grant.configuration() },
            accessToken: { _ in "token" },
            pickerDeveloperKey: "key",
            pickerAppID: "app"
        )
        let model = GoogleDriveEventSaveModel(
            attachment: PIMEventAttachment(
                url: "https://drive.google.com/file/d/file_1"
            ),
            accountID: "acct1",
            feature: feature,
            files: files
        )
        model.start()
        await gate.waitUntilEntered()
        model.start()
        await waitUntil { model.pickerOperationToken != nil }
        let currentPickerToken = model.pickerOperationToken
        await gate.release()
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(model.phase == .picking(accessToken: "token"))
        #expect(model.pickerOperationToken == currentPickerToken)
        let counts = await files.counts()
        #expect(counts.metadata == 0)
        #expect(counts.download == 0)
        #expect(counts.export == 0)
    }

    @Test("a mismatched Picker result is rejected before file services")
    func mismatchedPickerResultMakesNoServiceCalls() async {
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "file_1",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
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
        model.start()
        await waitUntil { model.pickerOperationToken != nil }
        model.picked(
            [GoogleDrivePick(id: "other", name: "Other.pdf", mimeType: "application/pdf")],
            pickerToken: model.pickerOperationToken
        )
        await waitUntil { model.errorMessage != nil }

        #expect(model.authorizedFileID == nil)
        #expect(model.pickerOperationToken != nil)
        let counts = await files.counts()
        #expect(counts.metadata == 0)
        #expect(counts.download == 0)
        #expect(counts.export == 0)
    }

    @Test("a revoked grant after Picker returns to opt-in without file calls")
    func revokedGrantStopsPickerOrchestration() async {
        let grant = GoogleDriveSaveTestGrant()
        await grant.enable()
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "file_1",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            )
        )
        let feature = GoogleDriveFeature(
            configuration: { _ in await grant.configuration() },
            accessToken: { _ in "token" },
            pickerDeveloperKey: "key",
            pickerAppID: "app"
        )
        let model = GoogleDriveEventSaveModel(
            attachment: PIMEventAttachment(
                url: "https://drive.google.com/file/d/file_1"
            ),
            accountID: "acct1",
            feature: feature,
            files: files
        )
        model.start()
        await waitUntil { model.pickerOperationToken != nil }
        let token = model.pickerOperationToken
        await grant.revoke()
        model.picked(
            [GoogleDrivePick(id: "file_1", name: "Agenda.pdf", mimeType: "application/pdf")],
            pickerToken: token
        )
        await waitUntil { model.phase == .optIn && model.errorMessage != nil }

        #expect(model.authorizedFileID == nil)
        #expect(model.pickerOperationToken == nil)
        let counts = await files.counts()
        #expect(counts.metadata == 0)
        #expect(counts.download == 0)
        #expect(counts.export == 0)
    }

    @Test("provider error details are replaced with a generic message")
    func unknownProviderFailureUsesGenericFallback() async {
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "file_1",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            ),
            metadataFailure: .failed
        )
        let model = GoogleDriveEventSaveModel(
            attachment: PIMEventAttachment(
                url: "https://drive.google.com/file/d/file_1"
            ),
            accountID: "acct1",
            feature: enabledFeature(),
            files: files
        )
        model.start()
        await waitUntil { model.pickerOperationToken != nil }
        let pickerToken = model.pickerOperationToken
        model.picked(
            [GoogleDrivePick(id: "file_1", name: "Agenda.pdf", mimeType: "application/pdf")],
            pickerToken: pickerToken
        )
        await waitUntil { model.errorMessage != nil }

        #expect(
            model.errorMessage
                == String(
                    localized: "Google Drive could not prepare this file.",
                    bundle: .module
                )
        )
        #expect(model.errorMessage != GoogleDriveSaveTestFailure.failed.localizedDescription)
    }

    @Test("cancellation during eligibility validation cannot start file calls")
    func cancellationDuringValidationStopsFlow() async {
        let gate = GoogleDriveSaveTestGate()
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "file_1",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            )
        )
        let feature = GoogleDriveFeature(
            configuration: { _ in
                await gate.pause()
                return GoogleOAuthAccountConfiguration(
                    subject: "subject",
                    email: "user@gmail.com",
                    grantedScopes: [GoogleDriveClient.scope],
                    platform: .macOS
                )
            },
            accessToken: { _ in "token" },
            pickerDeveloperKey: "key",
            pickerAppID: "app"
        )
        let model = GoogleDriveEventSaveModel(
            attachment: PIMEventAttachment(
                url: "https://drive.google.com/file/d/file_1"
            ),
            accountID: "acct1",
            feature: feature,
            files: files
        )
        model.start()
        await gate.waitUntilEntered()
        model.cancel()
        await gate.release()
        await waitUntil { model.phase == .finished }

        let counts = await files.counts()
        #expect(counts.metadata == 0)
        #expect(counts.download == 0)
        #expect(counts.export == 0)
    }

    @Test("dismissed opt-in cannot restart, but a fresh flow can")
    func dismissedEnableDoesNotRestartAndFreshFlowCanPrepare() async {
        let gate = GoogleDriveSaveTestGate()
        let grant = GoogleDriveSaveTestGrant()
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "file_1",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            )
        )
        let feature = GoogleDriveFeature(
            configuration: { _ in await grant.configuration() },
            enablement: { _ in
                await gate.pause()
                await grant.enable()
            },
            accessToken: { _ in "token" },
            files: files,
            pickerDeveloperKey: "key",
            pickerAppID: "app"
        )
        let oldPayload = GoogleDriveStagedPayload()
        let model = GoogleDriveEventSaveModel(
            attachment: PIMEventAttachment(
                url: "https://drive.google.com/file/d/file_1"
            ),
            accountID: "acct1",
            feature: feature,
            payload: oldPayload
        )
        model.start()
        await waitUntil { model.phase == .optIn }
        model.enable()
        await gate.waitUntilEntered()
        model.cancel()
        await gate.release()
        await waitUntil { feature.isEnabling == false }
        model.start()

        #expect(model.phase == .finished)
        #expect(model.pickerOperationToken == nil)
        #expect(oldPayload.bytes == nil)
        #expect(await files.counts().metadata == 0)

        let freshPayload = GoogleDriveStagedPayload()
        let freshModel = GoogleDriveEventSaveModel(
            attachment: model.attachment,
            accountID: "acct1",
            feature: feature,
            payload: freshPayload
        )
        freshModel.start()
        await waitUntil { freshModel.pickerOperationToken != nil }
        let pickerToken = freshModel.pickerOperationToken
        freshModel.picked(
            [GoogleDrivePick(id: "file_1", name: "Agenda.pdf", mimeType: "application/pdf")],
            pickerToken: pickerToken
        )
        await waitUntil { freshModel.phase == .saving }

        #expect(freshPayload.bytes == Data([1, 2, 3]))
        #expect(await files.counts().metadata == 1)
        #expect(await files.counts().download == 1)
        freshModel.cancel()
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

        let payload = model.payload
        model.start()
        await waitUntil { model.pickerOperationToken != nil }
        model.picked(
            [GoogleDrivePick(id: "file_1", name: "Agenda.pdf", mimeType: "application/pdf")],
            pickerToken: model.pickerOperationToken
        )
        await waitUntil { model.phase == .saving }
        let counts = await files.counts()
        #expect(payload.filename == "Agenda.pdf")
        #expect(payload.mimeType == "application/pdf")
        #expect(payload.bytes == Data([1, 2, 3]))
        #expect(payload.sourceFileID == "file_1")
        #expect(model.authorizedFileID == "file_1")
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
        let payload = model.payload
        model.start()
        await waitUntil { model.pickerOperationToken != nil }
        model.picked(
            [
                GoogleDrivePick(
                    id: "doc_1",
                    name: "Plan",
                    mimeType: "application/vnd.google-apps.document"
                ),
            ],
            pickerToken: model.pickerOperationToken
        )
        await waitUntil {
            if case .exportChoice = model.phase { return true }
            return false
        }
        model.chooseExport(format)
        await waitUntil { model.phase == .saving }
        let counts = await files.counts()
        #expect(payload.filename == "Plan.pdf")
        #expect(payload.mimeType == format.mimeType)
        #expect(payload.sourceFileID == "doc_1")
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
        #expect(await authorize(model, fileID: "file_1"))
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
            #expect(await authorize(model, fileID: "file_1"))
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
        #expect(await authorize(model, fileID: "file_1"))
        let pending = Task { try await model.prepare() }
        await gate.waitUntilEntered()
        sourceIsValid = false
        await gate.release()
        await #expect(throws: CancellationError.self) {
            try await pending.value
        }
        #expect(await files.counts().download == 0)
    }

    @Test("invalid live source prevents opt-in network work")
    func invalidSourceDoesNotEnableDrive() async {
        let calls = GoogleDriveEnableCallCounter()
        var sourceIsValid = false
        let feature = GoogleDriveFeature(
            configuration: { _ in
                GoogleOAuthAccountConfiguration(
                    subject: "subject",
                    email: "user@gmail.com",
                    grantedScopes: [GoogleDriveClient.scope],
                    platform: .macOS
                )
            },
            enablement: { _ in await calls.increment() },
            accessToken: { _ in "token" },
            pickerDeveloperKey: "key",
            pickerAppID: "app"
        )
        let model = GoogleDriveEventSaveModel(
            attachment: PIMEventAttachment(
                url: "https://drive.google.com/file/d/file_1"
            ),
            accountID: "acct1",
            feature: feature,
            isValid: { sourceIsValid }
        )

        model.enable()
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        #expect(await calls.value == 0)
        sourceIsValid = true
        model.cancel()
    }

    private func enabledFeature(
        scopes: Set<String> = [GoogleDriveClient.scope]
    ) -> GoogleDriveFeature {
        GoogleDriveFeature(
            configuration: { _ in
                GoogleOAuthAccountConfiguration(
                    subject: "subject",
                    email: "user@gmail.com",
                    grantedScopes: scopes,
                    platform: .macOS
                )
            },
            accessToken: { _ in "token" },
            pickerDeveloperKey: "key",
            pickerAppID: "app"
        )
    }

    private func authorize(
        _ model: GoogleDriveEventSaveModel,
        fileID: String
    ) async -> Bool {
        await model.authorize(
            pick: GoogleDrivePick(
                id: fileID,
                name: "Selected",
                mimeType: "application/pdf"
            )
        )
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async {
        for _ in 0 ..< 1000 {
            if condition() { return }
            await Task.yield()
        }
    }
}

@Suite("GoogleDrivePickerFailureRetry")
@MainActor
struct GoogleDrivePickerFailureRetryTests {
    @Test("event Picker failure waits for explicit Continue")
    func eventPickerFailureWaitsForExplicitRetry() async {
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "file_1",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            )
        )
        let payload = GoogleDriveStagedPayload(
            filename: "stale.pdf",
            mimeType: "application/pdf",
            bytes: Data([1]),
            sourceFileID: "stale-file"
        )
        let model = GoogleDriveEventSaveModel(
            attachment: PIMEventAttachment(
                url: "https://drive.google.com/file/d/file_1"
            ),
            accountID: "acct1",
            feature: enabledFeature(),
            files: files,
            payload: payload
        )

        model.start()
        await waitUntil { model.pickerOperationToken != nil }
        let failedToken = model.pickerOperationToken
        model.reportPickerFailure(pickerToken: failedToken)

        #expect(model.phase == .intent)
        #expect(model.errorMessage == "Google Drive could not prepare this file.")
        #expect(model.pickerOperationToken == nil)
        #expect(model.authorizedFileID == nil)
        #expect(payload.bytes == nil)
        #expect(payload.filename == nil)
        #expect(payload.mimeType == nil)
        #expect(payload.sourceFileID == nil)
        model.reportPickerFailure(pickerToken: failedToken)

        await settle()
        #expect(model.phase == .intent)
        #expect(model.pickerOperationToken == nil)
        await expectNoFileCalls(files.counts())

        model.start()
        await waitUntil { model.pickerOperationToken != nil }
        #expect(model.pickerOperationToken != failedToken)
        await expectNoFileCalls(files.counts())
        model.cancel()
    }

    @Test("shared Picker failure waits for explicit Retry")
    func sharedPickerFailureWaitsForExplicitRetry() async {
        let files = RecordingDriveFiles(
            metadata: GoogleDriveClient.File(
                id: "copy_1",
                name: "Agenda.pdf",
                mimeType: "application/pdf"
            )
        )
        let payload = GoogleDriveStagedPayload(
            filename: "Agenda.pdf",
            mimeType: "application/pdf",
            bytes: Data([1, 2, 3])
        )
        let model = GoogleDriveSaveModel(
            accountID: "acct1",
            payload: payload,
            files: files,
            feature: enabledFeature()
        )

        model.start()
        await waitUntil { model.pickerOperationToken != nil }
        let failedToken = model.pickerOperationToken
        model.reportPickerFailure(pickerToken: failedToken)

        #expect(model.phase == .retry)
        #expect(model.pickerOperationToken == nil)
        #expect(model.errorMessage == "Google Drive could not save this file. Try again.")
        #expect(payload.bytes == Data([1, 2, 3]))
        model.reportPickerFailure(pickerToken: failedToken)
        await settle()
        #expect(model.phase == .retry)
        #expect(model.pickerOperationToken == nil)
        await expectNoFileCalls(files.counts())

        model.start()
        await waitUntil { model.pickerOperationToken != nil }
        #expect(model.pickerOperationToken != failedToken)
        await expectNoFileCalls(files.counts())
        model.cancel()
    }

    private func enabledFeature() -> GoogleDriveFeature {
        GoogleDriveFeature(
            configuration: { _ in
                GoogleOAuthAccountConfiguration(
                    subject: "subject",
                    email: "user@gmail.com",
                    grantedScopes: [GoogleDriveClient.scope],
                    platform: .macOS
                )
            },
            accessToken: { _ in "token" },
            pickerDeveloperKey: "key",
            pickerAppID: "app"
        )
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async {
        for _ in 0 ..< 1000 {
            if condition() { return }
            await Task.yield()
        }
    }

    private func settle() async {
        for _ in 0 ..< 20 {
            await Task.yield()
        }
    }

    private func expectNoFileCalls(
        _ counts: RecordingDriveFiles.Counts,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(counts.metadata == 0, sourceLocation: sourceLocation)
        #expect(counts.download == 0, sourceLocation: sourceLocation)
        #expect(counts.export == 0, sourceLocation: sourceLocation)
        #expect(counts.existingFile == 0, sourceLocation: sourceLocation)
        #expect(counts.create == 0, sourceLocation: sourceLocation)
        #expect(counts.update == 0, sourceLocation: sourceLocation)
    }
}

actor RecordingDriveFiles: DriveFileServing {
    struct Counts: Sendable {
        var metadata = 0
        var download = 0
        var export = 0
        var existingFile = 0
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
    private let metadataFailure: GoogleDriveSaveTestFailure?
    private let conflictResponse: GoogleDriveClient.File?
    private var count = Counts()
    private var createFailuresRemaining: Int

    init(
        metadata: GoogleDriveClient.File,
        createGate: GoogleDriveSaveTestGate? = nil,
        metadataGate: GoogleDriveSaveTestGate? = nil,
        metadataFailure: GoogleDriveSaveTestFailure? = nil,
        conflict: GoogleDriveClient.File? = nil,
        createFailures: Int = 0
    ) {
        response = metadata
        self.createGate = createGate
        self.metadataGate = metadataGate
        self.metadataFailure = metadataFailure
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
        if let metadataFailure { throw metadataFailure }
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
        if let createGate {
            await createGate.pause()
        }
        onProgress?(1, 1)
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
        count.existingFile += 1
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

enum GoogleDriveSaveTestFailure: Error, Equatable, LocalizedError {
    case failed

    var errorDescription: String? { "Private provider response details" }
}

actor GoogleDriveSaveTestGrant {
    private var isEnabled = false
    private var firstConfigurationGate: GoogleDriveSaveTestGate?

    init(firstConfigurationGate: GoogleDriveSaveTestGate? = nil) {
        self.firstConfigurationGate = firstConfigurationGate
    }

    func configuration() async -> GoogleOAuthAccountConfiguration {
        let gate = firstConfigurationGate
        firstConfigurationGate = nil
        if let gate { await gate.pause() }
        return GoogleOAuthAccountConfiguration(
            subject: "subject",
            email: "user@gmail.com",
            grantedScopes: isEnabled ? [GoogleDriveClient.scope] : [],
            platform: .macOS
        )
    }

    func enable() { isEnabled = true }
    func revoke() { isEnabled = false }
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

actor GoogleDriveEnableCallCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
