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

import BrevDesign
import SwiftUI

struct ComposeBodyEditor: View {
    @Binding var text: String
    @Binding var richHTML: String?
    @Binding var selection: ComposeBodyTextSelection?
    @Binding var insertionPoint: ComposeBodyInsertionPoint?
    let bodyFormat: ComposeBodyFormat
    let appearance: ComposeBodyAppearance
    var htmlPublicationFlushBox: ComposeHTMLPublicationFlushBox?
    let textCheckingConfiguration: ComposeTextCheckingConfiguration
    var fontFamily: MailboxFontFamily = .system
    var textSize: MailboxTextSize = .medium
    /// Owned by ComposeView; shared reference so staged images persist across re-renders.
    var inlineImageRegistry: ComposeInlineImageRegistry?
    /// Called by the Coordinator when the user taps Insert Link, with pre-filled input.
    var onRequestLinkSheet: ((ComposeLinkSheetInput) -> Void)?
    /// Owned by ComposeView so the iOS formatting toolbar can reach the active UITextView.
    /// Unused on macOS (responder-chain `sendAction` is used instead).
    var iosRichTextTargetBox: ComposeIOSRichTextTargetBox?
    /// Called when files (not loose image data) are dropped onto the body so the
    /// parent can attach them. macOS only; on iOS the SwiftUI drop target above
    /// the editor handles drops.
    var onDropFileURLs: (([URL]) -> Void)?
    /// Reports whether a file drag is currently hovering the body, so the parent
    /// can show the same drop highlight it uses for the rest of the window.
    var onFileDragTargetChanged: ((Bool) -> Void)?

    var body: some View {
        PlatformComposeBodyEditor(
            text: $text,
            richHTML: $richHTML,
            selection: $selection,
            insertionPoint: $insertionPoint,
            bodyFormat: bodyFormat,
            appearance: appearance,
            htmlPublicationFlushBox: htmlPublicationFlushBox,
            textCheckingConfiguration: textCheckingConfiguration,
            fontFamily: fontFamily,
            textSize: textSize,
            inlineImageRegistry: inlineImageRegistry,
            onRequestLinkSheet: onRequestLinkSheet,
            iosRichTextTargetBox: iosRichTextTargetBox,
            onDropFileURLs: onDropFileURLs,
            onFileDragTargetChanged: onFileDragTargetChanged
        )
    }
}

#if os(macOS)
import AppKit

// MARK: - Responder-chain action names (#251)

/// Objective-C protocols whose selectors the Coordinator responds to via the
/// standard `NSApp.sendAction(selector:to:from:)` responder-chain mechanism.
///
/// These are declared here so both `ComposeView.swift` and `ComposeBodyEditor.swift`
/// can form `#selector(...)` expressions without cross-file private-type access.
@objc protocol ComposeBodyEditorRichActions {
    /// Sent by the toolbar's Insert Link button; handled by `requestLinkSheet()`.
    func brevInsertLink(_ sender: Any?)
    /// Toggles a bulleted (disc) list on the selection.
    func brevToggleBulletedList(_ sender: Any?)
    /// Toggles a numbered (decimal) list on the selection.
    func brevToggleNumberedList(_ sender: Any?)
    /// Opens NSOpenPanel to pick and insert an inline image.
    func brevInsertImage(_ sender: Any?)
    /// Applies a confirmed URL + display text (sender must be `ComposeBodyEditorLinkPayload`).
    func brevApplyLink(_ sender: Any?)
    /// Clears the `.link` attribute from the selection.
    func brevRemoveLink(_ sender: Any?)
    /// Inserts a pre-loaded image payload (data + mimeType) at the current caret.
    ///
    /// Called from the paste/drop override in `ComposeRichTextView` when
    /// `ComposePasteboardImage.imagePayload(...)` succeeds. Returns `true` if the
    /// image was staged and inserted, `false` if staging was rejected (type or size).
    @discardableResult
    func brevInsertImagePayload(data: Data, mimeType: String) -> Bool
}

/// Carries the URL and display text through the responder chain as the `sender` object.
final class ComposeBodyEditorLinkPayload: NSObject {
    let url: URL
    let displayText: String
    init(url: URL, displayText: String) {
        self.url = url
        self.displayText = displayText
        super.init()
    }
}

// MARK: - NSTextView subclass for responder-chain actions (#251)

/// `NSTextView` subclass that implements the `brev*` rich-compose action
/// selectors. Because the text view is the first responder when the compose
/// body has focus, `NSApp.sendAction(_:to:nil:from:)` dispatches here directly
/// — unlike the `Coordinator`, which is only a `delegate` and is therefore NOT
/// in the NSResponder chain.
final class ComposeRichTextView: NSTextView, ComposeBodyEditorRichActions {
    /// Set by `makeNSView` immediately after construction so the text view can
    /// forward actions to the coordinator.
    weak var richActionsTarget: ComposeBodyEditorRichActions?
    /// Receives file URLs dropped onto the body; the parent attaches them.
    var onDropFileURLs: (([URL]) -> Void)?
    /// Reports file-drag hover state so the parent can highlight the drop area.
    var onFileDragTargetChanged: ((Bool) -> Void)?

    func brevInsertLink(_ sender: Any?) {
        richActionsTarget?.brevInsertLink(sender)
    }

    func brevToggleBulletedList(_ sender: Any?) {
        richActionsTarget?.brevToggleBulletedList(sender)
    }

