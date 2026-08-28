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

@Suite("ComposeDraftBuilder")
struct ComposeDraftBuilderTests {
    @Test("draft maps compose fields and trims empty recipients")
    func draftMapsComposeFieldsAndTrimsEmptyRecipients() {
        let draft = ComposeDraftBuilder.draft(
            id: "local-1",
            remoteID: "remote-1",
            identityID: "sig-1",
            replyingTo: Self.makeHeader(id: "reply-id"),
            forwardingFrom: nil,
            to: [" ada@example.org ", ""],
            cc: [" team@example.org "],
            bcc: ["   "],
            subject: " Status ",
            bodyText: "Body"
        )

        #expect(draft.id == "local-1")
        #expect(draft.remoteID == "remote-1")
        #expect(draft.identityID == "sig-1")
        #expect(draft.threadID == "thread-reply-id")
        // The reference is the message's RFC Message-ID (threadID), never the
        // internal folderID:uid id ("reply-id"), so recipients can thread it.
        #expect(draft.inReplyToMessageID == "thread-reply-id")
        #expect(draft.forwardedMessageID == nil)
        #expect(draft.to == [Correspondent(email: "ada@example.org")])
        #expect(draft.cc == [Correspondent(email: "team@example.org")])
        #expect(draft.bcc.isEmpty)
        #expect(draft.subject == " Status ")
        #expect(draft.htmlBody == "Body")
    }

    @Test("reply references the RFC Message-ID, and omits it when the message has none")
    func replyUsesRFCMessageIDNotInternalID() {
        let withMessageID = MessageHeader(
            id: "inbox:42",
            threadID: "<abc123@example.org>",
            folderID: "inbox",
            from: Correspondent(email: "alex@example.org"),
            subject: "Hi",
            snippet: "",
            date: Date(timeIntervalSince1970: 0)
        )
        let reply = ComposeDraftBuilder.draft(
            id: "d1",
            replyingTo: withMessageID,
            forwardingFrom: nil,
            to: ["x@example.org"],
            cc: [],
            bcc: [],
            subject: "Re",
            bodyText: ""
        )
        #expect(reply.inReplyToMessageID == "<abc123@example.org>")

        // No Message-ID → threadID falls back to id; emit no reference rather
        // than a bogus `<folderID:uid>`.
        let withoutMessageID = MessageHeader(
            id: "inbox:43",
            threadID: "inbox:43",
            folderID: "inbox",
            from: Correspondent(email: "alex@example.org"),
            subject: "Hi",
            snippet: "",
            date: Date(timeIntervalSince1970: 0)
        )
        let replyNoID = ComposeDraftBuilder.draft(
            id: "d2",
            replyingTo: withoutMessageID,
            forwardingFrom: nil,
            to: ["x@example.org"],
            cc: [],
            bcc: [],
            subject: "Re",
            bodyText: ""
        )
        #expect(replyNoID.inReplyToMessageID == nil)
    }

