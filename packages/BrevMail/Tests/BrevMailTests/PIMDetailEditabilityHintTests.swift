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
@testable import BrevMail
import Foundation
import Testing

/// Coverage for the read-only explainer shown on PIM detail panes when
/// no Edit/Delete affordances are wired (UI/UX review 2026-09-27 M4/P1).
@Suite("PIMDetailEditabilityHint")
struct PIMDetailEditabilityHintTests {
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private func source(
        writable: Bool = false
    ) -> PIMSource {
        PIMSource(
            id: "s1",
            kind: .calendar,
            provider: .calDAV,
            displayName: "s1",
            enabledCapabilities: writable ? [.read, .write] : [.read],
            status: .ready,
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
    }

    private func collection(
        isReadOnly: Bool = false
    ) -> PIMCollection {
        PIMCollection(
            id: "c1",
            sourceID: "s1",
            kind: .calendar,
            displayName: "c1",
            colorHex: nil,
            isReadOnly: isReadOnly,
            isPrimary: false,
            supportsSyncToken: true,
            providerKey: "c1",
            providerVersion: nil,
            isVisible: true,
            updatedAt: fixedNow
        )
    }

    @Test("no hint while edit actions are available")
    func noHintWhenEditable() {
        #expect(
            PIMDetailEditabilityHint.text(
                source: source(),
                collection: collection(),
                editActionsAvailable: true
            ) == nil
        )
    }

    @Test("no hint when the source cannot be resolved")
    func noHintWithoutSource() {
        #expect(
            PIMDetailEditabilityHint.text(
                source: nil,
                collection: nil,
                editActionsAvailable: false
            ) == nil
        )
    }

    @Test("server read-only collection explains itself")
    func serverReadOnlyHint() {
        let hint = PIMDetailEditabilityHint.text(
            source: source(writable: true),
            collection: collection(isReadOnly: true),
            editActionsAvailable: false
        )
        #expect(hint?.contains("read-only") == true)
        #expect(hint?.contains("Allow editing") == false)
    }

    @Test("missing write capability points at the Allow editing toggle")
    func writeDisabledHint() {
        let hint = PIMDetailEditabilityHint.text(
            source: source(writable: false),
            collection: collection(),
            editActionsAvailable: false
        )
        #expect(hint?.contains("Allow editing") == true)
    }

    @Test("writable source with hidden actions stays undiagnosed")
    func writableButHiddenStaysSilent() {
        #expect(
            PIMDetailEditabilityHint.text(
                source: source(writable: true),
                collection: collection(),
                editActionsAvailable: false
            ) == nil
        )
    }
}
