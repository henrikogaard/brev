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
    @Test("the direction reflects optional connected sources (ADR-0072)")
    func directionReflectsOptionalConnectedSources() {
        let summary = CalendarContactsScopePresentation.summary

        #expect(summary.direction == .optionalConnectedSources)
    }

    @Test("available capabilities cover shipping mail workflows and DAV connect")
    func availableCapabilitiesCoverShippingWorkflows() {
        let summary = CalendarContactsScopePresentation.summary

        #expect(summary.currentCapabilities.map(\.kind) == [
            .calendarInvites,
            .caldavInviteWrite,
            .carddavComposeAutocomplete,
            .davSourceConnect
        ])
        #expect(summary.currentCapabilities.allSatisfy { $0.status == .available })
    }

    @Test("unshipped capabilities are labeled not available yet, never ready")
    func unshippedCapabilitiesAreNotAvailableYet() {
        let summary = CalendarContactsScopePresentation.summary

        #expect(summary.unavailableCapabilities.map(\.kind) == [
            .googleSourceEnablement,
            .readOnlyCalendarBrowsing,
            .readOnlyContactsBrowsing,
            .unifiedPIMSearch,
            .eventAuthoring,
            .contactAuthoring
        ])
        #expect(summary.unavailableCapabilities.allSatisfy { $0.status == .notAvailableYet })
    }

    @Test("authoring is accepted scope, not permanently out of scope")
    func authoringIsAcceptedScopeNotOutOfScope() {
        let summary = CalendarContactsScopePresentation.summary
        let all = summary.currentCapabilities + summary.unavailableCapabilities

        // ADR-0072 superseded ADR-0039's authoring boundary: event and
        // contact authoring ship as #7/#9, so nothing here is out of scope.
        #expect(all.allSatisfy { $0.status != .outOfScope })
        #expect(!all.contains { $0.detail.contains("outside Brev") })
    }
}
