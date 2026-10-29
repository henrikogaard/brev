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

@Suite("Synthetic navigation selection profile")
@MainActor
struct NavigationSelectionProfileTests {
    @Test("10k loaded headers, repeated projection and selection",
          .enabled(if: ProcessInfo.processInfo.environment["BREV_PROFILE_NAVIGATION"] == "1"))
    func repeatedSelection() async throws {
        #if DEBUG
        Issue.record("Navigation profiling requires a Release build")
        return
        #else
        let headers = (0 ..< 10000).map { index in
            MessageHeader(id: "synthetic:\(index)", threadID: "thread-\(index / 3)", folderID: "synthetic",
                          from: Correspondent(email: "sender@example.test"), subject: "Synthetic", snippet: "",
                          date: Date(timeIntervalSince1970: TimeInterval(index)))
        }
        let navigation = MailNavigationState(selectedFolderID: "synthetic")
        // Give the isolated CI tracer time to attach before the measured workload starts.
        try await Task.sleep(for: .seconds(10))
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(25))
        var projectionTime = Duration.zero
        var selectionTime = Duration.zero
        var iterations = 0
        while clock.now < deadline {
            let projectionSpan = MailUIPerformanceDiagnostics.beginInterval("Selection Navigation Projection")
            let start = clock.now
            let projected = MessageListNavigationHeaders.headers(from: headers, threadContext: headers)
            projectionTime += clock.now - start
            MailUIPerformanceDiagnostics.endInterval(projectionSpan)
            let selectionSpan = MailUIPerformanceDiagnostics.beginInterval("Selection Model Lookup")
            let selectStart = clock.now
            let selected = headers[iterations % headers.count]
            navigation.selectMessage(selected, from: projected)
            let resolved = navigation.selectedHeader
            selectionTime += clock.now - selectStart
            MailUIPerformanceDiagnostics.endInterval(selectionSpan)
            #expect(resolved?.id == selected.id)
            iterations += 1
        }
        print(
            "PERF navigation.selection rows=10000 iterations=\(iterations) build=release projection_total_ms=\(ms(projectionTime)) selection_total_ms=\(ms(selectionTime))"
        )
        #expect(iterations > 0)
        #endif
    }

    private func ms(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
    }
}
