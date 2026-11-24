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
import Foundation

struct UnifiedInboxSearchSource: Equatable, Sendable {
    let sourceID: MailSourceID
    let inbox: Folder
    let sourceTitle: String
    let sourceSubtitle: String
    let archiveFolder: Folder?
    private let foldersByID: [Folder.ID: Folder]

    init?(section: MailSourceSection, requiresInbox: Bool = true) {
        let fallbackFolder: Folder? = requiresInbox
            ? section.folders.first(where: { $0.role == .inbox })
            : (section.folders.first(where: { $0.role == .inbox }) ?? section.folders.first)
        guard let inbox = fallbackFolder else {
            return nil
        }
        sourceID = section.id
        self.inbox = inbox
        sourceTitle = section.title
        sourceSubtitle = section.subtitle
        archiveFolder = section.folders.first { $0.role == .archive }
        var foldersByID: [Folder.ID: Folder] = [:]
        for folder in section.folders {
            foldersByID[folder.id] = folder
        }
        self.foldersByID = foldersByID
    }

    func folder(for header: MessageHeader) -> Folder {
        foldersByID[header.folderID] ?? inbox
    }
}

/// Decides when typing a search query from a physical folder expands across
/// every visible account by default (#296, ADR-0041).
enum MailCrossAccountSearchPolicy {
    static func isActive(
        searchText: String,
        searchAllMailboxes: Bool,
        visibleSourceCount: Int,
        isSpecialDestination: Bool
    ) -> Bool {
        !isSpecialDestination
            && visibleSourceCount > 1
            && searchAllMailboxes
            && MessageListReloadPolicy.operation(forSearchText: searchText) != .folder
    }

    /// Compact iPhone navigation should not treat opening a cross-account result
    /// from another folder as sidebar folder navigation back to the list.
    static func shouldNavigateCompactOnFolderChange(
        searchOriginSourceFolderID: SourceFolderID?
    ) -> Bool {
        searchOriginSourceFolderID == nil
    }

    /// Folder-visibility synchronization must not replace `selectedFolderID` or
    /// clear `selectedMessageID` while cross-account search is presenting a
    /// result that may live in another account's hidden folder.
    static func shouldSyncSelectedFolder(
        isCrossAccountSearchActive: Bool,
        searchOriginSourceFolderID: SourceFolderID?
    ) -> Bool {
        !isCrossAccountSearchActive && searchOriginSourceFolderID == nil
    }
}

struct UnifiedInboxSearchRequest: Equatable, Sendable {
    let query: String
    let sourceIDs: [MailSourceID]
    let execution: SearchExecution
    let searchAllFolders: Bool
    let searchScope: SearchScope

    init(
        query: String,
        sourceIDs: [MailSourceID],
        execution: SearchExecution = .cacheThenServer,
        searchAllFolders: Bool = false,
        searchScope: SearchScope = .all
    ) {
        self.query = query
        self.sourceIDs = sourceIDs
        self.execution = execution
        self.searchAllFolders = searchAllFolders
        self.searchScope = searchScope
    }
}

struct UnifiedInboxSearchPlan: Equatable, Sendable {
    let source: UnifiedInboxSearchSource
    let query: SearchQuery
    let cachedPDFFolders: [Folder]?
}

enum UnifiedInboxSearchPolicy {
    static func capabilityKey(
        from sourceSections: [MailSourceSection],
        capabilities: (MailSourceID) -> BackendCapabilities
    ) -> String {
        sourceSections
            .map { section in
                "\(section.id.accountID):\(section.id.mailboxID):\(capabilities(section.id).rawValue)"
            }
            .joined(separator: "|")
    }

    static func defaultExecution(
        from sourceSections: [MailSourceSection],
        capabilities: (MailSourceID) -> BackendCapabilities
    ) -> SearchExecution {
        sourceSections.contains { section in
            capabilities(section.id).contains(.serverSideSearch)
        } ? .cacheThenServer : .cacheOnly
    }

    static func availableExecutions(
        from sourceSections: [MailSourceSection],
        capabilities: (MailSourceID) -> BackendCapabilities
    ) -> [SearchExecution] {
        let hasServerSearch = sourceSections.contains { section in
            capabilities(section.id).contains(.serverSideSearch)
        }
        guard hasServerSearch else {
            return [.cacheOnly]
        }
        return [.cacheOnly, .cacheThenServer, .serverOnly]
    }