    @Test("draft splits comma and semicolon recipient lists")
    func draftSplitsCommaAndSemicolonRecipientLists() {
        let draft = ComposeDraftBuilder.draft(
            id: "local-1",
            replyingTo: nil,
            forwardingFrom: nil,
            to: ["ada@example.org, team@example.org;ops@example.org"],
            cc: [],
            bcc: [],
            subject: "",
            bodyText: ""
        )

        #expect(draft.to == [
            Correspondent(email: "ada@example.org"),
            Correspondent(email: "team@example.org"),
            Correspondent(email: "ops@example.org")
        ])
    }

    @Test("draft carries explicit read receipt opt-in")
    func draftCarriesReadReceiptOptIn() {
        let draft = ComposeDraftBuilder.draft(
            id: "local-1",
            replyingTo: nil,
            forwardingFrom: nil,
            to: ["ada@example.org"],
            cc: [],
            bcc: [],
            subject: "",
            bodyText: "",
            readReceiptNotificationTo: "sender@example.org"
        )

        #expect(draft.readReceiptRequest?.notificationTo == "sender@example.org")
    }

    @Test("forward draft keeps forwarded message id")
    func forwardDraftKeepsForwardedMessageID() {
        let draft = ComposeDraftBuilder.draft(
            id: "local-1",
            replyingTo: nil,
            forwardingFrom: Self.makeHeader(id: "forward-id"),
            to: [],
            cc: [],
            bcc: [],
            subject: "Fwd: Status",
            bodyText: "Forwarded body"
        )

        #expect(draft.inReplyToMessageID == nil)
        #expect(draft.forwardedMessageID == "thread-forward-id")
    }

    @Test("can save when content or addressing exists")
    func canSaveWhenContentOrAddressingExists() {
        #expect(ComposeDraftBuilder.canSave(
            to: [],
            cc: [],
            bcc: [],
            subject: "",
            bodyText: "",
            hasAttachments: false
        ) == false)
        #expect(ComposeDraftBuilder.canSave(
            to: [],
            cc: [],
            bcc: [],
            subject: "  Status  ",
            bodyText: "",
            hasAttachments: false
        ))
        #expect(ComposeDraftBuilder.canSave(
            to: ["ada@example.org"],
            cc: [],
            bcc: [],
            subject: "",
            bodyText: "",
            hasAttachments: false
        ))
        #expect(ComposeDraftBuilder.canSave(
            to: [],
            cc: [],
            bcc: [],
            subject: "",
            bodyText: "",
            hasAttachments: true
        ))
    }

    @Test("can send only requires at least one recipient")
    func canSendOnlyRequiresAtLeastOneRecipient() {
        #expect(ComposeDraftBuilder.canSend(to: [], cc: [], bcc: []) == false)
        #expect(ComposeDraftBuilder.canSend(to: ["  "], cc: [], bcc: []) == false)
        #expect(ComposeDraftBuilder.canSend(to: ["ada@example.org"], cc: [], bcc: []))
        #expect(ComposeDraftBuilder.canSend(to: [], cc: ["team@example.org"], bcc: []))
        #expect(ComposeDraftBuilder.canSend(to: [], cc: [], bcc: ["hidden@example.org"]))
        #expect(ComposeDraftBuilder.canSend(
            to: ["ada@example.org, team@example.org"],
            cc: [],
            bcc: []
        ))
    }

    @Test("signature is injected into new draft body")
    func signatureInjectedIntoDraft() {
        let draft = ComposeDraftBuilder.draft(
            id: "local-1",
            replyingTo: nil,
            forwardingFrom: nil,
            to: ["ada@example.org"],
            cc: [],
            bcc: [],
            subject: "Hello",
            bodyText: "Body text",
            signatureBody: "<p>Henrik</p>"
        )

        #expect(draft.htmlBody.contains("Body text"))
        #expect(draft.htmlBody.contains("<hr"))
        #expect(draft.htmlBody.contains("<div class=\"signature\">"))
        #expect(draft.htmlBody.contains("<p>Henrik</p>"))
    }

    @Test("plain text body is serialized as safe HTML with preserved line breaks")
    func plainTextBodyIsSerializedAsSafeHTMLWithPreservedLineBreaks() {
        let draft = ComposeDraftBuilder.draft(
            id: "local-1",
            replyingTo: nil,
            forwardingFrom: nil,
            to: ["ada@example.org"],
            cc: [],
            bcc: [],
            subject: "Hello",
            bodyText: "Test ok\n\nMvh,\nHenrik\n-- \nHelsing,\nHenrik"
        )

        #expect(draft.htmlBody == "Test ok<br><br>Mvh,<br>Henrik<br>-- <br>Helsing,<br>Henrik")
        #expect(!draft.htmlBody.contains("\n"))
    }

    @Test("plain text body escapes HTML before provider handoff")
    func plainTextBodyEscapesHTMLBeforeProviderHandoff() {
        let draft = ComposeDraftBuilder.draft(
            id: "local-1",
            replyingTo: nil,
            forwardingFrom: nil,
            to: ["ada@example.org"],
            cc: [],
            bcc: [],
            subject: "Hello",
            bodyText: "Fish & <chips>\n\"quoted\""
        )

        #expect(draft.htmlBody == "Fish &amp; &lt;chips&gt;<br>&quot;quoted&quot;")
    }

    @Test("rich text body preserves the supported HTML formatting subset")
    func richTextBodyPreservesSupportedHTMLSubset() {
        let draft = ComposeDraftBuilder.draft(
            id: "local-1",
            replyingTo: nil,
            forwardingFrom: nil,
            to: ["ada@example.org"],
            cc: [],
            bcc: [],
            subject: "Hello",
            bodyText: """
            <p>Hello <strong>Ada</strong> and <em>Grace</em>.</p>
            <ul><li>One</li><li><u>Two</u></li></ul>
            <blockquote>Quoted</blockquote>
            """,
            bodyFormat: .richTextHTML
        )

        #expect(draft.htmlBody.contains("<p>Hello <strong>Ada</strong> and <em>Grace</em>.</p>"))
        #expect(draft.htmlBody.contains("<ul><li>One</li><li><u>Two</u></li></ul>"))
        #expect(draft.htmlBody.contains("<blockquote>Quoted</blockquote>"))
        #expect(!draft.htmlBody.contains("&lt;strong&gt;"))
    }

    @Test("rich text body strips unsupported or unsafe HTML")
    func richTextBodyStripsUnsupportedOrUnsafeHTML() {
        let draft = ComposeDraftBuilder.draft(
            id: "local-1",
            replyingTo: nil,
            forwardingFrom: nil,
            to: ["ada@example.org"],
            cc: [],
            bcc: [],
            subject: "Hello",
            bodyText: """
            <p onclick="steal()">Hello <script>alert(1)</script><strong>Ada</strong></p>
            <a href="javascript:alert(1)" title="bad">bad</a>
            <a href="https://example.com/a?b=1&amp;c=2" onclick="steal()">good</a>
            <img src="https://tracker.example/pixel.png" alt="pixel">
            """,
            bodyFormat: .richTextHTML
        )

        #expect(draft.htmlBody.contains("<p>Hello <strong>Ada</strong></p>"))
        #expect(draft.htmlBody.contains("<a href=\"https://example.com/a?b=1&amp;c=2\">good</a>"))
        #expect(!draft.htmlBody.contains("script"))
        #expect(!draft.htmlBody.contains("onclick"))
        #expect(!draft.htmlBody.contains("javascript:"))
        #expect(!draft.htmlBody.contains("<img"))
        #expect(!draft.htmlBody.contains("tracker.example"))
    }

    @Test("nil signature leaves body unchanged")
    func nilSignatureLeavesBodyUnchanged() {
        let draft = ComposeDraftBuilder.draft(
            id: "local-1",
            replyingTo: nil,
            forwardingFrom: nil,
            to: ["ada@example.org"],
            cc: [],
            bcc: [],
            subject: "Hello",
            bodyText: "Body text",
            signatureBody: nil
        )

        #expect(draft.htmlBody == "Body text")
    }

    @Test("empty signature leaves body unchanged")
    func emptySignatureLeavesBodyUnchanged() {
        let draft = ComposeDraftBuilder.draft(
            id: "local-1",
            replyingTo: nil,
            forwardingFrom: nil,
            to: ["ada@example.org"],
            cc: [],
            bcc: [],
            subject: "Hello",
            bodyText: "Body text",
            signatureBody: "  "
        )

        #expect(draft.htmlBody == "Body text")
    }

    @Test("signature injection is pure function")
    func signatureInjectionIsPure() {
        let result = ComposeDraftBuilder.injectSignature(
            into: "Hello",
            signatureBody: "Sig",
            isReplyOrForward: false
        )
        #expect(result.contains("Hello"))
        #expect(result.contains("Sig"))
        #expect(result.contains("<hr"))
    }

    @Test("reply draft includes signature")
    func replyDraftIncludesSignature() {
        let draft = ComposeDraftBuilder.draft(
            id: "local-1",
            replyingTo: Self.makeHeader(id: "reply-id"),
            forwardingFrom: nil,
            to: ["ada@example.org"],
            cc: [],
            bcc: [],
            subject: "Re: Hello",
            bodyText: "Reply body",
            signatureBody: "My Sig"
        )

        #expect(draft.htmlBody.contains("Reply body"))
        #expect(draft.htmlBody.contains("My Sig"))
    }

    @Test("plain text signature line breaks are preserved when injected")
    func plainTextSignatureLineBreaksArePreservedWhenInjected() {
        let draft = ComposeDraftBuilder.draft(
            id: "local-1",
            replyingTo: nil,
            forwardingFrom: nil,
            to: ["ada@example.org"],
            cc: [],
            bcc: [],
            subject: "Hello",
            bodyText: "Body text",
            signatureBody: "Helsing,\nHenrik & Ada"
        )

        #expect(draft.htmlBody.contains("<div class=\"signature\">Helsing,<br>Henrik &amp; Ada</div>"))
    }

    @Test("plain text signature email brackets are escaped")
    func plainTextSignatureEmailBracketsAreEscaped() {
        let draft = ComposeDraftBuilder.draft(
            id: "local-1",
            replyingTo: nil,
            forwardingFrom: nil,
            to: ["ada@example.org"],
            cc: [],
            bcc: [],
            subject: "Hello",
            bodyText: "Body text",
            signatureBody: "Henrik <henrik@example.org>"
        )

        #expect(draft.htmlBody.contains("Henrik &lt;henrik@example.org&gt;"))
    }

    @Test("autosave schedules only for changed non-empty drafts")
    func autosaveSchedulesOnlyForChangedNonEmptyDrafts() {
        #expect(!ComposeAutoSavePolicy.shouldScheduleAutoSave(
            canSave: false,
            isBusy: false,
            isBlocked: false
        ))
        #expect(!ComposeAutoSavePolicy.shouldScheduleAutoSave(
            canSave: true,
            isBusy: true,
            isBlocked: false
        ))
        #expect(!ComposeAutoSavePolicy.shouldScheduleAutoSave(
            canSave: true,
            isBusy: false,
            isBlocked: true
        ))
        #expect(ComposeAutoSavePolicy.shouldScheduleAutoSave(
            canSave: true,
            isBusy: false,
            isBlocked: false
        ))
    }

    @Test("dismiss autosave skips after explicit save or send")
    func dismissAutosaveSkipsAfterExplicitSaveOrSend() {
        #expect(!ComposeAutoSavePolicy.shouldAutoSaveOnDismiss(
            canSave: false,
            isBusy: false,
            hasCompletedExplicitOperation: false
        ))
        #expect(!ComposeAutoSavePolicy.shouldAutoSaveOnDismiss(
            canSave: true,
            isBusy: true,
            hasCompletedExplicitOperation: false
        ))
        #expect(!ComposeAutoSavePolicy.shouldAutoSaveOnDismiss(
            canSave: true,
            isBusy: false,
            hasCompletedExplicitOperation: true
        ))
        #expect(ComposeAutoSavePolicy.shouldAutoSaveOnDismiss(
            canSave: true,
            isBusy: false,
            hasCompletedExplicitOperation: false
        ))
    }

    @Test("new compose can recover the latest saved non reply draft")
    func newComposeCanRecoverLatestSavedNonReplyDraft() throws {
        let saved = Draft(
            id: "local-1",
            remoteID: "remote-1",
            to: [Correspondent(name: "Ada", email: "ada@example.org")],
            cc: [Correspondent(email: "team@example.org")],
            bcc: [Correspondent(email: "hidden@example.org")],
            subject: "Launch notes",
            htmlBody: "Recovered body"
        )

        let recovered = try #require(ComposeDraftRecoverySnapshot.recoverableNewMessageDraft(from: saved))

        #expect(recovered.draftID == "local-1")
        #expect(recovered.remoteID == "remote-1")
        #expect(recovered.to == ["ada@example.org"])
        #expect(recovered.cc == ["team@example.org"])
        #expect(recovered.bcc == ["hidden@example.org"])
        #expect(recovered.subject == "Launch notes")
        #expect(recovered.bodyText == "Recovered body")
    }

    @Test("new compose recovery converts stored HTML body back to editor text")
    func newComposeRecoveryConvertsStoredHTMLBodyBackToEditorText() throws {
        let saved = Draft(
            id: "local-1",
            remoteID: "remote-1",
            to: [Correspondent(email: "ada@example.org")],
            subject: "Launch notes",
            htmlBody: "Hello<br><br><div class=\"signature\">Henrik &amp; Ada</div>"
        )

        let recovered = try #require(ComposeDraftRecoverySnapshot.recoverableNewMessageDraft(from: saved))

        #expect(recovered.bodyText == "Hello\n\nHenrik & Ada")
    }

    @Test("reply and forward drafts are not restored into a new compose window")
    func replyAndForwardDraftsAreNotRestoredIntoNewComposeWindow() {
        #expect(ComposeDraftRecoverySnapshot.recoverableNewMessageDraft(from: Draft(
            id: "reply",
            inReplyToMessageID: "message-1",
            subject: "Re: Hello",
            htmlBody: "Reply"
        )) == nil)
        #expect(ComposeDraftRecoverySnapshot.recoverableNewMessageDraft(from: Draft(
            id: "forward",
            forwardedMessageID: "message-2",
            subject: "Fwd: Hello",
            htmlBody: "Forward"
        )) == nil)
    }

    @Test("recovery store persists and clears the latest new-message draft")
    func recoveryStorePersistsAndClearsLatestNewMessageDraft() throws {
        let suiteName = "ComposeDraftRecoveryStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sourceID = MailSourceID(accountID: "account-1", mailboxID: "mailbox-1")
        let snapshot = ComposeDraftRecoverySnapshot(
            draftID: "local-1",
            remoteID: "remote-1",
            to: ["ada@example.org"],
            cc: [],
            bcc: [],
            subject: "Recover me",
            bodyText: "Body"
        )

        ComposeDraftRecoveryStore.save(
            snapshot,
            accountID: "account-1",
            sourceID: sourceID,
            defaults: defaults
        )

        #expect(ComposeDraftRecoveryStore.load(
            accountID: "account-1",
            sourceID: sourceID,
            defaults: defaults
        ) == snapshot)

        ComposeDraftRecoveryStore.clear(
            accountID: "account-1",
            sourceID: sourceID,
            defaults: defaults
        )

        #expect(ComposeDraftRecoveryStore.load(
            accountID: "account-1",
            sourceID: sourceID,
            defaults: defaults
        ) == nil)
    }

    @Test("shared compose payload turns text and URLs into body prefill")
    func sharedComposePayloadTurnsTextAndURLsIntoBodyPrefill() throws {
        var inner = URLComponents()
        inner.queryItems = [
            URLQueryItem(name: "text", value: "Read this & reply"),
            URLQueryItem(name: "url", value: "https://example.com/a?b=c&d=e")
        ]
        let encoded = try #require(inner.percentEncodedQuery)
        var outer = URLComponents()
        outer.scheme = "brev"
        outer.host = "compose"
        outer.queryItems = [URLQueryItem(name: "shared", value: encoded)]
        let url = try #require(outer.url)

        let prefill = try #require(SharedComposePayload.prefill(from: url))

        #expect(prefill.bodyText == "Read this & reply\n\nhttps://example.com/a?b=c&d=e")
    }

    @Test("shared compose payload accepts an uppercase scheme")
    func sharedComposePayloadAcceptsUppercaseScheme() throws {
        let url = try #require(URL(string: "BREV://compose?shared=text%3DHello"))

        let prefill = try #require(SharedComposePayload.prefill(from: url))

        #expect(prefill.bodyText == "Hello")
    }

    @Test("shared compose payload carries single attachment URL")
    func sharedComposePayloadCarriesSingleAttachmentURL() throws {
        let attachmentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Board notes.pdf")

        var inner = URLComponents()
        inner.queryItems = [
            URLQueryItem(name: "attachment", value: attachmentURL.absoluteString)
        ]
        let encoded = try #require(inner.percentEncodedQuery)
        var outer = URLComponents()
        outer.scheme = "brev"
        outer.host = "compose"
        outer.queryItems = [URLQueryItem(name: "shared", value: encoded)]
        let url = try #require(outer.url)

        let prefill = try #require(SharedComposePayload.prefill(
            from: url,
            allowedAttachmentRoot: FileManager.default.temporaryDirectory
        ))

        #expect(prefill.bodyText.isEmpty)
        #expect(prefill.attachmentFileURLs == [attachmentURL])
        #expect(!prefill.isEmpty)
    }

    @Test("shared compose payload rejects attachments outside the allowed root")
    func sharedComposePayloadRejectsAttachmentsOutsideAllowedRoot() throws {
        // The brev:// scheme is public; a crafted attachment URL pointing outside
        // the share-handoff directory must not be attached.
        var inner = URLComponents()
        inner.queryItems = [
            URLQueryItem(name: "text", value: "hi"),
            URLQueryItem(name: "attachment", value: "file:///etc/passwd"),
            URLQueryItem(
                name: "attachment",
                value: URL(fileURLWithPath: "/var/some/other/secret.pdf").absoluteString
            )
        ]
        let encoded = try #require(inner.percentEncodedQuery)
        var outer = URLComponents()
        outer.scheme = "brev"
        outer.host = "compose"
        outer.queryItems = [URLQueryItem(name: "shared", value: encoded)]
        let url = try #require(outer.url)

        let prefill = try #require(SharedComposePayload.prefill(
            from: url,
            allowedAttachmentRoot: FileManager.default.temporaryDirectory
        ))
        #expect(prefill.attachmentFileURLs.isEmpty)
        #expect(prefill.bodyText == "hi")
    }

    @Test("shared compose payload preserves mixed text URL and attachments")
    func sharedComposePayloadPreservesMixedTextURLAndAttachments() throws {
        let firstAttachment = FileManager.default.temporaryDirectory
            .appendingPathComponent("image.png")
        let secondAttachment = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck.pdf")

        var inner = URLComponents()
        inner.queryItems = [
            URLQueryItem(name: "text", value: "Please review"),
            URLQueryItem(name: "url", value: "https://example.com/brief"),
            URLQueryItem(name: "attachment", value: firstAttachment.absoluteString),
            URLQueryItem(name: "attachment", value: secondAttachment.absoluteString)
        ]
        let encoded = try #require(inner.percentEncodedQuery)
        var outer = URLComponents()
        outer.scheme = "brev"
        outer.host = "compose"
        outer.queryItems = [URLQueryItem(name: "shared", value: encoded)]
        let url = try #require(outer.url)

        let prefill = try #require(SharedComposePayload.prefill(
            from: url,
            allowedAttachmentRoot: FileManager.default.temporaryDirectory
        ))

        #expect(prefill.bodyText == "Please review\n\nhttps://example.com/brief")
        #expect(prefill.attachmentFileURLs == [firstAttachment, secondAttachment])
    }

    @Test("shared compose payload ignores non-compose URLs")
    func sharedComposePayloadIgnoresNonComposeURLs() throws {
        let url = try #require(URL(string: "brev://settings?shared=text%3DHello"))
        #expect(SharedComposePayload.prefill(from: url) == nil)
    }

    @Test("scheduled draft carries scheduledFor")
    func scheduledDraftCarriesScheduledFor() {
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        let draft = ComposeDraftBuilder.draft(
            id: "local-1",
            replyingTo: nil,
            forwardingFrom: nil,
            to: ["ada@example.org"],
            cc: [],
            bcc: [],
            subject: "Hello",
            bodyText: "Body",
            signatureBody: nil,
            scheduledFor: date
        )

        #expect(draft.scheduledFor == date)
    }

    @Test("default scheduledFor is nil")
    func defaultScheduledForIsNil() {
        let draft = ComposeDraftBuilder.draft(
            id: "local-1",
            replyingTo: nil,
            forwardingFrom: nil,
            to: ["ada@example.org"],
            cc: [],
            bcc: [],
            subject: "Hello",
            bodyText: "Body"
        )

        #expect(draft.scheduledFor == nil)
    }

    // MARK: - Inline image staging

    @Test("inline image present in body is returned by inlineAttachments with matching contentID")
    func inlineImageInBodyIsReturnedByInlineAttachments() {
        let registry = ComposeInlineImageRegistry()
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0]) // minimal JPEG header bytes
        _ = registry.stage(data: imageData, mimeType: "image/jpeg") { "c@brev" }

        let bodyHTML = "<p>See this: <img src=\"cid:c@brev\" alt=\"photo\"></p>"
        let images = ComposeDraftBuilder.inlineAttachments(
            fromRegistry: registry,
            draftID: "local-1",
            bodyHTML: bodyHTML
        )

        #expect(images.count == 1)
        let image = images[0]
        // The returned ComposeInlineImage carries the content-ID and data needed
        // for stageInlineAttachment() to tag the backend record as isInline=true.
        #expect(image.contentID == "c@brev")
        #expect(image.mimeType == "image/jpeg")
        #expect(image.data == imageData)
    }

    @Test("inline image not referenced in body is reconciled away")
    func inlineImageNotInBodyIsReconciledAway() {
        let registry = ComposeInlineImageRegistry()
        let imageData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG magic bytes
        _ = registry.stage(data: imageData, mimeType: "image/png") { "orphan@brev" }

        let bodyHTML = "<p>No image here.</p>"
        let images = ComposeDraftBuilder.inlineAttachments(
            fromRegistry: registry,
            draftID: "local-1",
            bodyHTML: bodyHTML
        )

        // Orphaned image must be removed from both the returned list and the registry.
        #expect(images.isEmpty)
        #expect(registry.staged.isEmpty)
    }

    @Test("htmlBody still references cid after inline attachment extraction")
    func htmlBodyStillReferencesCIDAfterInlineAttachmentExtraction() {
        let registry = ComposeInlineImageRegistry()
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        _ = registry.stage(data: imageData, mimeType: "image/jpeg") { "c@brev" }

        let bodyHTML = "<p>Hello <img src=\"cid:c@brev\"></p>"

        // Verify that inlineAttachments() extracts the staged image from the registry
        // and the body's cid: reference is preserved.
        let images = ComposeDraftBuilder.inlineAttachments(
            fromRegistry: registry,
            draftID: "local-1",
            bodyHTML: bodyHTML
        )
        #expect(images.count == 1)
        #expect(images[0].contentID == "c@brev")
        #expect(images[0].mimeType == "image/jpeg")

        let draft = ComposeDraftBuilder.draft(
            id: "local-1",
            replyingTo: nil,
            forwardingFrom: nil,
            to: ["ada@example.org"],
            cc: [],
            bcc: [],
            subject: "With image",
            bodyText: "",
            bodyHTML: bodyHTML,
            bodyFormat: .richTextHTML
        )

        // The body serialiser must preserve `cid:` src attributes (not strip them).
        #expect(draft.htmlBody.contains("cid:c@brev"))
    }

    private static func makeHeader(id: MessageHeader.ID) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            subject: "Hello",
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600)
        )
    }
}
