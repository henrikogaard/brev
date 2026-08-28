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
import Foundation
import Testing

@Suite("MessageInlineCIDRenderPolicy")
struct MessageInlineCIDRenderPolicyTests {
    @Test("rewrites matching CID image sources to data URLs")
    func rewritesMatchingCIDImageSourcesToDataURLs() {
        let html = #"<p>Hello<img src="cid:hero-image@example.org"></p>"#
        let rewritten = MessageInlineCIDRenderPolicy.rewriteCIDImageSources(
            in: html,
            payloads: [
                MessageInlineCIDImagePayload(
                    contentID: "hero-image@example.org",
                    mimeType: "image/png",
                    data: Data([0x89, 0x50, 0x4E, 0x47])
                ),
            ]
        )

        #expect(rewritten == #"<p>Hello<img src="data:image/png;base64,iVBORw=="></p>"#)
    }

    @Test("ignores non image CID payloads")
    func ignoresNonImageCIDPayloads() {
        let html = #"<img src="cid:notes@example.org">"#
        let rewritten = MessageInlineCIDRenderPolicy.rewriteCIDImageSources(
            in: html,
            payloads: [
                MessageInlineCIDImagePayload(
                    contentID: "notes@example.org",
                    mimeType: "text/plain",
                    data: Data("hello".utf8)
                ),
            ]
        )

        #expect(rewritten == html)
    }
}
