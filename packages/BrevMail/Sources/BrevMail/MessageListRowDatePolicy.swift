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

enum MessageListRowDatePolicy {
    static func overrides<Item, ItemID: Hashable, GroupID: Hashable>(
        for rows: [Item],
        from visibleMembers: [Item],
        groupKey: (Item) -> GroupID?,
        itemID: (Item) -> ItemID,
        date: (Item) -> Date,
        effectiveDateOverrides: [ItemID: Date]
    ) -> [ItemID: Date] {
        var groupsWithEffectiveOverrides: Set<GroupID> = []
        for member in visibleMembers {
            guard let group = groupKey(member) else { continue }
            guard effectiveDateOverrides[itemID(member)] != nil else { continue }
            groupsWithEffectiveOverrides.insert(group)
        }

        var newestDateByGroup: [GroupID: Date] = [:]
        for member in visibleMembers {
            guard let group = groupKey(member), groupsWithEffectiveOverrides.contains(group) else { continue }
            let headerDate = date(member)
            let effectiveDate = max(effectiveDateOverrides[itemID(member)] ?? headerDate, headerDate)
            newestDateByGroup[group] = max(newestDateByGroup[group] ?? .distantPast, effectiveDate)
        }

        var rowDateOverrides: [ItemID: Date] = [:]
        for row in rows {
            let headerDate = date(row)
            let groupedEffectiveDate = groupKey(row).flatMap { group in
                groupsWithEffectiveOverrides.contains(group) ? newestDateByGroup[group] : nil
            }
            let effectiveDate = groupedEffectiveDate
                ?? max(effectiveDateOverrides[itemID(row)] ?? headerDate, headerDate)
            if effectiveDate > headerDate {
                rowDateOverrides[itemID(row)] = effectiveDate
            }
        }
        return rowDateOverrides
    }
}
