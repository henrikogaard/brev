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

@Suite("Message list pagination")
struct MessageListPaginationTests {
    @Test("load more starts within the final eight visible rows")
    func loadMoreStartsWithinFinalEightVisibleRows() {
        #expect(MessageListPaginationTriggerPolicy.shouldLoadMore(
            appearingIndex: 4,
            totalCount: 12,
            hasMore: true,
            isLoadingMore: false,
            isSearching: false
        ))
        #expect(!MessageListPaginationTriggerPolicy.shouldLoadMore(
            appearingIndex: 3,
            totalCount: 12,
            hasMore: true,
            isLoadingMore: false,
            isSearching: false
        ))
    }

    @Test("load more stays disabled without another folder page")
    func loadMoreStaysDisabledWithoutAnotherFolderPage() {
        #expect(!MessageListPaginationTriggerPolicy.shouldLoadMore(
            appearingIndex: 11,
            totalCount: 12,
            hasMore: false,
            isLoadingMore: false,
            isSearching: false
        ))
        #expect(!MessageListPaginationTriggerPolicy.shouldLoadMore(
            appearingIndex: 11,
            totalCount: 12,
            hasMore: true,
            isLoadingMore: true,
            isSearching: false
        ))
        #expect(!MessageListPaginationTriggerPolicy.shouldLoadMore(
            appearingIndex: 11,
            totalCount: 12,
            hasMore: true,
            isLoadingMore: false,
            isSearching: true
        ))
    }
}
