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

@Suite("MessageRemoteContentDetector")
struct MessageRemoteContentDetectorTests {
    @Test("detects remote source attributes")
    func detectsRemoteSourceAttributes() {
        #expect(MessageRemoteContentDetector.hasRemoteAssets(
            #"<img src="https://cdn.example.com/pixel.png">"#
        ))
        #expect(MessageRemoteContentDetector.hasRemoteAssets(
            #"<img srcset="//cdn.example.com/one.png 1x, /local.png 2x">"#
        ))
    }

    @Test("extracts remote asset hosts")
    func extractsRemoteAssetHosts() {
        #expect(MessageRemoteContentDetector.remoteAssetHosts(
            #"""
            <img src="https://cdn.example.com/pixel.png">
            <img srcset="//img.example.net/one.png 1x, /local.png 2x">
            <div style="background-image: url('https://assets.example.org/bg.png')">
            """#
        ) == [
            "assets.example.org",
            "cdn.example.com",
            "img.example.net",
        ])
    }

    @Test("summarizes likely tracking pixels from hidden remote images")
    func summarizesLikelyTrackingPixelsFromHiddenRemoteImages() {
        let report = MessageRemoteContentDetector.remoteAssetReport(
            #"""
            <img src="https://track.example.net/open.gif" width="1" height="1">
            <img src="https://cdn.example.com/logo.png" width="240" height="80">
            """#
        )

        #expect(report.assetCount == 2)
        #expect(report.likelyTrackerCount == 1)
        #expect(report.hosts == ["cdn.example.com", "track.example.net"])
        #expect(report.hasLikelyTrackers)
    }

    @Test("summarizes ordinary remote assets without tracking classification")
    func summarizesOrdinaryRemoteAssetsWithoutTrackingClassification() {
        let report = MessageRemoteContentDetector.remoteAssetReport(
            #"""
            <img src="https://cdn.example.com/header.png">
            <link rel="stylesheet" href="https://assets.example.com/mail.css">
            """#
        )

        #expect(report.assetCount == 2)
        #expect(report.likelyTrackerCount == 0)
        #expect(!report.hasLikelyTrackers)
    }

    @Test("detects unquoted remote source attributes")
    func detectsUnquotedRemoteSourceAttributes() {
        #expect(MessageRemoteContentDetector.hasRemoteAssets(
            #"<img src=https://cdn.example.com/pixel.png>"#
        ))
        #expect(MessageRemoteContentDetector.hasRemoteAssets(
            #"<video poster=//cdn.example.com/poster.jpg>"#
        ))
    }

    @Test("detects remote stylesheets and CSS URLs")
    func detectsRemoteStylesheetsAndCSSURLs() {
        #expect(MessageRemoteContentDetector.hasRemoteAssets(
            #"<link rel="stylesheet" href="https://cdn.example.com/mail.css">"#
        ))
        #expect(MessageRemoteContentDetector.hasRemoteAssets(
            #"<div style="background-image: url('https://cdn.example.com/bg.png')">"#
        ))
    }

    @Test("does not treat ordinary links as remote assets")
    func doesNotTreatOrdinaryLinksAsRemoteAssets() {
        #expect(MessageRemoteContentDetector.hasRemoteAssets(
            #"<a href="https://example.com/read-more">Read more</a>"#
        ) == false)
    }

    @Test("local inline and data assets are not remote")
    func localInlineAndDataAssetsAreNotRemote() {
        #expect(MessageRemoteContentDetector.hasRemoteAssets(
            #"<img src="cid:logo"><img src="data:image/png;base64,abc">"#
        ) == false)
    }

    // Regression: a `>` inside an earlier quoted attribute used to terminate the
    // element scan before `src`, so the remote asset went undetected and the
    // NSAttributedString render path fetched it (a silent tracker load).
    @Test("a > inside an earlier quoted attribute does not hide a remote source")
    func quotedAngleBracketDoesNotHideRemoteSource() {
        #expect(MessageRemoteContentDetector.hasRemoteAssets(
            #"<img alt="a>b" src="https://tracker.example/p.gif">"#
        ))
        #expect(MessageRemoteContentDetector.hasRemoteAssets(
            #"<img title="click here -> now" src='https://tracker.example/x.gif'>"#
        ))
        #expect(MessageRemoteContentDetector.remoteAssetHosts(
            #"<img alt="a>b" src="https://tracker.example/p.gif">"#
        ).contains("tracker.example"))
    }
}
