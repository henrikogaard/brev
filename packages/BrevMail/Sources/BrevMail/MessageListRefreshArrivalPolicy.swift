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

enum MessageListRefreshArrivalPolicy {
    /// A small cap keeps a large mailbox reconciliation from creating enough
    /// simultaneous animations to compete with list layout and scrolling.
    static let maximumAnimatedArrivals = 6

    /// Returns new first-page headers that should receive the refresh-arrival
    /// treatment. Initial loads and folder switches deliberately return none:
    /// cached mail must remain immediately usable, never animate in as filler.
    static func arrivalIDs(
        refreshedFirstPageIDs: [MessageHeader.ID],
        previousLoadedIDs: Set<MessageHeader.ID>,
        previousFirstPageWasLoaded: Bool,
        isSameFolder: Bool
    ) -> [MessageHeader.ID] {
        guard previousFirstPageWasLoaded, isSameFolder else { return [] }
        return refreshedFirstPageIDs
            .filter { !previousLoadedIDs.contains($0) }
            .prefix(maximumAnimatedArrivals)
            .map(\.self)
    }

    /// Search results use their own loading path and must never inherit the
    /// short-lived arrival treatment from a mailbox refresh.
    static func shouldAnimate(
        headerID: MessageHeader.ID,
        arrivalIDs: [MessageHeader.ID],
        isSearchActive: Bool
    ) -> Bool {
        !isSearchActive && arrivalIDs.contains(headerID)
    }
}
