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

@testable import BrevSettings
import Testing

@Suite("CalendarContactsScopePresentation")
struct CalendarContactsScopePresentationTests {
    @Test("scope summary keeps Brev mail-first while accepting read-only PIM browsing")
    func scopeSummaryKeepsMailFirstWhileAcceptingReadOnlyBrowsing() {
        let summary = CalendarContactsScopePresentation.summary

        #expect(summary.direction == .readOnlyBrowsingAfterDAVIntegration)
        #expect(summary.currentCapabilities.map(\.kind) == [
            .calendarInvites,
            .caldavInviteWrite,
            .carddavComposeAutocomplete
        ])
        #expect(summary.plannedCapabilities.map(\.kind) == [
            .readOnlyCalendarBrowsing,
            .readOnlyContactsBrowsing,
            .unifiedPIMSearch
        ])
        #expect(summary.outOfScopeCapabilities.map(\.kind) == [
            .fullCalendarEditing,
            .fullContactManagement
        ])
    }

    @Test("full editing states explain why they are out of scope")
    func fullEditingStatesExplainWhyTheyAreOutOfScope() {
        let outOfScope = CalendarContactsScopePresentation.summary.outOfScopeCapabilities

        #expect(outOfScope.allSatisfy { $0.status == .outOfScope })
        #expect(outOfScope.allSatisfy { $0.detail.contains("Brev stays mail-first") })
    }

    @Test("planned read-only browsing is sequenced after live DAV integration")
    func plannedReadOnlyBrowsingIsSequencedAfterLiveDAVIntegration() {
        let planned = CalendarContactsScopePresentation.summary.plannedCapabilities

        #expect(planned.allSatisfy { $0.status == .plannedAfterLiveDAV })
        #expect(planned.allSatisfy { $0.detail.contains("#121") })
    }
}
