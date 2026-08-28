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

enum MessageListPaginationTriggerPolicy {
    static func shouldLoadMore(
        appearingIndex: Int,
        totalCount: Int,
        hasMore: Bool,
        isLoadingMore: Bool,
        isSearching: Bool
    ) -> Bool {
        guard hasMore,
              !isLoadingMore,
              !isSearching,
              totalCount > 0,
              appearingIndex >= 0,
              appearingIndex < totalCount
        else {
            return false
        }
        return appearingIndex >= max(0, totalCount - 8)
    }
}
