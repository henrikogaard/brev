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
@testable import BrevMail
import Foundation
import Testing

@Suite("MessageListPresentation")
struct MessageListPresentationTests {
    @Test("load errors include a retry action")
    func loadErrorsIncludeRetryAction() {
        #expect(MessageListPresentation.errorStatus(
            "Couldn't load messages."
        ) == MessageListStatus(
            title: "Something went wrong",
            icon: "exclamationmark.triangle",
            subtitle: "Couldn't load messages.",
            actionTitle: "Try Again"
        ))
    }

    @Test("load errors keep localized backend messages")
    func loadErrorsKeepLocalizedBackendMessages() {
        #expect(MessageListPresentation.loadErrorMessage(
            for: MailBackendError.rateLimited(retryAfter: 12)
        ) == "Rate limited. Try again in 12 seconds.")
    }

    @Test("search errors keep localized backend messages")
    func searchErrorsKeepLocalizedBackendMessages() {
        #expect(MessageListPresentation.searchErrorMessage(
            for: MailBackendError.network(underlying: "offline")
        ) == "Network error: offline")
    }

    @Test("load more errors include a retry action and localized message")
    func loadMoreErrorsIncludeRetryActionAndLocalizedMessage() {
        #expect(MessageListPresentation.loadMoreErrorStatus(
            for: MailBackendError.network(underlying: "connection lost")
        ) == MessageListFooterStatus(
            message: "Network error: connection lost",
            actionTitle: "Try Again"
        ))
    }

    @Test("partial unified inbox errors keep loaded messages visible with retry")
    func partialUnifiedInboxErrorsKeepLoadedMessagesVisibleWithRetry() {
        #expect(MessageListPresentation.partialLoadErrorStatus(
            for: MailBackendError.network(underlying: "one account offline")
        ) == MessageListFooterStatus(
            message: "Some mailboxes couldn't load. Network error: one account offline",
            actionTitle: "Try Again"
        ))
    }

    @Test("mutation errors include a refresh action and localized message")
    func mutationErrorsIncludeRefreshActionAndLocalizedMessage() {
        #expect(MessageListPresentation.mutationErrorStatus(
            for: MailBackendError.network(underlying: "offline")
        ) == MessageListFooterStatus(
            message: "Network error: offline",
            actionTitle: "Refresh"
        ))
    }

    @Test("empty folder state has no retry action")
    func emptyFolderStateHasNoRetryAction() {
        #expect(MessageListPresentation.emptyStatus(
            searchText: ""
        ) == MessageListStatus(
            title: "No messages",
            icon: "tray",
            subtitle: "Messages you receive will appear here.",
            actionTitle: nil
        ))
    }

    @Test("missing folder selection has no retry action")
    func missingFolderSelectionHasNoRetryAction() {
        #expect(MessageListPresentation.noFolderStatus() == MessageListStatus(
            title: "No folder selected",
            icon: "folder",
            subtitle: "Choose a folder from the sidebar.",
            actionTitle: nil
        ))
    }

    @Test("empty search state offers clear search action")
    func emptySearchStateOffersClearSearchAction() {
        #expect(MessageListPresentation.emptyStatus(
            searchText: "budget"
        ) == MessageListStatus(
            title: "No messages",
            icon: "magnifyingglass",
            subtitle: "No results for \"budget\".",
            actionTitle: "Clear search"
        ))
    }

    @Test("pinned section header uses standout presentation")
    func pinnedSectionHeaderUsesStandoutPresentation() {
        #expect(MessageListPresentation.sectionHeader(
            title: "Pinned"
        ) == MessageListSectionHeaderPresentation(
            title: "PINNED",
            icon: "pin.fill",
            style: .pinned
        ))
    }

    @Test("date section headers stay quiet")
    func dateSectionHeadersStayQuiet() {
        #expect(MessageListPresentation.sectionHeader(
            title: "Today"
        ) == MessageListSectionHeaderPresentation(
            title: "Today",
            icon: nil,
            style: .date
        ))
    }

    @Test("listing previews discard markup and collapse whitespace")
    func listingPreviewsDiscardMarkupAndCollapseWhitespace() {
        #expect(MessageListPresentation.previewText(
            from: "<style>.receipt { color: red; }</style>\n<table class=\"receipt\"><tr><td>  Purchase&nbsp; confirmed </td></tr></table>"
        ) == "Purchase confirmed")
    }

    @Test("listing previews scrub cached MIME fragments left by the old fetch cleaner")
    func listingPreviewsScrubCachedMIMEFragments() {
        #expect(MessageListPresentation.previewText(
            from: "57916730746491120=Content-Type: multipart/alternative; boundary=\"xyz\" Til kunde hos AutoPASS,"
        ) == "Til kunde hos AutoPASS,")
        #expect(MessageListPresentation.previewText(
            from: "Mime-Version: 1.0 Oppdag de største film- og seriehøydepunktene akkurat nå"
        ) == "Oppdag de største film- og seriehøydepunktene akkurat nå")
        #expect(MessageListPresentation.previewText(
            from: "This is a multi-part message in MIME format View this email in your browser"
        ) == "View this email in your browser")
    }

    @Test("listing previews scrub CSS rules and merge tags from cached snippets")
    func listingPreviewsScrubCSSRulesAndMergeTags() {
        #expect(MessageListPresentation.previewText(
            from: "#outlook a { padding:0; } body { margin:0;padding:0;-webkit-text-size-adjust:100% } Dear customer, your order shipped."
        ) == "Dear customer, your order shipped.")
        #expect(MessageListPresentation.previewText(
            from: "*|SUBJECT|* Hello there, Your 2FA code is ready."
        ) == "Hello there, Your 2FA code is ready.")
        #expect(MessageListPresentation.previewText(
            from: "96 *|SUBJECT|* <td al"
        ) == "96")
    }

    @Test("listing previews decode cached base64 body runs into prose")
    func listingPreviewsDecodeCachedBase64Runs() {
        let html = "<!doctype html><html lang=\"no\"><head><title>AutoPASS</title></head>"
            + "<body><p>Til kunde hos AutoPASS, Fra 1. januar 2027 innf\u{00F8}res reviderte retningslinjer.</p></body></html>"
        let encoded = Data(html.utf8).base64EncodedString()
        #expect(MessageListPresentation.previewText(from: encoded)
            == "AutoPASS Til kunde hos AutoPASS, Fra 1. januar 2027 innføres reviderte retningslinjer.")

        // Base64 bodies arrive line-wrapped; cached snippets joined the
        // wrapped lines with spaces.
        let wrapped = stride(from: 0, to: encoded.count, by: 76).map { offset in
            let start = encoded.index(encoded.startIndex, offsetBy: offset)
            let end = encoded.index(start, offsetBy: 76, limitedBy: encoded.endIndex) ?? encoded.endIndex
            return String(encoded[start ..< end])
        }.joined(separator: " ")
        #expect(MessageListPresentation.previewText(from: wrapped)
            == "AutoPASS Til kunde hos AutoPASS, Fra 1. januar 2027 innføres reviderte retningslinjer.")
    }

    @Test("listing previews scrub Content-Description headers and QP escapes")
    func listingPreviewsScrubContentDescriptionAndQPEscapes() {
        #expect(MessageListPresentation.previewText(
            from: "Content-Description: Utsendingsbekreftelse 6008432247 fra Skittfiske.no "
                + "Varene er n=E5 pakket p=E5 v=E5rt lager i Sandefjord.",
            subject: "Utsendingsbekreftelse 6008432247 fra Skittfiske.no"
        ) == "Varene er nå pakket på vårt lager i Sandefjord.")

        // UTF-8 quoted-printable pairs decode as one character.
        #expect(MessageListPresentation.previewText(
            from: "Se v=C3=A5re nye varer"
        ) == "Se våre nye varer")

        // Hex-looking tokens in prose stay untouched: =AB decodes to
        // punctuation, not a letter, so the escape heuristic skips it.
        #expect(MessageListPresentation.previewText(
            from: "Order id=AB123 shipped."
        ) == "Order id=AB123 shipped.")
    }

    @Test("listing previews keep hex digests and short tokens untouched")
    func listingPreviewsKeepHexDigestsUntouched() {
        let digest = "3f786850e387550fdab836ed7e6dc881de23001b"
        #expect(MessageListPresentation.previewText(
            from: "Deployed commit \(digest) to production."
        ) == "Deployed commit \(digest) to production.")
    }

    @Test("listing previews drop a leading brand link and subject echo")
    func listingPreviewsDropLeadingBrandLinkAndSubjectEcho() {
        #expect(MessageListPresentation.previewText(
            from: "Resend (https://resend.com) $20.00 payment to Resend was unsuccessful We weren't able to charge the credit card you provided.",
            subject: "$20.00 payment to Resend was unsuccessful"
        ) == "We weren't able to charge the credit card you provided.")
    }

    @Test("expanded thread selections match the parent row radius and inset")
    func expandedThreadSelectionsMatchParentRowRadiusAndInset() {
        #expect(ThreadInlineChildRowPresentation.selectionCornerRadius == BrevRadius.md)
        #expect(ThreadInlineChildRowPresentation.selectionHorizontalInset == BrevSpacing.xxs)
    }

    @Test("list chrome avoids system row backgrounds")
    func listChromeAvoidsSystemRowBackgrounds() {
        #expect(MessageListPresentation.listChrome.clearsSystemRowBackgrounds)
        #expect(MessageListPresentation.listChrome.rendersDateHeadersAsRows)
    }

    @Test("compact folder stats stay terse")
    func compactFolderStatsStayTerse() {
        let presentation = MessageListPresentation.folderStatsFooter(
            MessageListFolderStats(
                folderName: "Inbox",
                totalCount: 229,
                unreadCount: 15,
                loadedCount: 64,
                visibleCount: 64,
                pinnedCount: 2,
                isThreaded: false,
                isConstrained: false
            ),
            detail: .compact
        )

        #expect(presentation.text == "229 messages · 15 unread")
        #expect(presentation.accessibilityLabel == "Inbox, 229 messages, 15 unread")
    }

    @Test("detailed folder stats include current view context")
    func detailedFolderStatsIncludeCurrentViewContext() {
        let presentation = MessageListPresentation.folderStatsFooter(
            MessageListFolderStats(
                folderName: "Inbox",
                totalCount: 229,
                unreadCount: 15,
                loadedCount: 64,
                visibleCount: 18,
                pinnedCount: 2,
                isThreaded: true,
                isConstrained: true
            ),
            detail: .detailed
        )

        #expect(presentation.text == "Inbox · 18 threads shown · 229 total · 15 unread · 2 pinned · 64 loaded")
        #expect(presentation.accessibilityLabel == "Inbox, 18 threads shown, 229 total, 15 unread, 2 pinned, 64 loaded")
    }
}
