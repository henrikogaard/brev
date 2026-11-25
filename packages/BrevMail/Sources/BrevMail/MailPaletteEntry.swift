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

#if os(macOS)
import AppKit
import BrevBackend
import BrevSettings
import SwiftUI

/// Semantic group used to rank and section entries in the macOS ⌘K command palette (#300).
enum MailPaletteCategory: Int, CaseIterable, Hashable, Sendable {
    case mailActions = 0
    case jumpTo = 1
    case settings = 2
    case otherCommands = 3
    case appAndWindow = 4

    var sectionTitle: String {
        switch self {
        case .mailActions:
            String(localized: "Mail Actions", bundle: .module)
        case .jumpTo:
            String(localized: "Jump To", bundle: .module)
        case .settings:
            String(localized: "Settings", bundle: .module)
        case .otherCommands:
            String(localized: "Commands", bundle: .module)
        case .appAndWindow:
            String(localized: "App & Window", bundle: .module)
        }
    }
}

/// Formats an `NSMenuItem`'s key equivalent and modifier mask into crisp keycap glyphs (#300).
enum MailPaletteShortcutFormatter {
    static func keycaps(keyEquivalent: String, modifiers: NSEvent.ModifierFlags) -> [String] {
        guard !keyEquivalent.isEmpty else { return [] }
        let isImplicitShift = keyEquivalent.count == 1
            && keyEquivalent.first?.isLetter == true
            && keyEquivalent.first?.isUppercase == true

        var caps: [String] = []
        if modifiers.contains(.control) { caps.append("⌃") }
        if modifiers.contains(.option) { caps.append("⌥") }
        if modifiers.contains(.shift) || isImplicitShift { caps.append("⇧") }
        if modifiers.contains(.command) { caps.append("⌘") }

        let keyLabel: String = switch keyEquivalent {
        case "\u{08}", "\u{7F}": "⌫"
        case "\u{F728}": "⌦"
        case "\r", "\n": "↩"
        case "\t": "⇥"
        case "\u{1B}": "⎋"
        case " ": "␣"
        case "\u{F700}": "↑"
        case "\u{F701}": "↓"
        case "\u{F702}": "←"
        case "\u{F703}": "→"
        default: keyEquivalent.uppercased()
        }
        caps.append(keyLabel)
        return caps
    }
}

/// A top-level workspace destination surfaced by the focused mail window (#300).
public struct MailPaletteWorkspaceDestination {
    let title: String
    let detail: String
    let keywords: String
    let emptyQueryPriority: Int
    let run: @MainActor () -> Void

    /// Builds the workspace destinations available for the focused mail window's current state.
    @MainActor
    static func build(
        canOpenAssistant: Bool,
        canStartTriage: Bool,
        openAssistant: @escaping @MainActor () -> Void,
        openToday: (@MainActor () -> Void)? = nil,
        startTriage: @escaping @MainActor () -> Void,
        openSubscriptions: @escaping @MainActor () -> Void
    ) -> [Self] {
        let detail = String(localized: "Mailbox", bundle: .module)
        var destinations: [Self] = []
        if canOpenAssistant {
            destinations.append(Self(
                title: String(localized: "Assistant", bundle: .module),
                detail: detail,
                keywords: "ai chat ask",
                emptyQueryPriority: 10,
                run: openAssistant
            ))
        }
        if let openToday {
            destinations.append(Self(
                title: String(localized: "Today", bundle: .module),
                detail: detail,
                keywords: "today digest daily",
                emptyQueryPriority: 20,
                run: openToday
            ))
        }
        if canStartTriage {
            destinations.append(Self(
                title: String(localized: "Triage", bundle: .module),
                detail: detail,
                keywords: "queue review",
                emptyQueryPriority: 30,
                run: startTriage
            ))
        }
        destinations.append(Self(
            title: String(localized: "Subscriptions", bundle: .module),
            detail: detail,
            keywords: "newsletters unsubscribe updates",
            emptyQueryPriority: 40,
            run: openSubscriptions
        ))
        return destinations
    }
}

/// The focused mail root supplies only folders and destinations visible in its current profile.
public struct MailPaletteMailboxContext {
    let sections: @MainActor () -> [MailSourceSection]
    let select: @MainActor (MailSourceID, Folder.ID) -> Void
    let workspaceDestinations: @MainActor () -> [MailPaletteWorkspaceDestination]

    init(
        sections: @escaping @MainActor () -> [MailSourceSection],
        select: @escaping @MainActor (MailSourceID, Folder.ID) -> Void,
        workspaceDestinations: @escaping @MainActor () -> [MailPaletteWorkspaceDestination] = { [] }
    ) {
        self.sections = sections
        self.select = select
        self.workspaceDestinations = workspaceDestinations
    }
}

