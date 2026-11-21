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

@testable import BrevMail
import Testing

/// Tracking pixels are stripped before a message renders, even with remote
/// content allowed (#299).
@Suite("Tracker stripping")
struct MessageTrackerStripTests {
    @Test("a 1x1 open pixel is removed and the content image stays")
    func onePixel() {
        let html = """
        <p>Hello</p>\
        <img src="https://cdn.shop.example/banner.jpg" width="600" height="200" alt="Sale">\
        <img src="https://email.shop.example/o/eyJ0Ijo" width="1" height="1" alt="" border="0">
        """
        let result = MessageRemoteContentDetector.strippingLikelyTrackers(html)
        #expect(result.removedCount == 1)
        #expect(!result.html.contains("email.shop.example"))
        #expect(result.html.contains("https://cdn.shop.example/banner.jpg"))
        #expect(result.html.contains("<p>Hello</p>"))
    }

    @Test("hidden images are removed", arguments: [
        #"<img src="https://t.example.net/a.gif" style="display:none">"#,
        #"<img style="visibility: hidden" src="https://t.example.net/b.gif">"#,
        #"<img src='https://t.example.net/c.gif' style='opacity:0;width:0'>"#,
    ])
    func hiddenImage(_ tracker: String) {
        let result = MessageRemoteContentDetector.strippingLikelyTrackers("<div>Hi</div>\(tracker)")
        #expect(result.removedCount == 1)
        #expect(!result.html.contains("t.example.net"))
        #expect(result.html == "<div>Hi</div>")
    }

    @Test("tracker-looking URLs and known tracker hosts are removed", arguments: [
        #"<img src="https://news.example.com/track/open?id=42" width="20" height="20">"#,
        #"<img src="https://mailtrack.io/trace/mail/abc.png">"#,
        #"<img src="https://t.yesware.com/t/123/abc/spacer.gif">"#,
    ])
    func trackerURL(_ tracker: String) {
        let result = MessageRemoteContentDetector.strippingLikelyTrackers("<p>x</p>\(tracker)")
        #expect(result.removedCount == 1)
        #expect(result.html == "<p>x</p>")
    }

    @Test("a quoted > inside an attribute does not hide the pixel")
    func quotedAngleBracket() {
        let html = #"<img alt="a>b" src="https://open.example.org/p.gif" width="1" height="1">"#
        let result = MessageRemoteContentDetector.strippingLikelyTrackers(html)
        #expect(result.removedCount == 1)
        #expect(result.html.isEmpty)
    }

    @Test("several pixels are all removed and counted")
    func severalPixels() {
        let html = """
        <img src="https://a.example/1.gif" width="1" height="1">\
        <p>Body</p>\
        <img src="https://b.example/pixel.png">\
        <img src="https://c.example/x.gif" style="display: none">
        """
        let result = MessageRemoteContentDetector.strippingLikelyTrackers(html)
        #expect(result.removedCount == 3)
        #expect(result.html == "<p>Body</p>")
    }

    @Test("faded and campaign-tagged content images are kept", arguments: [
        #"<img src="https://cdn.example.com/logo.png" style="opacity:0.8">"#,
        #"<img src="https://cdn.example.com/hero.jpg" style="opacity: 0.5; width: 600px">"#,
        #"<img src="https://img.example.com/hero.jpg?utm_campaign=fall&utm_source=mail">"#,
        #"<img src="https://music.example.com/tracks/cover.jpg">"#,
        #"<img src="https://shop.example.com/package-tracking-banner.png">"#,
    ])
    func contentImagesKept(_ image: String) {
        let result = MessageRemoteContentDetector.strippingLikelyTrackers(image)
        #expect(result.removedCount == 0)
        #expect(result.html == image)
    }

    @Test("a pixel behind another src-like attribute is still removed")
    func pixelAfterDataSrc() {
        let html = #"<img data-src="https://cdn.example.com/real.jpg" src="https://t.example.org/open.gif">"#
        let result = MessageRemoteContentDetector.strippingLikelyTrackers(html)
        #expect(result.removedCount == 1)
        #expect(result.html.isEmpty)
    }

    @Test("an entity-encoded tracker URL is still removed")
    func entityEncodedURL() {
        let html = #"<p>x</p><img src="&#104;ttps://mailtrack.io/trace/a.png">"#
        let result = MessageRemoteContentDetector.strippingLikelyTrackers(html)
        #expect(result.removedCount == 1)
        #expect(result.html == "<p>x</p>")
    }

