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
@testable import BrevMail
import BrevThemes
import Foundation
import Testing

@Suite("HTMLBodyDocument")
struct HTMLBodyDocumentTests {
    #if os(macOS)
    @Test("wheel events forward to the outer scroll view unless the document outgrows the self-size cap")
    func wheelEventsForwardUnlessDocumentOutgrowsCap() {
        #expect(HTMLBodyScrollForwardingPolicy.forwardsToEnclosingScrollView(
            contentHeight: 1200,
            selfSizingCap: 20000
        ))
        #expect(HTMLBodyScrollForwardingPolicy.forwardsToEnclosingScrollView(
            contentHeight: 20000,
            selfSizingCap: 20000
        ))
        #expect(!HTMLBodyScrollForwardingPolicy.forwardsToEnclosingScrollView(
            contentHeight: 20001,
            selfSizingCap: 20000
        ))
    }

    @MainActor
    @Test("reader store defers WebKit creation until it is needed")
    func readerStoreDefersWebViewCreation() {
        let store = HTMLBodyWebViewStore()

        #expect(!store.isWebViewCreated)
        _ = store.webView
        #expect(store.isWebViewCreated)
    }

    @MainActor
    @Test("reader web view forwards scroll wheel events by default")
    func readerWebViewForwardsScrollWheelByDefault() {
        let store = HTMLBodyWebViewStore()
        let forwarding = store.webView as? ScrollForwardingWebView

        #expect(forwarding != nil)
        #expect(forwarding?.forwardsScrollWheel == true)
    }

    @MainActor
    @Test("reader store prewarms and retains one web view across message changes")
    func readerStoreRetainsWebView() {
        let store = HTMLBodyWebViewStore()
        let original = store.webView

        store.prewarm()

        #expect(store.webView === original)
        #expect(store.isPrewarmed)
    }

    @MainActor
    @Test("late prewarm cannot replace a message document")
    func latePrewarmDoesNotReplaceMessageDocument() {
        let store = HTMLBodyWebViewStore()

        store.prepareForContentLoad()
        store.prewarm()

        #expect(!store.isPrewarmed)
    }

    @Test("reader permits repeated local documents after prewarming")
    func readerPermitsRepeatedLocalDocumentsAfterPrewarming() {
        #expect(HTMLBodyNavigationPolicy.isLocalDocumentURL(URL(string: "about:blank")))
        #expect(!HTMLBodyNavigationPolicy.isLocalDocumentURL(URL(string: "https://example.org")))
        #expect(!HTMLBodyNavigationPolicy.isLocalDocumentURL(URL(string: "file:///tmp/message.html")))
        #expect(!HTMLBodyNavigationPolicy.isLocalDocumentURL(nil))
    }
    #endif

    @Test("wrapped message body uses the provided link color")
    func wrappedMessageBodyUsesProvidedLinkColor() {
        let document = HTMLBodyDocument.wrap(
            "<p>Hello</p>",
            linkColorHex: "#7A6DFF"
        )

        #expect(document.contains("a{color:#7A6DFF}"))
        #expect(!document.contains("#2f6fdb"))
    }

    @Test("wrapped message body uses the provided text color")
    func wrappedMessageBodyUsesProvidedTextColor() {
        let document = HTMLBodyDocument.wrap(
            "<p>Hello</p>",
            linkColorHex: "#7A6DFF",
            textColorHex: "#111827"
        )

        #expect(document.contains("color:#111827;"))
    }

    @Test("invalid link colors fall back to current text color")
    func invalidLinkColorsFallBackToCurrentTextColor() {
        let document = HTMLBodyDocument.wrap(
            "<p>Hello</p>",
            linkColorHex: "};body{display:none"
        )

        #expect(document.contains("a{color:currentColor}"))
        #expect(!document.contains("};body{display:none"))
    }

    @Test("wrapped message body uses the selected font and text size")
    func wrappedMessageBodyUsesSelectedFontAndTextSize() {
        let document = HTMLBodyDocument.wrap(
            "<p>Hello</p>",
            linkColorHex: "#7A6DFF",
            fontFamily: .serif,
            textSize: .large
        )

        #expect(document.contains("font:17px ui-serif,Georgia,Times New Roman,serif"))
    }

    @Test("plain text HTML payloads preserve line breaks")
    func plainTextHTMLPayloadsPreserveLineBreaks() {
        let document = HTMLBodyDocument.wrap(
            "Test ok\n\nMvh,\nHenrik <henrik@example.org>",
            linkColorHex: "#7A6DFF"
        )

        #expect(document.contains("Test ok<br><br>Mvh,<br>Henrik &lt;henrik@example.org&gt;"))
    }

    @Test("dark rendering mode keeps the app canvas visible without touching media")
    func darkRenderingModeKeepsAppCanvasVisibleWithoutTouchingMedia() {
        let document = HTMLBodyDocument.wrap(
            #"<p>Hello</p><img src="https://cdn.example.com/logo.png">"#,
            linkColorHex: "#7A6DFF",
            renderingMode: .dark
        )

        #expect(document.contains("background:transparent!important"))
        #expect(document.contains("color:currentColor!important"))
        #expect(document.contains("a{color:#7A6DFF!important}"))
        #expect(document.contains(#"<img src="https://cdn.example.com/logo.png">"#))
        #expect(!document.contains("filter:"))
    }

    @Test("original rendering mode uses a readable white mail canvas")
    func originalRenderingModeUsesReadableWhiteMailCanvas() {
        let document = HTMLBodyDocument.wrap(
            #"<p style="color:#000">Hello</p>"#,
            linkColorHex: "#7A6DFF",
            textColorHex: "#D8DEE9",
            renderingMode: .original
        )

        #expect(document.contains("background:#FFFFFF;"))
        #expect(document.contains("color:#111827;"))
    }

    @Test("reply metadata after separators is wrapped for cleaner styling")
    func replyMetadataAfterSeparatorsIsWrappedForCleanerStyling() {
        let document = HTMLBodyDocument.wrap(
            #"<p>Test ok</p><hr><b>From:</b> Henrik<br><b>Sent:</b> Wednesday<br><b>To:</b> Alex<br><b>Subject:</b> test<br><br>Older body"#,
            linkColorHex: "#7A6DFF",
            renderingMode: .dark
        )

        #expect(document.contains(#"<section class="brev-mail-metadata">"#))
        #expect(document
            .contains(
                #"<b>From:</b> Henrik<br><b>Sent:</b> Wednesday<br><b>To:</b> Alex<br><b>Subject:</b> test<br></section><br>Older body"#
            ))
        #expect(document.contains(".brev-mail-metadata{"))
    }

    @Test("remote-blocked load plan fails closed when blocker is unavailable")
    func remoteBlockedLoadPlanFailsClosedWhenBlockerIsUnavailable() {
        let plan = HTMLBodyLoadPlan.resolve(
            allowRemoteContent: false,
            blockerAvailable: false
        )
        let document = HTMLBodyDocument.wrap(
            plan.bodyHTML(
                originalHTML: #"<p>Hello</p><img src="https://cdn.example.com/pixel.png">"#
            ),
            linkColorHex: "#7A6DFF"
        )

        #expect(plan == .blockedFallback)
        #expect(document.contains("Remote content is blocked"))
        #expect(!document.contains("https://cdn.example.com/pixel.png"))
        #expect(!document.contains("<img"))
    }

    @Test("remote-blocked load plan allows original HTML when blocker is available")
    func remoteBlockedLoadPlanAllowsOriginalHTMLWhenBlockerIsAvailable() {
        let plan = HTMLBodyLoadPlan.resolve(
            allowRemoteContent: false,
            blockerAvailable: true
        )

        #expect(plan == .original(blocksRemoteSubresources: true))
        #expect(plan.bodyHTML(originalHTML: "<p>Hello</p>") == "<p>Hello</p>")
    }

    @Test("remote blocker targets network subresources only")
    func remoteBlockerTargetsNetworkSubresourcesOnly() {
        let rule = HTMLRemoteContentBlockerRule.encodedContentRuleList

        #expect(rule.contains(#""url-filter":"^https?://""#))
        #expect(!rule.contains(#""url-filter":".*""#))
        #expect(!rule.contains("data:"))
        #expect(!rule.contains("cid:"))
    }

    @Test("static snapshot rendering preserves readable HTML text")
    func staticSnapshotRenderingPreservesReadableHTMLText() {
        #expect(
            HTMLBodyStaticSnapshot.plainText(
                from: "<p>Hello <strong>Brev</strong></p><p>Second line</p>"
            ) == "Hello Brev Second line"
        )
    }

    @Test("HTML rendering defaults follow the app theme")
    func htmlRenderingDefaultsFollowTheAppTheme() {
        let lightTheme = BrevThemes.builtIns.first { $0.mode == .light }!
        let darkTheme = BrevThemes.builtIns.first { $0.mode == .dark }!

        #expect(HTMLBodyRenderingMode.default(for: lightTheme) == .original)
        #expect(HTMLBodyRenderingMode.default(for: darkTheme) == .dark)
    }

    @Test("rendering mode toggle names the clean dark renderer")
    func renderingModeToggleNamesCleanDarkRenderer() {
        #expect(HTMLBodyRenderingMode.original.toggleTitle == "Dark")
        #expect(HTMLBodyRenderingMode.dark.toggleTitle == "Original")
    }
}
