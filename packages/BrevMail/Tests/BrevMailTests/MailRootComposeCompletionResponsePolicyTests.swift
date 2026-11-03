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

@Suite("MailRootComposeCompletionResponsePolicy")
struct MailRootComposeCompletionResponsePolicyTests {
    @Test("successful discard removes only the matching recovery snapshot", arguments: [false, true])
    func discardClearsOnlyMatchingRecovery(matching: Bool) throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanUp() }
        let draft = Draft(id: "saved", remoteID: "remote", subject: "Unsent")
        fixture.apply(.savedDraft(draft))
        ComposeDraftRecoveryStore.clear(
            matching: matching ? draft : Draft(id: "other", remoteID: "other-remote"),
            accountID: "account", sourceID: fixture.source, defaults: fixture.defaults
        )
        #expect((fixture.load() == nil) == matching)
    }

    @Test("root cleanup precedes presentation guards and discard cleanup follows success (source contract)")
    func recoveryCleanupSourceWiring() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/BrevMail")
        let root = try String(contentsOf: sources.appendingPathComponent("BrevMailRootView.swift"), encoding: .utf8)
        let rootStart = try #require(root.range(of: "private func handleComposeCompletion("))
        let rootEnd = try #require(root.range(of: "private func applyOrphanedDraftSaveFeedbackIfNeeded"))
        let handler = String(root[rootStart.lowerBound ..< rootEnd.lowerBound])
        let cleanup = try #require(handler.range(of: "BrevMail.updateComposeDraftRecovery("))
        let guardStart = try #require(handler.range(of: "guard let request else"))
        #expect(cleanup.lowerBound < guardStart.lowerBound)
        #expect(handler.contains("isCurrentPresentation: canApplyResponse"))

        let compose = try String(contentsOf: sources.appendingPathComponent("ComposeView.swift"), encoding: .utf8)
        let discardStart = try #require(compose.range(of: "private func discardDraft()"))
        let discardEnd = try #require(compose.range(of: "private func canStartComposeOperation("))
        let discard = String(compose[discardStart.lowerBound ..< discardEnd.lowerBound])
        let returnOnError = try #require(discard.range(of: "return\n        }"))
        let clear = try #require(discard.range(of: "ComposeDraftRecoveryStore.clear(matching: draft"))
        let finishAutosave = try #require(discard.range(of: "finishComposeOperation(pendingOperation)"))
        #expect(returnOnError.lowerBound < clear.lowerBound)
        #expect(returnOnError.lowerBound < finishAutosave.lowerBound && finishAutosave.lowerBound < clear.lowerBound)
        #expect(discard.contains("pendingOperation.kind == .autoSaveDraft"))
        #expect(discard.contains("accountID: backend.account.id, sourceID: sourceID"))
    }

    @Test(
        "successful send clears matching recovery even after the presentation request ends",
        arguments: RecoveryCompletionState.allCases
    )
    func sendClearsMatchingRecovery(state: RecoveryCompletionState) throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanUp() }
        let draft = Draft(id: "saved", remoteID: "remote", subject: "Sent subject", htmlBody: "Sent body")
        fixture.apply(.savedDraft(draft))
        #expect(fixture.load()?.draftID == draft.id)

        fixture.apply(.sentMessage(draft: draft, result: SendResult(), relatedHeader: nil), state: state)
        #expect(fixture.load() == nil)
        // A delayed callback from the old presentation must not restore the sent contents.
        fixture.apply(.savedDraft(draft), state: .finished)
        #expect(fixture.load() == nil)
    }

    @Test("sending an older draft preserves unrelated newer recovery", arguments: RecoveryCompletionState.allCases)
    func sendPreservesNewerRecovery(state: RecoveryCompletionState) throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanUp() }
        let older = Draft(id: "older", subject: "Old")
        let newer = Draft(id: "newer", subject: "Keep")
        fixture.apply(.savedDraft(older))
        fixture.apply(.savedDraft(newer))

        fixture.apply(.sentMessage(draft: older, result: SendResult(), relatedHeader: nil), state: state)
        #expect(fixture.load()?.draftID == newer.id)
        fixture.apply(.savedDraft(older), state: .replaced)
        #expect(fixture.load()?.draftID == newer.id)
    }

    @Test("reopened draft send matches its remote ID or stable local ID", arguments: [false, true])
    func reopenedDraftIdentityMatches(useRemoteIdentity: Bool) throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanUp() }
        let saved = Draft(id: "local", remoteID: "remote-before", subject: "Saved")
        fixture.apply(.savedDraft(saved))
        let sent = Draft(
            id: useRemoteIdentity ? "remote-before" : "local",
            remoteID: useRemoteIdentity ? "remote-before" : "remote-after",
            subject: "Edited before send"
        )
        fixture.apply(.sentMessage(draft: sent, result: SendResult(), relatedHeader: nil))
        #expect(fixture.load() == nil)
    }

    @Test("recovery cleanup is isolated by owning account and mailbox source")
    func recoveryCleanupIsSourceScoped() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanUp() }
        let draft = Draft(id: "same-local", remoteID: "same-remote", subject: "Scoped")
        let snapshot = try #require(ComposeDraftRecoverySnapshot.recoverableNewMessageDraft(from: draft))
        let otherSource = MailSourceID(accountID: "account", mailboxID: "other-mailbox")
        let otherAccount = MailSourceID(accountID: "other-account", mailboxID: "mailbox")
        for (account, source): (String, MailSourceID?) in [
            ("account", fixture.source), ("account", otherSource), ("other-account", otherAccount), ("account", nil)
        ] {
            ComposeDraftRecoveryStore.save(snapshot, accountID: account, sourceID: source, defaults: fixture.defaults)
        }
        fixture.apply(.sentMessage(draft: draft, result: SendResult(), relatedHeader: nil))
        #expect(fixture.load() == nil)
        for (account, source): (String, MailSourceID?) in [
            ("account", otherSource), ("other-account", otherAccount), ("account", nil)
        ] {
            #expect(ComposeDraftRecoveryStore.load(accountID: account, sourceID: source, defaults: fixture.defaults) == snapshot)
        }
    }

    @Test("reply and forward completions leave new-message recovery unchanged", arguments: [false, true])
    func replyForwardPreservesRecovery(isForward: Bool) throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanUp() }
        var draft = Draft(id: "local", remoteID: "remote", subject: "Unsent")
        fixture.apply(.savedDraft(draft))
        let expected = fixture.load()
        if isForward { draft.forwardedMessageID = "original" } else { draft.inReplyToMessageID = "original" }
        fixture.apply(.savedDraft(draft))
        fixture.apply(.sentMessage(draft: draft, result: SendResult(), relatedHeader: nil))
        #expect(fixture.load() == expected)
    }

    @Test("captured compose request wins over active fallback")
    func capturedComposeRequestWinsOverActiveFallback() {
        let captured = MailRootComposeCompletionRequest(
            id: 1,
            composePresentationID: 2,
            mailboxID: "mailbox-a"
        )
        let active = MailRootComposeCompletionRequest(
            id: 2,
            composePresentationID: 2,
            mailboxID: "mailbox-a"
        )

        #expect(MailRootComposeCompletionResponsePolicy.requestForCompletion(
            capturedRequest: captured,
            activeRequest: active,
            capturedComposePresentationID: 2
        ) == captured)
    }

    @Test("matching active request can recover missing captured request")
    func matchingActiveRequestCanRecoverMissingCapturedRequest() {
        let active = MailRootComposeCompletionRequest(
            id: 1,
            composePresentationID: 2,
            mailboxID: "mailbox-a"
        )

        #expect(MailRootComposeCompletionResponsePolicy.requestForCompletion(
            capturedRequest: nil,
            activeRequest: active,
            capturedComposePresentationID: 2
        ) == active)
        #expect(MailRootComposeCompletionResponsePolicy.requestForCompletion(
            capturedRequest: nil,
            activeRequest: active,
            capturedComposePresentationID: 3
        ) == nil)
        #expect(MailRootComposeCompletionResponsePolicy.requestForCompletion(
            capturedRequest: nil,
            activeRequest: nil,
            capturedComposePresentationID: 2
        ) == nil)
    }

    @Test("matching active compose request and mailbox can apply completion")
    func matchingActiveComposeRequestAndMailboxCanApplyCompletion() {
        let request = MailRootComposeCompletionRequest(
            id: 1,
            composePresentationID: 2,
            mailboxID: "mailbox-a"
        )

        #expect(MailRootComposeCompletionResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentComposePresentationID: 2,
            currentMailboxID: "mailbox-a"
        ))
    }

    @Test("unknown request mailbox can apply when compose presentation still matches")
    func unknownRequestMailboxCanApplyWhenComposePresentationStillMatches() {
        let request = MailRootComposeCompletionRequest(
            id: 1,
            composePresentationID: 2,
            mailboxID: nil
        )

        #expect(MailRootComposeCompletionResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentComposePresentationID: 2,
            currentMailboxID: "mailbox-a"
        ))
    }

    @Test("changed or missing active compose request rejects stale completion")
    func changedOrMissingActiveComposeRequestRejectsStaleCompletion() {
        let request = MailRootComposeCompletionRequest(
            id: 1,
            composePresentationID: 2,
            mailboxID: "mailbox-a"
        )

        #expect(!MailRootComposeCompletionResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: MailRootComposeCompletionRequest(
                id: 2,
                composePresentationID: 2,
                mailboxID: "mailbox-a"
            ),
            currentComposePresentationID: 2,
            currentMailboxID: "mailbox-a"
        ))
        #expect(!MailRootComposeCompletionResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: nil,
            currentComposePresentationID: 2,
            currentMailboxID: "mailbox-a"
        ))
    }

    @Test("changed compose presentation or mailbox rejects stale completion")
    func changedComposePresentationOrMailboxRejectsStaleCompletion() {
        let request = MailRootComposeCompletionRequest(
            id: 1,
            composePresentationID: 2,
            mailboxID: "mailbox-a"
        )

        #expect(!MailRootComposeCompletionResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentComposePresentationID: 3,
            currentMailboxID: "mailbox-a"
        ))
        #expect(!MailRootComposeCompletionResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentComposePresentationID: 2,
            currentMailboxID: "mailbox-b"
        ))
        #expect(!MailRootComposeCompletionResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentComposePresentationID: 2,
            currentMailboxID: nil
        ))
    }
}

