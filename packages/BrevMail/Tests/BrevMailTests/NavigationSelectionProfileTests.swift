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
import Darwin
import Foundation
import Testing

@Suite("Synthetic navigation selection profile")
@MainActor
struct NavigationSelectionProfileTests {
    @Test("Current inputs, retained selection and invalidation at 500 and 10k headers",
          .enabled(if: ProcessInfo.processInfo.environment["BREV_PROFILE_NAVIGATION"] == "1"))
    func repeatedSelection() async throws {
        #if DEBUG
        Issue.record("Navigation profiling requires a Release build")
        return
        #else
        try await NavigationSelectionProfileHandshake.awaitTracer()
        for rows in [500, 10000] {
            for scenario in ["warm", "workflow", "refresh"] {
                measure(rows: rows, scenario: scenario)
            }
        }
        #endif
    }

    private func measure(rows: Int, scenario: String) {
        let clock = ContinuousClock()
        let before = memory()
        let setupStart = clock.now
        let fixture = NavigationSelectionAcceptanceFixture(count: rows)
        defer { fixture.cleanup() }
        if scenario != "warm" { fixture.configureWorkflow() }
        _ = fixture.presentation()
        fixture.navigation.selectMessage(fixture.headers[0], from: fixture.selectionHeaders())
        _ = fixture.navigation.selectedHeader
        let setupTime = clock.now - setupStart
        let ready = memory()
        let deadline = clock.now.advanced(by: .seconds(2))
        var projectionTime = Duration.zero
        var selectionTime = Duration.zero
        var timerTime = Duration.zero
        var iterations = 0
        var correct = true
        var checksum = 0
        while clock.now < deadline {
            let timerStart = clock.now
            timerTime += clock.now - timerStart
            let selectedIndex = (iterations * 7919) % rows
            if scenario == "refresh" {
                fixture.replaceHeader(at: selectedIndex, snippet: "Revision \(iterations)")
            }
            let projectionSpan = MailUIPerformanceDiagnostics.beginInterval("Selection Navigation Projection")
            let start = clock.now
            // Refresh includes the invalidated list build in BOTH comparison arms.
            if scenario == "refresh" { _ = fixture.presentation() }
            let projected = fixture.selectionHeaders()
            projectionTime += clock.now - start
            MailUIPerformanceDiagnostics.endInterval(projectionSpan)
            let selectionSpan = MailUIPerformanceDiagnostics.beginInterval("Selection Model Lookup")
            let selectStart = clock.now
            let selected = fixture.headers[selectedIndex]
            fixture.navigation.selectMessage(selected, from: projected)
            let resolved = fixture.navigation.selectedHeader
            selectionTime += clock.now - selectStart
            MailUIPerformanceDiagnostics.endInterval(selectionSpan)
            correct = correct && resolved == selected
            checksum &+= resolved?.id.utf8.count ?? 0
            iterations += 1
        }
        let after = memory()
        print(
            "PERF navigation.selection rows=\(rows) scenario=\(scenario) iterations=\(iterations) build=release projection_total_ms=\(ms(projectionTime)) selection_total_ms=\(ms(selectionTime)) timer_total_ms=\(ms(timerTime)) setup_ms=\(ms(setupTime)) builds=\(fixture.builds) checksum=\(checksum) heap_before=\(before.heap) heap_ready=\(ready.heap) heap_after=\(after.heap) rss_before=\(before.rss) rss_ready=\(ready.rss) rss_after=\(after.rss)"
        )
        #expect(iterations > 0)
        #expect(correct)
        #expect(checksum > 0)
        #expect(fixture.builds == (scenario == "refresh" ? iterations + 1 : 1))
    }

    private func memory() -> (heap: UInt, rss: UInt64) {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        #expect(status == KERN_SUCCESS)
        return (UInt(statistics.size_in_use), info.resident_size)
    }

    private func ms(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
    }
}
