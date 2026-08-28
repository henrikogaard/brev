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

import SwiftUI

public enum MailboxViewPreferenceKey {
    public static let useRichRenderer = "body.useRichRenderer"
    public static let allowRemoteContent = "body.allowRemoteContent"
    public static let groupByThread = "list.groupByThread"
    public static let groupByDate = "list.groupByDate"
    public static let showAbsoluteArrivalTime = "list.showAbsoluteArrivalTime"
    public static let showSenderAvatars = "list.showSenderAvatars"
    public static let previewLineCount = "list.previewLineCount"
    public static let listDensity = "list.rowDensity"
    public static let showFolderStats = "list.showFolderStats"
    public static let folderStatsDetail = "list.folderStatsDetail"
    public static let fontFamily = "mailbox.fontFamily"
    public static let textSize = "mailbox.textSize"
    public static let sortOrder = "list.sortOrder"
    public static let readingPanePlacement = "list.readingPanePlacement"
    public static let inboxClassificationMode = "list.inboxClassificationMode"
    public static let threadMessageOrder = "thread.messageOrder"
}

/// Order of the messages inside a conversation thread in the reading pane.
public enum MailboxThreadOrder: String, Sendable, Hashable, CaseIterable, Identifiable {
    /// Oldest message at the top, newest at the bottom (read top to bottom).
    case oldestFirst
    /// Newest message at the top.
    case newestFirst

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .oldestFirst: return String(localized: "Oldest on top", bundle: .module)
        case .newestFirst: return String(localized: "Newest on top", bundle: .module)
        }
    }

    public var subtitle: String {
        switch self {
        case .oldestFirst: return String(localized: "Read a conversation top to bottom, oldest reply first.", bundle: .module)
        case .newestFirst: return String(localized: "Show the most recent reply at the top of the conversation.", bundle: .module)
        }
    }

    public var symbolName: String {
        switch self {
        case .oldestFirst: return "arrow.down.to.line"
        case .newestFirst: return "arrow.up.to.line"
        }
    }
}

public enum InboxClassificationMode: String, Sendable, Hashable, CaseIterable, Identifiable {
    case off
    case categories

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: return String(localized: "Off", bundle: .module)
        case .categories: return String(localized: "Categories", bundle: .module)
        }
    }

    public var subtitle: String {
        switch self {
        case .off: return String(localized: "Show one normal inbox without classification tabs.", bundle: .module)
        case .categories: return String(
                localized: "Sort messages locally into Primary, Transactions, Updates, Promotions, and Other.",
                bundle: .module
            )
        }
    }
}

public enum InboxCategory: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {
    case all
    case primary
    case transactions
    case updates
    case promotions
    case other

    public var id: String { rawValue }

    public static let selectableCases: [InboxCategory] = [
        .all,
        .primary,
        .transactions,
        .updates,
        .promotions,
        .other
    ]

    public static let assignableCases: [InboxCategory] = [
        .primary,
        .transactions,
        .updates,
        .promotions,
        .other
    ]

    public var title: String {
        switch self {
        case .all: return String(localized: "All", bundle: .module)
        case .primary: return String(localized: "Primary", bundle: .module)
        case .transactions: return String(localized: "Transactions", bundle: .module)
        case .updates: return String(localized: "Updates", bundle: .module)
        case .promotions: return String(localized: "Promotions", bundle: .module)
        case .other: return String(localized: "Other", bundle: .module)
        }
    }

    public var symbolName: String {
        switch self {
        case .all: return "tray.full"
        case .primary: return "person.2"
        case .transactions: return "receipt"
        case .updates: return "bell"
        case .promotions: return "tag"
        case .other: return "tray"
        }
    }
}

public enum MailboxFolderStatsDetail: String, Sendable, Hashable, CaseIterable, Identifiable {
    case compact
    case detailed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .compact: return String(localized: "Compact", bundle: .module)
        case .detailed: return String(localized: "Detailed", bundle: .module)
        }
    }

    public var subtitle: String {
        switch self {
        case .compact: return String(localized: "Show a short total and unread summary.", bundle: .module)
        case .detailed: return String(localized: "Show folder, shown, total, unread, pinned, and loaded counts.", bundle: .module)
        }
    }
}

public enum MailboxSortOrder: String, Sendable, Hashable, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst
    case sender
    case subject
    case unreadFirst
    case flaggedFirst
    case attachmentFirst

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .newestFirst: return String(localized: "Newest first", bundle: .module)
        case .oldestFirst: return String(localized: "Oldest first", bundle: .module)
        case .sender: return String(localized: "Sender", bundle: .module)
        case .subject: return String(localized: "Subject", bundle: .module)
        case .unreadFirst: return String(localized: "Unread first", bundle: .module)
        case .flaggedFirst: return String(localized: "Flagged first", bundle: .module)
        case .attachmentFirst: return String(localized: "Attachments first", bundle: .module)
        }
    }

    public var subtitle: String {
        switch self {
        case .newestFirst: return String(localized: "Show the most recent messages at the top.", bundle: .module)
        case .oldestFirst: return String(localized: "Show the oldest messages at the top.", bundle: .module)
        case .sender: return String(localized: "Sort alphabetically by sender name.", bundle: .module)
        case .subject: return String(localized: "Sort alphabetically by subject line.", bundle: .module)
        case .unreadFirst: return String(localized: "Show unread messages at the top.", bundle: .module)
        case .flaggedFirst: return String(localized: "Show flagged/starred messages at the top.", bundle: .module)
        case .attachmentFirst: return String(localized: "Show messages with attachments at the top.", bundle: .module)
        }
    }

    public var symbolName: String {
        switch self {
        case .newestFirst: return "arrow.down"
        case .oldestFirst: return "arrow.up"
        case .sender: return "person"
        case .subject: return "text.alignleft"
        case .unreadFirst: return "envelope.badge"
        case .flaggedFirst: return "flag"
        case .attachmentFirst: return "paperclip"
        }
    }
}