    static func reconciledExecution(
        current: SearchExecution,
        hasUserSelection: Bool,
        from sourceSections: [MailSourceSection],
        capabilities: (MailSourceID) -> BackendCapabilities
    ) -> SearchExecutionReconciliation {
        let available = availableExecutions(from: sourceSections, capabilities: capabilities)
        let defaultExecution = defaultExecution(from: sourceSections, capabilities: capabilities)
        guard available.contains(current) else {
            return SearchExecutionReconciliation(
                execution: defaultExecution,
                hasUserSelection: false
            )
        }
        return SearchExecutionReconciliation(
            execution: hasUserSelection ? current : defaultExecution,
            hasUserSelection: hasUserSelection
        )
    }

    static func searchQuery(
        text: String,
        inboxFolderID: Folder.ID,
        execution: SearchExecution,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SearchQuery {
        NaturalLanguageSearchPlanner.plan(
            for: text,
            folderID: inboxFolderID,
            execution: execution,
            now: now,
            calendar: calendar
        ).query
    }

    static func waitingSearchPlan(
        text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> NaturalLanguageSearchPlan {
        NaturalLanguageSearchPlanner.plan(
            for: text,
            folderID: nil,
            execution: .cacheOnly,
            now: now,
            calendar: calendar
        )
    }

    static func waitingSearchQuery(
        text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SearchQuery {
        waitingSearchPlan(text: text, now: now, calendar: calendar).query
    }

    static func searchableSources(
        from sourceSections: [MailSourceSection],
        execution: SearchExecution = .cacheThenServer,
        capabilities: (MailSourceID) -> BackendCapabilities
    ) -> [UnifiedInboxSearchSource] {
        sourceSections.compactMap { section in
            guard execution != .serverOnly || capabilities(section.id).contains(.serverSideSearch) else { return nil }
            return UnifiedInboxSearchSource(section: section)
        }
    }

    static func searchPlans(
        text: String,
        from sourceSections: [MailSourceSection],
        execution: SearchExecution,
        searchAllFolders: Bool = false,
        searchScope: SearchScope = .all,
        capabilities: (MailSourceID) -> BackendCapabilities,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (plans: [UnifiedInboxSearchPlan], unavailableServerCount: Int) {
        var plans: [UnifiedInboxSearchPlan] = []
        var unavailableServerCount = 0
        for section in sourceSections {
            guard let source = UnifiedInboxSearchSource(section: section, requiresInbox: !searchAllFolders) else { continue }
            let supported = capabilities(section.id)
            let sourceExecution = execution == .cacheThenServer
                && !supported.contains(.serverSideSearch)
                ? SearchExecution.cacheOnly
                : execution
            let plan = MessageListSearchQueryPolicy.plan(
                text: text,
                folderID: searchAllFolders ? nil : source.inbox.id,
                execution: sourceExecution,
                searchScope: searchScope,
                now: now,
                calendar: calendar
            )
            guard let query = plan.resolvedQuery(in: section.folders) else { continue }
            if execution == .serverOnly, !supported.contains(.serverSideSearch) {
                unavailableServerCount += 1
            } else {
                let cachedPDFFolders: [Folder]? = plan.searchesCachedPDFs ? section.folders : nil
                plans.append(UnifiedInboxSearchPlan(source: source, query: query, cachedPDFFolders: cachedPDFFolders))
            }
        }
        return (plans, unavailableServerCount)
    }

    static func items(
        from headers: [MessageHeader],
        source: UnifiedInboxSearchSource
    ) -> [UnifiedInboxItem] {
        headers.map {
            UnifiedInboxItem(
                sourceID: source.sourceID,
                folder: source.folder(for: $0),
                header: $0,
                sourceTitle: source.sourceTitle,
                sourceSubtitle: source.sourceSubtitle,
                archiveFolder: source.archiveFolder
            )
        }
    }
}

enum UnifiedInboxSearchResponsePolicy {
    static func canApplySearchResponse(
        request: UnifiedInboxSearchRequest,
        activeRequest: UnifiedInboxSearchRequest?,
        currentSearchText: String,
        currentSourceIDs: [MailSourceID]
    ) -> Bool {
        activeRequest == request
            && currentSourceIDs == request.sourceIDs
            && MessageListReloadPolicy.operation(forSearchText: currentSearchText) == .search(
                query: request.query
            )
    }
}
