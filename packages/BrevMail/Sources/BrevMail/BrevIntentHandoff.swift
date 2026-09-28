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
import Observation

/// In-process handoff between Brev's App Intents and the running app.
///
/// App Intents execute inside the app process when `openAppWhenRun`
/// foregrounds the app, so an intent can enqueue a request here instead
/// of round-tripping through a `brev://` URL. The app drains the
/// request once its mail root is live. Observable so a drain fires
/// immediately when the intent runs while the app is already in the
/// foreground (no scene-phase transition to hook).
@Observable
@MainActor
public final class BrevIntentHandoff {
    public static let shared = BrevIntentHandoff()

    /// The latest compose request an intent enqueued; nil once drained.
    public private(set) var pendingComposePrefill: ComposePrefill?

    /// Monotonic counter the mail root watches; each increment is one
    /// refresh request, so repeated Check Mail runs still refire.
    public private(set) var refreshRequestCount = 0

    private init() {}

    /// Enqueue a compose request from an intent.
    public func requestCompose(prefill: ComposePrefill) {
        pendingComposePrefill = prefill
    }

    /// Enqueue a refresh request from an intent. `openAppWhenRun` causes
    /// no scene-phase transition when the app is already active, so the
    /// refresh cannot ride the foreground path alone.
    public func requestRefresh() {
        refreshRequestCount += 1
    }

    /// Clear the pending request after the app has consumed it.
    public func clearComposePrefill() {
        pendingComposePrefill = nil
    }
}
