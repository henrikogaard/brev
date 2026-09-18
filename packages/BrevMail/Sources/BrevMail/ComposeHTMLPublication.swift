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

/// Bounds rich-editor HTML publication so selection and typing updates can
/// coalesce without delaying the editor's visible text or selection state.
enum ComposeHTMLPublicationPolicy {
    /// A short window keeps the published draft body fresh while avoiding a
    /// full attributed-string walk for every SwiftUI update.
    static let debounceNanoseconds: UInt64 = 50_000_000
}

/// Deterministic state machine for a debounced publication stream.
///
/// The editor owns the wall-clock task; this value type owns generation and
/// pending-value semantics so coalescing and flush behavior stay testable
/// without sleeping in tests.
struct ComposeDebouncedPublicationState<Value> {
    private(set) var generation: UInt64 = 0
    private var pendingValue: Value?

    /// Replaces the pending value and returns its generation token.
    mutating func schedule(_ value: Value) -> UInt64 {
        generation &+= 1
        pendingValue = value
        return generation
    }

    /// Takes a value only when the generation is still current.
    mutating func takePending(for generation: UInt64) -> Value? {
        guard self.generation == generation else { return nil }
        defer { pendingValue = nil }
        return pendingValue
    }

    /// Takes the newest value immediately and invalidates delayed work.
    mutating func flush() -> Value? {
        let value = pendingValue
        pendingValue = nil
        generation &+= 1
        return value
    }

    /// Whether a delayed serializer result may still be published.
    func isCurrent(_ generation: UInt64) -> Bool {
        self.generation == generation
    }
}

/// Main-actor bridge that coalesces rich HTML serialization and supports a
/// synchronous flush before a draft is saved or sent.
final class ComposeHTMLPublicationController<Value> {
    /// The pending payload is a producer, not a snapshot: building the value
    /// (a full attributed-string copy for the rich editor) is only paid when
    /// the debounce actually fires, not on every keystroke or SwiftUI update.
    private var state = ComposeDebouncedPublicationState<() -> Value>()
    private var publicationTask: Task<Void, Never>?
    private var lastPublished: String?
    private let serialize: (Value) -> String
    private let publish: (String) -> Void
    private let delayNanoseconds: UInt64

    /// Creates a debounced publication controller.
    init(
        delayNanoseconds: UInt64 = ComposeHTMLPublicationPolicy.debounceNanoseconds,
        serialize: @escaping (Value) -> String,
        publish: @escaping (String) -> Void
    ) {
        self.delayNanoseconds = delayNanoseconds
        self.serialize = serialize
        self.publish = publish
    }

    /// Schedules the newest editor snapshot for publication. The producer is
    /// invoked only if this generation survives the debounce window.
    func schedule(produce value: @escaping () -> Value) {
        let generation = state.schedule(value)
        publicationTask?.cancel()
        publicationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.delayNanoseconds ?? 0)
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  let pending = state.takePending(for: generation) else {
                return
            }
            let serialized = serialize(pending())
            guard !Task.isCancelled, state.isCurrent(generation) else { return }
            publishIfChanged(serialized)
        }
    }

    /// Schedules an already-materialized snapshot for publication.
    func schedule(_ value: Value) {
        schedule(produce: { value })
    }

    /// Publishes the newest pending snapshot synchronously for save/send.
    func flush() {
        publicationTask?.cancel()
        publicationTask = nil
        guard let pending = state.flush() else { return }
        publishIfChanged(serialize(pending()))
    }

    /// Cancels delayed work and drops any unpublished snapshot.
    func cancel() {
        publicationTask?.cancel()
        publicationTask = nil
        _ = state.flush()
        // The caller clears the published value itself (e.g. leaving rich
        // mode), so the next publication must not be skipped as unchanged.
        lastPublished = nil
    }

    /// Skips redundant binding writes when serialization produced the exact
    /// HTML that is already published.
    private func publishIfChanged(_ serialized: String) {
        guard serialized != lastPublished else { return }
        lastPublished = serialized
        publish(serialized)
    }

    deinit {
        publicationTask?.cancel()
    }
}

/// Shared reference used by ComposeView to flush the active platform editor.
final class ComposeHTMLPublicationFlushBox {
    var flush: (() -> Void)?

    /// Flushes the active editor when one is mounted.
    func performFlush() {
        flush?()
    }
}
