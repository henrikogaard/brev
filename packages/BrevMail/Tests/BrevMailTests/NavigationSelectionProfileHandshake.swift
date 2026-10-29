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

/// Coordinates the synthetic profiling workload with the shell harness tracer:
/// subscribe to the tracer's start notification, publish this process ID, then
/// wait (bounded) until recording has actually started.
enum NavigationSelectionProfileHandshake {
    /// Handshake failures surfaced to the synthetic workload.
    enum Failure: Error, Equatable {
        case missingConfiguration
        case registrationFailed(UInt32)
        case checkFailed(UInt32)
        case tracerDidNotStart
    }

    static func awaitTracer(environment: [String: String] = ProcessInfo.processInfo.environment) async throws {
        guard let directory = environment["BREV_PROFILE_HANDSHAKE_DIR"],
              !directory.isEmpty,
              let notification = environment["BREV_PROFILE_TRACING_NOTIFICATION"],
              !notification.isEmpty else { throw Failure.missingConfiguration }
        try await awaitTracer(directory: directory, notification: notification, timeout: .seconds(120))
    }

    /// - Parameters:
    ///   - directory: Private harness output directory receiving `workload.pid` and `workload.ready`.
    ///   - notification: Darwin notification name the tracer posts once recording started.
    ///   - timeout: Maximum time to wait for the tracer after publishing the PID.
    static func awaitTracer(directory: String, notification: String, timeout: Duration) async throws {
        var token: Int32 = 0
        let status = notify_register_check(notification, &token)
        guard status == UInt32(NOTIFY_STATUS_OK) else { throw Failure.registrationFailed(status) }
        defer { notify_cancel(token) }
        // The first check always reports a change; drain it before publishing readiness.
        _ = try hasNotification(token)
        try publish(String(getpid()), as: "workload.pid", in: directory)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if try hasNotification(token) {
                try publish(notification, as: "workload.ready", in: directory)
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Failure.tracerDidNotStart
    }

    private static func hasNotification(_ token: Int32) throws -> Bool {
        var changed: Int32 = 0
        let status = notify_check(token, &changed)
        guard status == UInt32(NOTIFY_STATUS_OK) else { throw Failure.checkFailed(status) }
        return changed != 0
    }

    private static func publish(_ contents: String, as name: String, in directory: String) throws {
        let base = URL(fileURLWithPath: directory)
        try contents.write(to: base.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
}