public enum MailboxReadingPanePlacement: String, Sendable, Hashable, CaseIterable, Identifiable {
    case side
    case bottom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .side: return String(localized: "Side", bundle: .module)
        case .bottom: return String(localized: "Bottom", bundle: .module)
        }
    }

    public var subtitle: String {
        switch self {
        case .side: return String(localized: "Reading pane to the right of the message list.", bundle: .module)
        case .bottom: return String(localized: "Reading pane below the message list.", bundle: .module)
        }
    }
}

public enum MailboxFontFamily: String, Sendable, Hashable, CaseIterable, Identifiable {
    case system
    case serif
    case rounded
    case monospaced

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return String(localized: "System", bundle: .module)
        case .serif: return String(localized: "Serif", bundle: .module)
        case .rounded: return String(localized: "Rounded", bundle: .module)
        case .monospaced: return String(localized: "Monospaced", bundle: .module)
        }
    }

    public var subtitle: String {
        switch self {
        case .system: return String(localized: "Apple San Francisco", bundle: .module)
        case .serif: return String(localized: "Editorial message reading", bundle: .module)
        case .rounded: return String(localized: "Softer interface text", bundle: .module)
        case .monospaced: return String(localized: "Code-like alignment", bundle: .module)
        }
    }

    public var fontDesign: Font.Design {
        switch self {
        case .system: return .default
        case .serif: return .serif
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        }
    }

    public var cssFamily: String {
        switch self {
        case .system:
            return "-apple-system,BlinkMacSystemFont,system-ui,sans-serif"
        case .serif:
            return "ui-serif,Georgia,Times New Roman,serif"
        case .rounded:
            return "ui-rounded,-apple-system,BlinkMacSystemFont,system-ui,sans-serif"
        case .monospaced:
            return "ui-monospace,SFMono-Regular,Menlo,monospace"
        }
    }

    public func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: fontDesign)
    }
}

public enum MailboxTextSize: String, Sendable, Hashable, CaseIterable, Identifiable {
    case small
    case medium
    case large

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .small: return String(localized: "Small", bundle: .module)
        case .medium: return String(localized: "Medium", bundle: .module)
        case .large: return String(localized: "Large", bundle: .module)
        }
    }

    public var bodyPointSize: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 15
        case .large: return 17
        }
    }

    public var listTitlePointSize: CGFloat {
        switch self {
        case .small: return 13
        case .medium: return 14
        case .large: return 16
        }
    }

    public var listDetailPointSize: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 13
        case .large: return 15
        }
    }

    public var captionPointSize: CGFloat {
        switch self {
        case .small: return 11
        case .medium: return 12
        case .large: return 13
        }
    }

    public var htmlPointSize: Int {
        Int(bodyPointSize.rounded())
    }
}

public enum MailboxListDensity: String, Sendable, Hashable, CaseIterable, Identifiable {
    case compact
    case comfortable
    case spacious

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .compact: return String(localized: "Compact", bundle: .module)
        case .comfortable: return String(localized: "Comfortable", bundle: .module)
        case .spacious: return String(localized: "Spacious", bundle: .module)
        }
    }

    public var verticalPadding: CGFloat {
        switch self {
        case .compact: return 4
        case .comfortable: return 8
        case .spacious: return 12
        }
    }

    public var avatarSize: CGFloat {
        switch self {
        case .compact: return 24
        case .comfortable: return 32
        case .spacious: return 36
        }
    }

    /// Vertical padding for one row in the mailbox/folder sidebar.
    public var sidebarRowVerticalPadding: CGFloat {
        switch self {
        case .compact: return 2
        case .comfortable: return 5
        case .spacious: return 8
        }
    }

    /// Vertical padding for compact filter and metadata chrome.
    public var chromeVerticalPadding: CGFloat {
        switch self {
        case .compact: return 3
        case .comfortable: return 6
        case .spacious: return 8
        }
    }

    /// Spacing between related metadata groups in list and reader headers.
    public var metadataSpacing: CGFloat {
        switch self {
        case .compact: return 3
        case .comfortable: return 8
        case .spacious: return 12
        }
    }
}

public enum MailboxPreviewLineCount: Int, Sendable, Hashable, CaseIterable, Identifiable {
    case none = 0
    case one = 1
    case two = 2
    case three = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .none: return String(localized: "No preview", bundle: .module)
        case .one: return String(localized: "1 line", bundle: .module)
        case .two: return String(localized: "2 lines", bundle: .module)
        case .three: return String(localized: "3 lines", bundle: .module)
        }
    }

    public var shortTitle: String {
        "\(rawValue)"
    }

    public var subtitle: String {
        switch self {
        case .none: return String(localized: "Hide preview text for the most compact mailbox list.", bundle: .module)
        case .one: return String(localized: "Show one row of preview text below each subject.", bundle: .module)
        case .two: return String(localized: "Show two rows of preview text below each subject.", bundle: .module)
        case .three: return String(localized: "Show three rows of preview text below each subject.", bundle: .module)
        }
    }

    public var visibleLineCount: Int {
        rawValue
    }
}
