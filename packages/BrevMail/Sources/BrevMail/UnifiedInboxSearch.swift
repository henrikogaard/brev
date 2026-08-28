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

    init?(section: MailSourceSection, capabilities: BackendCapabilities, execution: SearchExecution) {
        guard let inbox = section.folders.first(where: { $0.role == .inbox }) else {
            return nil
        }
        if execution == .serverOnly, !capabilities.contains(.serverSideSearch) {
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

struct UnifiedInboxSearchRequest: Equatable, Sendable {
    let query: String
    let sourceIDs: [MailSourceID]
    let execution: SearchExecution

    init(
        query: String,
        sourceIDs: [MailSourceID],
        execution: SearchExecution = .cacheThenServer
    ) {
        self.query = query
        self.sourceIDs = sourceIDs
        self.execution = execution
    }
}

struct UnifiedInboxSearchPlan: Equatable, Sendable {
    let source: UnifiedInboxSearchSource
    let query: SearchQuery
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

    static func searchableSources(
        from sourceSections: [MailSourceSection],
        execution: SearchExecution = .cacheThenServer,
        capabilities: (MailSourceID) -> BackendCapabilities
    ) -> [UnifiedInboxSearchSource] {
        sourceSections.compactMap { section in
            UnifiedInboxSearchSource(
                section: section,
                capabilities: capabilities(section.id),
                execution: execution
            )
        }
    }

    static func searchPlans(
        text: String,
        from sourceSections: [MailSourceSection],
        execution: SearchExecution,
        capabilities: (MailSourceID) -> BackendCapabilities,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [UnifiedInboxSearchPlan] {
        searchableSources(
            from: sourceSections,
            execution: execution,
            capabilities: capabilities
        ).map { source in
            let sourceExecution = execution == .cacheThenServer
                && !capabilities(source.sourceID).contains(.serverSideSearch)
                ? SearchExecution.cacheOnly
                : execution
            return UnifiedInboxSearchPlan(
                source: source,
                query: searchQuery(
                    text: text,
                    inboxFolderID: source.inbox.id,
                    execution: sourceExecution,
                    now: now,
                    calendar: calendar
                )
            )
        }
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
