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

@testable import BrevMail
import Testing

@Suite("MessageListRefreshArrivalPolicy")
struct MessageListRefreshArrivalPolicyTests {
    @Test("returns only new first-page IDs in server order")
    func returnsOnlyNewFirstPageIDsInServerOrder() {
        let arrivals = MessageListRefreshArrivalPolicy.arrivalIDs(
            refreshedFirstPageIDs: ["latest", "newer", "known"],
            previousLoadedIDs: ["known", "older"],
            previousFirstPageWasLoaded: true,
            isSameFolder: true
        )

        #expect(arrivals == ["latest", "newer"])
    }

    @Test("does not animate an initial folder load or a folder switch")
    func doesNotAnimateInitialFolderLoadOrFolderSwitch() {
        #expect(MessageListRefreshArrivalPolicy.arrivalIDs(
            refreshedFirstPageIDs: ["one", "two"],
            previousLoadedIDs: [],
            previousFirstPageWasLoaded: false,
            isSameFolder: true
        ).isEmpty)
        #expect(MessageListRefreshArrivalPolicy.arrivalIDs(
            refreshedFirstPageIDs: ["one", "two"],
            previousLoadedIDs: ["old"],
            previousFirstPageWasLoaded: true,
            isSameFolder: false
        ).isEmpty)
    }

    @Test("animates arrivals after a completed empty first page")
    func animatesArrivalsAfterACompletedEmptyFirstPage() {
        let arrivals = MessageListRefreshArrivalPolicy.arrivalIDs(
            refreshedFirstPageIDs: ["latest", "newer"],
            previousLoadedIDs: [],
            previousFirstPageWasLoaded: true,
            isSameFolder: true
        )

        #expect(arrivals == ["latest", "newer"])
    }

    @Test("does not apply arrival effects to search results")
    func doesNotApplyArrivalEffectsToSearchResults() {
        #expect(!MessageListRefreshArrivalPolicy.shouldAnimate(
            headerID: "latest",
            arrivalIDs: ["latest"],
            isSearchActive: true
        ))
    }

    @Test("caps the animation batch to protect list responsiveness")
    func capsTheAnimationBatchToProtectListResponsiveness() {
        let refreshedIDs = (0 ... 10).map { "message-\($0)" }

        let arrivals = MessageListRefreshArrivalPolicy.arrivalIDs(
            refreshedFirstPageIDs: refreshedIDs,
            previousLoadedIDs: [],
            previousFirstPageWasLoaded: true,
            isSameFolder: true
        )

        #expect(arrivals == Array(refreshedIDs.prefix(MessageListRefreshArrivalPolicy.maximumAnimatedArrivals)))
    }
}
