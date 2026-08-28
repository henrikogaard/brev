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
import Foundation
import Testing

@Suite("ThreadMessageBodyPresentation")
struct ThreadMessageBodyPresentationTests {
    @Test("plain text bodies keep the existing text presentation")
    func plainTextBodiesKeepTextPresentation() {
        let presentation = ThreadMessageBodyPresentation.resolve(
            ThreadMessageBodyPresentation.Context(
                isLoading: false,
                errorMessage: nil,
                renderedBody: RenderedBody(html: nil, plainText: "Plain body", attachments: []),
                useRichRenderer: false,
                allowRemoteContent: false,
                showRemoteContent: false
            )
        )

        #expect(presentation == .plainText("Plain body"))
    }

    @Test("rich renderer owns HTML and blocks remote content by default")
    func richRendererOwnsHTMLAndBlocksRemoteContentByDefault() {
        let presentation = ThreadMessageBodyPresentation.resolve(
            ThreadMessageBodyPresentation.Context(
                isLoading: false,
                errorMessage: nil,
                renderedBody: RenderedBody(
                    html: #"<p>Hello</p><img src="https://example.com/pixel.png">"#,
                    plainText: nil,
                    attachments: []
                ),
                useRichRenderer: true,
                allowRemoteContent: false,
                showRemoteContent: false
            )
        )

        #expect(presentation == .richHTML(
            html: #"<p>Hello</p><img src="https://example.com/pixel.png">"#,
            allowRemoteContent: false,
            showsRemoteContentBanner: true
        ))
    }

    @Test("local HTML uses attributed import when rich renderer is off")
    func localHTMLUsesAttributedImportWhenRichRendererIsOff() {
        let presentation = ThreadMessageBodyPresentation.resolve(
            ThreadMessageBodyPresentation.Context(
                isLoading: false,
                errorMessage: nil,
                renderedBody: RenderedBody(
                    html: "<p><strong>Hello</strong></p>",
                    plainText: nil,
                    attachments: []
                ),
                useRichRenderer: false,
                allowRemoteContent: false,
                showRemoteContent: false
            )
        )

        #expect(presentation == .attributedHTML("<p><strong>Hello</strong></p>"))
    }

    @Test("safe HTML is preferred over plain alternative")
    func safeHTMLIsPreferredOverPlainAlternative() {
        let presentation = ThreadMessageBodyPresentation.resolve(
            ThreadMessageBodyPresentation.Context(
                isLoading: false,
                errorMessage: nil,
                renderedBody: RenderedBody(
                    html: "<p><strong>Hello</strong> <em>Henrik</em></p>",
                    plainText: "Hello Henrik",
                    attachments: []
                ),
                useRichRenderer: false,
                allowRemoteContent: false,
                showRemoteContent: false
            )
        )

        #expect(presentation == .attributedHTML("<p><strong>Hello</strong> <em>Henrik</em></p>"))
    }

    @Test("remote HTML falls back safely when rich renderer is off and remote content is blocked")
    func remoteHTMLFallsBackSafelyWhenRichRendererIsOffAndRemoteContentIsBlocked() {
        let presentation = ThreadMessageBodyPresentation.resolve(
            ThreadMessageBodyPresentation.Context(
                isLoading: false,
                errorMessage: nil,
                renderedBody: RenderedBody(
                    html: #"<p>Hello</p><img src="https://example.com/pixel.png">"#,
                    plainText: nil,
                    attachments: []
                ),
                useRichRenderer: false,
                allowRemoteContent: false,
                showRemoteContent: false
            )
        )

        #expect(presentation == .htmlFallback("Hello"))
    }

    @Test("body load errors surface as safe error copy")
    func bodyLoadErrorsSurfaceAsSafeErrorCopy() {
        let presentation = ThreadMessageBodyPresentation.resolve(
            ThreadMessageBodyPresentation.Context(
                isLoading: false,
                errorMessage: "Could not load message.",
                renderedBody: nil,
                useRichRenderer: false,
                allowRemoteContent: false,
                showRemoteContent: false
            )
        )

        #expect(presentation == .error("Could not load message."))
    }
}

@Suite("ThreadCalendarInvitePresentation")
struct ThreadCalendarInvitePresentationTests {
    @Test("non invite messages do not show calendar UI")
    func nonInviteMessagesDoNotShowCalendarUI() {
        let presentation = ThreadCalendarInvitePresentation.resolve(
            header: Self.makeHeader(),
            renderedBody: RenderedBody(html: nil, plainText: "Hello", attachments: []),
            capabilities: .full,
            localResponse: nil
        )

        #expect(presentation == nil)
    }

