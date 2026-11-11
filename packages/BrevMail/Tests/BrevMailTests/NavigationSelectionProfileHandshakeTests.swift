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

import Foundation
import notify
import Testing

@Suite("Synthetic profiling tracer handshake")
struct NavigationSelectionProfileHandshakeTests {
    @Test("requires the harness configuration instead of proceeding untraced")
    func requiresConfiguration() async {
        await #expect(throws: NavigationSelectionProfileHandshake.Failure.missingConfiguration) {
            try await NavigationSelectionProfileHandshake.awaitTracer(environment: [:])
        }
    }

    @Test("publishes its PID before waiting and proceeds once tracing starts")
    func publishesPIDThenWaitsForTracer() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let notification = "eu.brevmail.brev.profile.test.\(UUID().uuidString)"
        let waiter = Task {
            try await NavigationSelectionProfileHandshake.awaitTracer(
                directory: directory, notification: notification, timeout: .seconds(5)
            )
        }
        defer { waiter.cancel() }
        let pidURL = URL(fileURLWithPath: directory).appendingPathComponent("workload.pid")
        for _ in 0 ..< 200 where !FileManager.default.fileExists(atPath: pidURL.path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let published = try String(contentsOf: pidURL, encoding: .utf8)
        #expect(published == String(getpid()))
        #expect(!FileManager.default.fileExists(atPath: directory + "/workload.ready"))
        notify_post(notification + ".unrelated")
        try await Task.sleep(for: .milliseconds(200))
        #expect(!FileManager.default.fileExists(atPath: directory + "/workload.ready"))
        notify_post(notification)
        try await waiter.value
        #expect(FileManager.default.fileExists(atPath: directory + "/workload.ready"))
    }

    @Test("fails within its budget when tracing never starts")
    func failsWhenTracerNeverStarts() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let notification = "eu.brevmail.brev.profile.test.\(UUID().uuidString)"
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: NavigationSelectionProfileHandshake.Failure.tracerDidNotStart) {
            try await NavigationSelectionProfileHandshake.awaitTracer(
                directory: directory, notification: notification, timeout: .milliseconds(300)
            )
        }
        #expect(clock.now - start < .seconds(3))
        #expect(!FileManager.default.fileExists(atPath: directory + "/workload.ready"))
    }

    private func makeDirectory() throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.path
    }
}
