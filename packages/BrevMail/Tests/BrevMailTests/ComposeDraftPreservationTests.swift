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

#if os(macOS)
import AppKit
@testable import BrevBackend
@testable import BrevMail
import SwiftUI
import Testing

@Suite("Compose draft preservation")
@MainActor
struct ComposeDraftPreservationTests {
    @Test("actual serializer multiline output restores without rewriting HTML", arguments: [false, true], [false, true])
    func serializedMultilineBody(recovery: Bool, autosave: Bool) async throws {
        let text = "Bold Italic Underline Link\n\nSecond paragraph"
        let authored = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 15)])
        for (word, trait) in [("Bold", NSFontTraitMask.boldFontMask), ("Italic", .italicFontMask)] {
            authored.addAttribute(
                .font,
                value: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 15), toHaveTrait: trait),
                range: (text as NSString).range(of: word)
            )
        }
        authored.addAttribute(.underlineStyle, value: 1, range: (text as NSString).range(of: "Underline"))
        try authored.addAttribute(
            .link,
            value: #require(URL(string: "https://example.invalid/help")),
            range: (text as NSString).range(of: "Link")
        )
        let html = ComposeRichTextHTMLSerializer.html(from: authored)
        #expect(html ==
            "<strong>Bold</strong> <em>Italic</em> <u>Underline</u> <a href=\"https://example.invalid/help\">Link</a><br><br>Second paragraph")
        let backend = MockBackend()
        let original = try await backend.save(draft: Draft(id: UUID().uuidString, subject: "Serialized", htmlBody: html))
        let harness = try Harness(backend: backend, original: original, recovery: recovery)
        defer { harness.dispose() }
        try await harness.prepare()
        #expect(harness.editor?.string == text)
        if autosave {
            await harness.mounted?.autoSaveDraftAfterInactivity()
        } else {
            await harness.mounted?.saveDraft()
        }
        #expect(try await backend.draft(for: original.remoteID ?? original.id) == original)
    }

    @Test("hosted existing and recovered drafts retain rich HTML through Save and autosave",
          arguments: [false, true], [false, true])
    func noEditSave(recovery: Bool, autosave: Bool) async throws {
        let backend = MockBackend()
        let html = "<strong>Bold</strong> <em>Italic</em> <u>Underline</u> "
            + "<a href=\"https://example.invalid/help\">Link</a><br>Second paragraph"
        let original = try await backend.save(draft: Draft(
            id: UUID().uuidString,
            to: [Correspondent(email: "recipient@example.invalid")],
            subject: "Rich draft",
            htmlBody: html
        ))
        let harness = try Harness(backend: backend, original: original, recovery: recovery)
        defer { harness.dispose() }
        try await harness.prepare()
        let native = try #require(harness.editor)
        #expect(native.isRichText)
        let mounted = try #require(harness.mounted)
        if autosave {
            await mounted.autoSaveDraftAfterInactivity()
        } else {
            await mounted.saveDraft()
        }
        let persisted = try #require(await backend.draft(for: original.remoteID ?? original.id))
        #expect(persisted.htmlBody == html)
        #expect(persisted.id == original.id)
        #expect(persisted.remoteID == original.remoteID)
    }

    @Test("no-reply opt-in survives existing and crash-recovered draft saves", arguments: [false, true])
    func noReplyRequestSurvivesRestoration(recovery: Bool) async throws {
        let backend = MockBackend()
        let messageID = MIMEMessageBuilder.messageIDHeaderValue(
            draftID: "no-reply-restore",
            fromEmail: "sender@example.invalid"
        )
        let original = try await backend.save(draft: Draft(
            id: "no-reply-restore",
            to: [Correspondent(email: "recipient@example.invalid")],
            subject: "No-reply restoration",
            followUpRequest: DraftNoReplyFollowUpRequest(expectedMessageID: messageID)
        ))
        let harness = try Harness(backend: backend, original: original, recovery: recovery)
        defer { harness.dispose() }
        try await harness.prepare()

        await harness.mounted?.saveDraft()

        let persisted = try #require(await backend.draft(for: original.remoteID ?? original.id))
        #expect(persisted.followUpRequest == original.followUpRequest)
    }

    @Test("opted-in server drafts save before Send and retain scheduled content")
    @MainActor
    func optedInServerDraftSavesBeforeSendAndRetainsIntent() async throws {
        let backing = MockBackend()
        let mailbox = try #require(await backing.mailboxes().first)
        let sourceID = backing.sourceID(for: mailbox)
        let draftID = "server-sourced-follow-up"
        let scheduledFor = Date(timeIntervalSince1970: 2_000_000_000)
        // Gmail can open an existing remote draft with no local staging copy.
        let original = Draft(
            id: draftID,
            remoteID: "server-draft-follow-up",
            to: [Correspondent(email: "recipient@example.invalid")],
            subject: "Server draft",
            htmlBody: "<p>Preserved body</p>",
            scheduledFor: scheduledFor
        )
        #expect(try await backing.draft(for: "server-draft-follow-up", sourceID: sourceID) == nil)
        let backend = NormalizingDraftSaveBackend(backing: backing, behavior: .stripIntentFromResponse)
        let probe = ComposeDraftSendProbe()
        backing.sendHandler = { draft, sendSourceID in
            let saveAttemptsBeforeSend = await backend.saveAttemptCount()
            await probe.record(
                draft: draft,
                sourceID: sendSourceID,
                saveAttemptsBeforeSend: saveAttemptsBeforeSend
            )
            return SendResult(sentMessageID: "accepted")
        }
        let harness = try Harness(
            backend: backend,
            original: original,
            sourceID: sourceID,
            isServerSourced: true
        )
        defer { harness.dispose() }
        try await harness.prepare()

        let mounted = try #require(harness.mounted)
        #expect(mounted.locksSenderToOriginalSource)
        let draftBeforeOptIn = mounted.currentDraft()
        #expect(draftBeforeOptIn.remoteID == original.remoteID)
        #expect(draftBeforeOptIn.scheduledFor == scheduledFor)
        #expect(draftBeforeOptIn.attachmentIDs == original.attachmentIDs)
        let saveAttemptsBeforeSend = await backend.saveAttemptCount()
        #expect(saveAttemptsBeforeSend == 0)

        let expectedMessageID = MIMEMessageBuilder.messageIDHeaderValue(
            draftID: original.id,
            fromEmail: "sender@example.invalid"
        )
        let expectedRequest = DraftNoReplyFollowUpRequest(expectedMessageID: expectedMessageID)
        mounted.setNoReplyFollowUpEnabled(true)
        let optedInDraft = mounted.currentDraft()
        #expect(optedInDraft.remoteID == original.remoteID)
        #expect(optedInDraft.scheduledFor == scheduledFor)
        #expect(optedInDraft.followUpRequest == expectedRequest)
        await mounted.send(bypassingSendGuard: true)

        let observation = await probe.snapshot()
        let sentDraft = try #require(observation.sentDraft)
        #expect(observation.sourceID == sourceID)
        #expect(observation.saveAttemptsBeforeSend > 0)
        #expect(sentDraft.remoteID == original.remoteID)
        #expect(sentDraft.scheduledFor == scheduledFor)
        #expect(sentDraft.followUpRequest == expectedRequest)
        #expect(sentDraft.htmlBody == original.htmlBody)
        #expect(sentDraft.attachmentIDs == original.attachmentIDs)
        #expect(harness.acceptedSends.count == 1)
    }

    @Test("failed opted-in server-draft save prevents Send and acceptance")
    @MainActor
    func failedOptedInServerDraftSavePreventsSendAndAcceptance() async throws {
        let backing = MockBackend()
        let mailbox = try #require(await backing.mailboxes().first)
        let sourceID = backing.sourceID(for: mailbox)
        let original = try await backing.save(draft: Draft(
            id: "failed-server-draft-save",
            remoteID: "failed-server-draft-save-remote",
            to: [Correspondent(email: "recipient@example.invalid")],
            subject: "Save must succeed first",
            htmlBody: "<p>Draft content</p>"
        ), sourceID: sourceID)
        let backend = NormalizingDraftSaveBackend(backing: backing, behavior: .fail)
        let sendAttempts = ComposeSendAttemptCounter()
        backing.sendHandler = { _, _ in
            await sendAttempts.record()
            return SendResult(sentMessageID: "unexpected")
        }
        let harness = try Harness(
            backend: backend,
            original: original,
            sourceID: sourceID,
            isServerSourced: true
        )
        defer { harness.dispose() }
        try await harness.prepare()

        let saveAttemptsBeforeSend = await backend.saveAttemptCount()
        #expect(saveAttemptsBeforeSend == 0)
        let mounted = try #require(harness.mounted)
        mounted.setNoReplyFollowUpEnabled(true)
        await mounted.send(bypassingSendGuard: true)

        let sendAttemptCount = await sendAttempts.count()
        let saveAttemptCount = await backend.saveAttemptCount()
        #expect(saveAttemptCount > 0)
        #expect(sendAttemptCount == 0)
        #expect(harness.acceptedSends.isEmpty)
    }

    @Test("mounted accepted Send invokes the captured callback exactly once")
    @MainActor
    func acceptedSendInvokesCallbackOnce() async throws {
        let backend = MockBackend()
        let mailbox = try #require(await backend.mailboxes().first)
        let sourceID = backend.sourceID(for: mailbox)
        let sendAttempts = ComposeSendAttemptCounter()
        backend.sendHandler = { _, _ in
            await sendAttempts.record()
            return SendResult(sentMessageID: "accepted")
        }
        let original = try await backend.save(draft: Draft(
            id: "accepted-callback",
            to: [Correspondent(email: "recipient@example.invalid")],
            subject: "Accepted callback",
            followUpRequest: DraftNoReplyFollowUpRequest(expectedMessageID: "<accepted@invalid>")
        ), sourceID: sourceID)
        let harness = try Harness(backend: backend, original: original, sourceID: sourceID)
        defer { harness.dispose() }
        try await harness.prepare()

        await harness.mounted?.send(bypassingSendGuard: true)

        let sendAttemptCount = await sendAttempts.count()
        #expect(sendAttemptCount == 1)
        #expect(harness.acceptedSends.count == 1)
        let acceptedSend = try #require(harness.acceptedSends.first)
        #expect(acceptedSend.0.id == original.id)
        #expect(acceptedSend.2 == sourceID)
        #expect(acceptedSend.3 == ObjectIdentifier(backend))
    }

    @Test("closing a mounted composer without Send never invokes the accepted callback")
    @MainActor
    func cancelDoesNotInvokeAcceptedCallback() async throws {
        let backend = MockBackend()
        let original = Draft(id: "cancelled-callback", to: [Correspondent(email: "recipient@example.invalid")])
        let harness = try Harness(backend: backend, original: original)
        defer { harness.dispose() }
        try await harness.prepare()

        harness.mounted?.close()

        #expect(harness.acceptedSends.isEmpty)
    }

    @Test("queued mounted send invokes the captured callback once")
    @MainActor
    func queuedSendInvokesCallbackOnce() async throws {
        let backend = MockBackend()
        let sendAttempts = ComposeSendAttemptCounter()
        backend.sendHandler = { _, _ in
            await sendAttempts.record()
            return SendResult(sentMessageID: "queued", warnings: [.queuedForRetry])
        }
        let mailbox = try #require(await backend.mailboxes().first)
        let sourceID = backend.sourceID(for: mailbox)
        let original = try await backend.save(draft: Draft(
            id: "queued-callback",
            to: [Correspondent(email: "recipient@example.invalid")]
        ), sourceID: sourceID)
        let harness = try Harness(backend: backend, original: original, sourceID: sourceID)
        defer { harness.dispose() }
        try await harness.prepare()

        await harness.mounted?.send(bypassingSendGuard: true)

        let sendAttemptCount = await sendAttempts.count()
        #expect(sendAttemptCount == 1)
        #expect(harness.acceptedSends.count == 1)
        let acceptedSend = try #require(harness.acceptedSends.first)
        #expect(acceptedSend.1.warnings == [.queuedForRetry])
        #expect(acceptedSend.2 == sourceID)
        #expect(acceptedSend.3 == ObjectIdentifier(backend))
    }

    @Test("failed mounted send never invokes the accepted callback")
    @MainActor
    func failedSendDoesNotInvokeCallback() async throws {
        let backend = MockBackend()
        let sendAttempts = ComposeSendAttemptCounter()
        backend.sendHandler = { _, _ in
            await sendAttempts.record()
            throw MockComposeSendFailure.failed
        }
        let original = try await backend.save(draft: Draft(
            id: "failed-callback",
            to: [Correspondent(email: "recipient@example.invalid")]
        ))
        let harness = try Harness(backend: backend, original: original)
        defer { harness.dispose() }
        try await harness.prepare()

        await harness.mounted?.send(bypassingSendGuard: true)

        let sendAttemptCount = await sendAttempts.count()
        #expect(sendAttemptCount == 1)
        #expect(harness.acceptedSends.isEmpty)
    }

    @Test("mounted sender switch recomputes the opted-in RFC Message-ID")
    @MainActor
    func senderSwitchRecomputesExpectedMessageID() async throws {
        let backend = MockBackend()
        let mailboxes = try await backend.mailboxes()
        let firstMailbox = try #require(mailboxes.first)
        let secondMailbox = try #require(mailboxes.dropFirst().first)
        let firstSource = backend.sourceID(for: firstMailbox)
        let secondSource = backend.sourceID(for: secondMailbox)
        let options = [
            ComposeSenderOption(sourceID: firstSource, accountID: backend.account.id,
                                displayName: "First", email: firstMailbox.email, subtitle: "First"),
            ComposeSenderOption(sourceID: secondSource, accountID: backend.account.id,
                                displayName: "Second", email: secondMailbox.email, subtitle: "Second")
        ]
        let defaultsName = "ComposeDraftPreservationTests.identity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        var mounted: ComposeView?
        var view = ComposeView(
            backend: backend,
            sourceID: firstSource,
            from: options[0].correspondent,
            senderOptions: options,
            initialSenderOption: options[0],
            recoveryDefaults: defaults
        )
        view.inspection = { mounted = $0 }
        let host = NSHostingView(rootView: AnyView(view.defaultAppStorage(defaults)))
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        host.layoutSubtreeIfNeeded()
        defer {
            host.rootView = AnyView(EmptyView())
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let compose = try #require(mounted)
        compose.setNoReplyFollowUpEnabled(true)
        compose.selectSender(options[1])
        let expected = MIMEMessageBuilder.messageIDHeaderValue(
            draftID: compose.currentDraft().id,
            fromEmail: secondMailbox.email
        )

        #expect(compose.currentDraft().followUpRequest?.expectedMessageID == expected)
    }

    @Test("native edit and Send retain restored rich semantics", arguments: [false, true], [false, true])
    func editRoundTrip(recovery: Bool, send: Bool) async throws {
        let backend = MockBackend()
        let original = try await backend.save(draft: Draft(
            id: UUID().uuidString,
            to: [Correspondent(email: "recipient@example.invalid")],
            subject: UUID().uuidString,
            htmlBody: "<strong>Bold</strong> <em>Italic</em> <u>Underline</u> "
                + "<a href=\"https://example.invalid/help\">Link</a><br>Second paragraph"
        ))
        let harness = try Harness(backend: backend, original: original, recovery: recovery)
        defer { harness.dispose() }
        try await harness.prepare()
        let native = try #require(harness.editor)
        let before = native.string
        native.insertText(" edited", replacementRange: NSRange(location: (before as NSString).length, length: 0))
        harness.host?.layoutSubtreeIfNeeded()
        let mounted = try #require(harness.mounted)
        let html: String
        if send {
            await mounted.send(bypassingSendGuard: true)
            let sent = try #require(await backend.folders().first { $0.role == .sent })
            let header = try #require(await backend.messages(in: sent, pageToken: nil).0.first { $0.subject == original.subject })
            html = try #require(await backend.body(for: header.id).html)
        } else {
            await mounted.saveDraft()
            html = try #require(await backend.draft(for: original.remoteID ?? original.id)).htmlBody
        }
        #expect(html.contains("<strong>Bold</strong>"))
        #expect(html.contains("<em>Italic</em>"))
        #expect(html.contains("<u>Underline</u>"))
        #expect(html.contains("<a href=\"https://example.invalid/help\">Link</a>"))
        #expect(html.contains("<br>Second paragraph edited"))
    }

    @Test(
        "plain and empty controls remain editable",
        arguments: ["", "Plain &amp; escaped<br>Second line"],
        ["plainText", "richText"]
    )
    func plainAndEmpty(html: String, format: String) async throws {
        let backend = MockBackend()
        let original = try await backend.save(draft: Draft(id: UUID().uuidString, subject: "Control", htmlBody: html))
        let harness = try Harness(backend: backend, original: original, format: format)
        defer { harness.dispose() }
        try await harness.prepare()
        #expect(harness.editor != nil)
        await harness.mounted?.saveDraft()
        #expect(try await backend.draft(for: original.remoteID ?? original.id)?.htmlBody == html)
    }

    @Test("a reopened reply relocks its quote only with a saved boundary", arguments: [true, false])
    func replyQuoteBoundary(hasBoundary: Bool) async throws {
        let backend = MockBackend()
        let marker = "On Jan 1, Ada wrote:"
        let original = try await backend.save(draft: Draft(
            id: UUID().uuidString,
            threadID: "thread",
            inReplyToMessageID: "<reply@example.invalid>",
            subject: "Re: Hello",
            htmlBody: "Thanks<br>\(marker)<blockquote>first</blockquote>",
            quoteBoundary: hasBoundary ? DraftQuoteBoundary(marker: marker, edge: .bottom) : nil
        ))
        let harness = try Harness(backend: backend, original: original)
        defer { harness.dispose() }
        try await harness.prepare()
        let native = try #require(harness.editor)
        let text = native.string
        #expect(text == "Thanks\n\(marker)\n> first")
        await harness.mounted?.saveDraft()
        #expect(try await backend.draft(for: original.remoteID ?? original.id) == original)
        // Save briefly disables the editor; typing before SwiftUI re-enables it is dropped.
        await harness.render { native.isEditable }

        let quoteLocation = (text as NSString).range(of: "first").location
        native.insertText("X", replacementRange: NSRange(location: quoteLocation, length: 0))
        #expect(native.string.contains("Xfirst") == !hasBoundary)
        native.insertText(" edited", replacementRange: NSRange(location: 6, length: 0))
        await harness.mounted?.saveDraft()
        let edited = try #require(await backend.draft(for: original.remoteID ?? original.id))
        #expect(edited.htmlBody.contains("Thanks edited"))
        #expect(edited.inReplyToMessageID == original.inReplyToMessageID)
        #expect(edited.threadID == original.threadID)
        #expect(edited.quoteBoundary == original.quoteBoundary)
    }

    @Test("a server-sourced Draft opens only through the explicit path", arguments: [true, false])
    func serverSourcedOpen(isServerSourced: Bool) async throws {
        let backend = MockBackend()
        let original = Draft(id: UUID().uuidString, remoteID: "server-message", subject: "Elsewhere",
                             htmlBody: "<div dir=\"ltr\">Written elsewhere</div>")
        let harness = try Harness(backend: backend, original: original, isServerSourced: isServerSourced)
        defer { harness.dispose() }
        try await harness.prepare()
        #expect((harness.editor?.string == "Written elsewhere") == isServerSourced)
        #expect((harness.editor == nil) == !isServerSourced)
    }

    @Test("restored edits survive preview and editor return without reimport")
    func previewRetainsEdits() async throws {
        let backend = MockBackend()
        let original = try await backend.save(draft: Draft(
            id: UUID().uuidString,
            subject: "Preview",
            htmlBody: "<strong>Bold</strong> plain <em>Italic</em><br>End"
        ))
        let harness = try Harness(backend: backend, original: original)
        defer { harness.dispose() }
        try await harness.prepare()
        let native = try #require(harness.editor)
        let text = native.string
        native.insertText(" edited", replacementRange: NSRange(location: (text as NSString).length, length: 0))
        harness.mounted?.toggleHTMLPreview()
        await harness.render { !native.isEditable }
        #expect(!native.isEditable)
        harness.mounted?.toggleHTMLPreview()
        await harness.render { native.isEditable }
        #expect(native.isEditable)
        let returnedEditor = try #require(harness.editor)
        #expect(returnedEditor.string == text + " edited")
        #expect(ComposeRichTextHTMLSerializer.html(from: returnedEditor.attributedString()).contains("<em>Italic</em>"))
        await harness.mounted?.saveDraft()
        let persisted = try #require(await backend.draft(for: original.remoteID ?? original.id))
        #expect(persisted.htmlBody.contains("<strong>Bold"))
        #expect(persisted.htmlBody.contains("<em>Italic</em>"))
        #expect(persisted.htmlBody.contains("edited"))
    }

    @Test("restoration pending blocks persistence and Send before mounting the editor")
    func pending() async throws {
        let backend = MockBackend()
        let original = try await backend.save(draft: Draft(
            id: UUID().uuidString,
            to: [Correspondent(email: "recipient@example.invalid")],
            subject: "Pending",
            htmlBody: "<strong>Original</strong>"
        ))
        let harness = try Harness(backend: backend, original: original, recovery: true)
        defer { harness.dispose() }
        #expect(harness.editor == nil)
        await harness.mounted?.saveDraft()
        await harness.mounted?.autoSaveDraftAfterInactivity()
        await harness.mounted?.autoSaveDraftOnDismiss()
        await harness.mounted?.send(bypassingSendGuard: true)
        #expect(try await backend.draft(for: original.remoteID ?? original.id) == original)
    }

    @Test("signature changes preserve restored mixed emphasis and Unicode text")
    func signaturePreservesBody() async throws {
        let backend = MockBackend()
        let original = try await backend.save(draft: Draft(
            id: UUID().uuidString,
            subject: "Signature",
            htmlBody: "<strong>Bold 🌱</strong> plain <em>Italic</em><br>End"
        ))
        let harness = try Harness(backend: backend, original: original)
        defer { harness.dispose() }
        try await harness.prepare()
        let native = try #require(harness.editor)
        for body in ["Sign 🌱", "Sign 🌿", "Sign e\u{301}", "Sign é"] {
            harness.mounted?.applySignatureSelection(ComposeSignatureOption(id: "signature", title: "Signature", body: body))
            await harness.render { native.string.hasSuffix(body) }
            let html = ComposeRichTextHTMLSerializer.html(from: native.attributedString())
            #expect(html.contains("<strong>Bold 🌱</strong>"))
            #expect(html.contains("<em>Italic</em>"))
            #expect(native.string.hasSuffix(body))
        }
        harness.mounted?.applySignatureSelection(nil)
        await harness.render { !native.string.contains("Sign") }
        await harness.mounted?.saveDraft()
        #expect(try await backend.draft(for: original.remoteID ?? original.id)?.htmlBody == original.htmlBody)
    }

    @Test("source-scoped restoration preserves owned payloads and canonical metadata", arguments: [false, true], [false, true])
    func metadataAndAttachments(recovery: Bool, autosave: Bool) async throws {
        let backend = MockBackend()
        let mailbox = try await backend.currentMailbox()
        let source = backend.sourceID(for: mailbox)
        var draft = Draft(
            id: UUID().uuidString,
            identityID: "retained-alias",
            threadID: "retained-thread",
            to: [Correspondent(name: "Recipient", email: "recipient@example.invalid")],
            cc: [Correspondent(name: "Copy", email: "cc@example.invalid")],
            bcc: [Correspondent(name: "Blind copy", email: "bcc@example.invalid")],
            subject: "Metadata",
            htmlBody: "<strong>Retained</strong>",
            scheduledFor: Date(timeIntervalSince1970: 2_000_000_000),
            readReceiptRequest: ReadReceiptRequest(notificationTo: "receipt@example.invalid"),
            readReceiptResponse: ReadReceiptResponse(
                finalRecipient: "sender@example.invalid",
                originalMessageID: "<original@example.invalid>"
            ),
            securityMode: .signAndEncrypt
        )
        draft.attachmentIDs = try await [backend.uploadAttachment(
            draftID: draft.id,
            data: Data([0, 1, 2, 255]),
            filename: "owned.bin",
            mimeType: "application/octet-stream",
            sourceID: source
        )]
        let original = try await backend.save(draft: draft, sourceID: source)
        let payloads = try await backend.localDraftAttachments(for: original, sourceID: source)
        let harness = try Harness(
            backend: backend,
            original: original,
            recovery: recovery,
            sourceID: source,
            attachments: payloads
        )
        defer { harness.dispose() }
        try await harness.prepare()
        #expect(harness.editor != nil)
        if autosave {
            await harness.mounted?.autoSaveDraftAfterInactivity()
        } else {
            await harness.mounted?.saveDraft()
        }
        let persisted = try #require(await backend.draft(for: original.remoteID ?? original.id, sourceID: source))
        #expect(persisted == original)
        #expect(try await backend.localDraftAttachments(for: persisted, sourceID: source) == payloads)
        #expect(harness.completions.count == 1)
    }

    @Test("closing or task cancellation during lookup prevents restoration and persistence", arguments: [false, true])
    func cancellationDuringLookup(viaClose: Bool) async throws {
        let draft = Draft(id: "delayed", remoteID: "remote-delayed", subject: "Delayed", htmlBody: "<strong>Original</strong>")
        let backend = DraftLookupProbe(canonical: draft, holdsLookup: true)
        let harness = try Harness(backend: backend, original: draft, recovery: true)
        defer { harness.dispose() }
        let mounted = try #require(harness.mounted)
        let task = Task { await mounted.restoreDraftIfNeeded() }
        await backend.waitForLookup()
        await mounted.saveDraft()
        await mounted.send(bypassingSendGuard: true)
        await mounted.autoSaveDraftAfterInactivity()
        if viaClose {
            mounted.close()
        } else {
            task.cancel()
        }
        await backend.releaseLookup()
        await task.value
        harness.host?.layoutSubtreeIfNeeded()
        #expect(harness.editor == nil)
        #expect(harness.closeCount == (viaClose ? 1 : 0))
        await mounted.saveDraft()
        await mounted.autoSaveDraftOnDismiss()
        await mounted.send(bypassingSendGuard: true)
        #expect(await backend.writeCount == 0)
        #expect(await backend.bodyReadCount == 0)
        await harness.render { !viaClose || harness.storedRecovery == nil }
        #expect((harness.storedRecovery == nil) == viaClose)
    }

    @Test("missing and foreign-owned attachment IDs fail closed", arguments: [false, true])
    func unownedPayloads(foreign: Bool) async throws {
        let backend = MockBackend()
        let id = foreign
            ? try await backend.uploadAttachment(
                draftID: "another-draft",
                data: Data([1]),
                filename: "foreign.txt",
                mimeType: "text/plain"
            )
            : "server-only-id"
        let original = try await backend.save(draft: Draft(
            id: UUID().uuidString,
            subject: "Unsafe payload",
            htmlBody: "<strong>Body</strong>",
            attachmentIDs: [id]
        ))
        let harness = try Harness(backend: backend, original: original)
        defer { harness.dispose() }
        try await harness.prepare()
        #expect(harness.editor == nil)
        await harness.mounted?.saveDraft()
        await harness.mounted?.autoSaveDraftAfterInactivity()
        await harness.mounted?.send(bypassingSendGuard: true)
        #expect(try await backend.draft(for: original.remoteID ?? original.id) == original)
    }

    // Nested blockquotes (#278) and semantic tables (#3) reopen non-destructively in richText
    // mode while plainText mode, malformed quotes, styled/colspan tables, and unsupported
    // editable-prefix markup fail closed.
    @Test("unsafe, lossy, inline and plain-mode formatted drafts fail closed", arguments: [
        ("<img src=\"https://example.invalid/image.png\">", "richText"),
        ("<img src=\"cid:local\">", "richText"),
        ("<style>body { background: url(https://example.invalid/bg) }</style>Text", "richText"),
        ("<table style=\"color:red\"><tr><td colspan=\"2\">Styled table</td></tr></table>", "richText"),
        ("<blockquote><blockquote>Nested quote</blockquote></blockquote>", "plainText"),
        ("<blockquote>Unclosed quote", "richText"),
        (
            "<table style=\"background:#fff\"><tr><td>Top</td></tr></table><blockquote type=\"cite\">Quoted</blockquote>",
            "richText"
        ),
        ("<script>alert(1)</script>Top<blockquote type=\"cite\">Quoted</blockquote>", "richText"),
        ("<strong>Formatted</strong>", "plainText")
    ])
    func unsafeRefused(fixture: (String, String)) async throws {
        let backend = MockBackend()
        let original = try await backend.save(draft: Draft(
            id: UUID().uuidString,
            to: [Correspondent(email: "recipient@example.invalid")],
            subject: "Unsafe",
            htmlBody: fixture.0
        ))
        let harness = try Harness(backend: backend, original: original, format: fixture.1)
        defer { harness.dispose() }
        try await harness.prepare()
        #expect(harness.editor == nil)
        await harness.mounted?.saveDraft()
        await harness.mounted?.autoSaveDraftAfterInactivity()
        await harness.mounted?.autoSaveDraftOnDismiss()
        await harness.mounted?.send(bypassingSendGuard: true)
        #expect(try await backend.draft(for: original.remoteID ?? original.id) == original)
        harness.mounted?.close()
        #expect(harness.closeCount == 1)
    }

    @Test("reopened drafts with nested, styled, Gmail, and Outlook quotes preserve originalHTML on no-edit Save and autosave",
          arguments: [
              "<strong>Reply</strong><br><br><blockquote>Outer<blockquote>Inner</blockquote></blockquote>",
              "<p>Reply</p><blockquote type=\"cite\" style=\"border-left: 2px solid #ccc\"><div>Styled quote</div></blockquote>",
              "<div dir=\"ltr\">Reply</div><br><div class=\"gmail_quote\"><div class=\"gmail_attr\">On Mon, Alice wrote:<br></div><blockquote class=\"gmail_quote\" style=\"margin:0\"><table><tr><td>Webmail table</td></tr></table></blockquote></div>",
              "<div dir=\"ltr\">Reply</div><div id=\"divRplyFwdMsg\" dir=\"ltr\"><b>From:</b> Alice</div><div><p>Outlook body</p></div>"
          ], [false, true])
    func preservedQuoteNoEditSave(html: String, autosave: Bool) async throws {
        let backend = MockBackend()
        let original = try await backend.save(draft: Draft(
            id: UUID().uuidString,
            threadID: "thread-preserved",
            inReplyToMessageID: "<parent@example.invalid>",
            to: [Correspondent(email: "recipient@example.invalid")],
            subject: "Re: Preserved thread",
            htmlBody: html
        ))
        let harness = try Harness(backend: backend, original: original)
        defer { harness.dispose() }
        try await harness.prepare()

        let native = try #require(harness.editor)
        #expect(native.string == "Reply")
        let mounted = try #require(harness.mounted)
        if autosave {
            await mounted.autoSaveDraftAfterInactivity()
        } else {
            await mounted.saveDraft()
        }
        let persisted = try #require(await backend.draft(for: original.remoteID ?? original.id))
        #expect(persisted.htmlBody == html)
        #expect(persisted.threadID == original.threadID)
        #expect(persisted.inReplyToMessageID == original.inReplyToMessageID)
    }

    @Test("editing top reply preserves rich formatting and keeps quoted HTML tail byte-for-byte on Save and Send",
          arguments: [false, true])
    func preservedQuoteEditRoundTrip(send: Bool) async throws {
        let backend = MockBackend()
        let quoteTail = """
        <div class="gmail_quote"><div dir="ltr" class="gmail_attr">On Mon, Alice wrote:<br></div>\
        <blockquote class="gmail_quote" style="margin:0;border-left:1px solid #ccc">\
        <table><tr><td style="padding:4px">Nested webmail cell</td></tr></table>\
        </blockquote></div>
        """
        let originalHTML = "<strong>Thanks</strong> for sending<br><br>\(quoteTail)"
        let subject = "Re: Preserved edit \(UUID().uuidString)"
        let original = try await backend.save(draft: Draft(
            id: UUID().uuidString,
            threadID: "thread-edit-quote",
            inReplyToMessageID: "<parent-edit@example.invalid>",
            to: [Correspondent(email: "recipient@example.invalid")],
            subject: subject,
            htmlBody: originalHTML
        ))
        let harness = try Harness(backend: backend, original: original)
        defer { harness.dispose() }
        try await harness.prepare()

        let native = try #require(harness.editor)
        #expect(native.string == "Thanks for sending")
        native.insertText(" this over!", replacementRange: NSRange(location: (native.string as NSString).length, length: 0))
        harness.host?.layoutSubtreeIfNeeded()

        let mounted = try #require(harness.mounted)
        let resultingHTML: String
        if send {
            await mounted.send(bypassingSendGuard: true)
            let sent = try #require(await backend.folders().first { $0.role == .sent })
            let header = try #require(await backend.messages(in: sent, pageToken: nil).0.first { $0.subject == subject })
            let body = try await backend.body(for: header.id)
            resultingHTML = try #require(body.html)
            let plainText = try #require(body.plainText)
            #expect(plainText.contains("Thanks for sending this over!"))
            #expect(plainText.contains("Nested webmail cell"))
        } else {
            await mounted.saveDraft()
            let saved = try #require(await backend.draft(for: original.remoteID ?? original.id))
            #expect(saved.threadID == original.threadID)
            #expect(saved.inReplyToMessageID == original.inReplyToMessageID)
            resultingHTML = saved.htmlBody
        }

        #expect(resultingHTML.contains("<strong>Thanks</strong> for sending this over!"))
        #expect(resultingHTML.hasSuffix("<br><br>\(quoteTail)"))
    }

    @Test("legacy bodyText snapshot without canonical local proof opens a blank message and is not saved")
    func legacyWithoutProof() async throws {
        let backend = MockBackend()
        let absent = Draft(
            id: UUID().uuidString,
            to: [Correspondent(email: "recipient@example.invalid")],
            subject: "Legacy",
            htmlBody: "Legacy text"
        )
        let harness = try Harness(backend: backend, original: absent, recovery: true)
        defer { harness.dispose() }
        try await harness.prepare()
        await harness.render { harness.editor != nil }
        #expect(harness.editor?.string == "")
        #expect(harness.storedRecovery == nil)
        await harness.mounted?.autoSaveDraftAfterInactivity()
        await harness.mounted?.autoSaveDraftOnDismiss()
        #expect(try await backend.draft(for: absent.id) == nil)
        #expect(harness.completions.isEmpty)
    }

    @Test("a refused recovery opens a blank message and forgets only the pointer",
          arguments: ["stale", "missing", "list", "unowned"])
    func refusedRecoveryFallsBack(kind: String) async throws {
        let backend = MockBackend()
        var hint = Draft(
            id: UUID().uuidString,
            to: [Correspondent(email: "recipient@example.invalid")],
            subject: "Recovery hint",
            htmlBody: "<strong>Original</strong>"
        )
        switch kind {
        case "list": hint.htmlBody = "<ul><li>Item<ul><li>Nested</li></ul></li></ul>"
        case "unowned": hint.attachmentIDs = ["server-only-id"]
        default: break
        }
        if kind != "missing" { hint = try await backend.save(draft: hint) }
        let original = try await backend.draft(for: hint.remoteID ?? hint.id)
        var snapshotSource = hint
        if kind == "stale" { snapshotSource.subject = "Unsaved newer subject" }
        let harness = try Harness(backend: backend, original: snapshotSource, recovery: true)
        defer { harness.dispose() }
        #expect(harness.storedRecovery != nil)
        try await harness.prepare()
        await harness.render { harness.editor != nil }
        let mounted = try #require(harness.mounted)
        #expect(harness.editor?.string == "")
        #expect(harness.storedRecovery == nil)
        // The blank message has no recipients, subject or body, so autosave writes nothing.
        await mounted.autoSaveDraftAfterInactivity()
        #expect(harness.completions.isEmpty)
        #expect(try await backend.draft(for: hint.remoteID ?? hint.id) == original)
        // Typing starts a new Draft; the refused one stays as it was.
        #expect(!mounted.locksSenderToOriginalSource, "a blank message may use any sender")
        let editor = try #require(harness.editor)
        editor.insertText("Fresh start", replacementRange: NSRange(location: 0, length: 0))
        harness.host?.layoutSubtreeIfNeeded()
        await mounted.saveDraft()
        guard case .savedDraft(let fresh)? = harness.completions.first else {
            Issue.record("A typed blank message should save as a new Draft")
            return
        }
        #expect(fresh.id != hint.id)
        #expect(fresh.remoteID != hint.remoteID)
        #expect(try await backend.draft(for: hint.remoteID ?? hint.id) == original)
    }

    @Test("closing a recovered new message forgets its pointer", arguments: ["close", "save", "teardown"])
    func closeForgetsRecovery(path: String) async throws {
        let backend = MockBackend()
        let original = try await backend.save(draft: Draft(
            id: UUID().uuidString,
            to: [Correspondent(email: "recipient@example.invalid")],
            subject: "Recovered",
            htmlBody: "Recovered body"
        ))
        let harness = try Harness(backend: backend, original: original, recovery: true)
        defer { harness.dispose() }
        try await harness.prepare()
        #expect(harness.editor?.string == "Recovered body")
        let mounted = try #require(harness.mounted)
        #expect(mounted.locksSenderToOriginalSource, "a recovered Draft stays in its own mailbox")
        await mounted.autoSaveDraftAfterInactivity()
        #expect(harness.storedRecovery != nil, "an autosave while open keeps crash recovery")
        switch path {
        case "save": await mounted.saveDraft()
        case "close": mounted.close()
        default:
            harness.host?.rootView = AnyView(EmptyView())
            harness.host?.layoutSubtreeIfNeeded()
        }
        await harness.render { harness.storedRecovery == nil }
        #expect(harness.storedRecovery == nil)
        #expect(try await backend.draft(for: original.remoteID ?? original.id) == original)
    }

    private enum DraftSaveFailure: Error {
        case failed
    }

    private final class NormalizingDraftSaveBackend: MailBackend, ScheduledSendManaging, @unchecked Sendable {
        enum Behavior: Equatable {
            case stripIntentFromResponse
            case fail
        }

        private let backing: MockBackend
        private let behavior: Behavior
        private let saveAttempts = ComposeSendAttemptCounter()

        var account: BrevAccount { backing.account }
        var capabilities: BackendCapabilities { backing.capabilities }
        var extendedCapabilities: BackendExtendedCapabilities { backing.extendedCapabilities }

        init(backing: MockBackend, behavior: Behavior) {
            self.backing = backing
            self.behavior = behavior
        }

        func connect() async throws { try await backing.connect() }
        func disconnect() async { await backing.disconnect() }
        func folders() async throws -> [Folder] { try await backing.folders() }
        func refresh(folder: Folder) async throws { try await backing.refresh(folder: folder) }
        func messages(in folder: Folder, pageToken: String?) async throws -> (
            headers: [MessageHeader],
            nextPageToken: String?
        ) {
            try await backing.messages(in: folder, pageToken: pageToken)
        }

        func body(for messageID: String) async throws -> MessageBody {
            try await backing.body(for: messageID)
        }

        func setRead(_ isRead: Bool, for messageIDs: [String]) async throws {
            try await backing.setRead(isRead, for: messageIDs)
        }

        func setFlagged(_ isFlagged: Bool, for messageIDs: [String]) async throws {
            try await backing.setFlagged(isFlagged, for: messageIDs)
        }

        func move(messageIDs: [String], to folder: Folder) async throws {
            try await backing.move(messageIDs: messageIDs, to: folder)
        }

        func delete(messageIDs: [String]) async throws { try await backing.delete(messageIDs: messageIDs) }

        func save(draft: Draft) async throws -> Draft {
            await saveAttempts.record()
            return try await normalizedSave(draft) { try await backing.save(draft: $0) }
        }

        func draft(for messageID: String) async throws -> Draft? {
            try await backing.draft(for: messageID)
        }

        func uploadAttachment(draftID: String, data: Data, filename: String, mimeType: String) async throws -> String {
            try await backing.uploadAttachment(draftID: draftID, data: data, filename: filename, mimeType: mimeType)
        }

        func discard(draftID: String) async throws { try await backing.discard(draftID: draftID) }

        func send(draft: Draft) async throws -> SendResult { try await backing.send(draft: draft) }

        func search(_ query: SearchQuery) async throws -> [MessageHeader] { try await backing.search(query) }

        func calendarEvent(from attachmentID: String) async throws -> CalendarEvent {
            try await backing.calendarEvent(from: attachmentID)
        }

        func replyToCalendarInvite(messageID: String, response: AttendeeState) async throws {
            try await backing.replyToCalendarInvite(messageID: messageID, response: response)
        }

        func subscribeToChanges() -> AsyncStream<MailEvent> { backing.subscribeToChanges() }

        func save(draft: Draft, sourceID: MailSourceID) async throws -> Draft {
            await saveAttempts.record()
            return try await normalizedSave(draft) { try await backing.save(draft: $0, sourceID: sourceID) }
        }

        func saveAttemptCount() async -> Int { await saveAttempts.count() }

        func draft(for messageID: String, sourceID: MailSourceID) async throws -> Draft? {
            try await backing.draft(for: messageID, sourceID: sourceID)
        }

        func send(draft: Draft, sourceID: MailSourceID) async throws -> SendResult {
            try await backing.send(draft: draft, sourceID: sourceID)
        }

        func pendingScheduledSends() -> [PendingScheduledSend] { [] }

        func deliverDueScheduledSends() async {}

        func extensionService<Service>(_ type: Service.Type) -> Service? {
            if ObjectIdentifier(type) == ObjectIdentifier(ScheduledSendManaging.self) { return self as? Service }
            return backing.extensionService(type)
        }

        private func normalizedSave(
            _ draft: Draft,
            save: (Draft) async throws -> Draft
        ) async throws -> Draft {
            guard behavior != .fail else { throw DraftSaveFailure.failed }
            var saved = try await save(draft)
            if behavior == .stripIntentFromResponse {
                saved.scheduledFor = nil
                saved.followUpRequest = nil
            }
            return saved
        }
    }

    private actor ComposeDraftSendProbe {
        private var sentDraft: Draft?
        private var sourceID: MailSourceID?
        private var saveAttemptsBeforeSend = 0

        func record(draft: Draft, sourceID: MailSourceID?, saveAttemptsBeforeSend: Int) {
            sentDraft = draft
            self.sourceID = sourceID
            self.saveAttemptsBeforeSend = saveAttemptsBeforeSend
        }

        func snapshot() -> (sentDraft: Draft?, sourceID: MailSourceID?, saveAttemptsBeforeSend: Int) {
            (sentDraft, sourceID, saveAttemptsBeforeSend)
        }
    }

    @MainActor
    private final class Harness {
        var mounted: ComposeView?
        var host: NSHostingView<AnyView>?
        var closeCount = 0
        var completions: [ComposeCompletion] = []
        var acceptedSends: [(Draft, SendResult, MailSourceID?, ObjectIdentifier)] = []
        private let defaultsName = "ComposeDraftPreservationTests.\(UUID().uuidString)"
        private let defaults: UserDefaults
        private let accountID: String
        private let sourceID: MailSourceID?

        var storedRecovery: ComposeDraftRecoverySnapshot? {
            ComposeDraftRecoveryStore.load(accountID: accountID, sourceID: sourceID, defaults: defaults)
        }

        init(
            backend: any MailBackend,
            original: Draft,
            recovery: Bool = false,
            format: String = "richText",
            sourceID: MailSourceID? = nil,
            attachments: [MIMEMessageAttachment] = [],
            isServerSourced: Bool = false
        ) throws {
            defaults = try #require(UserDefaults(suiteName: defaultsName))
            accountID = backend.account.id
            self.sourceID = sourceID
            defaults.set(format, forKey: "compose.messageFormat")
            if recovery, let snapshot = ComposeDraftRecoverySnapshot.recoverableNewMessageDraft(from: original) {
                ComposeDraftRecoveryStore.save(snapshot, accountID: accountID, sourceID: sourceID, defaults: defaults)
            }
            var view = ComposeView(
                backend: backend,
                sourceID: sourceID,
                from: Correspondent(email: "sender@example.invalid"),
                senderOptions: [],
                recoveredDraft: recovery ? storedRecovery : nil,
                existingDraft: recovery ? nil : original,
                existingDraftAttachments: attachments,
                existingDraftIsServerSourced: isServerSourced,
                recoveryDefaults: defaults,
                onClose: { [weak self] in self?.closeCount += 1 },
                onAcceptedSend: { [weak self] draft, result, sourceID, sendBackend in
                    self?.acceptedSends.append((draft, result, sourceID, ObjectIdentifier(sendBackend as AnyObject)))
                },
                onCompletion: { [weak self] completion in
                    guard let self else { return }
                    completions.append(completion)
                    updateComposeDraftRecovery(for: completion, accountID: accountID, sourceID: sourceID, defaults: defaults)
                }
            )
            view.inspection = { [weak self] in self?.mounted = $0 }
            host = NSHostingView(rootView: AnyView(view.defaultAppStorage(defaults)))
            host?.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
            host?.layoutSubtreeIfNeeded()
        }

        func prepare() async throws {
            let mounted = try #require(mounted)
            await mounted.restoreDraftIfNeeded()
            host?.layoutSubtreeIfNeeded()
        }

        /// Lays out until `condition` holds. macOS 15 can apply a SwiftUI state
        /// change after the current pass, so one layout does not prove a render.
        func render(until condition: () -> Bool) async {
            for _ in 0 ..< 500 {
                host?.layoutSubtreeIfNeeded()
                if condition() { return }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        var editor: ComposeRichTextView? {
            guard let host else { return nil }
            return Self.editor(in: host)
        }

        private static func editor(in view: NSView) -> ComposeRichTextView? {
            if let editor = view as? ComposeRichTextView { return editor }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }

        func dispose() {
            host?.rootView = AnyView(EmptyView())
            host?.layoutSubtreeIfNeeded()
            host = nil
            mounted = nil
            defaults.removePersistentDomain(forName: defaultsName)
        }
    }
}

private enum MockComposeSendFailure: Error {
    case failed
}

private actor ComposeSendAttemptCounter {
    private var attempts = 0

    func record() {
        attempts += 1
    }

    func count() -> Int {
        attempts
    }
}
#endif
