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

enum MailboxFavoriteID: Codable, Hashable, Sendable {
    case allInboxes
    case folder(SourceFolderID)
}

struct MailboxFavorite: Identifiable, Equatable, Sendable {
    let id: MailboxFavoriteID
    let title: String
    let subtitle: String?
    let symbol: String
    let count: Int
    let isDefault: Bool

    static func candidates(sections: [MailSourceSection]) -> [Self] {
        guard !sections.isEmpty else { return [] }
        let inboxes = sections.flatMap { $0.folders.filter { $0.role == .inbox } }
        var result = [Self(id: .allInboxes, title: String(localized: "All Inboxes", bundle: .module),
                           subtitle: nil, symbol: "tray.2", count: inboxes.reduce(0) { $0 + $1.unreadCount }, isDefault: true)]
        for role in [FolderRole.inbox, .drafts, .sent] {
            for section in sections {
                guard let folder = section.folders.first(where: { $0.role == role }) else { continue }
                let title: String = switch role {
                case .drafts: String(localized: "Drafts", bundle: .module)
                case .sent: String(localized: "Sent", bundle: .module)
                default: section.title
                }
                result.append(Self(id: .folder(SourceFolderID(sourceID: section.id, folderID: folder.id)),
                                   title: title, subtitle: role == .inbox ? nil : section.title,
                                   symbol: role == .drafts ? "doc" : role == .sent ? "paperplane" : "tray",
                                   count: role == .drafts ? folder.totalCount : role == .inbox ? folder.unreadCount : 0,
                                   isDefault: role == .inbox))
            }
        }
        return result
    }
}

/// Local shortcut preferences retain choices for temporarily hidden profile members.
struct MailboxFavorites: Codable, Equatable, Sendable {
    static let storageKey = "mailbox.favorites"
    var order: [MailboxFavoriteID] = []
    var hidden: Set<MailboxFavoriteID> = []
    var added: Set<MailboxFavoriteID> = []

    init(data: Data = Data()) {
        self = (try? JSONDecoder().decode(Self.self, from: data)) ?? Self.empty
    }

    private init() {}
    private static var empty: Self { Self() }

    var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }

    func isVisible(_ favorite: MailboxFavorite) -> Bool {
        !hidden.contains(favorite.id) && (favorite.isDefault || added.contains(favorite.id))
    }

    func ordered(_ candidates: [MailboxFavorite], visibleOnly: Bool = false) -> [MailboxFavorite] {
        var seen = Set<MailboxFavoriteID>()
        let ids = (order + candidates.map(\.id)).filter { seen.insert($0).inserted }
        return ids.compactMap { id in
            candidates.first { $0.id == id && (!visibleOnly || isVisible($0)) }
        }
    }

    mutating func setVisible(_ visible: Bool, id: MailboxFavoriteID) {
        if visible {
            hidden.remove(id)
            added.insert(id)
        } else {
            hidden.insert(id)
            added.remove(id)
        }
    }

    mutating func reorder(_ ids: [MailboxFavoriteID]) {
        order = ids + order.filter { !ids.contains($0) }
    }
}
