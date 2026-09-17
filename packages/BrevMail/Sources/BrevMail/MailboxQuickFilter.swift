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
import BrevDesign
import Foundation

enum MailboxQuickFilter: String, Sendable, Hashable, CaseIterable, Identifiable {
    case unread
    case flagged
    case hasAttachment
    case today
    case lastWeek
    case fromSender
    /// Show only messages from senders marked as VIP.
    case vip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unread: return String(localized: "Unread", bundle: .module)
        case .flagged: return String(localized: "Flagged", bundle: .module)
        case .hasAttachment: return String(localized: "Attachments", bundle: .module)
        case .today: return String(localized: "Today", bundle: .module)
        case .lastWeek: return String(localized: "Last week", bundle: .module)
        case .fromSender: return String(localized: "From me", bundle: .module)
        case .vip: return String(localized: "VIP", bundle: .module)
        }
    }

    var symbolName: String {
        switch self {
        case .unread: return "envelope.badge"
        case .flagged: return "flag"
        case .hasAttachment: return "paperclip"
        case .today: return "calendar"
        case .lastWeek: return "calendar.badge.clock"
        case .fromSender: return "person.crop.circle"
        case .vip: return "star"
        }
    }
}

/// Presentation grouping for the compact mailbox filter strip.
enum MailboxQuickFilterPresentation {
    static let primaryFilters: [MailboxQuickFilter] = [.unread, .flagged, .hasAttachment, .vip]
    static let dateFilters: [MailboxQuickFilter] = [.today, .lastWeek]
}

struct MailboxFilterQuery: Equatable, Sendable {
    var activeFilters: Set<MailboxQuickFilter>
    var senderEmail: String?
    var sourceIDs: Set<MailSourceID>?
    /// Normalized (lowercased) email addresses for senders marked as VIP.
    /// Populated by the mail root from `VIPSenderSettings`.
    var vipEmails: Set<String>

    static let none = MailboxFilterQuery(
        activeFilters: [],
        senderEmail: nil,
        sourceIDs: nil,
        vipEmails: []
    )

    init(
        activeFilters: Set<MailboxQuickFilter>,
        senderEmail: String? = nil,
        sourceIDs: Set<MailSourceID>? = nil,
        vipEmails: Set<String> = []
    ) {
        self.activeFilters = activeFilters
        self.senderEmail = senderEmail
        self.sourceIDs = sourceIDs
        self.vipEmails = vipEmails
    }

    var isActive: Bool {
        !activeFilters.isEmpty
            || (activeFilters.contains(.fromSender) && senderEmail != nil)
            || sourceIDs?.isEmpty == false
    }

    func matches(
        _ header: MessageHeader,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard isActive else { return true }

        for filter in activeFilters {
            switch filter {
            case .unread:
                guard header.isRead == false else { return false }
            case .flagged:
                guard header.isFlagged else { return false }
            case .hasAttachment:
                guard header.hasAttachments else { return false }
            case .today:
                guard calendar.isDate(header.date, inSameDayAs: now) else { return false }
            case .lastWeek:
                guard header.date > now.addingTimeInterval(-604_800) else { return false }
            case .fromSender:
                if let senderEmail {
                    guard header.from.email.lowercased() == senderEmail.lowercased() else {
                        return false
                    }
                }
            case .vip:
                guard vipEmails.contains(header.from.email.lowercased()) else { return false }
            }
        }
        return true
    }

    func matches(
        _ item: UnifiedInboxItem,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        if let sourceIDs, !sourceIDs.contains(item.sourceID) {
            return false
        }
        return matches(item.header, now: now, calendar: calendar)
    }

    mutating func toggle(_ filter: MailboxQuickFilter) {
        if activeFilters.contains(filter) {
            activeFilters.remove(filter)
        } else {
            activeFilters.insert(filter)
        }
    }

    mutating func clear() {
        activeFilters.removeAll()
        senderEmail = nil
        sourceIDs = nil
    }
}