    @Test("supported unanswered invites show RSVP actions")
    func supportedUnansweredInvitesShowRSVPActions() {
        let presentation = ThreadCalendarInvitePresentation.resolve(
            header: Self.makeHeader(),
            renderedBody: Self.inviteBody,
            capabilities: [.serverSideCalendarReply],
            localResponse: nil
        )

        #expect(presentation?.showsActions == true)
        #expect(presentation?.unsupportedMessage == nil)
    }

    @Test("unsupported invites render read only with explanatory copy")
    func unsupportedInvitesRenderReadOnlyWithExplanatoryCopy() {
        let presentation = ThreadCalendarInvitePresentation.resolve(
            header: Self.makeHeader(),
            renderedBody: Self.inviteBody,
            capabilities: [],
            localResponse: nil
        )

        #expect(presentation?.showsActions == false)
        #expect(presentation?.unsupportedMessage == "Calendar replies require server support or an SMTP-capable account.")
    }

    @Test("SMTP-capable invites show client-side RSVP actions")
    func smtpCapableInvitesShowClientSideRSVPActions() {
        let presentation = ThreadCalendarInvitePresentation.resolve(
            header: Self.makeHeader(),
            renderedBody: Self.inviteBody,
            capabilities: [.smtpOAuth],
            localResponse: nil
        )

        #expect(presentation?.showsActions == true)
        #expect(presentation?.unsupportedMessage == nil)
    }

    @Test("IMAP SMTP backend invites show client-side RSVP actions")
    func imapSMTPBackendInvitesShowClientSideRSVPActions() {
        let backend = IMAPSMTPBackend(
            account: BrevAccount(
                id: "imap-smtp:person@example.org",
                displayName: "Person",
                emailAddress: "person@example.org"
            ),
            configuration: IMAPAccountConfiguration(
                accountID: "imap-smtp:person@example.org",
                emailAddress: "person@example.org",
                displayName: "Person",
                incoming: MailServerSettings(
                    kind: .imap,
                    host: "imap.example.org",
                    port: 993,
                    tlsMode: .implicit,
                    authentication: .password
                ),
                outgoing: MailServerSettings(
                    kind: .smtp,
                    host: "smtp.example.org",
                    port: 587,
                    tlsMode: .startTLS,
                    authentication: .password
                ),
                credentialID: "imap-smtp:person@example.org"
            ),
            credential: MailAccountCredential(
                incomingUsername: "person@example.org",
                outgoingUsername: "person@example.org",
                secret: "secret",
                authentication: .password
            ),
            listFolders: { _, _ in [] },
            sendMessage: { _, _, _ in SendResult(sentMessageID: "sent") }
        )
        let presentation = ThreadCalendarInvitePresentation.resolve(
            header: Self.makeHeader(),
            renderedBody: Self.inviteBody,
            capabilities: backend.capabilities,
            localResponse: nil
        )

        #expect(presentation?.showsActions == true)
        #expect(presentation?.unsupportedMessage == nil)
    }

    @Test("answered invites show response status instead of actions")
    func answeredInvitesShowResponseStatusInsteadOfActions() {
        let presentation = ThreadCalendarInvitePresentation.resolve(
            header: Self.makeHeader(isAnswered: true),
            renderedBody: Self.inviteBody,
            capabilities: [.serverSideCalendarReply],
            localResponse: nil
        )

        #expect(presentation?.responseLabel == "Responded")
        #expect(presentation?.showsActions == false)
    }

    private static var inviteBody: RenderedBody {
        RenderedBody(
            html: nil,
            plainText: "Invite attached.",
            attachments: [
                Attachment(
                    id: "invite",
                    name: "invite.ics",
                    mimeType: "text/calendar",
                    sizeBytes: 128,
                    resource: "invite"
                )
            ]
        )
    }

    private static func makeHeader(isAnswered: Bool = false) -> MessageHeader {
        MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Ada", email: "ada@example.org"),
            subject: "Planning",
            snippet: "Invite attached.",
            date: Date(timeIntervalSince1970: 1_735_689_600),
            isAnswered: isAnswered,
            hasAttachments: true
        )
    }
}
