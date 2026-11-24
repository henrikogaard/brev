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
import BrevThemes
import Foundation
import SnapshotTesting
import SwiftUI
import Testing

/// macOS snapshot coverage for `ComposeView`'s header field rows.
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh the baselines.
@Suite("ComposeView macOS snapshots")
@MainActor
struct ComposeViewMacOSSnapshotTests {
    @Test("compose header renders aligned optional and subject rows", arguments: ["light", "dark"])
    func composeChrome(mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let backend = MockBackend(supportsScheduledSend: false)
        let accountID = backend.account.id
        let senderOptions = [
            ComposeSenderOption(
                sourceID: nil,
                accountID: accountID,
                displayName: "Henrik Øgård",
                email: "henrik@ogard.example",
                subtitle: "Primary"
            ),
            ComposeSenderOption(
                sourceID: nil,
                accountID: accountID,
                displayName: nil,
                email: "henrik@ogard.no",
                subtitle: "Alias"
            ),
        ]
        let view = ComposeView(
            backend: backend,
            from: Correspondent(name: "Henrik Øgård", email: "henrik@ogard.example"),
            senderOptions: senderOptions,
            prefill: ComposePrefill(
                cc: ["team@acme.example"],
                bcc: ["audit@acme.example"]
            )
        )
        .frame(width: 700, height: 560)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 700, height: 560)
        host.view.needsLayout = true
        host.view.layoutSubtreeIfNeeded()

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 700, height: 560)),
            named: "compose-chrome-\(mode)",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    /// The collapsed Cc/Bcc row keeps From in the To/Subject label column and
    /// its divider runs to the edge like the other rows (#279 native QA).
    @Test("collapsed compose header keeps one label column", arguments: ["light", "dark"])
    func collapsedHeader(mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let view = ComposeView(
            backend: MockBackend(supportsScheduledSend: false),
            from: Correspondent(name: "Henrik Øgård", email: "henrik@ogard.example"),
            prefill: ComposePrefill(to: ["qa-recipient@example.org"], subject: "Header alignment")
        )
        .frame(width: 700, height: 560)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 700, height: 560)
        host.view.needsLayout = true
        host.view.layoutSubtreeIfNeeded()

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 700, height: 560)),
            named: "compose-collapsed-header-\(mode)",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    /// Reopened drafts with nested/styled quoted HTML display a clean, theme-aware
    /// preserved-quote indicator and expandable read-only preview below the editor (#278).
    @Test("preserved quoted HTML section renders collapsed and expanded", arguments: ["light", "dark"])
    func preservedQuoteSection(mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let quoteHTML = """
        <div class="gmail_quote">\
        <div class="gmail_attr">On Mon, Jan 1, 2026, Ada &lt;ada@example.org&gt; wrote:</div>\
        <blockquote type="cite" style="border-left: 2px solid #ccc">\
        <div>Let's review the release checklist tomorrow morning.</div>\
        <blockquote><div>Earlier thread note from Henrik.</div></blockquote>\
        </blockquote>\
        </div>
        """
        let view = VStack(alignment: .leading, spacing: 16) {
            ComposePreservedQuoteSection(
                preservedQuotedHTML: quoteHTML,
                renderingMode: mode == "dark" ? .dark : .original,
                initiallyExpanded: false
            )
            ComposePreservedQuoteSection(
                preservedQuotedHTML: quoteHTML,
                renderingMode: mode == "dark" ? .dark : .original,
                initiallyExpanded: true
            )
        }
        .frame(width: 700, height: 340, alignment: .top)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .htmlBodyRenderTarget(.staticSnapshot)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 700, height: 340)
        host.view.needsLayout = true
        host.view.layoutSubtreeIfNeeded()

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 700, height: 340)),
            named: "compose-preserved-quote-\(mode)",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    /// Integrated compose body layout combining the editable compose editor area
    /// above an expanded long preserved quote: the quote preview stays capped so
    /// the editor retains usable vertical space in both light and dark modes (#278).
    @Test("compose body keeps editable space above long expanded preserved quote", arguments: ["light", "dark"])
    func editorWithExpandedLongPreservedQuote(mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let paragraphs = (1 ... 14).map { index in
            "<p>Quoted thread paragraph \(index): confirming milestone notes, migration checks, and follow-up dates for the release.</p>"
        }.joined()
        let longQuoteHTML = """
        <div class="gmail_quote">\
        <div class="gmail_attr">On Mon, Jan 1, 2026, Ada wrote:</div>\
        <blockquote type="cite" style="border-left: 2px solid #ccc">\(paragraphs)</blockquote>\
        </div>
        """
        let replyText = "Hi Ada,\n\nThanks for sending the updated rollout schedule. Everything looks good for Thursday."
        let view = VStack(spacing: 0) {
            ComposeBodyEditor(
                text: .constant(replyText),
                richHTML: .constant(nil),
                selection: .constant(nil),
                insertionPoint: .constant(nil),
                bodyFormat: .richTextHTML,
                appearance: mode == "dark" ? .dark : .light,
                textCheckingConfiguration: ComposeTextCheckingPolicy.configuration(isEnabled: false)
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            ComposePreservedQuoteSection(
                preservedQuotedHTML: longQuoteHTML,
                renderingMode: mode == "dark" ? .dark : .original,
                initiallyExpanded: true
            )
        }
        .frame(width: 700, height: 560)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .htmlBodyRenderTarget(.staticSnapshot)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 700, height: 560)
        host.view.needsLayout = true
        host.view.layoutSubtreeIfNeeded()

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 700, height: 560)),
            named: "compose-editor-with-long-preserved-quote-\(mode)",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    /// Rich HTML compose v2 visual coverage: heading, inline formatting,
    /// rounded code-block backdrop (`drawCodeBlockBackgrounds`), native
    /// `NSTextTable`, and an inline `cid:` PNG attachment in light and dark modes.
    @Test("rich compose editor renders headings, code blocks, native tables, and inline images", arguments: ["light", "dark"])
    func richComposeElements(mode: String) throws {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let appearance: ComposeBodyAppearance = mode == "dark" ? .dark : .light
        let badgePNG = try #require(Self.makeSnapshotBadgePNG(theme: theme))
        let inlineAttachment = MIMEMessageAttachment(
            id: "snap-inline-1",
            filename: "badge.png",
            mimeType: "image/png",
            data: badgePNG,
            isInline: true,
            contentID: "snap-badge@brev.inline"
        )
        let richHTML = """
        <h1>Launch Readiness</h1>\
        <p>Check <strong>inline formatting</strong>, <code>swift test</code>, and <s>legacy flow</s>.</p>\
        <pre><code>let status = "ready"\nprint("Brev compose v2")</code></pre>\
        <table><thead><tr><th>Area</th><th>Owner</th></tr></thead>\
        <tbody><tr><td>Tables &amp; Code</td><td>Henrik</td></tr>\
        <tr><td>Inline Images</td><td>Ada</td></tr></tbody></table>\
        <p><img src="cid:snap-badge@brev.inline" alt="Badge"></p>
        """
        let style = ComposeRichHTMLAttributedBuilder.Style.default(
            fontFamily: .system,
            textSize: .medium,
            theme: appearance.editorTheme,
            maxImageWidth: 640
        )
        let attributed = try #require(ComposeRichHTMLAttributedBuilder.attributedString(
            from: richHTML,
            inlineAttachments: ["snap-badge@brev.inline": inlineAttachment],
            style: style,
            strict: true
        ))
        let view = ComposeBodyEditor(
            text: .constant(attributed.string),
            richHTML: .constant(richHTML),
            selection: .constant(nil),
            insertionPoint: .constant(nil),
            bodyFormat: .richTextHTML,
            appearance: appearance,
            textCheckingConfiguration: ComposeTextCheckingPolicy.configuration(isEnabled: false),
            restoredAttributedText: attributed
        )
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(width: 700, height: 520, alignment: .topLeading)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 700, height: 520)
        host.view.needsLayout = true
        host.view.layoutSubtreeIfNeeded()

        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 700, height: 520)),
            named: "rich-compose-elements-\(mode)",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    private static func makeSnapshotBadgePNG(theme: BrevTheme) -> Data? {
        let size = NSSize(width: 120, height: 36)
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        NSColor(theme.accent.color).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor(theme.bgPrimary.color)
        ]
        let label = NSString(string: "Inline PNG")
        let labelSize = label.size(withAttributes: attrs)
        label.draw(
            at: NSPoint(x: (size.width - labelSize.width) / 2, y: (size.height - labelSize.height) / 2),
            withAttributes: attrs
        )
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif
