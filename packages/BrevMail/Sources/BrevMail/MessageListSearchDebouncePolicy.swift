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
import CoreGraphics

enum MessageListSearchFieldPlatform: Equatable, Sendable {
    case iOS
    case macOS
}

enum MessageListSearchFieldPlacement: Equatable, Sendable {
    case inPaneField
    case nativeSearchable
}

struct MessageListSearchFieldConfiguration: Equatable, Sendable {
    let placement: MessageListSearchFieldPlacement
    let disablesAutocorrection: Bool
    let hidesInputAssistant: Bool
    let chromeHeight: CGFloat?
}

enum MessageListSearchFieldPolicy {
    static func configuration(platform: MessageListSearchFieldPlatform) -> MessageListSearchFieldConfiguration {
        switch platform {
        case .iOS:
            MessageListSearchFieldConfiguration(
                placement: .inPaneField,
                disablesAutocorrection: true,
                hidesInputAssistant: true,
                chromeHeight: 44
            )
        case .macOS:
            // A plain toolbar item in the message list column's own section,
            // not `.searchable`. SwiftUI hosts the latter as a window-level
            // `NSSearchToolbarItem` that re-lays out and collapses to a
            // magnifying glass whenever another column such as the AI Sidebar
            // appears, and it reads as scoped to the window rather than to the
            // list it actually filters.
            MessageListSearchFieldConfiguration(
                placement: .inPaneField,
                disablesAutocorrection: false,
                hidesInputAssistant: false,
                chromeHeight: 24
            )
        }
    }
}

enum InboxCategoryBarPresentation {
    static func height(platform: MessageListSearchFieldPlatform) -> CGFloat {
        switch platform {
        case .iOS: 44
        case .macOS: 34
        }
    }
}

/// Drives the macOS toolbar search control, which is a magnifying-glass button
/// until the user opens it.
///
/// Collapsing is user-initiated rather than layout-driven: `.searchable`'s
/// `NSSearchToolbarItem` collapsed on its own whenever a column appeared, which
/// hid the control at the moment the window got busier.
enum MessageListSearchExpansionPolicy {
    /// Clicking away collapses the field whatever it holds, and the query is
    /// kept rather than cleared so reopening restores what was typed.
    static func collapsesOnEndEditing() -> Bool {
        true
    }

    /// Whether the collapsed button should read as active. A retained query
    /// still filters the list, so the control has to say so — otherwise the
    /// list looks filtered for no visible reason.
    static func showsRetainedQuery(isToggledOpen: Bool, query: String) -> Bool {
        !isToggledOpen && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Widest the expanded macOS field may draw, given the reader it sits over.
    ///
    /// The field shares the reader's trailing toolbar section with the message
    /// actions, so an unbounded field takes its extra width from those icons —
    /// which then spill back over the message list. `reservedClusterWidth` is
    /// what the rest of that section measures with the field collapsed; only
    /// what is left over past it belongs to the field.
    static func expandedFieldWidth(
        readerWidth: CGFloat,
        reservedClusterWidth: CGFloat = 380
    ) -> CGFloat {
        min(maximumFieldWidth, max(minimumFieldWidth, readerWidth - reservedClusterWidth))
    }

    /// What the rest of the section measures with the field collapsed. A
    /// condensed cluster (`MailRootDetailToolbarPolicy` folded Reply All,
    /// Forward, and Flag into the overflow menu) is three buttons lighter,
    /// and the expanded field may take that width back.
    static func reservedClusterWidth(isCondensed: Bool) -> CGFloat {
        isCondensed ? 290 : 380
    }

    static let minimumFieldWidth: CGFloat = 140
    static let maximumFieldWidth: CGFloat = 240
}

struct MessageListSearchRequest: Equatable, Sendable {
    let query: String
    let sourceID: MailSourceID?
    let searchAllFolders: Bool
    let searchScope: SearchScope
    /// The selected folder at request time. This anchors response application
    /// to the same visible folder, even when the query itself searches all
    /// folders.
    let folderID: String?
    let execution: SearchExecution

    init(
        query: String,
        sourceID: MailSourceID? = nil,
        searchAllFolders: Bool = false,
        searchScope: SearchScope = .all,
        folderID: String?,
        execution: SearchExecution = .cacheOnly
    ) {
        self.query = query
        self.sourceID = sourceID
        self.searchAllFolders = searchAllFolders
        self.searchScope = searchScope
        self.folderID = folderID
        self.execution = execution
    }
}

struct MessageListSearchPlan: Equatable, Sendable {
    let request: MessageListSearchRequest
    let query: SearchQuery
}

enum MessageListAttachmentSearchDisclosurePolicy {
    static func shouldShowDisclosure(query: SearchQuery, isLoading: Bool) -> Bool {
        shouldShowDisclosure(queries: [query], isLoading: isLoading)
    }

