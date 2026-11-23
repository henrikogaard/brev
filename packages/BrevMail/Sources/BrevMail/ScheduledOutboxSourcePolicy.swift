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

struct ScheduledOutboxContext: Hashable {
    let backendID: ObjectIdentifier
    let sourceID: MailSourceID?
}

struct ScheduledOutboxContextTransition {
    private(set) var context: ScheduledOutboxContext?
    private(set) var generation = 0

    mutating func transition(to context: ScheduledOutboxContext) -> Bool {
        guard self.context != context else { return false }
        self.context = context
        generation += 1
        return true
    }
}

enum ScheduledOutboxSourcePolicy {
    static func visibleEntries(
        _ entries: [PendingScheduledSend],
        selectedSourceID: MailSourceID?
    ) -> [PendingScheduledSend] {
        entries.filter { $0.sourceID == nil || $0.sourceID == selectedSourceID }
    }

    static func isCurrent(
        requested: ScheduledOutboxContext,
        current: ScheduledOutboxContext,
        generation: Int,
        currentGeneration: Int,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled && requested == current && generation == currentGeneration
    }

    static func isLoaded(
        loaded: ScheduledOutboxContext?,
        requested: ScheduledOutboxContext,
        loadedGeneration: Int,
        currentGeneration: Int
    ) -> Bool {
        loaded == requested && loadedGeneration == currentGeneration
    }
}
