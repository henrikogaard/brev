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

import BackgroundTasks
@testable import BrevIOS
import Foundation
import Testing

@Suite("BrevBackgroundRefreshCoordinator")
struct BackgroundRefreshCoordinatorTests {
    @Test("task identifier is listed in BGTaskSchedulerPermittedIdentifiers")
    func taskIdentifierIsPermitted() {
        // Registration silently fails when the identifier is missing from the
        // app's Info.plist, so pin the constant to the declared value. The
        // test bundle is hosted in BrevIOS, so Bundle.main is the app.
        let permitted = Bundle.main.object(
            forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers"
        ) as? [String]
        #expect(permitted?.contains(BrevBackgroundRefreshCoordinator.taskIdentifier) == true)
    }

    @Test("refresh request uses the registered identifier and a 15-minute earliest begin date")
    func refreshRequestMatchesPolicy() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let request = BrevBackgroundRefreshCoordinator.makeRefreshRequest(now: now)

        #expect(request.identifier == BrevBackgroundRefreshCoordinator.taskIdentifier)
        #expect(request.earliestBeginDate == now.addingTimeInterval(15 * 60))
    }

    @Test("scheduleNextRefresh submits exactly one refresh request")
    func scheduleSubmitsOneRequest() {
        var submitted: [BGAppRefreshTaskRequest] = []
        BrevBackgroundRefreshCoordinator.scheduleNextRefresh { request in
            submitted.append(request)
        }

        #expect(submitted.count == 1)
        #expect(submitted.first?.identifier == BrevBackgroundRefreshCoordinator.taskIdentifier)
    }

    @Test("a scheduler failure is logged and swallowed")
    func scheduleSwallowsSchedulerErrors() {
        struct SchedulerError: Error {}
        var submitCalls = 0

        // Must not propagate — a missed background refresh is not critical.
        BrevBackgroundRefreshCoordinator.scheduleNextRefresh { _ in
            submitCalls += 1
            throw SchedulerError()
        }

        #expect(submitCalls == 1)
    }
}