private struct MailPaletteMailboxContextKey: FocusedValueKey {
    typealias Value = MailPaletteMailboxContext
}

public extension FocusedValues {
    /// Source-scoped destinations for the frontmost mail window.
    var mailPaletteMailboxContext: MailPaletteMailboxContext? {
        get { self[MailPaletteMailboxContextKey.self] }
        set { self[MailPaletteMailboxContextKey.self] = newValue }
    }
}

@MainActor
struct MailPaletteSection: Identifiable {
    let category: MailPaletteCategory
    let rows: [(index: Int, entry: MailPaletteEntry)]

    var id: MailPaletteCategory { category }
    var title: String { category.sectionTitle }
}

@MainActor
struct MailPaletteEntry: Identifiable {
    // Entries are built once per presentation, so repeated titles remain distinct.
    let id = UUID()
    let title: String
    let detail: String
    let keywords: String
    let section: SettingsSection?
    let category: MailPaletteCategory
    let emptyQueryPriority: Int
    let shortcutKeycaps: [String]
    let run: @MainActor () -> Void

    init(
        _ title: String,
        detail: String,
        keywords: String = "",
        section: SettingsSection? = nil,
        category: MailPaletteCategory? = nil,
        emptyQueryPriority: Int? = nil,
        shortcutKeycaps: [String] = [],
        run: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.detail = detail
        self.keywords = keywords
        self.section = section
        let inferred = Self.inferClassification(
            title: title,
            detail: detail,
            section: section,
            action: nil,
            isTopLevelAppMenu: false
        )
        self.category = category ?? inferred.category
        self.emptyQueryPriority = emptyQueryPriority ?? inferred.priority
        self.shortcutKeycaps = shortcutKeycaps
        self.run = run
    }

    func matches(_ query: String) -> Bool {
        let haystack = [title, detail, keywords].joined(separator: " ")
        return query.split(whereSeparator: \.isWhitespace).allSatisfy {
            haystack.localizedStandardContains(String($0)) || section?.matches(searchQuery: String($0)) == true
        }
    }

