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

/// Feature-gating coverage for Google Drive attachments (#14):
/// eligibility by backend, scope presence from the stored grant,
/// picker readiness, and the opt-in coordinator.
@Suite("GoogleDriveFeature")
@MainActor
struct GoogleDriveFeatureTests {
    private nonisolated static let driveScope =
        "https://www.googleapis.com/auth/drive.file"

    private nonisolated static func account(
        backendIdentifier: String =
            BrevAccount.gmailAPIBackendIdentifier
    ) -> BrevAccount {
        BrevAccount(
            id: "acct1",
            displayName: "User",
            emailAddress: "user@gmail.com",
            backendIdentifier: backendIdentifier
        )
    }

    private nonisolated static func configuration(
        scopes: Set<String>
    ) -> GoogleOAuthAccountConfiguration {
        GoogleOAuthAccountConfiguration(
            subject: "sub",
            email: "user@gmail.com",
            grantedScopes: scopes,
            platform: .macOS
        )
    }

    @Test("only Gmail API accounts are eligible")
    func eligibility() {
        let feature = GoogleDriveFeature { _ in nil }
        #expect(feature.isEligible(account: Self.account()))
        #expect(
            !feature.isEligible(
                account: Self.account(
                    backendIdentifier:
                    BrevAccount.imapSMTPBackendIdentifier
                )
            )
        )
    }

    @Test("isEnabled reads the stored granted scopes")
    func enablementFromScopes() async {
        let feature = GoogleDriveFeature { _ in
            Self.configuration(scopes: [Self.driveScope])
        }
        #expect(await feature.isEnabled(accountID: "acct1"))

        let disabled = GoogleDriveFeature { _ in
            Self.configuration(scopes: ["openid"])
        }
        #expect(await !disabled.isEnabled(accountID: "acct1"))

        let missing = GoogleDriveFeature { _ in nil }
        #expect(await !missing.isEnabled(accountID: "acct1"))
    }

    @Test("the picker needs the grant plus developer key and app ID")
    func pickerReadiness() async {
        let ready = GoogleDriveFeature(
            configuration: { _ in
                Self.configuration(scopes: [Self.driveScope])
            },
            pickerDeveloperKey: "key",
            pickerAppID: "123"
        )
        #expect(await ready.canPresentPicker(accountID: "acct1"))

        let noKey = GoogleDriveFeature(
            configuration: { _ in
                Self.configuration(scopes: [Self.driveScope])
            },
            pickerDeveloperKey: "",
            pickerAppID: "123"
        )
        #expect(await !noKey.canPresentPicker(accountID: "acct1"))
    }

    @Test("enable runs the coordinator and clears the error")
    func enableRunsCoordinator() async throws {
        final class Recorder: @unchecked Sendable {
            var accountIDs: [String] = []
        }
        let recorder = Recorder()
        let feature = GoogleDriveFeature(
            configuration: { _ in nil },
            enablement: { accountID in
                recorder.accountIDs.append(accountID)
            }
        )

        try await feature.enable(accountID: "acct1")

        #expect(recorder.accountIDs == ["acct1"])
        #expect(feature.lastError == nil)
        #expect(!feature.isEnabling)
    }

    @Test("a declined opt-in surfaces the error and keeps Drive off")
    func enableFailure() async {
        struct Declined: LocalizedError {
            var errorDescription: String? { "Declined" }
        }
        let feature = GoogleDriveFeature(
            configuration: { _ in nil },
            enablement: { _ in throw Declined() }
        )

        await #expect(throws: Declined.self) {
            try await feature.enable(accountID: "acct1")
        }
        #expect(feature.lastError == "Declined")
        #expect(!feature.isEnabling)
    }

    @Test("a session without an enablement coordinator cannot opt in")
    func missingCoordinator() async {
        let feature = GoogleDriveFeature { _ in nil }

        await #expect(throws: MailBackendError.self) {
            try await feature.enable(accountID: "acct1")
        }
        #expect(feature.lastError != nil)
    }
}

/// Picker-page coverage (#14): generated HTML carries the token, key,
/// app ID and view mode; script messages parse into picks, cancel, or
/// errors.
@Suite("GoogleDrivePickerView")
struct GoogleDrivePickerViewTests {
    private static func configuration(
        mode: GoogleDrivePickerMode = .files
    ) -> GoogleDrivePickerView.Configuration {
        .init(
            accessToken: "tok",
            developerKey: "devkey",
            appID: "12345",
            mode: mode
        )
    }

    @Test("the page embeds credentials and loads api.js")
    func htmlContents() {
        let html = GoogleDrivePickerView.html(
            configuration: Self.configuration()
        )

        #expect(html.contains("apis.google.com/js/api.js"))
        #expect(html.contains(#""tok""#))
        #expect(html.contains(#""devkey""#))
        #expect(html.contains(#""12345""#))
        #expect(html.contains("ViewId.DOCS"))
        #expect(html.contains("setOAuthToken"))
        #expect(html.contains("setDeveloperKey"))
        #expect(html.contains("setAppId"))
    }

    @Test("folder mode selects folders instead of files")
    func folderMode() {
        let html = GoogleDrivePickerView.html(
            configuration: Self.configuration(mode: .folder)
        )

        #expect(html.contains("ViewId.FOLDERS"))
        #expect(html.contains("setSelectFolderEnabled(true)"))
    }

    @Test("tokens with quotes cannot break the script")
    func tokenEscaping() {
        let html = GoogleDrivePickerView.html(
            configuration: .init(
                accessToken: #"tok"en"#,
                developerKey: "k",
                appID: "1",
                mode: .files
            )
        )

        // JSONEncoder escapes the inner quote, so the page carries
        // "tok\"en" — a literal the script can still parse.
        #expect(html.contains(#""tok\"en""#))
    }

    @Test("picked messages decode into picks")
    func pickedMessage() {
        let outcome = GoogleDrivePickerView.handle(message: [
            "action": "picked",
            "docs": [
                [
                    "id": "f1",
                    "name": "Report.pdf",
                    "mimeType": "application/pdf",
                    "url": "https://drive.google.com/file/d/f1",
                ],
            ],
        ])

        guard case .picked(let picks) = outcome else {
            Issue.record("expected picked")
            return
        }
        #expect(picks.count == 1)
        #expect(picks[0].id == "f1")
        #expect(picks[0].name == "Report.pdf")
    }

    @Test("cancel and error messages map to their outcomes")
    func cancelAndError() {
        #expect(
            GoogleDrivePickerView.handle(message: ["action": "cancel"])
                == .cancelled
        )
        #expect(
            GoogleDrivePickerView.handle(
                message: ["action": "error", "message": "boom"]
            ) == .failed("boom")
        )
        #expect(
            GoogleDrivePickerView.handle(message: ["bogus": true])
                == .failed("unreadable picker message")
        )
    }

    @Test("picked docs missing required fields are dropped")
    func malformedDocs() {
        let outcome = GoogleDrivePickerView.handle(message: [
            "action": "picked",
            "docs": [["id": "f1"], ["name": "x"]],
        ])

        guard case .picked(let picks) = outcome else {
            Issue.record("expected picked")
            return
        }
        #expect(picks.isEmpty)
    }
}