    @Test("a fully transparent image is removed", arguments: [
        #"<img src="https://t.example.net/a.gif" style="opacity:0">"#,
        #"<img src="https://t.example.net/a.gif" style="opacity: 0.0;">"#,
    ])
    func transparentImage(_ tracker: String) {
        #expect(MessageRemoteContentDetector.strippingLikelyTrackers(tracker).removedCount == 1)
    }

    @Test("images whose names only resemble tracker files are kept", arguments: [
        #"<img src="https://travel.example.com/photos/beacon-hill.jpg" width="640" height="480">"#,
        #"<img src="https://cdn.example.com/img/open.gif-banner.png">"#,
        #"<img src="https://cdn.example.com/track/opening-night.jpg">"#,
    ])
    func lookalikeNamesKept(_ image: String) {
        #expect(MessageRemoteContentDetector.strippingLikelyTrackers(image).removedCount == 0)
    }

    @Test("a sized, hidden responsive image is kept for its media query")
    func responsiveHiddenImageKept() {
        let html = #"<img class="mobile" src="https://cdn.example.com/hero-mobile.jpg" width="320" height="200" style="display:none">"#
        #expect(MessageRemoteContentDetector.strippingLikelyTrackers(html).removedCount == 0)
    }

    @Test("pixels sized by inline CSS are removed", arguments: [
        #"<img src="https://stats.example.net/o/123" style="width:1px;height:1px">"#,
        #"<img src="https://stats.example.net/o/124" style="height: 0px; width: 0">"#,
        #"<img src="https://stats.example.net/o/125" style="max-height:1px;width:1px;height:1px;border:0">"#,
    ])
    func cssSizedPixel(_ tracker: String) {
        #expect(MessageRemoteContentDetector.strippingLikelyTrackers(tracker).removedCount == 1)
    }

    @Test("a body whose only tag was a pixel still renders as HTML")
    func onlyTagRemovedStaysHTML() {
        let html = #"Fish &amp; chips<img src="https://a.example/1.gif" width="1" height="1">"#
        let plan = HTMLBodyLoadPlan.resolve(allowRemoteContent: true, blockerAvailable: true)
        let document = HTMLBodyDocument.wrap(plan.bodyHTML(originalHTML: html), linkColorHex: "#0000FF")
        #expect(document.contains("Fish &amp; chips"))
        #expect(!document.contains("&amp;amp;"))
        #expect(!document.contains("a.example"))
    }

    @Test("turning tracker removal off does not change remote-content permission")
    func trackerRemovalOptOutKeepsRemotePermissionIndependent() {
        let html = #"<img src="https://a.example/1.gif" width="1" height="1">"#
        let allowed = HTMLBodyLoadPlan.resolve(allowRemoteContent: true, blockerAvailable: false)
        #expect(allowed.bodyHTML(originalHTML: html, stripTrackingPixels: false) == html)

        let blocked = HTMLBodyLoadPlan.resolve(allowRemoteContent: false, blockerAvailable: true)
        #expect(blocked == .original(blocksRemoteSubresources: true))
        #expect(blocked.bodyHTML(originalHTML: html, stripTrackingPixels: false) == html)
        #expect(HTMLBodyLoadPlan.resolve(allowRemoteContent: false, blockerAvailable: false) == .blockedFallback)
    }

