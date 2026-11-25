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
import BrevDesign
import BrevThemes
import SwiftUI
import UniformTypeIdentifiers

private func updateAttributedEditorText(_ text: String, storage: NSMutableAttributedString) {
    let previous = storage.string as NSString
    let incoming = text as NSString
    let prefixLength = zip(storage.string.unicodeScalars, text.unicodeScalars)
        .prefix { $0.0 == $0.1 }
        .reduce(0) { $0 + ($1.0.value > 0xFFFF ? 2 : 1) }
    let previousTail = previous.substring(from: prefixLength)
    let incomingTail = incoming.substring(from: prefixLength)
    let suffixLength = zip(previousTail.unicodeScalars.reversed(), incomingTail.unicodeScalars.reversed())
        .prefix { $0.0 == $0.1 }
        .reduce(0) { $0 + ($1.0.value > 0xFFFF ? 2 : 1) }
    let replacedRange = NSRange(location: prefixLength, length: previous.length - prefixLength - suffixLength)
    let incomingRange = NSRange(location: prefixLength, length: incoming.length - prefixLength - suffixLength)
    storage.replaceCharacters(in: replacedRange, with: incoming.substring(with: incomingRange))
}

/// Holds the active macOS editor's rich actions so ComposeView can call them
/// directly instead of through the key window's responder chain. Empty on iOS,
/// which uses `ComposeIOSRichTextTargetBox`.
@MainActor
final class ComposeMacRichTextTargetBox {
    #if os(macOS)
    weak var target: ComposeBodyEditorRichActions?
    #endif
}

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
    /// Called when an inline image insert/paste/drop is rejected for unsupported format or size limit.
    var onInlineImageRejected: ((String) -> Void)?
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
    /// Read-only quoted-original region of the body (replies/forwards); the
    /// platform editor refuses text changes landing inside it.
    var quoteProtection: ComposeQuoteProtection?
    /// Asks the iOS text view to take keyboard focus (and place the caret);
    /// ignored on macOS, where the window's first responder logic applies.
    var focusRequest: ComposeBodyFocusRequest?
    /// Owned by ComposeView so the link sheet reaches the macOS editor even when
    /// the sheet left keyboard focus on another field. Unused on iOS.
    var macRichTextTargetBox: ComposeMacRichTextTargetBox?
    var restoredAttributedText: NSAttributedString?

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
            onInlineImageRejected: onInlineImageRejected,
            onRequestLinkSheet: onRequestLinkSheet,
            iosRichTextTargetBox: iosRichTextTargetBox,
            onDropFileURLs: onDropFileURLs,
            onFileDragTargetChanged: onFileDragTargetChanged,
            quoteProtection: quoteProtection,
            focusRequest: focusRequest,
            macRichTextTargetBox: macRichTextTargetBox,
            restoredAttributedText: restoredAttributedText
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
    /// Toggles bold on the selection, or for the next typed text.
    func brevToggleBold(_ sender: Any?)
    /// Toggles italic on the selection, or for the next typed text.
    func brevToggleItalic(_ sender: Any?)
    /// Toggles strikethrough on the selection, or for the next typed text.
    func brevToggleStrikethrough(_ sender: Any?)
    /// Toggles Heading 1 on the selected paragraphs.
    func brevToggleHeading1(_ sender: Any?)
    /// Toggles Heading 2 on the selected paragraphs.
    func brevToggleHeading2(_ sender: Any?)
    /// Toggles Heading 3 on the selected paragraphs.
    func brevToggleHeading3(_ sender: Any?)
    /// Toggles inline code styling on the selection, or for the next typed text.
    func brevToggleInlineCode(_ sender: Any?)
    /// Toggles a `<pre><code>` code block on the selected paragraphs.
    func brevToggleCodeBlock(_ sender: Any?)
    /// Inserts a semantic 2x2 table at the current caret.
    func brevInsertTable(_ sender: Any?)
    /// Resets the selection, or the whole body, to plain body text.
    func brevClearFormatting(_ sender: Any?)
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
    /// Sanitizes raw pasted HTML and inserts the resulting semantic attributed text.
    @discardableResult
    func brevInsertSanitizedHTML(_ rawHTML: String) -> Bool
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
    /// Read-only reply-quote character range, set by `applyQuoteStyling`.
    /// Drawn as an accent vertical bar, Apple Mail style, in `drawBackground`.
    var quoteBarRange: NSRange? {
        didSet { needsDisplay = true }
    }

    var quoteBarColor: NSColor?
    var codeBlockBackgroundColor: NSColor?
    var codeBlockBorderColor: NSColor?

    /// Distinguishes untouched empty-editor defaults from authored typing fonts.
    fileprivate var lastAppearanceFont: NSFont?
    /// Tracks the last theme-derived foreground color applied to this editor so
    /// appearance switches update default text without clobbering custom colors.
    fileprivate var lastAppliedTextColor: NSColor?

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        if let textStorage, let layoutManager, let container = textContainer {
            drawCodeBlockBackgrounds(
                textStorage: textStorage,
                layoutManager: layoutManager,
                container: container
            )
            if let quoteBarRange, NSMaxRange(quoteBarRange) <= textStorage.length {
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: quoteBarRange,
                    actualCharacterRange: nil
                )
                var barRect = layoutManager.boundingRect(
                    forGlyphRange: glyphRange,
                    in: container
                )
                barRect.origin.x += textContainerOrigin.x + 2
                barRect.origin.y += textContainerOrigin.y
                let bar = NSRect(x: barRect.minX, y: barRect.minY, width: 3, height: barRect.height)
                (quoteBarColor ?? NSColor.controlAccentColor).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
    }

    private func drawCodeBlockBackgrounds(
        textStorage: NSTextStorage,
        layoutManager: NSLayoutManager,
        container: NSTextContainer
    ) {
        guard textStorage.length > 0,
              let fillColor = codeBlockBackgroundColor else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var blockRanges: [NSRange] = []
        var activeID: String?
        var activeRange: NSRange?

        textStorage.enumerateAttribute(
            ComposeRichTextAttribute.codeBlockID,
            in: fullRange,
            options: []
        ) { value, range, _ in
            if let id = value as? String {
                if activeID == id, let existing = activeRange {
                    activeRange = NSUnionRange(existing, range)
                } else {
                    if let existing = activeRange {
                        blockRanges.append(existing)
                    }
                    activeID = id
                    activeRange = range
                }
            } else if let existing = activeRange {
                blockRanges.append(existing)
                activeID = nil
                activeRange = nil
            }
        }
        if let existing = activeRange {
            blockRanges.append(existing)
        }

        for range in blockRanges {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }
            var box = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            box.origin.x = textContainerOrigin.x
            box.origin.y += textContainerOrigin.y - 3
            box.size.width = max(container.containerSize.width, box.width)
            box.size.height += 6
            let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
            fillColor.setFill()
            path.fill()
            if let borderColor = codeBlockBorderColor {
                borderColor.setStroke()
                path.lineWidth = 0.5
                path.stroke()
            }
        }
    }

    func brevToggleBold(_ sender: Any?) {
        richActionsTarget?.brevToggleBold(sender)
    }

    func brevToggleItalic(_ sender: Any?) {
        richActionsTarget?.brevToggleItalic(sender)
    }

    func brevToggleStrikethrough(_ sender: Any?) {
        richActionsTarget?.brevToggleStrikethrough(sender)
    }

    func brevToggleHeading1(_ sender: Any?) {
        richActionsTarget?.brevToggleHeading1(sender)
    }

    func brevToggleHeading2(_ sender: Any?) {
        richActionsTarget?.brevToggleHeading2(sender)
    }

    func brevToggleHeading3(_ sender: Any?) {
        richActionsTarget?.brevToggleHeading3(sender)
    }

    func brevToggleInlineCode(_ sender: Any?) {
        richActionsTarget?.brevToggleInlineCode(sender)
    }

    func brevToggleCodeBlock(_ sender: Any?) {
        richActionsTarget?.brevToggleCodeBlock(sender)
    }

    func brevInsertTable(_ sender: Any?) {
        richActionsTarget?.brevInsertTable(sender)
    }

    func brevClearFormatting(_ sender: Any?) {
        richActionsTarget?.brevClearFormatting(sender)
    }

    /// Cmd-B, Cmd-I and Cmd-U format the focused body. Without this they fall
    /// through to the main menu, where Cmd-U toggles a message's read state.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRichText,
              window?.firstResponder === self,
              event.type == .keyDown,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b": brevToggleBold(nil)
        case "i": brevToggleItalic(nil)
        case "u": underline(nil)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

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

    @discardableResult
    func brevInsertSanitizedHTML(_ rawHTML: String) -> Bool {
        richActionsTarget?.brevInsertSanitizedHTML(rawHTML) ?? false
    }

    // MARK: - Paste override (#251, #3)

    /// Intercepts paste in rich mode:
    /// 1. Supported inline image UTIs (PNG/JPEG/GIF/WebP) route through the
    ///    inline-image stage→tag→insert path.
    /// 2. Rich HTML pasteboard payloads route through `ComposeHTMLPasteSanitizer`
    ///    and `ComposeRichHTMLAttributedBuilder` so pasted markup never fetches
    ///    remote images or overrides Brev's theme colors.
    /// 3. Everything else falls through to default NSTextView plain/text paste.
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if isRichText, richActionsTarget != nil {
            let types = pboard.types?.map(\.rawValue) ?? []
            if let payload = ComposePasteboardImage.imagePayload(
                types: types,
                data: { uti in pboard.data(forType: NSPasteboard.PasteboardType(uti)) }
            ) {
                let sniffedMIME = ComposeInlineImageData.mimeType(for: payload.data) ?? payload.mimeType
                _ = brevInsertImagePayload(data: payload.data, mimeType: sniffedMIME)
                return true
            }
            if type == .html || pboard.types?.contains(.html) == true,
               let rawHTML = pboard.string(forType: .html) {
                if brevInsertSanitizedHTML(rawHTML) {
                    return true
                }
                // Oversized or unsanitizable HTML fails closed to plain text
                // instead of reaching AppKit's WebKit HTML paste importer.
                if let plain = pboard.string(forType: .string) {
                    insertText(plain, replacementRange: selectedRange())
                    return true
                }
                return false
            }
        }
        return super.readSelection(from: pboard, type: type)
    }

    // MARK: - Drag-and-drop override (#251, #3)

    /// Intercepts drop: if the drag pasteboard contains a supported image UTI, route
    /// it through the inline-image stage→tag→insert path. Otherwise falls through to
    /// file attachment drop or NSTextView's default drop handling.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if isRichText, richActionsTarget != nil {
            let pboard = sender.draggingPasteboard
            let types = pboard.types?.map(\.rawValue) ?? []
            if let payload = ComposePasteboardImage.imagePayload(
                types: types,
                data: { uti in pboard.data(forType: NSPasteboard.PasteboardType(uti)) }
            ) {
                // Position the caret at the drop point before inserting.
                if let layout = layoutManager, let container = textContainer {
                    let point = convert(sender.draggingLocation, from: nil)
                    let glyphIndex = layout.glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: nil)
                    let charIndex = layout.characterIndexForGlyph(at: glyphIndex)
                    setSelectedRange(NSRange(location: charIndex, length: 0))
                }
                let sniffedMIME = ComposeInlineImageData.mimeType(for: payload.data) ?? payload.mimeType
                if brevInsertImagePayload(data: payload.data, mimeType: sniffedMIME) {
                    return true
                }
                return false
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
    @Environment(\.isEnabled) private var isEnabled
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
    var onInlineImageRejected: ((String) -> Void)?
    var onRequestLinkSheet: ((ComposeLinkSheetInput) -> Void)?
    /// Unused on macOS; kept for call-site parity with the iOS representable.
    var iosRichTextTargetBox: ComposeIOSRichTextTargetBox?
    var onDropFileURLs: (([URL]) -> Void)?
    var onFileDragTargetChanged: ((Bool) -> Void)?
    var quoteProtection: ComposeQuoteProtection?
    /// Unused on macOS.
    var focusRequest: ComposeBodyFocusRequest?
    var macRichTextTargetBox: ComposeMacRichTextTargetBox?
    var restoredAttributedText: NSAttributedString?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            richHTML: $richHTML,
            selection: $selection,
            insertionPoint: $insertionPoint,
            inlineImageRegistry: inlineImageRegistry,
            onInlineImageRejected: onInlineImageRejected,
            onRequestLinkSheet: onRequestLinkSheet,
            htmlPublicationFlushBox: htmlPublicationFlushBox,
            appearance: appearance,
            fontFamily: fontFamily,
            textSize: textSize
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true

        let textView = ComposeRichTextView()
        textView.richActionsTarget = context.coordinator
        macRichTextTargetBox?.target = context.coordinator
        textView.onDropFileURLs = onDropFileURLs
        textView.onFileDragTargetChanged = onFileDragTargetChanged
        textView.delegate = context.coordinator
        textView.isRichText = bodyFormat == .richTextHTML
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = isEnabled
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 0, height: 0)
        // No hidden 5 pt padding, so body text lines up with the header labels.
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        applyAppearance(to: scrollView, textView: textView)
        textView.string = text
        if let restoredAttributedText, bodyFormat == .richTextHTML, let storage = textView.textStorage {
            storage.setAttributedString(restoredAttributedText)
            // The HTML importer sets its own default font (Times); keep only the emphasis.
            ComposeEditorTypography.applyBaseFont(
                ComposeEditorTypography.nsFont(family: fontFamily, textSize: textSize),
                to: storage
            )
            applyAppearance(to: scrollView, textView: textView)
        }
        textView.setAccessibilityLabel(String(localized: "Message body", bundle: .module))
        if bodyFormat == .richTextHTML {
            context.coordinator.publishRichHTML(from: textView)
        }

        scrollView.documentView = textView
        applyQuoteStyling(to: textView)
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
        textView.isEditable = isEnabled
        let shouldUseRichText = bodyFormat == .richTextHTML
        if textView.isRichText != shouldUseRichText {
            textView.isRichText = shouldUseRichText
        }
        applyAppearance(to: scrollView, textView: textView)
        applyTextChecking(to: textView)
        if !(textView.string as NSString).isEqual(to: text) {
            if shouldUseRichText, let storage = textView.textStorage, storage.length > 0 {
                updateAttributedEditorText(text, storage: storage)
            } else {
                textView.string = text
            }
            context.coordinator.updateSelection(from: textView)
        }
        if shouldUseRichText {
            context.coordinator.publishRichHTML(from: textView)
        } else if richHTML != nil {
            richHTML = nil
        }
        // Keep callbacks in sync across SwiftUI re-renders.
        context.coordinator.inlineImageRegistry = inlineImageRegistry
        context.coordinator.onInlineImageRejected = onInlineImageRejected
        context.coordinator.onRequestLinkSheet = onRequestLinkSheet
        context.coordinator.appearance = appearance
        context.coordinator.fontFamily = fontFamily
        context.coordinator.textSize = textSize
        macRichTextTargetBox?.target = context.coordinator
        context.coordinator.quoteProtection = quoteProtection
        context.coordinator.attachHTMLPublicationFlushBox(htmlPublicationFlushBox)
        textView.onDropFileURLs = onDropFileURLs
        textView.onFileDragTargetChanged = onFileDragTargetChanged
        applyQuoteStyling(to: textView)
        context.coordinator.isUpdatingFromSwiftUI = false
    }

    private func applyAppearance(to scrollView: NSScrollView, textView: ComposeRichTextView) {
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
        let theme = appearance.editorTheme
        let font = ComposeEditorTypography.nsFont(family: fontFamily, textSize: textSize)
        let textColor = NSColor(theme.textPrimary.color)
        let surfaceSecondaryColor = NSColor(theme.bgSecondary.color)
        let borderColor = NSColor(theme.border.color)
        let previousTextColor = textView.lastAppliedTextColor
        let typingFont = textView.typingAttributes[.font] as? NSFont
        let usesDefaultTypingFont = textView.lastAppearanceFont == nil || typingFont == nil
            || typingFont == textView.lastAppearanceFont
        // Setting the font replaces attributed fonts; rich content owns its typography.
        if !textView.isRichText || (textView.string.isEmpty && usesDefaultTypingFont) {
            textView.font = font
        }
        if !textView.isRichText || textView.string.isEmpty {
            textView.textColor = textColor
        } else if let storage = textView.textStorage {
            let savedSelection = textView.selectedRange()
            ComposeRichHTMLAttributedBuilder.reapplyAppearanceColors(
                to: storage,
                theme: theme,
                previousTextColor: previousTextColor
            )
            if textView.selectedRange() != savedSelection,
               NSMaxRange(savedSelection) <= storage.length {
                textView.setSelectedRange(savedSelection)
            }
        }
        textView.lastAppearanceFont = font
        textView.lastAppliedTextColor = textColor
        textView.insertionPointColor = NSColor(theme.accent.color)
        textView.codeBlockBackgroundColor = surfaceSecondaryColor
        textView.codeBlockBorderColor = borderColor
        var typing = textView.typingAttributes
        if typing[.font] == nil || !textView.isRichText {
            typing[.font] = font
        }
        let currentTypingColor = typing[.foregroundColor] as? NSColor
        if !textView.isRichText
            || ComposeRichHTMLAttributedBuilder.isDefaultComposeTextColor(
                currentTypingColor,
                previousTextColor: previousTextColor
            ) {
            typing[.foregroundColor] = textColor
        }
        if (typing[ComposeRichTextAttribute.inlineCode] as? Bool) == true {
            typing[.backgroundColor] = surfaceSecondaryColor
        }
        textView.typingAttributes = typing
        textView.needsDisplay = true
    }

    private func applyTextChecking(to textView: NSTextView) {
        textView.isContinuousSpellCheckingEnabled = textCheckingConfiguration.spellChecking == .native
        textView.isGrammarCheckingEnabled = textCheckingConfiguration.grammarChecking == .native
        textView.isAutomaticSpellingCorrectionEnabled = textCheckingConfiguration.autocorrection == .native
    }

    /// Mutes the read-only quoted-original region so the quote reads as a
    /// quote block instead of blending into the reply text, and hands the
    /// range to the text view so it can draw the accent quote bar.
    private func applyQuoteStyling(to textView: NSTextView) {
        guard let quoteProtection,
              let storage = textView.textStorage,
              let protected = ComposeQuoteEditGuard.protectedRange(
                  in: storage.string as NSString,
                  protection: quoteProtection
              ),
              protected.length > 0 else {
            (textView as? ComposeRichTextView)?.quoteBarRange = nil
            return
        }
        storage.addAttribute(
            .foregroundColor,
            value: NSColor(appearance.editorTheme.textTertiary.color),
            range: protected
        )
        let quoteIndent = NSMutableParagraphStyle()
        quoteIndent.headIndent = 12
        quoteIndent.firstLineHeadIndent = 12
        storage.addAttribute(
            .paragraphStyle,
            value: quoteIndent,
            range: protected
        )
        if let richTextView = textView as? ComposeRichTextView {
            richTextView.quoteBarRange = protected
            richTextView.quoteBarColor = NSColor(appearance.editorTheme.accent.color)
        }
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
        /// Reports inline-image format or byte-cap rejections to ComposeView.
        var onInlineImageRejected: ((String) -> Void)?
        /// Callback to request the link insertion sheet from the parent view.
        var onRequestLinkSheet: ((ComposeLinkSheetInput) -> Void)?
        var htmlPublicationFlushBox: ComposeHTMLPublicationFlushBox?
        var appearance: ComposeBodyAppearance
        var fontFamily: MailboxFontFamily
        var textSize: MailboxTextSize
        /// Read-only quoted-original region; edits inside it are refused.
        var quoteProtection: ComposeQuoteProtection?
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
            onInlineImageRejected: ((String) -> Void)?,
            onRequestLinkSheet: ((ComposeLinkSheetInput) -> Void)?,
            htmlPublicationFlushBox: ComposeHTMLPublicationFlushBox?,
            appearance: ComposeBodyAppearance,
            fontFamily: MailboxFontFamily,
            textSize: MailboxTextSize
        ) {
            _text = text
            _richHTML = richHTML
            _selection = selection
            _insertionPoint = insertionPoint
            self.inlineImageRegistry = inlineImageRegistry
            self.onInlineImageRejected = onInlineImageRejected
            self.onRequestLinkSheet = onRequestLinkSheet
            self.htmlPublicationFlushBox = htmlPublicationFlushBox
            self.appearance = appearance
            self.fontFamily = fontFamily
            self.textSize = textSize
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

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let storage = textView.textStorage else { return true }
            return ComposeQuoteEditGuard.allows(
                changeRange: affectedCharRange,
                in: storage.mutableString,
                protection: quoteProtection
            )
        }

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
            // Borrow the live text storage instead of copying `textView.string`
            // twice per caret movement; only the selected range materializes.
            let characters = textView.textStorage?.mutableString
                ?? textView.string as NSString
            selection = ComposeBodyTextSelection(
                characters: characters,
                nsRange: selectedRange
            )
            insertionPoint = ComposeBodyInsertionPoint(
                characterCount: characters.length,
                nsRange: selectedRange
            )
        }

        func publishRichHTML(from textView: NSTextView) {
            guard textView.isRichText else {
                htmlPublicationController.cancel()
                richHTML = nil
                return
            }
            // Lazy: the attributed-string copy is only paid when the debounce
            // actually fires, not per keystroke or SwiftUI update.
            htmlPublicationController.schedule { textView.attributedString() }
        }

        // MARK: - Responder-chain actions (#251)

        // The Coordinator conforms to `ComposeBodyEditorRichActions` and is called
        // from `ComposeRichTextView` (the first responder) which forwards those
        // selectors here via `richActionsTarget`. The coordinator is NOT itself in
        // the NSResponder chain — it is only a delegate.

        func brevToggleBold(_ sender: Any?) {
            toggleFontTrait(.bold)
        }

        func brevToggleItalic(_ sender: Any?) {
            toggleFontTrait(.italic)
        }

        func brevToggleStrikethrough(_ sender: Any?) {
            toggleStrikethrough()
        }

        func brevToggleHeading1(_ sender: Any?) {
            toggleHeading(1)
        }

        func brevToggleHeading2(_ sender: Any?) {
            toggleHeading(2)
        }

        func brevToggleHeading3(_ sender: Any?) {
            toggleHeading(3)
        }

        func brevToggleInlineCode(_ sender: Any?) {
            toggleInlineCode()
        }

        func brevToggleCodeBlock(_ sender: Any?) {
            toggleCodeBlock()
        }

        func brevInsertTable(_ sender: Any?) {
            insertDefaultTable()
        }

        func brevClearFormatting(_ sender: Any?) {
            clearRichFormatting()
        }

        func brevInsertLink(_ sender: Any?) {
            requestLinkSheet()
        }

        // MARK: - Emphasis

        private func allowsEdit(in range: NSRange, storage: NSTextStorage) -> Bool {
            ComposeQuoteEditGuard.allows(
                changeRange: range,
                in: storage.mutableString,
                protection: quoteProtection
            )
        }

        private func activeInlineContentIDs(in storage: NSTextStorage) -> Set<String> {
            var ids = Set<String>()
            let fullRange = NSRange(location: 0, length: storage.length)
            guard fullRange.length > 0 else { return ids }
            storage.enumerateAttribute(
                ComposeInlineImageAttribute.contentID,
                in: fullRange,
                options: []
            ) { value, _, _ in
                if let cid = value as? String, !cid.isEmpty {
                    ids.insert(cid)
                }
            }
            return ids
        }

        private func paragraphContainsInlineImage(_ range: NSRange, in storage: NSTextStorage) -> Bool {
            guard range.length > 0, NSMaxRange(range) <= storage.length else { return false }
            var found = false
            storage.enumerateAttribute(
                ComposeInlineImageAttribute.contentID,
                in: range,
                options: []
            ) { value, _, stop in
                if value is String {
                    found = true
                    stop.pointee = true
                }
            }
            if found { return true }
            storage.enumerateAttribute(.attachment, in: range, options: []) { value, _, stop in
                if value != nil {
                    found = true
                    stop.pointee = true
                }
            }
            return found
        }

        /// Toggles `trait` over the selection, or for the next typed text when
        /// nothing is selected. AppKit's text view has no bold/italic action of
        /// its own without a Font menu, so the Format menu needs this.
        private func toggleFontTrait(_ trait: NSFontDescriptor.SymbolicTraits) {
            guard let textView, textView.isRichText, let storage = textView.textStorage else { return }
            let fallback = textView.lastAppearanceFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            func toggled(_ font: NSFont, add: Bool) -> NSFont {
                let current = font.fontDescriptor.symbolicTraits
                let emphasis = add ? current.union(trait) : current.subtracting(trait)
                return ComposeEditorTypography.font(font, emphasis: emphasis) ?? font
            }
            let range = textView.selectedRange()
            guard allowsEdit(in: range, storage: storage) else { return }
            guard range.length > 0 else {
                let font = textView.typingAttributes[.font] as? NSFont ?? fallback
                textView.typingAttributes[.font] = toggled(font, add: !font.fontDescriptor.symbolicTraits.contains(trait))
                return
            }
            var allHaveTrait = true
            storage.enumerateAttribute(.font, in: range) { value, _, stop in
                let font = value as? NSFont ?? fallback
                if !font.fontDescriptor.symbolicTraits.contains(trait) {
                    allHaveTrait = false
                    stop.pointee = true
                }
            }
            // Routing through shouldChange/didChange keeps quote protection, undo
            // and the HTML publication in step with a typed edit.
            guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, run, _ in
                storage.addAttribute(.font, value: toggled(value as? NSFont ?? fallback, add: !allHaveTrait), range: run)
            }
            storage.endEditing()
            textView.didChangeText()
        }

        /// The whole body outside a protected reply quote, which stays as quoted.
        private func editableRange(in storage: NSTextStorage) -> NSRange {
            let all = NSRange(location: 0, length: storage.length)
            guard let quoteProtection,
                  let quote = ComposeQuoteEditGuard.protectedRange(in: storage.mutableString, protection: quoteProtection),
                  quote.length > 0 else { return all }
            switch quoteProtection.edge {
            case .bottom: return NSRange(location: 0, length: quote.location)
            case .top: return NSRange(location: NSMaxRange(quote), length: storage.length - NSMaxRange(quote))
            }
        }

        /// Resets the selection (or the editable body when nothing is selected)
        /// to plain body text: editor font, no underline, strikethrough, link,
        /// code, heading, table cell, or list formatting.
        private func clearRichFormatting() {
            guard let textView, textView.isRichText, let storage = textView.textStorage else { return }
            let base = textView.lastAppearanceFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let selected = textView.selectedRange()
            let range = selected.length > 0 ? selected : editableRange(in: storage)
            guard allowsEdit(in: selected, storage: storage),
                  allowsEdit(in: range, storage: storage) else { return }
            textView.typingAttributes[.font] = base
            textView.typingAttributes[.underlineStyle] = nil
            textView.typingAttributes[.strikethroughStyle] = nil
            textView.typingAttributes[.link] = nil
            textView.typingAttributes[.backgroundColor] = nil
            textView.typingAttributes[ComposeRichTextAttribute.inlineCode] = nil
            textView.typingAttributes[ComposeRichTextAttribute.codeBlockID] = nil
            textView.typingAttributes[ComposeRichTextAttribute.headingLevel] = nil
            textView.typingAttributes[ComposeRichTextAttribute.tableCell] = nil
            guard range.length > 0, textView.shouldChangeText(in: range, replacementString: nil) else { return }
            storage.beginEditing()
            storage.addAttribute(.font, value: base, range: range)
            storage.removeAttribute(.underlineStyle, range: range)
            storage.removeAttribute(.strikethroughStyle, range: range)
            storage.removeAttribute(.link, range: range)
            storage.removeAttribute(.backgroundColor, range: range)
            storage.removeAttribute(ComposeRichTextAttribute.inlineCode, range: range)
            storage.removeAttribute(ComposeRichTextAttribute.codeBlockID, range: range)
            storage.removeAttribute(ComposeRichTextAttribute.headingLevel, range: range)
            storage.removeAttribute(ComposeRichTextAttribute.tableCell, range: range)
            storage.enumerateAttribute(.paragraphStyle, in: range) { value, run, _ in
                guard let style = value as? NSParagraphStyle,
                      !style.textLists.isEmpty || !style.textBlocks.isEmpty || style.headIndent != 0
                      || style.firstLineHeadIndent != 0,
                      let plain = style.mutableCopy() as? NSMutableParagraphStyle else { return }
                plain.textLists = []
                plain.textBlocks = []
                plain.headIndent = 0
                plain.firstLineHeadIndent = 0
                plain.paragraphSpacingBefore = 0
                plain.paragraphSpacing = 0
                storage.addAttribute(.paragraphStyle, value: plain, range: run)
            }
            storage.endEditing()
            textView.didChangeText()
            textView.needsDisplay = true
        }

        // MARK: - Strikethrough, Headings, Code, Tables, and Sanitized Paste

        private func currentBuilderStyle(for textView: NSTextView) -> ComposeRichHTMLAttributedBuilder.Style {
            let maxWidth = max(textView.textContainer?.containerSize.width ?? 520, 240)
            return ComposeRichHTMLAttributedBuilder.Style.default(
                fontFamily: fontFamily,
                textSize: textSize,
                theme: appearance.editorTheme,
                maxImageWidth: maxWidth
            )
        }

        private func toggleStrikethrough() {
            guard let textView, textView.isRichText, let storage = textView.textStorage else { return }
            let range = textView.selectedRange()
            guard allowsEdit(in: range, storage: storage) else { return }
            guard range.length > 0 else {
                if ComposeRichTextHTMLSerializer.isStrikethrough(textView.typingAttributes) {
                    textView.typingAttributes.removeValue(forKey: .strikethroughStyle)
                } else {
                    textView.typingAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
                return
            }
            var allStruck = true
            storage.enumerateAttribute(.strikethroughStyle, in: range) { value, _, stop in
                if value == nil || (value as? NSNumber)?.intValue == 0 {
                    allStruck = false
                    stop.pointee = true
                }
            }
            guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
            storage.beginEditing()
            if allStruck {
                storage.removeAttribute(.strikethroughStyle, range: range)
            } else {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            storage.endEditing()
            textView.didChangeText()
        }

        private func toggleInlineCode() {
            guard let textView, textView.isRichText, let storage = textView.textStorage else { return }
            let base = textView.lastAppearanceFont ?? ComposeEditorTypography.nsFont(family: fontFamily, textSize: textSize)
            let mono = ComposeEditorTypography.monospacedNSFont(textSize: textSize)
            let bg = NSColor(appearance.editorTheme.bgSecondary.color)
            let range = textView.selectedRange()
            guard allowsEdit(in: range, storage: storage) else { return }
            guard range.length > 0 else {
                let isCurrentlyCode = (textView.typingAttributes[ComposeRichTextAttribute.inlineCode] as? Bool) == true
                if isCurrentlyCode {
                    textView.typingAttributes.removeValue(forKey: ComposeRichTextAttribute.inlineCode)
                    textView.typingAttributes.removeValue(forKey: .backgroundColor)
                    textView.typingAttributes[.font] = base
                } else {
                    textView.typingAttributes[ComposeRichTextAttribute.inlineCode] = true
                    textView.typingAttributes[.backgroundColor] = bg
                    textView.typingAttributes[.font] = mono
                }
                return
            }
            var allCode = true
            storage.enumerateAttribute(ComposeRichTextAttribute.inlineCode, in: range) { value, _, stop in
                if (value as? Bool) != true {
                    allCode = false
                    stop.pointee = true
                }
            }
            guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
            storage.beginEditing()
            if allCode {
                storage.removeAttribute(ComposeRichTextAttribute.inlineCode, range: range)
                storage.removeAttribute(.backgroundColor, range: range)
                storage.addAttribute(.font, value: base, range: range)
            } else {
                storage.addAttribute(ComposeRichTextAttribute.inlineCode, value: true, range: range)
                storage.addAttribute(.backgroundColor, value: bg, range: range)
                storage.addAttribute(.font, value: mono, range: range)
            }
            storage.endEditing()
            textView.didChangeText()
        }

        private func selectedParagraphRanges(in storage: NSTextStorage, selectedRange: NSRange) -> [NSRange] {
            let nsString = storage.string as NSString
            guard nsString.length > 0 else { return [] }
            if ComposeRichHTMLAttributedBuilder.isCaretAtTrailingEmptyParagraph(
                selectedRange: selectedRange,
                in: nsString
            ) {
                return []
            }
            var ranges: [NSRange] = []
            var pos = min(selectedRange.location, nsString.length - 1)
            let end = selectedRange.length == 0
                ? pos
                : min(max(selectedRange.upperBound - 1, pos), nsString.length - 1)
            while pos <= end {
                let paraRange = nsString.paragraphRange(for: NSRange(location: pos, length: 0))
                ranges.append(paraRange)
                let next = paraRange.upperBound
                if next <= pos || next >= nsString.length { break }
                pos = next
            }
            return ranges
        }

        private func toggleHeading(_ level: Int) {
            guard (1 ... 3).contains(level),
                  let textView,
                  textView.isRichText,
                  let storage = textView.textStorage else { return }
            let base = textView.lastAppearanceFont ?? ComposeEditorTypography.nsFont(family: fontFamily, textSize: textSize)
            let selected = textView.selectedRange()
            guard allowsEdit(in: selected, storage: storage) else { return }
            let paragraphs = selectedParagraphRanges(in: storage, selectedRange: selected)
            guard !paragraphs.isEmpty else {
                let isSame = (textView.typingAttributes[ComposeRichTextAttribute.headingLevel] as? Int) == level
                if isSame {
                    textView.typingAttributes.removeValue(forKey: ComposeRichTextAttribute.headingLevel)
                    textView.typingAttributes[.font] = base
                } else {
                    let scaled = NSFont(
                        descriptor: base.fontDescriptor,
                        size: base.pointSize * ComposeEditorTypography.headingScale(for: level)
                    ) ?? base
                    textView.typingAttributes[ComposeRichTextAttribute.headingLevel] = level
                    textView.typingAttributes[.font] = ComposeEditorTypography.font(scaled, emphasis: .bold) ?? scaled
                }
                return
            }

            let allMatch = paragraphs.allSatisfy { range in
                (storage.attribute(ComposeRichTextAttribute.headingLevel, at: range.location, effectiveRange: nil) as? Int)
                    == level
            }
            let unionRange = paragraphs.reduce(paragraphs[0]) { NSUnionRange($0, $1) }
            guard allowsEdit(in: unionRange, storage: storage),
                  textView.shouldChangeText(in: unionRange, replacementString: nil) else { return }
            storage.beginEditing()
            for paraRange in paragraphs {
                if allMatch {
                    storage.removeAttribute(ComposeRichTextAttribute.headingLevel, range: paraRange)
                    storage.addAttribute(.font, value: base, range: paraRange)
                } else {
                    storage.removeAttribute(ComposeRichTextAttribute.codeBlockID, range: paraRange)
                    storage.addAttribute(ComposeRichTextAttribute.headingLevel, value: level, range: paraRange)
                    let scaled = NSFont(
                        descriptor: base.fontDescriptor,
                        size: base.pointSize * ComposeEditorTypography.headingScale(for: level)
                    ) ?? base
                    let headingFont = ComposeEditorTypography.font(scaled, emphasis: .bold) ?? scaled
                    storage.addAttribute(.font, value: headingFont, range: paraRange)
                    let paraStyle = NSMutableParagraphStyle()
                    paraStyle.paragraphSpacingBefore = level == 1 ? 8 : 6
                    paraStyle.paragraphSpacing = 4
                    storage.addAttribute(.paragraphStyle, value: paraStyle, range: paraRange)
                }
            }
            storage.endEditing()
            textView.didChangeText()
            textView.needsDisplay = true
        }

        private func toggleCodeBlock() {
            guard let textView, textView.isRichText, let storage = textView.textStorage else { return }
            let base = textView.lastAppearanceFont ?? ComposeEditorTypography.nsFont(family: fontFamily, textSize: textSize)
            let mono = ComposeEditorTypography.monospacedNSFont(textSize: textSize)
            let selected = textView.selectedRange()
            guard allowsEdit(in: selected, storage: storage) else { return }
            let paragraphs = selectedParagraphRanges(in: storage, selectedRange: selected)
            guard !paragraphs.isEmpty else {
                if textView.typingAttributes[ComposeRichTextAttribute.codeBlockID] != nil {
                    textView.typingAttributes.removeValue(forKey: ComposeRichTextAttribute.codeBlockID)
                    textView.typingAttributes[.font] = base
                    textView.typingAttributes[.paragraphStyle] = NSParagraphStyle.default
                } else {
                    textView.typingAttributes[ComposeRichTextAttribute.codeBlockID] = UUID().uuidString
                    textView.typingAttributes[.font] = mono
                    textView.typingAttributes[.paragraphStyle] = ComposeRichHTMLAttributedBuilder.makeCodeBlockParagraphStyle()
                }
                return
            }

            let eligibleParagraphs = paragraphs.filter { !paragraphContainsInlineImage($0, in: storage) }
            guard !eligibleParagraphs.isEmpty else { return }

            let allCodeBlocks = eligibleParagraphs.allSatisfy { range in
                storage.attribute(ComposeRichTextAttribute.codeBlockID, at: range.location, effectiveRange: nil) != nil
            }
            let unionRange = eligibleParagraphs.reduce(eligibleParagraphs[0]) { NSUnionRange($0, $1) }
            guard allowsEdit(in: unionRange, storage: storage),
                  textView.shouldChangeText(in: unionRange, replacementString: nil) else { return }
            let blockID = UUID().uuidString
            let codeStyle = ComposeRichHTMLAttributedBuilder.makeCodeBlockParagraphStyle()
            storage.beginEditing()
            for paraRange in eligibleParagraphs {
                if allCodeBlocks {
                    storage.removeAttribute(ComposeRichTextAttribute.codeBlockID, range: paraRange)
                    storage.addAttribute(.font, value: base, range: paraRange)
                    storage.addAttribute(.paragraphStyle, value: NSParagraphStyle.default, range: paraRange)
                } else {
                    storage.removeAttribute(ComposeRichTextAttribute.headingLevel, range: paraRange)
                    storage.removeAttribute(ComposeRichTextAttribute.inlineCode, range: paraRange)
                    storage.removeAttribute(.backgroundColor, range: paraRange)
                    storage.addAttribute(ComposeRichTextAttribute.codeBlockID, value: blockID, range: paraRange)
                    storage.addAttribute(.font, value: mono, range: paraRange)
                    storage.addAttribute(.paragraphStyle, value: codeStyle.copy(), range: paraRange)
                }
            }
            storage.endEditing()
            textView.didChangeText()
            textView.needsDisplay = true
        }

        private func insertDefaultTable() {
            let headers = [
                String(localized: "Header 1", bundle: .module),
                String(localized: "Header 2", bundle: .module)
            ]
            let rows = [[
                String(localized: "Cell 1", bundle: .module),
                String(localized: "Cell 2", bundle: .module)
            ]]
            insertTable(headers: headers, rows: rows)
        }

        func insertTable(headers: [String], rows: [[String]]) {
            guard let textView, textView.isRichText, let storage = textView.textStorage else { return }
            let selected = textView.selectedRange()
            guard allowsEdit(in: selected, storage: storage) else { return }
            let style = currentBuilderStyle(for: textView)
            let tableAttr = ComposeRichHTMLAttributedBuilder.makeTableAttributedString(
                headers: headers,
                rows: rows,
                style: style
            )
            let insertion = ComposeRichHTMLAttributedBuilder.splicedInsertion(
                tableAttr,
                into: storage,
                at: selected,
                style: style
            )
            guard textView.shouldChangeText(in: selected, replacementString: insertion.string) else { return }
            storage.beginEditing()
            storage.replaceCharacters(in: selected, with: insertion)
            storage.endEditing()
            let caret = selected.location + insertion.length
            textView.setSelectedRange(NSRange(location: caret, length: 0))
            textView.didChangeText()
            textView.needsDisplay = true
        }

        @discardableResult
        func brevInsertSanitizedHTML(_ rawHTML: String) -> Bool {
            guard let textView, textView.isRichText, let storage = textView.textStorage else { return false }
            let selected = textView.selectedRange()
            guard allowsEdit(in: selected, storage: storage) else { return false }
            let allowedCIDs = Set((inlineImageRegistry?.staged ?? []).map(\.contentID))
            guard let sanitized = ComposeHTMLPasteSanitizer.sanitize(rawHTML, allowedCIDs: allowedCIDs) else {
                return false
            }
            let inlineLookup: [String: MIMEMessageAttachment] = Dictionary(
                (inlineImageRegistry?.staged ?? []).map { image in
                    (
                        ComposeInlineImageData.normalizedContentID(image.contentID),
                        MIMEMessageAttachment(
                            id: image.contentID,
                            filename: image.filename,
                            mimeType: image.mimeType,
                            data: image.data,
                            isInline: true,
                            contentID: image.contentID
                        )
                    )
                },
                uniquingKeysWith: { first, _ in first }
            )
            let style = currentBuilderStyle(for: textView)
            guard let attributed = ComposeRichHTMLAttributedBuilder.attributedString(
                from: sanitized,
                inlineAttachments: inlineLookup,
                style: style,
                strict: false
            ) else {
                return false
            }
            let insertion = ComposeRichHTMLAttributedBuilder.splicedInsertion(
                attributed,
                into: storage,
                at: selected,
                style: style
            )
            guard textView.shouldChangeText(in: selected, replacementString: insertion.string) else {
                return false
            }
            storage.beginEditing()
            storage.replaceCharacters(in: selected, with: insertion)
            storage.endEditing()
            textView.setSelectedRange(NSRange(location: selected.location + insertion.length, length: 0))
            textView.didChangeText()
            textView.needsDisplay = true
            return true
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
            guard allowsEdit(in: selectedRange, storage: textStorage) else { return }

            let paragraphRanges = selectedParagraphRanges(in: textStorage, selectedRange: selectedRange)
            guard !paragraphRanges.isEmpty else { return }
            let unionRange = paragraphRanges.reduce(paragraphRanges[0]) { NSUnionRange($0, $1) }
            guard allowsEdit(in: unionRange, storage: textStorage) else { return }

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
            guard allowsEdit(in: selectedRange, storage: textStorage) else { return }

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

            // Move the caret past the inserted link and return focus from the sheet.
            let newLocation = selectedRange.location + (labelText as NSString).length
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))
            textView.window?.makeFirstResponder(textView)

            publishRichHTML(from: textView)
            text = textView.string
            updateSelection(from: textView)
        }

        /// Clears the `.link` attribute from the current selection.
        func removeLink() {
            guard let textView, let textStorage = textView.textStorage else { return }
            let selectedRange = textView.selectedRange()
            guard selectedRange.length > 0,
                  allowsEdit(in: selectedRange, storage: textStorage) else { return }

            textStorage.beginEditing()
            textStorage.removeAttribute(.link, range: selectedRange)
            textStorage.endEditing()

            publishRichHTML(from: textView)
            text = textView.string
            updateSelection(from: textView)
        }

        // MARK: - Image insertion

        /// Opens an NSOpenPanel for image files, validates magic bytes, stages the
        /// image via the registry, builds an NSTextAttachment, tags it with the cid
        /// attribute, and inserts it at the current caret position.
        func insertImageFromPanel() {
            guard textView != nil, inlineImageRegistry != nil else { return }

            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
            panel.allowsMultipleSelection = false
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.prompt = String(localized: "Insert", bundle: .module)
            panel.message = String(localized: "Choose an image to insert inline.", bundle: .module)

            guard panel.runModal() == .OK, let url = panel.url else { return }

            guard let data = try? Data(contentsOf: url) else { return }

            guard let sniffedMIME = ComposeInlineImageData.mimeType(for: data) else {
                onInlineImageRejected?(ComposeInlineImagePolicy.unsupportedFormatMessage)
                return
            }

            insertInlineImage(data: data, mimeType: sniffedMIME)
        }

        /// Stages `data` via the registry, builds an `NSTextAttachment`, tags it with
        /// the cid attribute, and inserts it at the current caret position.
        ///
        /// Used by both the toolbar Insert Image panel path and the paste/drop path.
        /// Returns `true` if the image was successfully staged and inserted, `false`
        /// if validation (type / size) rejected it.
        @discardableResult
        func insertInlineImage(data: Data, mimeType: String) -> Bool {
            guard let textView,
                  textView.isRichText,
                  let textStorage = textView.textStorage,
                  let registry = inlineImageRegistry else { return false }

            let insertionRange = textView.selectedRange()
            guard allowsEdit(in: insertionRange, storage: textStorage) else { return false }

            let normalizedMIME = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !data.isEmpty, ComposeInlineImagePolicy.allowedMIMETypes.contains(normalizedMIME) else {
                onInlineImageRejected?(ComposeInlineImagePolicy.unsupportedFormatMessage)
                return false
            }
            let activeCIDs = activeInlineContentIDs(in: textStorage)
            guard data.count <= ComposeInlineImagePolicy.maxBytes,
                  registry.activeTotalBytes(keepingContentIDs: activeCIDs) + data.count
                  <= ComposeInlineImagePolicy.maxTotalBytes else {
                onInlineImageRejected?(ComposeInlineImagePolicy.sizeLimitExceededMessage)
                return false
            }

            guard let staged = registry.stage(
                data: data,
                mimeType: normalizedMIME,
                activeContentIDs: activeCIDs,
                makeID: { UUID().uuidString + "@brev.inline" }
            ) else {
                onInlineImageRejected?(ComposeInlineImagePolicy.sizeLimitExceededMessage)
                return false
            }

            // Build the attachment with the raw image data and fit wide images to editor width.
            let attachment = NSTextAttachment()
            if let image = NSImage(data: data) {
                attachment.image = image
                let maxWidth = max(textView.textContainer?.containerSize.width ?? 520, 240)
                if image.size.width > maxWidth, image.size.width > 0 {
                    let scale = maxWidth / image.size.width
                    attachment.bounds = CGRect(
                        x: 0,
                        y: 0,
                        width: maxWidth,
                        height: image.size.height * scale
                    )
                }
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

            guard textView.shouldChangeText(in: insertionRange, replacementString: attachmentString.string) else {
                return false
            }

            textStorage.beginEditing()
            textStorage.replaceCharacters(in: insertionRange, with: attachmentString)
            textStorage.endEditing()

            // Move caret past the attachment.
            textView.setSelectedRange(
                NSRange(location: insertionRange.location + attachmentString.length, length: 0)
            )
            textView.didChangeText()
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
    @Environment(\.isEnabled) private var isEnabled
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
    var onInlineImageRejected: ((String) -> Void)?
    var onRequestLinkSheet: ((ComposeLinkSheetInput) -> Void)?
    var iosRichTextTargetBox: ComposeIOSRichTextTargetBox?
    /// Unused on iOS: the SwiftUI drop target in `ComposeView` handles drops.
    var onDropFileURLs: (([URL]) -> Void)?
    var onFileDragTargetChanged: ((Bool) -> Void)?
    var quoteProtection: ComposeQuoteProtection?
    var focusRequest: ComposeBodyFocusRequest?
    /// Unused on iOS; kept for call-site parity with the macOS representable.
    var macRichTextTargetBox: ComposeMacRichTextTargetBox?
    var restoredAttributedText: NSAttributedString?

    private var isRichText: Bool { bodyFormat == .richTextHTML }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            richHTML: $richHTML,
            selection: $selection,
            insertionPoint: $insertionPoint,
            isRichText: isRichText,
            inlineImageRegistry: inlineImageRegistry,
            onInlineImageRejected: onInlineImageRejected,
            onRequestLinkSheet: onRequestLinkSheet,
            htmlPublicationFlushBox: htmlPublicationFlushBox,
            targetBox: iosRichTextTargetBox,
            appearance: appearance,
            fontFamily: fontFamily,
            textSize: textSize
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = ComposeBodyTextView()
        textView.delegate = context.coordinator
        textView.richPasteTarget = context.coordinator
        textView.isRichTextMode = isRichText
        textView.isEditable = isEnabled
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.allowsEditingTextAttributes = isRichText
        // Dynamic Type: the font is a `UIFontMetrics` body font, so the text
        // view rescales it when the content size category changes.
        textView.adjustsFontForContentSizeCategory = true
        context.coordinator.textView = textView
        context.coordinator.isRichText = isRichText
        context.coordinator.inlineImageRegistry = inlineImageRegistry
        context.coordinator.onRequestLinkSheet = onRequestLinkSheet
        context.coordinator.attachHTMLPublicationFlushBox(htmlPublicationFlushBox)
        context.coordinator.targetBox = iosRichTextTargetBox
        iosRichTextTargetBox?.target = context.coordinator
        context.coordinator.quoteProtection = quoteProtection
        textView.onUserInterfaceStyleDidChange = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            coordinator.applyAppearance(to: textView)
            coordinator.applyQuoteStyling(to: textView)
        }
        // Font and colour go on before the text so the initial body (a reply's
        // quote, a restored draft) is not left in UIKit's fixed default font.
        context.coordinator.applyAppearance(to: textView)
        let baseFont = ComposeEditorTypography.uiFont(
            family: fontFamily,
            textSize: textSize,
            compatibleWith: textView.traitCollection
        )
        textView.text = text
        if let restoredAttributedText, isRichText {
            textView.attributedText = restoredAttributedText
            ComposeEditorTypography.applyBaseFont(baseFont, to: textView.textStorage)
        }
        context.coordinator.applyAppearance(to: textView)
        textView.accessibilityLabel = String(localized: "Message body", bundle: .module)
        applyTextChecking(to: textView)
        context.coordinator.publishRichHTML(from: textView)
        // The selection bindings are SwiftUI state; writing them while the
        // view is being made logs "Modifying state during view update".
        context.coordinator.updateSelection(from: textView, deferringStateWrite: true)
        context.coordinator.applyQuoteStyling(to: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.isEditable = isEnabled
        context.coordinator.isUpdatingFromSwiftUI = true
        context.coordinator.isRichText = isRichText
        context.coordinator.quoteProtection = quoteProtection
        context.coordinator.inlineImageRegistry = inlineImageRegistry
        context.coordinator.onInlineImageRejected = onInlineImageRejected
        context.coordinator.onRequestLinkSheet = onRequestLinkSheet
        context.coordinator.appearance = appearance
        context.coordinator.fontFamily = fontFamily
        context.coordinator.textSize = textSize
        context.coordinator.targetBox = iosRichTextTargetBox
        iosRichTextTargetBox?.target = context.coordinator
        if let composeTextView = textView as? ComposeBodyTextView {
            composeTextView.richPasteTarget = context.coordinator
            composeTextView.isRichTextMode = isRichText
        }
        textView.allowsEditingTextAttributes = isRichText
        if !((textView.text ?? "") as NSString).isEqual(to: text) {
            if isRichText, textView.textStorage.length > 0 {
                updateAttributedEditorText(text, storage: textView.textStorage)
            } else {
                textView.text = text
            }
            context.coordinator.updateSelection(from: textView, deferringStateWrite: true)
        }
        if isRichText {
            context.coordinator.publishRichHTML(from: textView)
        } else if richHTML != nil {
            // A binding write during a view update; hop to the next turn.
            let richHTMLBinding = $richHTML
            DispatchQueue.main.async { richHTMLBinding.wrappedValue = nil }
        }
        if let composeTextView = textView as? ComposeBodyTextView {
            context.coordinator.applyAppearance(to: composeTextView)
        }
        applyTextChecking(to: textView)
        context.coordinator.applyQuoteStyling(to: textView)
        context.coordinator.isUpdatingFromSwiftUI = false
        if let focusRequest, focusRequest.id != context.coordinator.handledFocusRequestID {
            context.coordinator.handledFocusRequestID = focusRequest.id
            (textView as? ComposeBodyTextView)?.requestFocus(selection: focusRequest.selection)
        }
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
        /// The newest `ComposeBodyFocusRequest.id` already acted on.
        var handledFocusRequestID = 0
        var isRichText: Bool
        var inlineImageRegistry: ComposeInlineImageRegistry?
        var onInlineImageRejected: ((String) -> Void)?
        var onRequestLinkSheet: ((ComposeLinkSheetInput) -> Void)?
        var htmlPublicationFlushBox: ComposeHTMLPublicationFlushBox?
        var appearance: ComposeBodyAppearance
        var fontFamily: MailboxFontFamily
        var textSize: MailboxTextSize
        /// Read-only quoted-original region; edits inside it are refused.
        var quoteProtection: ComposeQuoteProtection?
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
            onInlineImageRejected: ((String) -> Void)?,
            onRequestLinkSheet: ((ComposeLinkSheetInput) -> Void)?,
            htmlPublicationFlushBox: ComposeHTMLPublicationFlushBox?,
            targetBox: ComposeIOSRichTextTargetBox?,
            appearance: ComposeBodyAppearance,
            fontFamily: MailboxFontFamily,
            textSize: MailboxTextSize
        ) {
            _text = text
            _richHTML = richHTML
            _selection = selection
            _insertionPoint = insertionPoint
            self.isRichText = isRichText
            self.inlineImageRegistry = inlineImageRegistry
            self.onInlineImageRejected = onInlineImageRejected
            self.onRequestLinkSheet = onRequestLinkSheet
            self.htmlPublicationFlushBox = htmlPublicationFlushBox
            self.appearance = appearance
            self.fontFamily = fontFamily
            self.textSize = textSize
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

        func applyAppearance(to textView: ComposeBodyTextView) {
            let targetStyle = appearance.uiUserInterfaceStyle
            if textView.overrideUserInterfaceStyle != targetStyle {
                textView.overrideUserInterfaceStyle = targetStyle
            }
            let theme = appearance.resolvedEditorTheme(for: textView.traitCollection)
            let font = ComposeEditorTypography.uiFont(
                family: fontFamily,
                textSize: textSize,
                compatibleWith: textView.traitCollection
            )
            let textColor = UIColor(theme.textPrimary.color)
            let surfaceSecondaryColor = UIColor(theme.bgSecondary.color)
            let previousTextColor = textView.lastAppliedTextColor

            textView.tintColor = UIColor(theme.accent.color)
            textView.backgroundColor = .clear

            let typingFont = textView.typingAttributes[.font] as? UIFont
            let usesDefaultTypingFont = textView.lastAppearanceFont == nil
                || typingFont == nil
                || typingFont == textView.lastAppearanceFont
            // Setting UITextView.font replaces fonts across attributed runs — only
            // apply the mailbox chrome font in plain mode or an untouched empty editor.
            if !isRichText || (textView.textStorage.length == 0 && usesDefaultTypingFont) {
                textView.font = font
            }
            if !isRichText || textView.textStorage.length == 0 {
                textView.textColor = textColor
            } else {
                let savedSelection = textView.selectedRange
                ComposeRichHTMLAttributedBuilder.reapplyAppearanceColors(
                    to: textView.textStorage,
                    theme: theme,
                    previousTextColor: previousTextColor
                )
                if textView.selectedRange != savedSelection,
                   NSMaxRange(savedSelection) <= textView.textStorage.length {
                    textView.selectedRange = savedSelection
                }
            }

            textView.lastAppearanceFont = font
            textView.lastAppliedTextColor = textColor

            var typing = textView.typingAttributes
            if typing[.font] == nil || !isRichText {
                typing[.font] = font
            }
            let currentTypingColor = typing[.foregroundColor] as? UIColor
            if !isRichText
                || ComposeRichHTMLAttributedBuilder.isDefaultComposeTextColor(
                    currentTypingColor,
                    previousTextColor: previousTextColor
                ) {
                typing[.foregroundColor] = textColor
            }
            if (typing[ComposeRichTextAttribute.inlineCode] as? Bool) == true
                || typing[ComposeRichTextAttribute.codeBlockID] != nil {
                typing[.backgroundColor] = surfaceSecondaryColor
            }
            textView.typingAttributes = typing
            textView.setNeedsDisplay()
        }

        /// Mutes the read-only quoted-original region so the quote reads as a
        /// quote block instead of blending into the reply text.
        func applyQuoteStyling(to textView: UITextView) {
            guard let quoteProtection,
                  let protected = ComposeQuoteEditGuard.protectedRange(
                      in: textView.textStorage.string as NSString,
                      protection: quoteProtection
                  ),
                  protected.length > 0 else { return }
            let theme = appearance.resolvedEditorTheme(for: textView.traitCollection)
            textView.textStorage.addAttribute(
                .foregroundColor,
                value: UIColor(theme.textTertiary.color),
                range: protected
            )
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText: String
        ) -> Bool {
            ComposeQuoteEditGuard.allows(
                changeRange: range,
                in: textView.textStorage.mutableString,
                protection: quoteProtection
            )
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

        func updateSelection(from textView: UITextView, deferringStateWrite: Bool = false) {
            if deferringStateWrite {
                // Called while SwiftUI is making/updating the representable, where
                // writing @State bindings is undefined behaviour.
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView else { return }
                    updateSelection(from: textView)
                }
                return
            }
            let selectedRange = textView.selectedRange
            // Borrow the live text storage instead of copying `textView.text`
            // twice per caret movement; only the selected range materializes.
            let characters = textView.textStorage.mutableString
            selection = ComposeBodyTextSelection(
                characters: characters,
                nsRange: selectedRange
            )
            insertionPoint = ComposeBodyInsertionPoint(
                characterCount: characters.length,
                nsRange: selectedRange
            )
        }

        func publishRichHTML(from textView: UITextView) {
            guard isRichText else {
                htmlPublicationController.cancel()
                richHTML = nil
                return
            }
            // Lazy: the attributed-string copy is only paid when the debounce
            // actually fires, not per keystroke or SwiftUI update.
            htmlPublicationController.schedule { textView.attributedText }
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

        private func allowsEdit(in range: NSRange, storage: NSTextStorage) -> Bool {
            ComposeQuoteEditGuard.allows(
                changeRange: range,
                in: storage.mutableString,
                protection: quoteProtection
            )
        }

        private func editableRange(in storage: NSTextStorage) -> NSRange {
            let all = NSRange(location: 0, length: storage.length)
            guard let quoteProtection,
                  let quote = ComposeQuoteEditGuard.protectedRange(in: storage.mutableString, protection: quoteProtection),
                  quote.length > 0 else { return all }
            switch quoteProtection.edge {
            case .bottom: return NSRange(location: 0, length: quote.location)
            case .top: return NSRange(location: NSMaxRange(quote), length: storage.length - NSMaxRange(quote))
            }
        }

        private func activeInlineContentIDs(in storage: NSTextStorage) -> Set<String> {
            var ids = Set<String>()
            let fullRange = NSRange(location: 0, length: storage.length)
            guard fullRange.length > 0 else { return ids }
            storage.enumerateAttribute(
                ComposeInlineImageAttribute.contentID,
                in: fullRange,
                options: []
            ) { value, _, _ in
                if let cid = value as? String, !cid.isEmpty {
                    ids.insert(cid)
                }
            }
            return ids
        }

        private func paragraphContainsInlineImage(_ range: NSRange, in storage: NSTextStorage) -> Bool {
            guard range.length > 0, NSMaxRange(range) <= storage.length else { return false }
            var found = false
            storage.enumerateAttribute(
                ComposeInlineImageAttribute.contentID,
                in: range,
                options: []
            ) { value, _, stop in
                if value is String {
                    found = true
                    stop.pointee = true
                }
            }
            if found { return true }
            storage.enumerateAttribute(.attachment, in: range, options: []) { value, _, stop in
                if value != nil {
                    found = true
                    stop.pointee = true
                }
            }
            return found
        }

        private func selectedParagraphRanges(in storage: NSTextStorage, selectedRange: NSRange) -> [NSRange] {
            let nsString = storage.string as NSString
            guard nsString.length > 0 else { return [] }
            if ComposeRichHTMLAttributedBuilder.isCaretAtTrailingEmptyParagraph(
                selectedRange: selectedRange,
                in: nsString
            ) {
                return []
            }
            var ranges: [NSRange] = []
            var pos = min(selectedRange.location, nsString.length - 1)
            let end = selectedRange.length == 0
                ? pos
                : min(max(selectedRange.upperBound - 1, pos), nsString.length - 1)
            while pos <= end {
                let paraRange = nsString.paragraphRange(for: NSRange(location: pos, length: 0))
                ranges.append(paraRange)
                let next = paraRange.upperBound
                if next <= pos || next >= nsString.length { break }
                pos = next
            }
            return ranges
        }

        func toggleStrikethrough() {
            guard let textView else { return }
            let textStorage = textView.textStorage
            let selectedRange = textView.selectedRange
            guard allowsEdit(in: selectedRange, storage: textStorage) else { return }
            if selectedRange.length == 0 {
                var typing = textView.typingAttributes
                if ComposeRichTextHTMLSerializer.isStrikethrough(typing) {
                    typing.removeValue(forKey: .strikethroughStyle)
                } else {
                    typing[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
                textView.typingAttributes = typing
                return
            }
            var allStruck = true
            textStorage.enumerateAttribute(.strikethroughStyle, in: selectedRange, options: []) { value, _, _ in
                if value == nil || (value as? NSNumber)?.intValue == 0 { allStruck = false }
            }
            textStorage.beginEditing()
            if allStruck {
                textStorage.removeAttribute(.strikethroughStyle, range: selectedRange)
            } else {
                textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: selectedRange)
            }
            textStorage.endEditing()
            text = textView.text
            publishRichHTML(from: textView)
            updateSelection(from: textView)
        }

        func toggleHeading(_ level: Int) {
            guard (1 ... 3).contains(level), let textView else { return }
            let textStorage = textView.textStorage
            let selected = textView.selectedRange
            guard allowsEdit(in: selected, storage: textStorage) else { return }
            let baseFont = ComposeEditorTypography.uiFont(
                family: fontFamily,
                textSize: textSize,
                compatibleWith: textView.traitCollection
            )
            let paragraphs = selectedParagraphRanges(in: textStorage, selectedRange: selected)
            guard !paragraphs.isEmpty else {
                var typing = textView.typingAttributes
                if (typing[ComposeRichTextAttribute.headingLevel] as? Int) == level {
                    typing.removeValue(forKey: ComposeRichTextAttribute.headingLevel)
                    typing[.font] = baseFont
                } else {
                    typing[ComposeRichTextAttribute.headingLevel] = level
                    let scaled = baseFont.withSize(baseFont.pointSize * ComposeEditorTypography.headingScale(for: level))
                    typing[.font] = scaled.fontDescriptor.withSymbolicTraits(.traitBold).map {
                        UIFont(descriptor: $0, size: scaled.pointSize)
                    } ?? scaled
                }
                textView.typingAttributes = typing
                return
            }
            let unionRange = paragraphs.reduce(paragraphs[0]) { NSUnionRange($0, $1) }
            guard allowsEdit(in: unionRange, storage: textStorage) else { return }
            let allMatch = paragraphs.allSatisfy { range in
                (textStorage.attribute(ComposeRichTextAttribute.headingLevel, at: range.location, effectiveRange: nil) as? Int)
                    == level
            }
            textStorage.beginEditing()
            for paraRange in paragraphs {
                if allMatch {
                    textStorage.removeAttribute(ComposeRichTextAttribute.headingLevel, range: paraRange)
                    textStorage.addAttribute(.font, value: baseFont, range: paraRange)
                } else {
                    textStorage.removeAttribute(ComposeRichTextAttribute.codeBlockID, range: paraRange)
                    textStorage.addAttribute(ComposeRichTextAttribute.headingLevel, value: level, range: paraRange)
                    let scaled = baseFont.withSize(baseFont.pointSize * ComposeEditorTypography.headingScale(for: level))
                    let boldFont = scaled.fontDescriptor.withSymbolicTraits(.traitBold).map {
                        UIFont(descriptor: $0, size: scaled.pointSize)
                    } ?? scaled
                    textStorage.addAttribute(.font, value: boldFont, range: paraRange)
                }
            }
            textStorage.endEditing()
            text = textView.text
            publishRichHTML(from: textView)
            updateSelection(from: textView)
        }

        func toggleInlineCode() {
            guard let textView else { return }
            let textStorage = textView.textStorage
            let range = textView.selectedRange
            guard allowsEdit(in: range, storage: textStorage) else { return }
            let baseFont = ComposeEditorTypography.uiFont(
                family: fontFamily,
                textSize: textSize,
                compatibleWith: textView.traitCollection
            )
            let mono = ComposeEditorTypography.monospacedUIFont(
                textSize: textSize,
                compatibleWith: textView.traitCollection
            )
            let bg = UIColor(appearance.resolvedEditorTheme(for: textView.traitCollection).bgSecondary.color)
            if range.length == 0 {
                var typing = textView.typingAttributes
                if (typing[ComposeRichTextAttribute.inlineCode] as? Bool) == true {
                    typing.removeValue(forKey: ComposeRichTextAttribute.inlineCode)
                    typing.removeValue(forKey: .backgroundColor)
                    typing[.font] = baseFont
                } else {
                    typing[ComposeRichTextAttribute.inlineCode] = true
                    typing[.backgroundColor] = bg
                    typing[.font] = mono
                }
                textView.typingAttributes = typing
                return
            }
            var allCode = true
            textStorage.enumerateAttribute(ComposeRichTextAttribute.inlineCode, in: range, options: []) { value, _, _ in
                if (value as? Bool) != true { allCode = false }
            }
            textStorage.beginEditing()
            if allCode {
                textStorage.removeAttribute(ComposeRichTextAttribute.inlineCode, range: range)
                textStorage.removeAttribute(.backgroundColor, range: range)
                textStorage.addAttribute(.font, value: baseFont, range: range)
            } else {
                textStorage.addAttribute(ComposeRichTextAttribute.inlineCode, value: true, range: range)
                textStorage.addAttribute(.backgroundColor, value: bg, range: range)
                textStorage.addAttribute(.font, value: mono, range: range)
            }
            textStorage.endEditing()
            text = textView.text
            publishRichHTML(from: textView)
            updateSelection(from: textView)
        }

        func toggleCodeBlock() {
            guard let textView else { return }
            let textStorage = textView.textStorage
            let selected = textView.selectedRange
            guard allowsEdit(in: selected, storage: textStorage) else { return }
            let baseFont = ComposeEditorTypography.uiFont(
                family: fontFamily,
                textSize: textSize,
                compatibleWith: textView.traitCollection
            )
            let mono = ComposeEditorTypography.monospacedUIFont(
                textSize: textSize,
                compatibleWith: textView.traitCollection
            )
            let bg = UIColor(appearance.resolvedEditorTheme(for: textView.traitCollection).bgSecondary.color)
            let paragraphs = selectedParagraphRanges(in: textStorage, selectedRange: selected)
            guard !paragraphs.isEmpty else {
                var typing = textView.typingAttributes
                if typing[ComposeRichTextAttribute.codeBlockID] != nil {
                    typing.removeValue(forKey: ComposeRichTextAttribute.codeBlockID)
                    typing.removeValue(forKey: .backgroundColor)
                    typing[.font] = baseFont
                } else {
                    typing[ComposeRichTextAttribute.codeBlockID] = UUID().uuidString
                    typing[.backgroundColor] = bg
                    typing[.font] = mono
                    typing[.paragraphStyle] = ComposeRichHTMLAttributedBuilder.makeCodeBlockParagraphStyle()
                }
                textView.typingAttributes = typing
                return
            }
            let eligibleParagraphs = paragraphs.filter { !paragraphContainsInlineImage($0, in: textStorage) }
            guard !eligibleParagraphs.isEmpty else { return }
            let unionRange = eligibleParagraphs.reduce(eligibleParagraphs[0]) { NSUnionRange($0, $1) }
            guard allowsEdit(in: unionRange, storage: textStorage) else { return }
            let allBlocks = eligibleParagraphs.allSatisfy { range in
                textStorage.attribute(ComposeRichTextAttribute.codeBlockID, at: range.location, effectiveRange: nil) != nil
            }
            let blockID = UUID().uuidString
            let codeStyle = ComposeRichHTMLAttributedBuilder.makeCodeBlockParagraphStyle()
            textStorage.beginEditing()
            for paraRange in eligibleParagraphs {
                if allBlocks {
                    textStorage.removeAttribute(ComposeRichTextAttribute.codeBlockID, range: paraRange)
                    textStorage.removeAttribute(.backgroundColor, range: paraRange)
                    textStorage.addAttribute(.font, value: baseFont, range: paraRange)
                    textStorage.addAttribute(.paragraphStyle, value: NSParagraphStyle.default, range: paraRange)
                } else {
                    textStorage.removeAttribute(ComposeRichTextAttribute.headingLevel, range: paraRange)
                    textStorage.removeAttribute(ComposeRichTextAttribute.inlineCode, range: paraRange)
                    textStorage.addAttribute(ComposeRichTextAttribute.codeBlockID, value: blockID, range: paraRange)
                    textStorage.addAttribute(.backgroundColor, value: bg, range: paraRange)
                    textStorage.addAttribute(.font, value: mono, range: paraRange)
                    textStorage.addAttribute(.paragraphStyle, value: codeStyle.copy(), range: paraRange)
                }
            }
            textStorage.endEditing()
            text = textView.text
            publishRichHTML(from: textView)
            updateSelection(from: textView)
        }

        func insertTable() {
            guard isRichText, let textView else { return }
            let selected = textView.selectedRange
            guard allowsEdit(in: selected, storage: textView.textStorage) else { return }
            let style = ComposeRichHTMLAttributedBuilder.Style.default(
                fontFamily: fontFamily,
                textSize: textSize,
                theme: appearance.resolvedEditorTheme(for: textView.traitCollection)
            )
            let tableAttr = ComposeRichHTMLAttributedBuilder.makeTableAttributedString(
                headers: [
                    String(localized: "Header 1", bundle: .module),
                    String(localized: "Header 2", bundle: .module)
                ],
                rows: [[
                    String(localized: "Cell 1", bundle: .module),
                    String(localized: "Cell 2", bundle: .module)
                ]],
                style: style
            )
            let insertion = ComposeRichHTMLAttributedBuilder.splicedInsertion(
                tableAttr,
                into: textView.textStorage,
                at: selected,
                style: style
            )
            textView.textStorage.beginEditing()
            textView.textStorage.replaceCharacters(in: selected, with: insertion)
            textView.textStorage.endEditing()
            textView.selectedRange = NSRange(location: selected.location + insertion.length, length: 0)
            text = textView.text
            publishRichHTML(from: textView)
            updateSelection(from: textView)
        }

        @discardableResult
        func insertSanitizedHTML(_ rawHTML: String) -> Bool {
            guard isRichText, let textView else { return false }
            let selected = textView.selectedRange
            guard allowsEdit(in: selected, storage: textView.textStorage) else { return false }
            let allowedCIDs = Set((inlineImageRegistry?.staged ?? []).map(\.contentID))
            guard let sanitized = ComposeHTMLPasteSanitizer.sanitize(rawHTML, allowedCIDs: allowedCIDs) else {
                return false
            }
            let inlineLookup: [String: MIMEMessageAttachment] = Dictionary(
                (inlineImageRegistry?.staged ?? []).map { image in
                    (
                        ComposeInlineImageData.normalizedContentID(image.contentID),
                        MIMEMessageAttachment(
                            id: image.contentID,
                            filename: image.filename,
                            mimeType: image.mimeType,
                            data: image.data,
                            isInline: true,
                            contentID: image.contentID
                        )
                    )
                },
                uniquingKeysWith: { first, _ in first }
            )
            let style = ComposeRichHTMLAttributedBuilder.Style.default(
                fontFamily: fontFamily,
                textSize: textSize,
                theme: appearance.resolvedEditorTheme(for: textView.traitCollection)
            )
            guard let attributed = ComposeRichHTMLAttributedBuilder.attributedString(
                from: sanitized,
                inlineAttachments: inlineLookup,
                style: style,
                strict: false
            ) else {
                return false
            }
            let insertion = ComposeRichHTMLAttributedBuilder.splicedInsertion(
                attributed,
                into: textView.textStorage,
                at: selected,
                style: style
            )
            textView.textStorage.beginEditing()
            textView.textStorage.replaceCharacters(in: selected, with: insertion)
            textView.textStorage.endEditing()
            textView.selectedRange = NSRange(location: selected.location + insertion.length, length: 0)
            text = textView.text
            publishRichHTML(from: textView)
            updateSelection(from: textView)
            return true
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
            guard allowsEdit(in: selectedRange, storage: textStorage) else { return }
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

        /// Resets the selection (or the editable body when nothing is selected)
        /// to plain body text: default font, no underline, no link, no list
        /// indentation. Mirrors macOS Edit > Format > Clear Formatting.
        private func clearRichFormatting() {
            guard let textView else { return }
            let textStorage = textView.textStorage
            let selected = textView.selectedRange
            let range = selected.length > 0 ? selected : editableRange(in: textStorage)
            guard allowsEdit(in: selected, storage: textStorage),
                  allowsEdit(in: range, storage: textStorage),
                  range.length > 0 else { return }
            textStorage.beginEditing()
            textStorage.addAttribute(.font, value: UIFont.preferredFont(forTextStyle: .body), range: range)
            textStorage.removeAttribute(.underlineStyle, range: range)
            textStorage.removeAttribute(.strikethroughStyle, range: range)
            textStorage.removeAttribute(.link, range: range)
            textStorage.removeAttribute(.backgroundColor, range: range)
            textStorage.removeAttribute(ComposeRichTextAttribute.inlineCode, range: range)
            textStorage.removeAttribute(ComposeRichTextAttribute.codeBlockID, range: range)
            textStorage.removeAttribute(ComposeRichTextAttribute.headingLevel, range: range)
            textStorage.removeAttribute(ComposeRichTextAttribute.tableCell, range: range)
            textStorage.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, paraRange, _ in
                guard let style = value as? NSParagraphStyle,
                      !style.textLists.isEmpty || style.headIndent != 0 || style.firstLineHeadIndent != 0 else { return }
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
            guard allowsEdit(in: selectedRange, storage: textStorage) else { return }
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
            guard selectedRange.length > 0,
                  allowsEdit(in: selectedRange, storage: textStorage) else { return }
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
                  let registry = inlineImageRegistry else {
                return false
            }
            let insertionRange = textView.selectedRange
            guard allowsEdit(in: insertionRange, storage: textView.textStorage) else { return false }
            let normalizedMIME = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !data.isEmpty, ComposeInlineImagePolicy.allowedMIMETypes.contains(normalizedMIME) else {
                onInlineImageRejected?(ComposeInlineImagePolicy.unsupportedFormatMessage)
                return false
            }
            let activeCIDs = activeInlineContentIDs(in: textView.textStorage)
            guard data.count <= ComposeInlineImagePolicy.maxBytes,
                  registry.activeTotalBytes(keepingContentIDs: activeCIDs) + data.count
                  <= ComposeInlineImagePolicy.maxTotalBytes else {
                onInlineImageRejected?(ComposeInlineImagePolicy.sizeLimitExceededMessage)
                return false
            }
            guard let image = UIImage(data: data),
                  let staged = registry.stage(
                      data: data,
                      mimeType: normalizedMIME,
                      activeContentIDs: activeCIDs,
                      makeID: { UUID().uuidString + "@brev.inline" }
                  ) else {
                onInlineImageRejected?(ComposeInlineImagePolicy.unsupportedFormatMessage)
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
            guard allowsEdit(in: selectedRange, storage: textStorage) else { return }
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
            guard allowsEdit(in: selectedRange, storage: textStorage) else { return }
            let paragraphRanges = selectedParagraphRanges(in: textStorage, selectedRange: selectedRange)
            guard !paragraphRanges.isEmpty else { return }
            let unionRange = paragraphRanges.reduce(paragraphRanges[0]) { NSUnionRange($0, $1) }
            guard allowsEdit(in: unionRange, storage: textStorage) else { return }

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

private extension ComposeBodyAppearance {
    var uiUserInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system:
            return .unspecified
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    func resolvedEditorTheme(for traitCollection: UITraitCollection) -> BrevTheme {
        switch self {
        case .system:
            return traitCollection.userInterfaceStyle == .dark ? .brevMonoDark : .brevMonoLight
        case .light:
            return .brevMonoLight
        case .dark:
            return .brevMonoDark
        }
    }
}

/// The compose body text view. It can be asked to take focus before it is in a
/// window (the sheet is still presenting when SwiftUI first updates it), and
/// carries that request over until it is.
final class ComposeBodyTextView: UITextView {
    private var pendingFocus: (selection: NSRange?, isPending: Bool) = (nil, false)
    weak var richPasteTarget: ComposeIOSRichTextTarget?
    var isRichTextMode = false
    /// Distinguishes untouched empty-editor defaults from authored typing fonts.
    fileprivate var lastAppearanceFont: UIFont?
    /// Tracks the last theme-derived foreground color applied to this editor so
    /// appearance switches update default text without clobbering custom colors.
    fileprivate var lastAppliedTextColor: UIColor?
    /// Invoked whenever `UITraitUserInterfaceStyle` changes so `.system` editors
    /// re-resolve attributed colors immediately.
    var onUserInterfaceStyleDidChange: (() -> Void)?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: ComposeBodyTextView, _) in
            self.onUserInterfaceStyleDidChange?()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func paste(_ sender: Any?) {
        if isRichTextMode, let target = richPasteTarget {
            let pasteboard = UIPasteboard.general
            if let payload = ComposePasteboardImage.imagePayload(
                types: pasteboard.types,
                data: { uti in pasteboard.data(forPasteboardType: uti) }
            ) {
                let sniffed = ComposeInlineImageData.mimeType(for: payload.data) ?? payload.mimeType
                _ = target.insertInlineImage(data: payload.data, mimeType: sniffed)
                return
            }
            if let htmlData = pasteboard.data(forPasteboardType: UTType.html.identifier),
               let rawHTML = String(data: htmlData, encoding: .utf8) {
                if target.insertSanitizedHTML(rawHTML) {
                    return
                }
                if let plain = pasteboard.string {
                    insertText(plain)
                    return
                }
                return
            }
        }
        super.paste(sender)
    }

    /// Takes keyboard focus now, or as soon as the view joins a window.
    func requestFocus(selection: NSRange?) {
        pendingFocus = (selection, true)
        applyPendingFocus()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyPendingFocus()
    }

    private func applyPendingFocus() {
        guard pendingFocus.isPending, window != nil else { return }
        let selection = pendingFocus.selection
        pendingFocus = (nil, false)
        DispatchQueue.main.async { [weak self] in
            guard let self, window != nil else { return }
            becomeFirstResponder()
            if let selection {
                let length = (text as NSString).length
                let location = min(selection.location, length)
                selectedRange = NSRange(location: location, length: min(selection.length, length - location))
            }
        }
    }
}
#endif
