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

import BrevCalendar
@testable import BrevSettings
import Foundation
import Testing

@Suite("PIMSourceRowPresentation")
struct PIMSourceRowPresentationTests {
    private static func source(
        status: PIMSourceStatus,
        provider: PIMSourceProvider = .calDAV,
        kind: PIMSourceKind = .calendar,
        syncEnabled: Bool = false
    ) -> PIMSource {
        PIMSource(
            id: "src",
            kind: kind,
            provider: provider,
            displayName: "Work DAV",
            syncEnabled: syncEnabled,
            status: status,
            statusDetail: status == .failed ? "PROPFIND timed out" : nil
        )
    }

    @Test("provider and kind names compose the subtitle")
    func subtitleComposesProviderAndKind() {
        let cal = PIMSourceRowPresentation(
            source: Self.source(status: .ready, provider: .calDAV, kind: .calendar)
        )
        #expect(cal.subtitle == "CalDAV · Calendar")

        let card = PIMSourceRowPresentation(
            source: Self.source(status: .ready, provider: .cardDAV, kind: .contacts)
        )
        #expect(card.subtitle == "CardDAV · Contacts")

        let google = PIMSourceRowPresentation(
            source: Self.source(status: .ready, provider: .google, kind: .contacts)
        )
        #expect(google.subtitle == "Google · Contacts")
    }

    @Test("connected states allow sync toggling and disconnect")
    func connectedStatesAllowSyncAndDisconnect() {
        for status: PIMSourceStatus in [.ready, .syncing, .permissionLimited] {
            let row = PIMSourceRowPresentation(source: Self.source(status: status))
            #expect(row.canToggleSync, "expected sync toggle for (status)")
            #expect(row.canDisconnect, "expected disconnect for (status)")
        }
    }

    @Test("unconnected states cannot toggle sync")
    func unconnectedStatesCannotToggleSync() {
        for status: PIMSourceStatus in [.disconnected, .connecting, .authenticationRequired, .failed] {
            let row = PIMSourceRowPresentation(source: Self.source(status: status))
            #expect(!row.canToggleSync, "unexpected sync toggle for (status)")
            #expect(!row.canDisconnect, "unexpected disconnect for (status)")
        }
    }

    @Test("reconnect is offered for states with a credential remedy")
    func reconnectOfferedForCredentialRemedy() {
        for status: PIMSourceStatus in [.disconnected, .authenticationRequired, .failed] {
            let row = PIMSourceRowPresentation(source: Self.source(status: status))
            #expect(row.canReconnect, "expected reconnect for (status)")
        }
        let ready = PIMSourceRowPresentation(source: Self.source(status: .ready))
        #expect(!ready.canReconnect)
    }

    @Test("removal is blocked only while a connect is in flight")
    func removalBlockedOnlyWhileConnecting() {
        let connecting = PIMSourceRowPresentation(source: Self.source(status: .connecting))
        #expect(!connecting.canRemove)

        for status: PIMSourceStatus in PIMSourceStatus.allCases where status != .connecting {
            let row = PIMSourceRowPresentation(source: Self.source(status: status))
            #expect(row.canRemove, "expected remove for (status)")
        }
    }

    @Test("failed sources surface the diagnostic detail")
    func failedSourcesSurfaceDetail() {
        let row = PIMSourceRowPresentation(source: Self.source(status: .failed))
        #expect(row.statusDetail == "PROPFIND timed out")

        let ready = PIMSourceRowPresentation(source: Self.source(status: .ready))
        #expect(ready.statusDetail == nil)
    }

    @Test("status presentation comes from the shared presenter")
    func statusPresentationMatchesSharedPresenter() {
        for status: PIMSourceStatus in PIMSourceStatus.allCases {
            let row = PIMSourceRowPresentation(source: Self.source(status: status))
            let shared = PIMSourceStatusPresenter.presentation(for: status)
            #expect(row.statusTitle == shared.title)
            #expect(row.statusSymbolName == shared.symbolName)
        }
    }
}