    @Test("native imports honor tracking and remote-content preferences")
    func nativeImportPreferences() {
        let html = #"<p>Body</p><img src="https://a.example/1.gif" width="1" height="1">"#
        #expect(MessageHTMLImportPolicy.prepareForNativeImport(html, stripTrackingPixels: true) == "<p>Body</p>")
        #expect(MessageHTMLImportPolicy.prepareForNativeImport(html, stripTrackingPixels: false) == html)
        #expect(MessageHTMLImportPolicy.prepareForRemoteContentImport(
            html,
            allowRemoteContent: false,
            stripTrackingPixels: true
        ) == html)
        #expect(MessageHTMLImportPolicy.prepareForRemoteContentImport(
            html,
            allowRemoteContent: true,
            stripTrackingPixels: false
        ) == html)
        #expect(MessageHTMLImportPolicy.prepareForNativeImport("<p>Body</p>", stripTrackingPixels: true) == "<p>Body</p>")
    }

    @Test("native import results require the current message, generation, and preference")
    func staleNativeImportRequestCannotApply() {
        let request = MessageHTMLImportRequest(
            generation: 3,
            messageKey: "account/inbox/message-1",
            stripTrackingPixels: true
        )

        #expect(request.matchesCurrent(
            generation: 3,
            messageKey: "account/inbox/message-1",
            stripTrackingPixels: true
        ))
        #expect(!request.matchesCurrent(
            generation: 4,
            messageKey: "account/inbox/message-1",
            stripTrackingPixels: true
        ))
        #expect(!request.matchesCurrent(
            generation: 3,
            messageKey: "account/inbox/message-2",
            stripTrackingPixels: true
        ))
        #expect(!request.matchesCurrent(
            generation: 3,
            messageKey: "account/inbox/message-1",
            stripTrackingPixels: false
        ))
    }

    @Test("an icon sized in em is kept")
    func emSizedIconKept() {
        let html = #"<img src="https://cdn.example.com/icons/star.png" style="width:0.8em;height:0.8em">"#
        #expect(MessageRemoteContentDetector.strippingLikelyTrackers(html).removedCount == 0)
    }

    @Test("script-suffixed open-tracking endpoints are removed", arguments: [
        #"<img src="https://list.example.com/track/open.php?u=1&id=2">"#,
        #"<img src="https://mail.example.com/wf/open.aspx?upn=abc">"#,
    ])
    func scriptSuffixedEndpoint(_ tracker: String) {
        #expect(MessageRemoteContentDetector.strippingLikelyTrackers(tracker).removedCount == 1)
    }

    @Test("a transparent image is removed even when it declares a size")
    func sizedTransparentImage() {
        let html = #"<img src="https://t.example.net/o.gif" width="10" height="10" style="opacity:0">"#
        #expect(MessageRemoteContentDetector.strippingLikelyTrackers(html).removedCount == 1)
    }

    @Test("look-alike opacity and open names on content images are kept", arguments: [
        #"<img src="https://cdn.example.com/a.jpg" width="200" height="100" style="--border-opacity:0">"#,
        #"<img src="https://cdn.example.com/track/open.jpg" width="200" height="100">"#,
        #"<img src="https://cdn.example.com/wf/open.house/photo.jpg">"#,
    ])
    func lookalikeOpacityAndOpenKept(_ image: String) {
        #expect(MessageRemoteContentDetector.strippingLikelyTrackers(image).removedCount == 0)
    }

    @Test("a zero-percent sized image is removed")
    func zeroPercentPixel() {
        let html = #"<img src="https://stats.example.net/o/9" style="width:0%;height:0%">"#
        #expect(MessageRemoteContentDetector.strippingLikelyTrackers(html).removedCount == 1)
    }

    @Test("a later CSS size overrides an earlier zero, like the browser")
    func laterDeclarationWins() {
        let html = #"<img src="https://cdn.example.com/a.jpg" style="width:0%;height:0%;width:300px;height:200px">"#
        #expect(MessageRemoteContentDetector.strippingLikelyTrackers(html).removedCount == 0)
    }

    @Test("an !important tiny size beats a later larger one")
    func importantSizeWins() {
        let html = #"<img src="https://stats.example.net/o/1" style="width:1px !important;height:1px !important;width:300px;height:200px">"#
        #expect(MessageRemoteContentDetector.strippingLikelyTrackers(html).removedCount == 1)
    }

    @Test("a later !important size beats an earlier !important one")
    func laterImportantWins() {
        let html = #"<img src="https://cdn.example.com/a.jpg" style="width:1px !important;height:1px !important;width:300px !important;height:200px !important">"#
        #expect(MessageRemoteContentDetector.strippingLikelyTrackers(html).removedCount == 0)
    }

    @Test("CSS comments are ignored when reading sizes", arguments: [
        // Commented-out tiny sizes do not apply: the image is kept.
        (
            #"<img src="https://cdn.example.com/a.jpg" style="/* width:1px !important; height:1px !important; */ width:300px; height:200px">"#,
            0
        ),
        // A comment inside the priority marker still counts as !important.
        (
            #"<img src="https://stats.example.net/o/2" style="width:1px !/**/important;height:1px !/**/important;width:300px;height:200px">"#,
            1
        ),
    ])
    func cssCommentsIgnored(html: String, expected: Int) {
        #expect(MessageRemoteContentDetector.strippingLikelyTrackers(html).removedCount == expected)
    }

    @Test("CSS sizes are read from the style attribute as the browser does", arguments: [
        // A multiline comment hides the tiny sizes: kept.
        ("<img src=\"https://cdn.example.com/a.jpg\" style=\"/* width:1px;\nheight:1px; */ width:300px; height:200px\">", 0),
        // A comment between number and unit makes an invalid size: kept.
        (#"<img src="https://cdn.example.com/b.jpg" style="width:1/**/px;height:1/**/px">"#, 0),
        // Comment markers in another attribute do not hide the real sizes.
        (#"<img alt="/*" src="https://stats.example.net/o/3" style="width:1px;height:1px" title="*/">"#, 1),
    ])
    func styleAttributeSizes(html: String, expected: Int) {
        #expect(MessageRemoteContentDetector.strippingLikelyTrackers(html).removedCount == expected)
    }

    @Test("only the real style attribute counts, quoted or not", arguments: [
        // `data-style` is metadata, not the image's style: kept.
        (#"<img data-style="width:1px;height:1px" src="https://cdn.example.com/c.jpg" style="width:300px;height:200px">"#, 0),
        // An unquoted style is valid HTML: the pixel is removed.
        (#"<img src="https://stats.example.net/o/4" style=width:1px;height:1px>"#, 1),
        // A slash or a closing quote also separates attributes in HTML.
        (#"<img src="https://stats.example.net/o/5"/style="width:1px;height:1px">"#, 1),
        (#"<img src="https://stats.example.net/o/6"style="width:1px;height:1px">"#, 1),
        // Text inside another attribute's value is never an attribute: kept.
        (#"<img alt="style='width:1px;height:1px'" src="https://cdn.example.com/d.jpg" style="width:300px;height:200px">"#, 0),
        (#"<img title='a "style=width:1px;height:1px"' src="https://cdn.example.com/e.jpg">"#, 0),
        // A combining mark after a closing quote does not hide the next attribute.
        ("<img src=\"https://stats.example.net/o/7\" title=\"x\"\u{0301} style=\"width:1px;height:1px\">", 1),
    ])
    func realStyleAttribute(html: String, expected: Int) {
        #expect(MessageRemoteContentDetector.strippingLikelyTrackers(html).removedCount == expected)
    }

    @Test("an ASP.NET handler open endpoint is removed")
    func ashxEndpoint() {
        let html = #"<img src="https://mail.example.com/track/open.ashx?id=7">"#
        #expect(MessageRemoteContentDetector.strippingLikelyTrackers(html).removedCount == 1)
    }

    @Test("plain mail and normal images are left exactly as they are")
    func nothingToStrip() {
        let html = #"<p>Hi</p><img src="https://cdn.example.com/photo.jpg" width="320" height="240">"#
        let result = MessageRemoteContentDetector.strippingLikelyTrackers(html)
        #expect(result.removedCount == 0)
        #expect(result.html == html)
    }

    @Test("the web view loads stripped HTML when remote content is allowed")
    func loadPlanStripsWhenAllowed() {
        let html = #"<p>Hi</p><img src="https://a.example/1.gif" width="1" height="1">"#
        let allowed = HTMLBodyLoadPlan.resolve(allowRemoteContent: true, blockerAvailable: true)
        #expect(allowed.bodyHTML(originalHTML: html) == "<p>Hi</p>")
        // Blocked loads keep the original: WebKit's blocker stops every request.
        let blocked = HTMLBodyLoadPlan.resolve(allowRemoteContent: false, blockerAvailable: true)
        #expect(blocked.bodyHTML(originalHTML: html) == html)
    }

    @Test("the reader note accurately counts blocked and unblocked trackers")
    func readerNote() {
        #expect(MessageTrackerNote.text(trackerCount: 0, strippingEnabled: true) == nil)
        #expect(MessageTrackerNote.text(trackerCount: 1, strippingEnabled: true) == "Blocked 1 tracker")
        #expect(MessageTrackerNote.text(trackerCount: 2, strippingEnabled: true) == "Blocked 2 trackers")
        #expect(MessageTrackerNote.text(trackerCount: 1, strippingEnabled: false) == "1 likely tracker may load")
        #expect(MessageTrackerNote.text(trackerCount: 2, strippingEnabled: false) == "2 likely trackers may load")
    }
}
