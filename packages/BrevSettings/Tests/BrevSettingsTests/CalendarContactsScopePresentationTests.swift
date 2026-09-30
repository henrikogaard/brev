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

    @Test("available capabilities cover browsing, authoring, DAV connect and Google enablement")
    func availableCapabilitiesCoverShippingWorkflows() {
        let summary = CalendarContactsScopePresentation.summary

        #expect(summary.currentCapabilities.map(\.kind) == [
            .calendarInvites,
            .caldavInviteWrite,
            .carddavComposeAutocomplete,
            .davSourceConnect,
            .googleSourceEnablement,
            .readOnlyCalendarBrowsing,
            .readOnlyContactsBrowsing,
            .tasksBrowsing,
            .eventAuthoring,
            .contactAuthoring,
            .tasksAuthoring
        ])
        #expect(summary.currentCapabilities.allSatisfy { $0.status == .available })
    }

    @Test("unshipped capabilities are labeled not available yet, never ready")
    func unshippedCapabilitiesAreNotAvailableYet() {
        let summary = CalendarContactsScopePresentation.summary

        // Unified calendar/contact search result groups are the only
        // remaining unshipped capability; browsing and authoring ship.
        #expect(summary.unavailableCapabilities.map(\.kind) == [.unifiedPIMSearch])
        #expect(summary.unavailableCapabilities.allSatisfy { $0.status == .notAvailableYet })
    }

    @Test("authoring ships under ADR-0072 instead of staying out of scope")
    func authoringIsAcceptedScopeNotOutOfScope() {
        let summary = CalendarContactsScopePresentation.summary
        let all = summary.currentCapabilities + summary.unavailableCapabilities

        // ADR-0072 superseded ADR-0039's authoring boundary: event, contact
        // and task authoring ship with their browsing surfaces, so nothing
        // here is out of scope.
        #expect(all.allSatisfy { $0.status != .outOfScope })
        #expect(!all.contains { $0.detail.contains("outside Brev") })
        #expect(summary.currentCapabilities.contains { $0.kind == .eventAuthoring })
        #expect(summary.currentCapabilities.contains { $0.kind == .contactAuthoring })
        #expect(summary.currentCapabilities.contains { $0.kind == .tasksAuthoring })
    }
}
