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

/// The small dot on a list avatar that says which account a message came
/// from (#306 slice 5). Colours come from the theme's avatar palette.
enum MessageListAccountDot {
    /// The palette slot for an account. Accounts take slots in sidebar order,
    /// so two accounts only share a colour when there are more accounts than
    /// colours. Nil when the list shows a single account, the account is not
    /// in the list, or the theme has no palette.
    static func paletteIndex(accountID: String, orderedAccountIDs: [String], paletteCount: Int) -> Int? {
        guard paletteCount > 0, orderedAccountIDs.count > 1,
              let position = orderedAccountIDs.firstIndex(of: accountID)
        else { return nil }
        return position % paletteCount
    }

    /// Account IDs in the order the sources list them, each account once.
    static func orderedAccountIDs(_ sourceAccountIDs: [String]) -> [String] {
        var seen = Set<String>()
        return sourceAccountIDs.filter { seen.insert($0).inserted }
    }
}