struct MailboxSmartView: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let symbolName: String
    let navigationFolderID: Folder.ID
    let query: MailboxFilterQuery
    let workflowMode: LocalMessageWorkflowVisibilityMode

    static let today = MailboxSmartView(
        id: "today",
        title: String(localized: "Today", bundle: .module),
        symbolName: "calendar",
        navigationFolderID: MailNavigationState.todaySmartViewFolderID,
        query: MailboxFilterQuery(activeFilters: [.today]),
        workflowMode: .active
    )

    static let flagged = MailboxSmartView(
        id: "flagged",
        title: String(localized: "Flagged", bundle: .module),
        symbolName: "flag",
        navigationFolderID: MailNavigationState.flaggedSmartViewFolderID,
        query: MailboxFilterQuery(activeFilters: [.flagged]),
        workflowMode: .active
    )

    static let snoozed = MailboxSmartView(
        id: "snoozed",
        title: String(localized: "Snoozed", bundle: .module),
        symbolName: "clock",
        navigationFolderID: MailNavigationState.snoozedSmartViewFolderID,
        query: .none,
        workflowMode: .snoozed
    )

    static let done = MailboxSmartView(
        id: "done",
        title: String(localized: "Done", bundle: .module),
        symbolName: "checkmark.circle",
        navigationFolderID: MailNavigationState.doneSmartViewFolderID,
        query: .none,
        workflowMode: .done
    )

    /// VIP smart view — shows messages from VIP senders.
    /// The `vipEmails` set is populated at render-time from `VIPSenderSettings`.
    static let vip = MailboxSmartView(
        id: "vip",
        title: String(localized: "VIP", bundle: .module),
        symbolName: "star",
        navigationFolderID: MailNavigationState.vipSmartViewFolderID,
        query: MailboxFilterQuery(activeFilters: [.vip]),
        workflowMode: .active
    )

    static let builtIns: [MailboxSmartView] = [.today, .flagged, .snoozed, .done, .vip]

    /// Resolves the local VIP sender set at render time without persisting it
    /// inside the built-in view definition.
    func resolvingVIPEmails(_ emails: Set<String>) -> MailboxSmartView {
        guard id == Self.vip.id else { return self }
        var resolvedQuery = query
        resolvedQuery.vipEmails = Set(emails.map { $0.lowercased() })
        return MailboxSmartView(
            id: id,
            title: title,
            symbolName: symbolName,
            navigationFolderID: navigationFolderID,
            query: resolvedQuery,
            workflowMode: workflowMode
        )
    }

    @MainActor
    static func selected(for navigation: MailNavigationState) -> MailboxSmartView? {
        builtIns.first { $0.isSelected(in: navigation) }
    }

    @MainActor
    func select(in navigation: MailNavigationState) {
        navigation.selectSmartView(folderID: navigationFolderID)
    }

    @MainActor
    func isSelected(in navigation: MailNavigationState) -> Bool {
        navigation.browsingFolderID == navigationFolderID
    }
}

struct MailboxSortControlPresentation: Equatable, Sendable {
    let title: String
    let symbolName: String
    let help: String
    let accessibilityLabel: String

    static func presentation(for sortOrder: MailboxSortOrder) -> Self {
        MailboxSortControlPresentation(
            title: sortOrder.title,
            symbolName: sortOrder.symbolName,
            help: sortOrder.subtitle,
            accessibilityLabel: String(localized: "Sort order: \(sortOrder.title)", bundle: .module)
        )
    }
}

/// Labels for the mailbox filter menu that replaced the horizontally scrolling
/// chip strip. The menu collapses every quick filter into one control, so its
/// title has to convey how many criteria are active without listing them all.
enum MailboxFilterMenuPresentation {
    /// Menu title: the filter's own name when exactly one is active, a count
    /// when several are, and a neutral label when none are.
    static func title(
        activeFilters: Set<MailboxQuickFilter>,
        allFilters: [MailboxQuickFilter]
    ) -> String {
        let active = allFilters.filter { activeFilters.contains($0) }
        switch active.count {
        case 0:
            return String(localized: "Filter", bundle: .module)
        case 1:
            return active[0].title
        default:
            return String(localized: "\(active.count) Filters", bundle: .module)
        }
    }

    /// Spoken label, which always names the control before its state so the
    /// menu is identifiable when no filter is applied. The menu carries sort
    /// order too, so the label names both jobs rather than the filter alone.
    static func accessibilityLabel(activeCount: Int, sortOrder: MailboxSortOrder) -> String {
        let sort = String(localized: "sorted \(sortOrder.title.lowercased())", bundle: .module)
        switch activeCount {
        case 0:
            return String(localized: "Sort and filter, \(sort)", bundle: .module)
        case 1:
            return String(localized: "Sort and filter, 1 filter active, \(sort)", bundle: .module)
        default:
            return String(localized: "Sort and filter, \(activeCount) filters active, \(sort)", bundle: .module)
        }
    }
}

/// Where the sort-and-filter menu is drawn on each platform.
enum MailboxFilterControlPolicy {
    /// macOS puts it in the window toolbar above the list, where Mail puts it.
    /// The in-pane strip cost a full row of column height for one control and
    /// read as a second, competing toolbar.
    static func usesToolbarControl(platform: MailRootToolbarPlatform) -> Bool {
        // iOS hosts it in the navigation bar's action cluster (see
        // `toolbarList`), beside refresh and compose, since the 2026-08 polish:
        // the in-pane strip cost a full row of list height for one control and
        // stacked a second chrome band under the search band.
        true
    }

    /// No platform keeps the in-pane strip anymore; the toolbar hosts the
    /// control on both.
    static func usesInPaneBar(platform: MailRootToolbarPlatform) -> Bool {
        !usesToolbarControl(platform: platform)
    }
}
