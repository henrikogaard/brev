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

    @Test("the reader note counts the blocked trackers")
    func readerNote() {
        #expect(MessageTrackerNote.text(removedCount: 0) == nil)
        #expect(MessageTrackerNote.text(removedCount: 1) == "Blocked 1 tracker")
        #expect(MessageTrackerNote.text(removedCount: 2) == "Blocked 2 trackers")
    }
}