    func brevToggleNumberedList(_ sender: Any?) {
        richActionsTarget?.brevToggleNumberedList(sender)
    }

    func brevInsertImage(_ sender: Any?) {
        richActionsTarget?.brevInsertImage(sender)
    }

    func brevApplyLink(_ sender: Any?) {
        richActionsTarget?.brevApplyLink(sender)
    }

    func brevRemoveLink(_ sender: Any?) {
        richActionsTarget?.brevRemoveLink(sender)
    }

    @discardableResult
    func brevInsertImagePayload(data: Data, mimeType: String) -> Bool {
        richActionsTarget?.brevInsertImagePayload(data: data, mimeType: mimeType) ?? false
    }

    // MARK: - Paste override (#251)

    /// Intercepts paste: if the pasteboard contains a supported image UTI, route it
    /// through the inline-image stage→tag→insert path. Otherwise fall through to the
    /// default NSTextView paste so plain/rich text paste keeps working.
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        // Only intercept when there is an actions target (i.e. we're wired up).
        if richActionsTarget != nil {
            let types = pboard.types?.map(\.rawValue) ?? []
            let payload = ComposePasteboardImage.imagePayload(
                types: types,
                data: { uti in pboard.data(forType: NSPasteboard.PasteboardType(uti)) }
            )
            if let payload {
                return brevInsertImagePayload(data: payload.data, mimeType: payload.mimeType)
            }
        }
        return super.readSelection(from: pboard, type: type)
    }

    // MARK: - Drag-and-drop override (#251)

    /// Intercepts drop: if the drag pasteboard contains a supported image UTI, route
    /// it through the inline-image stage→tag→insert path. Otherwise falls through to
    /// NSTextView's default drop handling.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if richActionsTarget != nil {
            let pboard = sender.draggingPasteboard
            let types = pboard.types?.map(\.rawValue) ?? []
            let payload = ComposePasteboardImage.imagePayload(
                types: types,
                data: { uti in pboard.data(forType: NSPasteboard.PasteboardType(uti)) }
            )
            if let payload {
                // Position the caret at the drop point before inserting.
                if let layout = layoutManager, let container = textContainer {
                    let point = convert(sender.draggingLocation, from: nil)
                    let glyphIndex = layout.glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: nil)
                    let charIndex = layout.characterIndexForGlyph(at: glyphIndex)
                    setSelectedRange(NSRange(location: charIndex, length: 0))
                }
                if brevInsertImagePayload(data: payload.data, mimeType: payload.mimeType) {
                    return true
                }
            }
        }
        // Files dropped onto the body become regular attachments instead of
        // NSTextView's default file-attachment cell in the text.
        if let onDropFileURLs {
            let urls = Self.droppedFileURLs(from: sender.draggingPasteboard)
            if !urls.isEmpty {
                onFileDragTargetChanged?(false)
                onDropFileURLs(urls)
                return true
            }
        }
        return super.performDragOperation(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if onDropFileURLs != nil, !Self.droppedFileURLs(from: sender.draggingPasteboard).isEmpty {
            onFileDragTargetChanged?(true)
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if onDropFileURLs != nil, !Self.droppedFileURLs(from: sender.draggingPasteboard).isEmpty {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onFileDragTargetChanged?(false)
        super.draggingExited(sender)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onFileDragTargetChanged?(false)
        super.draggingEnded(sender)
    }

    /// File URLs carried by a drag pasteboard (empty when the drag has none).
    private static func droppedFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        return objects ?? []
    }
}

// MARK: - NSViewRepresentable

