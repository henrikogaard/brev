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
import Testing

@Suite("MessageHTMLRenderPolicy")
struct MessageHTMLRenderPolicyTests {
    @Test("rich renderer owns HTML when enabled")
    func richRendererOwnsHTMLWhenEnabled() {
        #expect(MessageHTMLRenderPolicy.shouldImportAttributedHTML(
            "<p>Hello</p>",
            useRichRenderer: true,
            allowRemoteContent: false
        ) == false)
    }

    @Test("remote asset HTML is not imported when remote content is blocked")
    func remoteAssetHTMLIsNotImportedWhenRemoteContentIsBlocked() {
        #expect(MessageHTMLRenderPolicy.shouldImportAttributedHTML(
            #"<p>Hello</p><img src="https://cdn.example.com/pixel.png">"#,
            useRichRenderer: false,
            allowRemoteContent: false
        ) == false)
    }

    @Test("remote asset HTML may be imported after explicit opt in")
    func remoteAssetHTMLMayBeImportedAfterExplicitOptIn() {
        #expect(MessageHTMLRenderPolicy.shouldImportAttributedHTML(
            #"<link rel="stylesheet" href="https://cdn.example.com/mail.css"><p>Hello</p>"#,
            useRichRenderer: false,
            allowRemoteContent: true
        ))
    }

    @Test("local HTML may be imported when rich renderer is off")
    func localHTMLMayBeImportedWhenRichRendererIsOff() {
        #expect(MessageHTMLRenderPolicy.shouldImportAttributedHTML(
            "<p><strong>Hello</strong></p>",
            useRichRenderer: false,
            allowRemoteContent: false
        ))
    }

    @Test("remote render state blocks by default")
    func remoteRenderStateBlocksByDefault() {
        let state = MessageRemoteContentRenderPolicy.state(
            html: #"<p>Hello</p><img src="https://cdn.example.com/pixel.png">"#,
            senderEmail: "ada@example.com",
            allowRemoteContentDefault: false,
            loadOnce: false,
            policy: .defaults
        )

        #expect(!state.allowsRemoteContent)
        #expect(state.isBlocked)
        #expect(state.senderDomain == "example.com")
        #expect(state.report.assetCount == 1)
        #expect(state.report.hosts == ["cdn.example.com"])
    }

    @Test("load once affects only the current render state")
    func loadOnceAffectsOnlyCurrentRenderState() {
        let html = #"<img src="https://cdn.example.com/pixel.png">"#
        let loadedOnce = MessageRemoteContentRenderPolicy.state(
            html: html,
            senderEmail: "ada@example.com",
            allowRemoteContentDefault: false,
            loadOnce: true,
            policy: .defaults
        )
        let nextMessage = MessageRemoteContentRenderPolicy.state(
            html: html,
            senderEmail: "ada@example.com",
            allowRemoteContentDefault: false,
            loadOnce: false,
            policy: .defaults
        )

        #expect(loadedOnce.allowsRemoteContent)
        #expect(!loadedOnce.isBlocked)
        #expect(loadedOnce.report.assetCount == 1)
        #expect(!nextMessage.allowsRemoteContent)
        #expect(nextMessage.isBlocked)
    }

    @Test("sender and domain allowlists permit matching remote content")
    func senderAndDomainAllowlistsPermitMatchingRemoteContent() {
        let html = #"<img src="https://cdn.example.com/pixel.png">"#
        var senderPolicy = RemoteContentPolicy.defaults
        senderPolicy.allow(senderEmail: "ADA@EXAMPLE.COM")
        var domainPolicy = RemoteContentPolicy.defaults
        domainPolicy.allow(domain: "example.com")
        var senderDomainPolicy = RemoteContentPolicy.defaults
        senderDomainPolicy.allow(domain: "example.net")

        #expect(MessageRemoteContentRenderPolicy.state(
            html: html,
            senderEmail: "ada@example.com",
            allowRemoteContentDefault: false,
            loadOnce: false,
            policy: senderPolicy
        ).allowsRemoteContent)
        #expect(MessageRemoteContentRenderPolicy.state(
            html: html,
            senderEmail: "other@example.net",
            allowRemoteContentDefault: false,
            loadOnce: false,
            policy: domainPolicy
        ).allowsRemoteContent)
        #expect(MessageRemoteContentRenderPolicy.state(
            html: #"<img src="https://tracker.example.org/pixel.png">"#,
            senderEmail: "news@example.net",
            allowRemoteContentDefault: false,
            loadOnce: false,
            policy: senderDomainPolicy
        ).allowsRemoteContent)
    }

    @Test("privacy copy distinguishes tracking pixels from ordinary assets")
    func privacyCopyDistinguishesTrackingPixelsFromOrdinaryAssets() {
        let trackerState = MessageRemoteContentRenderPolicy.state(
            html: #"<img src="https://track.example.net/open.gif" width="1" height="1">"#,
            senderEmail: "news@example.com",
            allowRemoteContentDefault: false,
            loadOnce: false,
            policy: .defaults
        )
        let ordinaryState = MessageRemoteContentRenderPolicy.state(
            html: #"<img src="https://cdn.example.com/header.png">"#,
            senderEmail: "news@example.com",
            allowRemoteContentDefault: false,
            loadOnce: false,
            policy: .defaults
        )

        #expect(MessageRemoteContentPrivacyPresentation.resolve(
            trackerState
        ) == MessageRemoteContentPrivacyCopy(
            title: "Tracking pixels blocked",
            explanation: "Brev blocked 1 likely tracking pixel. Loading remote content would contact track.example.net, which can reveal your IP address and when you opened this message.",
            primaryActionTitle: "Download images"
        ))
        #expect(MessageRemoteContentPrivacyPresentation.resolve(
            ordinaryState
        ) == MessageRemoteContentPrivacyCopy(
            title: "Remote content blocked",
            explanation: "Brev blocked 1 remote asset. Loading remote content would contact cdn.example.com, which can reveal your IP address and when you opened this message.",
            primaryActionTitle: "Download images"
        ))
    }

    @Test("privacy copy names the per-message image action")
    func privacyCopyNamesPerMessageImageAction() {
        let state = MessageRemoteContentRenderPolicy.state(
            html: #"<img src="https://cdn.example.com/header.png">"#,
            senderEmail: "news@example.com",
            allowRemoteContentDefault: false,
            loadOnce: false,
            policy: .defaults
        )

        #expect(MessageRemoteContentPrivacyPresentation.resolve(state).primaryActionTitle == "Download images")
    }

    @Test("privacy copy summarizes longer host lists")
    func privacyCopySummarizesLongerHostLists() {
        let state = MessageRemoteContentRenderPolicy.state(
            html: #"""
            <img src="https://a.example.com/a.png">
            <img src="https://b.example.com/b.png">
            <img src="https://c.example.com/c.png">
            <img src="https://d.example.com/d.png">
            """#,
            senderEmail: "news@example.com",
            allowRemoteContentDefault: false,
            loadOnce: false,
            policy: .defaults
        )

        #expect(MessageRemoteContentPrivacyPresentation.resolve(state).explanation ==
            "Brev blocked 4 remote assets. Loading remote content would contact a.example.com, b.example.com, c.example.com, and 1 more host, which can reveal your IP address and when you opened this message.")
    }
}
