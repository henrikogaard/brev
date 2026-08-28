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

@Suite("DraftContentFingerprint")
struct DraftContentFingerprintTests {
    @Test("normalization ignores whitespace and HTML noise")
    func normalizationIgnoresWhitespaceAndHTMLNoise() {
        let left = Draft(
            id: "a",
            subject: "  Hello  ",
            htmlBody: "<p>Hi&nbsp;there</p>"
        )
        let right = Draft(
            id: "b",
            subject: "hello",
            htmlBody: "Hi there"
        )

        #expect(
            DraftContentFingerprint.fingerprint(for: left)
                == DraftContentFingerprint.fingerprint(for: right)
        )
    }

    @Test("recipient order is stable")
    func recipientOrderIsStable() {
        let draft = Draft(
            id: "a",
            to: [
                Correspondent(name: "B", email: "b@example.org"),
                Correspondent(name: "A", email: "a@example.org")
            ]
        )

        let again = Draft(
            id: "b",
            to: [
                Correspondent(name: "A", email: "a@example.org"),
                Correspondent(name: "B", email: "b@example.org")
            ]
        )

        #expect(
            DraftContentFingerprint.fingerprint(for: draft)
                == DraftContentFingerprint.fingerprint(for: again)
        )
    }

    @Test("dirty local drafts are not silently overwritten")
    func dirtyLocalDraftsAreNotSilentlyOverwritten() {
        let local = Draft(id: "local", remoteID: "INBOX:7", subject: "Local edit", htmlBody: "Keep me")
        let remote = Draft(id: "remote", remoteID: "INBOX:7", subject: "Server", htmlBody: "Server body")
        let metadata = DraftSyncMetadata(isDirty: true)

        let decision = DraftReconciliation.reconcile(
            local: local,
            remote: remote,
            metadata: metadata
        )

        #expect(decision == .createConflict(local: local, remote: remote))
    }

    @Test("clean drafts accept newer remote versions")
    func cleanDraftsAcceptNewerRemoteVersions() {
        let local = Draft(id: "local", remoteID: "INBOX:7", subject: "Old", htmlBody: "Old body")
        let remote = Draft(id: "remote", remoteID: "INBOX:7", subject: "New", htmlBody: "New body")
        let metadata = DraftSyncMetadata(isDirty: false)

        let decision = DraftReconciliation.reconcile(
            local: local,
            remote: remote,
            metadata: metadata
        )

        #expect(decision == .acceptRemote)
    }

    @Test("send recovery matches message ID and fingerprint")
    func sendRecoveryMatchesMessageIDAndFingerprint() {
        let draft = Draft(id: "d1", subject: "Hello", htmlBody: "Body")
        let fingerprint = DraftContentFingerprint.fingerprint(for: draft, messageID: "<abc@mail>")

        #expect(
            DraftReconciliation.matchesSendCandidate(
                draft: draft,
                messageID: "<abc@mail>",
                expectedFingerprint: fingerprint
            )
        )
    }
}