private struct PlatformComposeBodyEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var richHTML: String?
    @Binding var selection: ComposeBodyTextSelection?
    @Binding var insertionPoint: ComposeBodyInsertionPoint?
    let bodyFormat: ComposeBodyFormat
    let appearance: ComposeBodyAppearance
    var htmlPublicationFlushBox: ComposeHTMLPublicationFlushBox?
    let textCheckingConfiguration: ComposeTextCheckingConfiguration
    var fontFamily: MailboxFontFamily
    var textSize: MailboxTextSize
    var inlineImageRegistry: ComposeInlineImageRegistry?
    var onRequestLinkSheet: ((ComposeLinkSheetInput) -> Void)?
    /// Unused on macOS; kept for call-site parity with the iOS representable.
    var iosRichTextTargetBox: ComposeIOSRichTextTargetBox?
    var onDropFileURLs: (([URL]) -> Void)?
    var onFileDragTargetChanged: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            richHTML: $richHTML,
            selection: $selection,
            insertionPoint: $insertionPoint,
            inlineImageRegistry: inlineImageRegistry,
            onRequestLinkSheet: onRequestLinkSheet,
            htmlPublicationFlushBox: htmlPublicationFlushBox
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true

        let textView = ComposeRichTextView()
        textView.richActionsTarget = context.coordinator
        textView.onDropFileURLs = onDropFileURLs
        textView.onFileDragTargetChanged = onFileDragTargetChanged
        textView.delegate = context.coordinator
        textView.isRichText = bodyFormat == .richTextHTML
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.string = text
        if bodyFormat == .richTextHTML {
            context.coordinator.publishRichHTML(from: textView)
        }

        scrollView.documentView = textView
        applyAppearance(to: scrollView, textView: textView)
        applyTextChecking(to: textView)
        context.coordinator.textView = textView
        context.coordinator.updateSelection(from: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposeRichTextView else {
            return
        }
        context.coordinator.isUpdatingFromSwiftUI = true
        let shouldUseRichText = bodyFormat == .richTextHTML
        if textView.isRichText != shouldUseRichText {
            textView.isRichText = shouldUseRichText
        }
        applyAppearance(to: scrollView, textView: textView)
        applyTextChecking(to: textView)
        if textView.string != text {
            textView.string = text
            context.coordinator.updateSelection(from: textView)
        }
        if shouldUseRichText {
            context.coordinator.publishRichHTML(from: textView)
        } else if richHTML != nil {
            richHTML = nil
        }
        // Keep callbacks in sync across SwiftUI re-renders.
        context.coordinator.inlineImageRegistry = inlineImageRegistry
        context.coordinator.onRequestLinkSheet = onRequestLinkSheet
        context.coordinator.attachHTMLPublicationFlushBox(htmlPublicationFlushBox)
        textView.onDropFileURLs = onDropFileURLs
        textView.onFileDragTargetChanged = onFileDragTargetChanged
        context.coordinator.isUpdatingFromSwiftUI = false
    }

    private func applyAppearance(to scrollView: NSScrollView, textView: NSTextView) {
        let appKitAppearance = NSAppearance(named: appearance.nsAppearanceName)
        // Transparent so the window's (opacity-aware) surface shows through. The
        // body then matches the rest of the window instead of painting its own
        // opaque slate/paper rectangle, and it inherits the app's translucency.
        scrollView.appearance = appKitAppearance
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.appearance = appKitAppearance
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        textView.appearance = appKitAppearance
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        let font = ComposeEditorTypography.nsFont(family: fontFamily, textSize: textSize)
        let textColor = NSColor(appearance.editorTheme.textPrimary.color)
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = NSColor(appearance.editorTheme.accent.color)
        var typing = textView.typingAttributes
        typing[.font] = font
        typing[.foregroundColor] = textColor
        textView.typingAttributes = typing
    }

    private func applyTextChecking(to textView: NSTextView) {
        textView.isContinuousSpellCheckingEnabled = textCheckingConfiguration.spellChecking == .native
        textView.isGrammarCheckingEnabled = textCheckingConfiguration.grammarChecking == .native
        textView.isAutomaticSpellingCorrectionEnabled = textCheckingConfiguration.autocorrection == .native
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate, ComposeBodyEditorRichActions {
        @Binding private var text: String
        @Binding private var richHTML: String?
        @Binding private var selection: ComposeBodyTextSelection?
        @Binding private var insertionPoint: ComposeBodyInsertionPoint?
        weak var textView: ComposeRichTextView?
        var isUpdatingFromSwiftUI = false
        /// Shared registry — updated on every SwiftUI re-render via `updateNSView`.
        var inlineImageRegistry: ComposeInlineImageRegistry?
        /// Callback to request the link insertion sheet from the parent view.
        var onRequestLinkSheet: ((ComposeLinkSheetInput) -> Void)?
        var htmlPublicationFlushBox: ComposeHTMLPublicationFlushBox?
        private lazy var htmlPublicationController = ComposeHTMLPublicationController<NSAttributedString>(
            serialize: { ComposeRichTextHTMLSerializer.html(from: $0) },
            publish: { [weak self] html in self?.richHTML = html }
        )

        init(
            text: Binding<String>,
            richHTML: Binding<String?>,
            selection: Binding<ComposeBodyTextSelection?>,
            insertionPoint: Binding<ComposeBodyInsertionPoint?>,
            inlineImageRegistry: ComposeInlineImageRegistry?,
            onRequestLinkSheet: ((ComposeLinkSheetInput) -> Void)?,
            htmlPublicationFlushBox: ComposeHTMLPublicationFlushBox?
        ) {
            _text = text
            _richHTML = richHTML
            _selection = selection
            _insertionPoint = insertionPoint
            self.inlineImageRegistry = inlineImageRegistry
            self.onRequestLinkSheet = onRequestLinkSheet
            self.htmlPublicationFlushBox = htmlPublicationFlushBox
            super.init()
            htmlPublicationFlushBox?.flush = { [weak self] in self?.flushPendingHTML() }
        }

        func attachHTMLPublicationFlushBox(_ box: ComposeHTMLPublicationFlushBox?) {
            htmlPublicationFlushBox?.flush = nil
            htmlPublicationFlushBox = box
            box?.flush = { [weak self] in self?.flushPendingHTML() }
        }

        func flushPendingHTML() {
            if let textView, textView.isRichText {
                publishRichHTML(from: textView)
            }
            htmlPublicationController.flush()
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI, let textView = notification.object as? NSTextView else {
                return
            }
            text = textView.string
            publishRichHTML(from: textView)
            updateSelection(from: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            updateSelection(from: textView)
        }

        func updateSelection(from textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            selection = ComposeBodyTextSelection(
                bodyText: textView.string,
                nsRange: selectedRange
            )
            insertionPoint = ComposeBodyInsertionPoint(
                bodyText: textView.string,
                nsRange: selectedRange
            )
        }

        func publishRichHTML(from textView: NSTextView) {
            guard textView.isRichText else {
                htmlPublicationController.cancel()
                richHTML = nil
                return
            }
            htmlPublicationController.schedule(textView.attributedString())
        }

        // MARK: - Responder-chain actions (#251)

        // The Coordinator conforms to `ComposeBodyEditorRichActions` and is called
        // from `ComposeRichTextView` (the first responder) which forwards those
        // selectors here via `richActionsTarget`. The coordinator is NOT itself in
        // the NSResponder chain — it is only a delegate.

        func brevInsertLink(_ sender: Any?) {
            requestLinkSheet()
        }

        func brevToggleBulletedList(_ sender: Any?) {
            toggleList(.disc)
        }

        func brevToggleNumberedList(_ sender: Any?) {
            toggleList(.decimal)
        }

        func brevInsertImage(_ sender: Any?) {
            insertImageFromPanel()
        }

        func brevApplyLink(_ sender: Any?) {
            if let payload = sender as? ComposeBodyEditorLinkPayload {
                applyLink(url: payload.url, displayText: payload.displayText)
            }
        }

        func brevRemoveLink(_ sender: Any?) {
            removeLink()
        }

        @discardableResult
        func brevInsertImagePayload(data: Data, mimeType: String) -> Bool {
            insertInlineImage(data: data, mimeType: mimeType)
        }

        // MARK: - List toggling

        /// Toggles `NSTextList` with `markerFormat` on all paragraphs that
        /// intersect the current selection. If every affected paragraph already
        /// has the given marker the list is cleared; otherwise it is applied.
        func toggleList(_ markerFormat: NSTextList.MarkerFormat) {
            guard let textView, let textStorage = textView.textStorage else { return }
            let selectedRange = textView.selectedRange()

            // Collect all paragraph ranges that overlap the selection.
            let nsString = textStorage.string as NSString
            var paragraphRanges: [NSRange] = []
            var pos = selectedRange.location
            let end = selectedRange.upperBound == 0 ? selectedRange.location : selectedRange.upperBound
            while pos <= end {
                let paraRange = nsString.paragraphRange(for: NSRange(location: pos, length: 0))
                paragraphRanges.append(paraRange)
                let next = paraRange.upperBound
                if next <= pos { break }
                pos = next
                if pos > end { break }
            }
            guard !paragraphRanges.isEmpty else { return }

            // Determine whether all paragraphs already carry this marker (toggle off).
            let allHaveList = paragraphRanges.allSatisfy { range -> Bool in
                guard range.length > 0 else { return false }
                guard
                    let style = textStorage.attribute(
                        .paragraphStyle, at: range.location, effectiveRange: nil
                    ) as? NSParagraphStyle,
                    let first = style.textLists.first,
                    first.markerFormat == markerFormat
                else {
                    return false
                }
                return true
            }

            textStorage.beginEditing()
            for paraRange in paragraphRanges {
                guard paraRange.length > 0 else { continue }
                let existing = textStorage.attribute(
                    .paragraphStyle, at: paraRange.location, effectiveRange: nil
                ) as? NSParagraphStyle

                let mutableStyle = existing.flatMap { $0.mutableCopy() as? NSMutableParagraphStyle }
                    ?? NSMutableParagraphStyle()

                if allHaveList {
                    // Remove the list.
                    mutableStyle.textLists = []
                    mutableStyle.headIndent = 0
                    mutableStyle.firstLineHeadIndent = 0
                } else {
                    // Apply the list.
                    let list = NSTextList(markerFormat: markerFormat, options: 0)
                    mutableStyle.textLists = [list]
                    mutableStyle.headIndent = 24
                    mutableStyle.firstLineHeadIndent = 8
                }
                textStorage.addAttribute(.paragraphStyle, value: mutableStyle, range: paraRange)
            }
            textStorage.endEditing()

            // Re-publish so bodyHTML reflects the new list state.
            publishRichHTML(from: textView)
            text = textView.string
        }

        // MARK: - Link insertion

        /// Reads the current selection / existing link and presents the sheet.
        private func requestLinkSheet() {
            guard let textView else { return }
            let selectedRange = textView.selectedRange()
            let storage = textView.textStorage

            var existingURL: URL?
            var selectionText = ""

            if selectedRange.length > 0, let storage {
                selectionText = (storage.string as NSString).substring(with: selectedRange)
                // Check if the selection already carries a link attribute.
                if let linkAttr = storage.attribute(.link, at: selectedRange.location, effectiveRange: nil) {
                    if let url = linkAttr as? URL {
                        existingURL = url
                    } else if let nsurl = linkAttr as? NSURL, let url = nsurl as URL? {
                        existingURL = url
                    }
                }
            }

            let input = ComposeLinkSheetInput(
                urlString: existingURL?.absoluteString ?? "",
                displayText: selectionText,
                hasExistingLink: existingURL != nil
            )
            onRequestLinkSheet?(input)
        }

        /// Applies the link URL and display text to the current selection.
        ///
        /// If the selection is empty, inserts the display text (or URL string) at
        /// the caret and applies the link to it. If a selection is present, wraps
        /// it with the link attribute (and replaces the text with displayText when
        /// the display text field is non-empty and differs from the selection).
        func applyLink(url: URL, displayText: String) {
            guard let textView, let textStorage = textView.textStorage else { return }
            let selectedRange = textView.selectedRange()

            // Resolve the text to use as the link label.
            let labelText: String
            if !displayText.isEmpty {
                labelText = displayText
            } else if selectedRange.length > 0 {
                labelText = (textStorage.string as NSString).substring(with: selectedRange)
            } else {
                labelText = url.absoluteString
            }

            textStorage.beginEditing()

            // Build an attributed string for the label with the link attribute.
            let baseFont = textView.font ?? NSFont.preferredFont(forTextStyle: .body)
            let attributed = NSMutableAttributedString(string: labelText, attributes: [
                .font: baseFont,
                .link: url,
            ])

            if selectedRange.length > 0 {
                textStorage.replaceCharacters(in: selectedRange, with: attributed)
            } else {
                textStorage.insert(attributed, at: selectedRange.location)
            }

            textStorage.endEditing()

            // Move the caret past the inserted link.
            let newLocation = selectedRange.location + (labelText as NSString).length
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))

            publishRichHTML(from: textView)
            text = textView.string
            updateSelection(from: textView)
        }

        /// Clears the `.link` attribute from the current selection.
        func removeLink() {
            guard let textView, let textStorage = textView.textStorage else { return }
            let selectedRange = textView.selectedRange()
            guard selectedRange.length > 0 else { return }

            textStorage.beginEditing()
            textStorage.removeAttribute(.link, range: selectedRange)
            textStorage.endEditing()

            publishRichHTML(from: textView)
            text = textView.string
            updateSelection(from: textView)
        }

        // MARK: - Image insertion

        /// Opens an NSOpenPanel for image files, stages the image via the registry,
        /// builds an NSTextAttachment, tags it with the cid attribute, and inserts
        /// it at the current caret position.
        func insertImageFromPanel() {
            guard textView != nil, inlineImageRegistry != nil else { return }

            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.png, .jpeg, .gif]
            panel.allowsMultipleSelection = false
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.prompt = String(localized: "Insert", bundle: .module)
            panel.message = String(localized: "Choose an image to insert inline.", bundle: .module)

            guard panel.runModal() == .OK, let url = panel.url else { return }

            guard let data = try? Data(contentsOf: url) else { return }

            // Derive the MIME type from the file extension.
            let ext = url.pathExtension.lowercased()
            let mimeType: String
            switch ext {
            case "jpg", "jpeg": mimeType = "image/jpeg"
            case "gif": mimeType = "image/gif"
            default: mimeType = "image/png"
            }

            insertInlineImage(data: data, mimeType: mimeType)
        }

        /// Stages `data` via the registry, builds an `NSTextAttachment`, tags it with
        /// the cid attribute, and inserts it at the current caret position.
        ///
        /// Used by both the toolbar Insert Image panel path and the paste/drop path.
        /// Returns `true` if the image was successfully staged and inserted, `false`
        /// if validation (type / size) rejected it.
        @discardableResult
        func insertInlineImage(data: Data, mimeType: String) -> Bool {
            guard let textView, let registry = inlineImageRegistry else { return false }

            guard let staged = registry.stage(data: data, mimeType: mimeType, makeID: {
                // Use a deterministic-looking but unique content-ID.
                UUID().uuidString + "@brev.inline"
            }) else {
                // Validation failed (unsupported type or too large) — silently no-op.
                return false
            }

            // Build the attachment with the raw image data.
            let attachment = NSTextAttachment()
            if let image = NSImage(data: data) {
                attachment.image = image
            }

            let attachmentString = NSMutableAttributedString(attachment: attachment)
            // Tag the attachment character with the content-ID so the serializer
            // emits <img src="cid:…"> instead of raw bytes.
            let attachmentRange = NSRange(location: 0, length: attachmentString.length)
            attachmentString.addAttribute(
                ComposeInlineImageAttribute.contentID,
                value: staged.contentID,
                range: attachmentRange
            )

            guard let textStorage = textView.textStorage else { return false }
            let insertionRange = textView.selectedRange()

            textStorage.beginEditing()
            textStorage.insert(attachmentString, at: insertionRange.location)
            textStorage.endEditing()

            // Move caret past the attachment.
            textView.setSelectedRange(
                NSRange(location: insertionRange.location + attachmentString.length, length: 0)
            )

            publishRichHTML(from: textView)
            text = textView.string
            updateSelection(from: textView)
            return true
        }
    }
}