    static func shouldShowDisclosure(queries: [SearchQuery], isLoading: Bool) -> Bool {
        isLoading && queries.contains {
            $0.hasAttachments == true && $0.execution != .cacheOnly
        }
    }
}

struct SearchExecutionReconciliation: Equatable, Sendable {
    let execution: SearchExecution
    let hasUserSelection: Bool
}

enum MessageListSearchPlanPolicy {
    static func plan(
        text: String,
        sourceID: MailSourceID?,
        selectedFolderID: Folder.ID?,
        execution: SearchExecution,
        searchAllFolders: Bool,
        searchScope: SearchScope
    ) -> MessageListSearchPlan {
        let request = MessageListSearchRequest(
            query: text,
            sourceID: sourceID,
            searchAllFolders: searchAllFolders,
            searchScope: searchScope,
            folderID: selectedFolderID,
            execution: execution
        )
        let query = MessageListSearchQueryPolicy.query(
            text: text,
            folderID: searchAllFolders ? nil : selectedFolderID,
            execution: execution,
            searchScope: searchScope
        )
        return MessageListSearchPlan(request: request, query: query)
    }
}

enum MessageListSearchStartPolicy {
    static func canStartSearch(
        request: MessageListSearchRequest,
        activeRequest: MessageListSearchRequest?,
        isBlocked: Bool
    ) -> Bool {
        !isBlocked && activeRequest != request
    }
}

enum MessageListSearchExecutionPolicy {
    static func defaultExecution(capabilities: BackendCapabilities) -> SearchExecution {
        capabilities.contains(.serverSideSearch) ? .cacheThenServer : .cacheOnly
    }

    static func availableExecutions(capabilities: BackendCapabilities) -> [SearchExecution] {
        guard capabilities.contains(.serverSideSearch) else {
            return [.cacheOnly]
        }
        return [.cacheOnly, .cacheThenServer, .serverOnly]
    }

    static func reconciledExecution(
        current: SearchExecution,
        hasUserSelection: Bool,
        capabilities: BackendCapabilities
    ) -> SearchExecutionReconciliation {
        let available = availableExecutions(capabilities: capabilities)
        let defaultExecution = defaultExecution(capabilities: capabilities)
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
}

enum MessageListSearchFallbackPolicy {
    static func shouldApplyLocalFallback(
        for error: any Error,
        execution: SearchExecution
    ) -> Bool {
        guard execution != .serverOnly else { return false }
        if let backendError = error as? MailBackendError {
            switch backendError {
            case .notSupported, .notConnected, .network:
                return true
            case .authenticationRequired,
                 .notFound,
                 .permissionDenied,
                 .quotaExceeded,
                 .rateLimited,
                 .credentialStoreUnavailable,
                 .backendSpecific:
                return false
            }
        }
        if let imapError = error as? IMAPClientError {
            switch imapError {
            case .authenticationFailed, .invalidServerKind:
                return false
            case .connectionLimitExceeded,
                 .unsupportedTLSMode,
                 .unsupportedSearchCriterion,
                 .commandNotSupported,
                 .connectionRejected,
                 .commandFailed,
                 .malformedResponse,
                 .transport,
                 .serverBye,
                 .idleNotSupported:
                return true
            }
        }
        return false
    }
}

enum MessageListSearchDebouncePolicy {
    static let delayNanoseconds: UInt64 = 250_000_000

    static func waitForDebounce(
        sleep: @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) async -> Bool {
        do {
            try await sleep(delayNanoseconds)
            return true
        } catch {
            return false
        }
    }

    static func isCurrentSearch(
        requestedQuery: String,
        currentSearchText: String
    ) -> Bool {
        MessageListReloadPolicy.operation(
            forSearchText: currentSearchText
        ) == .search(query: requestedQuery)
    }

    static func canApplySearchResponse(
        request: MessageListSearchRequest,
        activeRequest: MessageListSearchRequest?,
        currentSearchText: String,
        currentSourceID: MailSourceID? = nil,
        currentFolderID: String?
    ) -> Bool {
        activeRequest == request
            && request.sourceID == currentSourceID
            && request.folderID == currentFolderID
            && isCurrentSearch(
                requestedQuery: request.query,
                currentSearchText: currentSearchText
            )
    }
}