    /// Returns matching entries ranked for presentation: contextual Mail Actions
    /// and Jump To lead when unfiltered, while generic macOS app/window
    /// boilerplate is pushed to the bottom (#300).
    static func ranked(_ entries: [Self], for query: String) -> [Self] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return entries.enumerated()
                .sorted { lhs, rhs in
                    if lhs.element.category.rawValue != rhs.element.category.rawValue {
                        return lhs.element.category.rawValue < rhs.element.category.rawValue
                    }
                    if lhs.element.emptyQueryPriority != rhs.element.emptyQueryPriority {
                        return lhs.element.emptyQueryPriority < rhs.element.emptyQueryPriority
                    }
                    return lhs.offset < rhs.offset
                }
                .map(\.element)
        }

        let lowered = trimmed.lowercased()
        return entries.enumerated()
            .filter { $0.element.matches(trimmed) }
            .sorted { lhs, rhs in
                let lhsScore = Self.matchRank(lhs.element, loweredQuery: lowered)
                let rhsScore = Self.matchRank(rhs.element, loweredQuery: lowered)
                if lhsScore != rhsScore { return lhsScore < rhsScore }
                if lhs.element.category.rawValue != rhs.element.category.rawValue {
                    return lhs.element.category.rawValue < rhs.element.category.rawValue
                }
                if lhs.element.emptyQueryPriority != rhs.element.emptyQueryPriority {
                    return lhs.element.emptyQueryPriority < rhs.element.emptyQueryPriority
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Groups ranked entries by category while preserving their flat row indices
    /// for keyboard navigation (#300).
    static func groupedSections(from entries: [Self]) -> [MailPaletteSection] {
        var buckets: [MailPaletteCategory: [(index: Int, entry: MailPaletteEntry)]] = [:]
        for (index, entry) in entries.enumerated() {
            buckets[entry.category, default: []].append((index: index, entry: entry))
        }
        return MailPaletteCategory.allCases.compactMap { category in
            guard let rows = buckets[category], !rows.isEmpty else { return nil }
            return MailPaletteSection(category: category, rows: rows)
        }
    }

    /// Walk the current native menu, including app, system, and nested commands.
    /// Never dispatch an action that was removed or disabled while the sheet was open.
    static func commands(in root: NSMenu) -> [Self] {
        let appMenuItem = root.items.first
        func visit(_ menu: NSMenu, ancestors: [NSMenuItem]) -> [Self] {
            menu.update()
            return menu.items.flatMap { item -> [Self] in
                guard !item.isHidden, !item.isSeparatorItem, item.isEnabled else { return [] }
                if let submenu = item.submenu { return visit(submenu, ancestors: ancestors + [item]) }
                guard item.action != nil, !item.title.isEmpty else { return [] }
                let title = item.title
                let detail = ancestors.map(\.title).joined(separator: " › ")
                let isTopLevelAppMenu = ancestors.first === appMenuItem && appMenuItem != nil
                let classification = Self.inferClassification(
                    title: title,
                    detail: detail,
                    section: nil,
                    action: item.action,
                    isTopLevelAppMenu: isTopLevelAppMenu
                )
                let keycaps = MailPaletteShortcutFormatter.keycaps(
                    keyEquivalent: item.keyEquivalent,
                    modifiers: item.keyEquivalentModifierMask
                )
                return [Self(
                    title,
                    detail: detail,
                    category: classification.category,
                    emptyQueryPriority: classification.priority,
                    shortcutKeycaps: keycaps
                ) {
                    // Validate every ancestor; the same row index can now hold another command.
                    var current = root
                    for parent in ancestors {
                        current.update()
                        guard current.items.contains(where: { $0 === parent }), parent.isEnabled,
                              !parent.isHidden, let child = parent.submenu else { return }
                        current = child
                    }
                    current.update()
                    guard let index = current.items.firstIndex(where: { $0 === item }),
                          item.isEnabled, !item.isHidden, item.title == title else { return }
                    current.performActionForItem(at: index)
                }]
            }
        }
        return visit(root, ancestors: [])
    }

    static func settings(_ sections: [SettingsSection], open: @escaping @MainActor (SettingsSection) -> Void) -> [Self] {
        sections.enumerated().map { index, section in
            Self(
                section.title,
                detail: String(localized: "Settings", bundle: .module),
                section: section,
                category: .settings,
                emptyQueryPriority: index
            ) { open(section) }
        }
    }

    static func workspaceDestinations(_ destinations: [MailPaletteWorkspaceDestination]) -> [Self] {
        destinations.map { destination in
            Self(
                destination.title,
                detail: destination.detail,
                keywords: destination.keywords,
                category: .jumpTo,
                emptyQueryPriority: destination.emptyQueryPriority,
                run: destination.run
            )
        }
    }

    static func mailDestinations(
        in sections: [MailSourceSection], select: @escaping @MainActor (MailSourceID, Folder.ID) -> Void
    ) -> [Self] {
        let available = sections.filter { $0.loadError == nil && !$0.folders.isEmpty }
        let groups = Dictionary(grouping: available, by: \.account.id)
        var entries: [Self] = []
        var accounts = Set<BrevAccount.ID>()
        for source in available {
            let address = source.account.emailAddress
            let name = source.account.displayName.isEmpty ? address : source.account.displayName
            if accounts.insert(source.account.id).inserted {
                let primary = groups[source.account.id]?.first { $0.mailbox.isPrimary } ?? source
                if let folder = primary.folders.first(where: { $0.role == .inbox }) ?? primary.folders.first {
                    entries.append(Self(
                        name,
                        detail: String(localized: "Account", bundle: .module) + " · " + address,
                        category: .jumpTo,
                        emptyQueryPriority: 60
                    ) {
                        select(primary.id, folder.id)
                    })
                }
            }
            for folder in source.folders {
                let detail = [String(localized: "Mailbox", bundle: .module), name, source.title, source.mailbox.email]
                    .joined(separator: " · ")
                let priority = folder.role == .inbox ? 50 : 70
                entries.append(Self(
                    folder.name,
                    detail: detail,
                    keywords: address,
                    category: .jumpTo,
                    emptyQueryPriority: priority
                ) { select(source.id, folder.id) })
            }
        }
        return entries
    }

    private static func matchRank(_ entry: Self, loweredQuery: String) -> Int {
        let title = entry.title.lowercased()
        if title == loweredQuery { return 0 }
        if title.hasPrefix(loweredQuery) { return 1 }
        if title.contains(loweredQuery) { return 2 }
        return 3
    }

    private static let appBoilerplateSelectors: Set<String> = [
        "orderFrontStandardAboutPanel:",
        "hide:",
        "hideOtherApplications:",
        "unhideAllApplications:",
        "terminate:",
        "performMiniaturize:",
        "performZoom:",
        "arrangeInFront:",
        "toggleFullScreen:",
        "orderFrontCharacterPalette:",
        "startDictation:",
        "performClose:",
        "orderFrontFontPanel:",
        "orderFrontColorPanel:",
    ]

    private static func inferClassification(
        title: String,
        detail: String,
        section: SettingsSection?,
        action: Selector?,
        isTopLevelAppMenu: Bool
    ) -> (category: MailPaletteCategory, priority: Int) {
        if section != nil {
            return (.settings, 100)
        }

        let normalizedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "...", with: "…")
        let normalizedDetail = detail.lowercased()

        // Settings… from the macOS app menu is a useful jump destination rather than boilerplate.
        if normalizedTitle == "settings…" || normalizedTitle == "preferences…" || normalizedTitle == "innstillinger…" {
            return (.jumpTo, 80)
        }

        if let action, appBoilerplateSelectors.contains(NSStringFromSelector(action)) {
            return (.appAndWindow, 900)
        }

        if isAppOrWindowBoilerplate(title: normalizedTitle, detail: normalizedDetail, isTopLevelAppMenu: isTopLevelAppMenu) {
            return (.appAndWindow, 900)
        }

        // Duplicate alternate-shortcut entries stay searchable under Commands without crowding Mail Actions.
        if normalizedDetail.contains("alternate shortcuts") || normalizedDetail.contains("alternative snarveier") {
            return (.otherCommands, 600)
        }

        if let priority = mailActionPriority(title: normalizedTitle, detail: normalizedDetail) {
            return (.mailActions, priority)
        }

        let mailboxPrefix = String(localized: "Mailbox", bundle: .module).lowercased()
        let accountPrefix = String(localized: "Account", bundle: .module).lowercased()
        if normalizedDetail.hasPrefix(mailboxPrefix) || normalizedDetail.hasPrefix("mailbox")
            || normalizedDetail.hasPrefix(accountPrefix) || normalizedDetail.hasPrefix("account") {
            let isInbox = normalizedTitle == "inbox" || normalizedTitle == "innboks"
            return (.jumpTo, isInbox ? 50 : 70)
        }

        if normalizedTitle == "message viewer" {
            return (.jumpTo, 90)
        }

        return (.otherCommands, 500)
    }

    private static func isAppOrWindowBoilerplate(
        title: String,
        detail: String,
        isTopLevelAppMenu: Bool
    ) -> Bool {
        let boilerplatePrefixes = [
            "about ",
            "om ",
            "hide ",
            "skjul ",
            "quit ",
            "avslutt ",
            "start dictation",
        ]
        if boilerplatePrefixes.contains(where: { title.hasPrefix($0) }) {
            return true
        }
        let boilerplateExact: Set<String> = [
            "about",
            "hide",
            "hide others",
            "skjul andre",
            "show all",
            "vis alle",
            "quit",
            "quit and keep windows",
            "avslutt og behold vinduer",
            "services",
            "tjenester",
            "minimize",
            "minimer",
            "zoom",
            "bring all to front",
            "enter full screen",
            "exit full screen",
            "emoji & symbols",
            "command palette…",
            "kommandopalett …",
        ]
        if boilerplateExact.contains(title) {
            return true
        }
        if isTopLevelAppMenu {
            return true
        }
        if detail == "window" || detail.hasPrefix("window ›") || detail == "vindu" || detail.hasPrefix("vindu ›") {
            return title != "message viewer"
        }
        return false
    }

    private static func mailActionPriority(title: String, detail: String) -> Int? {
        let explicitPriorities: [(matches: [String], priority: Int)] = [
            (["new message", "ny melding"], 10),
            (["reply", "svar"], 20),
            (["reply all", "svar alle"], 25),
            (["forward", "videresend"], 30),
            (["archive", "arkiver"], 40),
            (["snooze", "snooze…", "slumre", "slumre…"], 50),
            (["get new mail", "hent ny e-post"], 60),
            (["start triage", "exit triage"], 70),
            (["search mail", "focus search", "søk i e-post"], 80),
            (["mark as unread", "mark as read", "flag", "unflag", "star", "unstar"], 90),
            (["delete", "slett", "move to junk", "mark as junk", "not junk"], 100),
            (["show ai sidebar", "hide ai sidebar", "select all messages"], 110),
            (["import mail…", "export mail…", "print…", "export as pdf…"], 120),
        ]
        for entry in explicitPriorities where entry.matches.contains(title) {
            return entry.priority
        }
        let localizedMessageMenu = String(localized: "message", bundle: .module).lowercased()
        if detail == "message"
            || detail.hasPrefix("message ›")
            || detail == localizedMessageMenu
            || detail.hasPrefix("\(localizedMessageMenu) ›") {
            return 130
        }
        return nil
    }
}
#endif
