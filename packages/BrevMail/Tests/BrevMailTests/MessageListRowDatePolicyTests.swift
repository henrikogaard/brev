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
import Foundation
import Testing

@Suite("Message list row date policy")
struct MessageListRowDatePolicyTests {
    private struct Row {
        let id: String
        let group: String?
        let date: Date
    }

    @Test("empty wake overrides do not aggregate original group dates")
    func emptyOverridesLeaveVisibleGroupsUntouched() {
        let parent = Row(id: "parent", group: "thread", date: Date(timeIntervalSince1970: 1))
        let newerMember = Row(id: "newer-member", group: "thread", date: Date(timeIntervalSince1970: 2))
        let overrides = MessageListRowDatePolicy.overrides(
            for: [parent],
            from: [parent, newerMember],
            groupKey: \.group,
            itemID: \.id,
            date: \.date,
            effectiveDateOverrides: [:]
        )

        #expect(overrides.isEmpty)
    }

    @Test("an untouched group keeps its row date when another group wakes")
    func wakeAggregationDoesNotChangeUntouchedGroups() {
        let wakeParent = Row(id: "wake-parent", group: "wake-thread", date: Date(timeIntervalSince1970: 1))
        let wakeMember = Row(id: "wake-member", group: "wake-thread", date: Date(timeIntervalSince1970: 0))
        let untouchedParent = Row(id: "untouched-parent", group: "untouched-thread", date: Date(timeIntervalSince1970: 3))
        let newerUntouchedMember = Row(id: "untouched-member", group: "untouched-thread", date: Date(timeIntervalSince1970: 4))
        let wakeAt = Date(timeIntervalSince1970: 5)
        let overrides = MessageListRowDatePolicy.overrides(
            for: [wakeParent, untouchedParent],
            from: [wakeParent, wakeMember, untouchedParent, newerUntouchedMember],
            groupKey: \.group,
            itemID: \.id,
            date: \.date,
            effectiveDateOverrides: [wakeMember.id: wakeAt]
        )

        #expect(overrides == [wakeParent.id: wakeAt])
    }

    @Test("singleton wake overrides remain and older wakes do not demote a group")
    func singletonAndNoDemotionRemainCorrect() {
        let parent = Row(id: "parent", group: "thread", date: Date(timeIntervalSince1970: 10))
        let wakeMember = Row(id: "wake-member", group: "thread", date: Date(timeIntervalSince1970: 8))
        let singleton = Row(id: "singleton", group: "singleton", date: Date(timeIntervalSince1970: 4))
        let olderWake = Date(timeIntervalSince1970: 9)
        let singletonWake = Date(timeIntervalSince1970: 7)
        let overrides = MessageListRowDatePolicy.overrides(
            for: [parent, singleton],
            from: [parent, wakeMember, singleton],
            groupKey: \.group,
            itemID: \.id,
            date: \.date,
            effectiveDateOverrides: [wakeMember.id: olderWake, singleton.id: singletonWake]
        )

        #expect(overrides == [singleton.id: singletonWake])
    }
}
