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

/// Serializes IMAP schedule editing/delivery across live instances of the same account.
final class ScheduledSendWorkGate: @unchecked Sendable {
    private final class WeakGate {
        weak var value: ScheduledSendWorkGate?
        init(_ value: ScheduledSendWorkGate) { self.value = value }
    }

    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var gates: [String: WeakGate] = [:]
    }

    private static let registry = Registry()
    private let lock = NSLock()
    private enum Resource { case deliveryPass, draft(String, editing: Bool) }
    private var owners: [UUID: Resource] = [:]

    static func forAccount(_ accountID: String) -> ScheduledSendWorkGate {
        registry.lock.withLock {
            if let existing = registry.gates[accountID]?.value { return existing }
            let gate = ScheduledSendWorkGate()
            registry.gates = registry.gates.filter { $0.value.value != nil }
            registry.gates[accountID] = WeakGate(gate)
            return gate
        }
    }

    func acquireDeliveryPass() -> UUID? {
        lock.withLock {
            guard !owners.values.contains(where: { if case .deliveryPass = $0 { return true }; return false }) else { return nil }
            let id = UUID()
            owners[id] = .deliveryPass
            return id
        }
    }

    func acquireDraft(_ draftID: String, editing: Bool) -> UUID? {
        lock.withLock {
            guard !owners.values.contains(where: { if case .draft(let id, _) = $0 { return id == draftID }; return false })
            else { return nil }
            let id = UUID()
            owners[id] = .draft(draftID, editing: editing)
            return id
        }
    }

    func isDelivering(_ draftID: String) -> Bool {
        lock
            .withLock {
                owners.values
                    .contains { if case .draft(let id, let editing) = $0 { return id == draftID && !editing }; return false }
            }
    }

    func release(_ id: UUID) { _ = lock.withLock { owners.removeValue(forKey: id) } }
}