private extension ComposeBodyAppearance {
    var nsAppearanceName: NSAppearance.Name {
        switch self {
        case .system:
            return .aqua
        case .light:
            return .aqua
        case .dark:
            return .darkAqua
        }
    }
}
#else
import UIKit

private struct PlatformComposeBodyEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var richHTML: String?
    @Binding var selection: ComposeBodyTextSelection?
    @Binding var insertionPoint: ComposeBodyInsertionPoint?
    let bodyFormat: ComposeBodyFormat
    let appearance: ComposeBodyAppearance
    var htmlPublicationFlushBox: ComposeHTMLPublicationFlushBox?
    let textCheckingConfiguration: ComposeTextCheckingConfiguration
    var fontFamily: MailboxFontFamily
    var textSize: MailboxTextSize
    var inlineImageRegistry: ComposeInlineImageRegistry?
    var onRequestLinkSheet: ((ComposeLinkSheetInput) -> Void)?
    var iosRichTextTargetBox: ComposeIOSRichTextTargetBox?
    /// Unused on iOS: the SwiftUI drop target in `ComposeView` handles drops.
    var onDropFileURLs: (([URL]) -> Void)?
    var onFileDragTargetChanged: ((Bool) -> Void)?

    private var isRichText: Bool { bodyFormat == .richTextHTML }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            richHTML: $richHTML,
            selection: $selection,
            insertionPoint: $insertionPoint,
            isRichText: isRichText,
            inlineImageRegistry: inlineImageRegistry,
            onRequestLinkSheet: onRequestLinkSheet,
            htmlPublicationFlushBox: htmlPublicationFlushBox,
            targetBox: iosRichTextTargetBox
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.allowsEditingTextAttributes = isRichText
        textView.text = text
        applyTextChecking(to: textView)
        context.coordinator.textView = textView
        context.coordinator.isRichText = isRichText
        context.coordinator.inlineImageRegistry = inlineImageRegistry
        context.coordinator.onRequestLinkSheet = onRequestLinkSheet
        context.coordinator.attachHTMLPublicationFlushBox(htmlPublicationFlushBox)
        context.coordinator.targetBox = iosRichTextTargetBox
        iosRichTextTargetBox?.target = context.coordinator
        context.coordinator.publishRichHTML(from: textView)
        context.coordinator.updateSelection(from: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.isUpdatingFromSwiftUI = true
        context.coordinator.isRichText = isRichText
        context.coordinator.inlineImageRegistry = inlineImageRegistry
        context.coordinator.onRequestLinkSheet = onRequestLinkSheet
        context.coordinator.targetBox = iosRichTextTargetBox
        iosRichTextTargetBox?.target = context.coordinator
        textView.allowsEditingTextAttributes = isRichText
        if textView.text != text {
            textView.text = text
            context.coordinator.updateSelection(from: textView)
        }
        if isRichText {
            context.coordinator.publishRichHTML(from: textView)
        } else if richHTML != nil {
            richHTML = nil
        }
        let font = ComposeEditorTypography.uiFont(family: fontFamily, textSize: textSize)
        let textColor = UIColor(appearance.editorTheme.textPrimary.color)
        textView.tintColor = UIColor(appearance.editorTheme.accent.color)
        textView.backgroundColor = .clear
        // Setting UITextView.font replaces fonts across attributed runs — only
        // apply the mailbox chrome font in plain mode (or when the body is empty).
        if !isRichText || textView.text.isEmpty {
            textView.font = font
            textView.textColor = textColor
        }
        var typing = textView.typingAttributes
        if typing[.font] == nil || !isRichText {
            typing[.font] = font
        }
        if typing[.foregroundColor] == nil || !isRichText {
            typing[.foregroundColor] = textColor
        }
        textView.typingAttributes = typing
        applyTextChecking(to: textView)
        context.coordinator.isUpdatingFromSwiftUI = false
    }

    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        if coordinator.targetBox?.target === coordinator {
            coordinator.targetBox?.target = nil
        }
    }

    private func applyTextChecking(to textView: UITextView) {
        textView.spellCheckingType = textCheckingConfiguration.spellChecking == .native ? .default : .no
        textView.autocorrectionType = textCheckingConfiguration.autocorrection == .native ? .default : .no
    }

    final class Coordinator: NSObject, UITextViewDelegate, ComposeIOSRichTextTarget {
        @Binding private var text: String
        @Binding private var richHTML: String?
        @Binding private var selection: ComposeBodyTextSelection?
        @Binding private var insertionPoint: ComposeBodyInsertionPoint?
        weak var textView: UITextView?
        weak var targetBox: ComposeIOSRichTextTargetBox?
        var isUpdatingFromSwiftUI = false
        var isRichText: Bool
        var inlineImageRegistry: ComposeInlineImageRegistry?
        var onRequestLinkSheet: ((ComposeLinkSheetInput) -> Void)?
        var htmlPublicationFlushBox: ComposeHTMLPublicationFlushBox?
        private lazy var htmlPublicationController = ComposeHTMLPublicationController<NSAttributedString>(
            serialize: { ComposeRichTextHTMLSerializer.html(from: $0) },
            publish: { [weak self] html in self?.richHTML = html }
        )

        init(
            text: Binding<String>,
            richHTML: Binding<String?>,
            selection: Binding<ComposeBodyTextSelection?>,
            insertionPoint: Binding<ComposeBodyInsertionPoint?>,
            isRichText: Bool,
            inlineImageRegistry: ComposeInlineImageRegistry?,
            onRequestLinkSheet: ((ComposeLinkSheetInput) -> Void)?,
            htmlPublicationFlushBox: ComposeHTMLPublicationFlushBox?,
            targetBox: ComposeIOSRichTextTargetBox?
        ) {
            _text = text
            _richHTML = richHTML
            _selection = selection
            _insertionPoint = insertionPoint
            self.isRichText = isRichText
            self.inlineImageRegistry = inlineImageRegistry
            self.onRequestLinkSheet = onRequestLinkSheet
            self.htmlPublicationFlushBox = htmlPublicationFlushBox
            super.init()
            htmlPublicationFlushBox?.flush = { [weak self] in self?.flushPendingHTML() }
            self.targetBox = targetBox
        }

        func attachHTMLPublicationFlushBox(_ box: ComposeHTMLPublicationFlushBox?) {
            htmlPublicationFlushBox?.flush = nil
            htmlPublicationFlushBox = box
            box?.flush = { [weak self] in self?.flushPendingHTML() }
        }

        func flushPendingHTML() {
            if let textView, isRichText {
                publishRichHTML(from: textView)
            }
            htmlPublicationController.flush()
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdatingFromSwiftUI else { return }
            text = textView.text
            publishRichHTML(from: textView)
            updateSelection(from: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            updateSelection(from: textView)
        }

        func updateSelection(from textView: UITextView) {
            let selectedRange = textView.selectedRange
            selection = ComposeBodyTextSelection(
                bodyText: textView.text,
                nsRange: selectedRange
            )
            insertionPoint = ComposeBodyInsertionPoint(
                bodyText: textView.text,
                nsRange: selectedRange
            )
        }

        func publishRichHTML(from textView: UITextView) {
            guard isRichText else {
                htmlPublicationController.cancel()
                richHTML = nil
                return
            }
            htmlPublicationController.schedule(textView.attributedText)
        }

        // MARK: ComposeIOSRichTextTarget

        func toggleBold() {
            toggleFontTrait(.traitBold)
        }

        func toggleItalic() {
            toggleFontTrait(.traitItalic)
        }

        func toggleBulletedList() {
            toggleList(.disc)
        }

        func toggleNumberedList() {
            toggleList(.decimal)
        }

        func toggleUnderline() {
            toggleUnderlineStyle()
        }

        func clearFormatting() {
            clearRichFormatting()
        }

        /// Toggles single-line underline over the selection, or for future
        /// typing when nothing is selected — same shape as the trait toggles.
        private func toggleUnderlineStyle() {
            guard let textView else { return }
            let textStorage = textView.textStorage
            let selectedRange = textView.selectedRange
            if selectedRange.length == 0 {
                var typing = textView.typingAttributes
                if typing[.underlineStyle] != nil {
                    typing.removeValue(forKey: .underlineStyle)
                } else {
                    typing[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                textView.typingAttributes = typing
                return
            }
            var allUnderlined = true
            textStorage.enumerateAttribute(.underlineStyle, in: selectedRange, options: []) { value, _, _ in
                if value == nil { allUnderlined = false }
            }
            textStorage.beginEditing()
            if allUnderlined {
                textStorage.removeAttribute(.underlineStyle, range: selectedRange)
            } else {
                textStorage.addAttribute(
                    .underlineStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: selectedRange
                )
            }
            textStorage.endEditing()
            text = textView.text
            publishRichHTML(from: textView)
            updateSelection(from: textView)
        }

        /// Resets the selection (or the whole body when nothing is selected)
        /// to plain body text: default font, no underline, no link, no list
        /// indentation. Mirrors macOS Edit > Format > Clear Formatting.
        private func clearRichFormatting() {
            guard let textView else { return }
            let textStorage = textView.textStorage
            let range = textView.selectedRange.length > 0
                ? textView.selectedRange
                : NSRange(location: 0, length: textStorage.length)
            guard range.length > 0 else { return }
            textStorage.beginEditing()
            textStorage.addAttribute(.font, value: UIFont.preferredFont(forTextStyle: .body), range: range)
            textStorage.removeAttribute(.underlineStyle, range: range)
            textStorage.removeAttribute(.link, range: range)
            textStorage.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, paraRange, _ in
                guard let style = value as? NSParagraphStyle, !style.textLists.isEmpty else { return }
                let mutable = style.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                mutable.textLists = []
                mutable.headIndent = 0
                mutable.firstLineHeadIndent = 0
                textStorage.addAttribute(.paragraphStyle, value: mutable, range: paraRange)
            }
            textStorage.endEditing()
            text = textView.text
            publishRichHTML(from: textView)
            updateSelection(from: textView)
        }

        func requestLinkSheet() {
            guard let textView else { return }
            let selectedRange = textView.selectedRange
            var existingURL: URL?
            var selectionText = ""
            if selectedRange.length > 0 {
                selectionText = (textView.text as NSString).substring(with: selectedRange)
                if let linkAttr = textView.attributedText.attribute(
                    .link, at: selectedRange.location, effectiveRange: nil
                ) {
                    if let url = linkAttr as? URL {
                        existingURL = url
                    } else if let nsurl = linkAttr as? NSURL, let url = nsurl as URL? {
                        existingURL = url
                    }
                }
            }
            onRequestLinkSheet?(
                ComposeLinkSheetInput(
                    urlString: existingURL?.absoluteString ?? "",
                    displayText: selectionText,
                    hasExistingLink: existingURL != nil
                )
            )
        }

        func applyLink(url: URL, displayText: String) {
            // `UITextView.textStorage` is non-optional, unlike AppKit's, so it
            // cannot take part in the optional binding above.
            guard let textView else { return }
            let textStorage = textView.textStorage
            let selectedRange = textView.selectedRange
            let labelText: String
            if !displayText.isEmpty {
                labelText = displayText
            } else if selectedRange.length > 0 {
                labelText = (textStorage.string as NSString).substring(with: selectedRange)
            } else {
                labelText = url.absoluteString
            }

            let baseFont = textView.typingAttributes[.font] as? UIFont
                ?? textView.font
                ?? .preferredFont(forTextStyle: .body)
            let attributed = NSMutableAttributedString(string: labelText, attributes: [
                .font: baseFont,
                .link: url,
            ])

            textStorage.beginEditing()
            if selectedRange.length > 0 {
                textStorage.replaceCharacters(in: selectedRange, with: attributed)
            } else {
                textStorage.insert(attributed, at: selectedRange.location)
            }
            textStorage.endEditing()

            let newLocation = selectedRange.location + (labelText as NSString).length
            textView.selectedRange = NSRange(location: newLocation, length: 0)
            text = textView.text
            publishRichHTML(from: textView)
            updateSelection(from: textView)
        }

        func removeLink() {
            // `UITextView.textStorage` is non-optional, unlike AppKit's, so it
            // cannot take part in the optional binding above.
            guard let textView else { return }
            let textStorage = textView.textStorage
            let selectedRange = textView.selectedRange
            guard selectedRange.length > 0 else { return }
            textStorage.beginEditing()
            textStorage.removeAttribute(.link, range: selectedRange)
            textStorage.endEditing()
            text = textView.text
            publishRichHTML(from: textView)
            updateSelection(from: textView)
        }

        @discardableResult
        func insertInlineImage(data: Data, mimeType: String) -> Bool {
            guard isRichText,
                  let textView,
                  let registry = inlineImageRegistry,
                  let image = UIImage(data: data),
                  let staged = registry.stage(data: data, mimeType: mimeType, makeID: {
                      UUID().uuidString + "@brev.inline"
                  }) else {
                return false
            }

            let attachment = NSTextAttachment()
            attachment.image = image
            let availableWidth = max(
                textView.bounds.width
                    - textView.textContainerInset.left
                    - textView.textContainerInset.right
                    - (textView.textContainer.lineFragmentPadding * 2),
                1
            )
            if image.size.width > availableWidth {
                let scale = availableWidth / image.size.width
                attachment.bounds = CGRect(
                    x: 0,
                    y: 0,
                    width: availableWidth,
                    height: image.size.height * scale
                )
            }

            let attachmentString = NSMutableAttributedString(attachment: attachment)
            attachmentString.addAttribute(
                ComposeInlineImageAttribute.contentID,
                value: staged.contentID,
                range: NSRange(location: 0, length: attachmentString.length)
            )

            let insertionRange = textView.selectedRange
            textView.textStorage.beginEditing()
            textView.textStorage.replaceCharacters(in: insertionRange, with: attachmentString)
            textView.textStorage.endEditing()

            textView.selectedRange = NSRange(
                location: insertionRange.location + attachmentString.length,
                length: 0
            )
            text = textView.text
            publishRichHTML(from: textView)
            updateSelection(from: textView)
            return true
        }

        private func toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
            // `UITextView.textStorage` is non-optional, unlike AppKit's, so it
            // cannot take part in the optional binding above.
            guard let textView else { return }
            let textStorage = textView.textStorage
            let selectedRange = textView.selectedRange
            if selectedRange.length == 0 {
                var typing = textView.typingAttributes
                let current = (typing[.font] as? UIFont)
                    ?? textView.font
                    ?? .preferredFont(forTextStyle: .body)
                typing[.font] = current.brevToggling(trait)
                textView.typingAttributes = typing
                return
            }

            textStorage.beginEditing()
            textStorage.enumerateAttribute(.font, in: selectedRange, options: []) { value, range, _ in
                let current = (value as? UIFont)
                    ?? textView.font
                    ?? .preferredFont(forTextStyle: .body)
                textStorage.addAttribute(.font, value: current.brevToggling(trait), range: range)
            }
            textStorage.endEditing()
            text = textView.text
            publishRichHTML(from: textView)
            updateSelection(from: textView)
        }

        private func toggleList(_ markerFormat: NSTextList.MarkerFormat) {
            // `UITextView.textStorage` is non-optional, unlike AppKit's, so it
            // cannot take part in the optional binding above.
            guard let textView else { return }
            let textStorage = textView.textStorage
            let selectedRange = textView.selectedRange
            let nsString = textStorage.string as NSString
            var paragraphRanges: [NSRange] = []
            var pos = selectedRange.location
            let end = selectedRange.upperBound == 0 ? selectedRange.location : selectedRange.upperBound
            while pos <= end {
                let paraRange = nsString.paragraphRange(for: NSRange(location: pos, length: 0))
                paragraphRanges.append(paraRange)
                let next = paraRange.upperBound
                if next <= pos { break }
                pos = next
                if pos > end { break }
            }
            guard !paragraphRanges.isEmpty else { return }

            let allHaveList = paragraphRanges.allSatisfy { range -> Bool in
                guard range.length > 0 else { return false }
                guard
                    let style = textStorage.attribute(
                        .paragraphStyle, at: range.location, effectiveRange: nil
                    ) as? NSParagraphStyle,
                    let first = style.textLists.first,
                    first.markerFormat == markerFormat
                else {
                    return false
                }
                return true
            }

            textStorage.beginEditing()
            for paraRange in paragraphRanges {
                guard paraRange.length > 0 else { continue }
                let existing = textStorage.attribute(
                    .paragraphStyle, at: paraRange.location, effectiveRange: nil
                ) as? NSParagraphStyle
                let mutableStyle = existing.flatMap { $0.mutableCopy() as? NSMutableParagraphStyle }
                    ?? NSMutableParagraphStyle()
                if allHaveList {
                    mutableStyle.textLists = []
                    mutableStyle.headIndent = 0
                    mutableStyle.firstLineHeadIndent = 0
                } else {
                    mutableStyle.textLists = [NSTextList(markerFormat: markerFormat, options: 0)]
                    mutableStyle.headIndent = 24
                    mutableStyle.firstLineHeadIndent = 8
                }
                textStorage.addAttribute(.paragraphStyle, value: mutableStyle, range: paraRange)
            }
            textStorage.endEditing()

            text = textView.text
            publishRichHTML(from: textView)
            updateSelection(from: textView)
        }
    }
}

private extension UIFont {
    /// Returns a copy of this font with `trait` toggled on or off.
    func brevToggling(_ trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        var traits = fontDescriptor.symbolicTraits
        if traits.contains(trait) {
            traits.remove(trait)
        } else {
            traits.insert(trait)
        }
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
#endif
