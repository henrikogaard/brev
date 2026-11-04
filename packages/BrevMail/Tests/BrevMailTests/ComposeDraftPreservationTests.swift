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
import BrevBackend
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

    @Test("unsafe, lossy, inline and plain-mode formatted drafts fail closed", arguments: [
        ("<img src=\"https://example.invalid/image.png\">", "richText"),
        ("<img src=\"cid:local\">", "richText"),
        ("<style>body { background: url(https://example.invalid/bg) }</style>Text", "richText"),
        ("<table><tr><td>Table</td></tr></table>", "richText"),
        ("<blockquote><blockquote>Nested quote</blockquote></blockquote>", "richText"),
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
        case "list": hint.htmlBody = "<ul><li>Item</li></ul>"
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

    @MainActor
    private final class Harness {
        var mounted: ComposeView?
        var host: NSHostingView<AnyView>?
        var closeCount = 0
        var completions: [ComposeCompletion] = []
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
#endif
