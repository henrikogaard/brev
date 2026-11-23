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

/// A top-level workspace destination surfaced by the focused mail window (#300).
public struct MailPaletteWorkspaceDestination {
    let title: String
    let detail: String
    let keywords: String
    let run: @MainActor () -> Void
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
struct MailPaletteEntry: Identifiable {
    // Entries are built once per presentation, so repeated titles remain distinct.
    let id = UUID()
    let title: String
    let detail: String
    let keywords: String
    let section: SettingsSection?
    let run: @MainActor () -> Void

    init(_ title: String, detail: String, keywords: String = "", section: SettingsSection? = nil,
         run: @escaping @MainActor () -> Void) {
        self.title = title
        self.detail = detail
        self.keywords = keywords
        self.section = section
        self.run = run
    }

    func matches(_ query: String) -> Bool {
        let haystack = [title, detail, keywords].joined(separator: " ")
        return query.split(whereSeparator: \.isWhitespace).allSatisfy {
            haystack.localizedStandardContains(String($0)) || section?.matches(searchQuery: String($0)) == true
        }
    }

    /// Walk the current native menu, including app, system, and nested commands.
    /// Never dispatch an action that was removed or disabled while the sheet was open.
    static func commands(in root: NSMenu) -> [Self] {
        func visit(_ menu: NSMenu, ancestors: [NSMenuItem]) -> [Self] {
            menu.update()
            return menu.items.flatMap { item -> [Self] in
                guard !item.isHidden, !item.isSeparatorItem, item.isEnabled else { return [] }
                if let submenu = item.submenu { return visit(submenu, ancestors: ancestors + [item]) }
                guard item.action != nil, !item.title.isEmpty else { return [] }
                let title = item.title
                return [Self(title, detail: ancestors.map(\.title).joined(separator: " › ")) {
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
        sections.map { section in
            Self(section.title, detail: String(localized: "Settings", bundle: .module), section: section) { open(section) }
        }
    }

    static func workspaceDestinations(_ destinations: [MailPaletteWorkspaceDestination]) -> [Self] {
        destinations.map { destination in
            Self(destination.title, detail: destination.detail, keywords: destination.keywords, run: destination.run)
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
                    entries.append(Self(name, detail: String(localized: "Account", bundle: .module) + " · " + address) {
                        select(primary.id, folder.id)
                    })
                }
            }
            for folder in source.folders {
                let detail = [String(localized: "Mailbox", bundle: .module), name, source.title, source.mailbox.email]
                    .joined(separator: " · ")
                entries.append(Self(folder.name, detail: detail, keywords: address) { select(source.id, folder.id) })
            }
        }
        return entries
    }
}
#endif
