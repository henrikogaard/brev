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

@Suite("MailRefreshAction")
struct MailRefreshActionTests {
    @Test("refresh action invokes the root-owned refresh closure")
    @MainActor
    func refreshActionInvokesRootOwnedClosure() async {
        var callCount = 0
        let action = MailRefreshAction {
            callCount += 1
        }

        await action()

        #expect(callCount == 1)
    }

    @Test("refresh action exposes pending refresh state")
    @MainActor
    func refreshActionExposesPendingRefreshState() {
        let action = MailRefreshAction(isRefreshing: true) {}

        #expect(action.isRefreshing)
        #expect(!action.isAvailable)
    }

    @Test("refresh action exposes blocked refresh state")
    @MainActor
    func refreshActionExposesBlockedRefreshState() {
        let action = MailRefreshAction(isBlocked: true) {}

        #expect(action.isBlocked)
        #expect(!action.isAvailable)
    }

    @Test("unavailable refresh actions do not invoke closures")
    @MainActor
    func unavailableRefreshActionsDoNotInvokeClosures() async {
        var callCount = 0
        let refreshing = MailRefreshAction(isRefreshing: true) {
            callCount += 1
        }
        let blocked = MailRefreshAction(isBlocked: true) {
            callCount += 1
        }

        await refreshing()
        await blocked()

        #expect(callCount == 0)
    }
}