enum RecoveryCompletionState: CaseIterable {
    case current, finished, uncapturedFinished, replaced, changedMailbox
}

private struct RecoveryFixture {
    let suite = "ComposeRecoveryLifecycleTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let source = MailSourceID(accountID: "account", mailboxID: "mailbox")

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    func cleanUp() { defaults.removePersistentDomain(forName: suite) }

    func load() -> ComposeDraftRecoverySnapshot? {
        ComposeDraftRecoveryStore.load(accountID: "account", sourceID: source, defaults: defaults)
    }

    func apply(_ completion: ComposeCompletion, state: RecoveryCompletionState = .current) {
        let captured = MailRootComposeCompletionRequest(id: 1, composePresentationID: 1, mailboxID: "mailbox")
        let active: MailRootComposeCompletionRequest? = switch state {
        case .current, .changedMailbox: captured
        case .finished, .uncapturedFinished: nil
        case .replaced: MailRootComposeCompletionRequest(id: 2, composePresentationID: 2, mailboxID: "mailbox")
        }
        let request = MailRootComposeCompletionResponsePolicy.requestForCompletion(
            capturedRequest: state == .uncapturedFinished ? nil : captured,
            activeRequest: active,
            capturedComposePresentationID: 1
        )
        let applicable = request.map {
            MailRootComposeCompletionResponsePolicy.canApplyResponse(
                request: $0, activeRequest: active,
                currentComposePresentationID: state == .replaced ? 2 : 1,
                currentMailboxID: state == .changedMailbox ? "other-mailbox" : "mailbox"
            )
        } ?? false
        updateComposeDraftRecovery(
            for: completion, accountID: "account", sourceID: source,
            isCurrentPresentation: applicable, defaults: defaults
        )
    }
}
