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

/// The label chips a message row shows: the first few user labels plus a
/// "+N" overflow count.
struct MessageLabelRowChips: Equatable, Sendable {
    let visible: [String]
    let overflowCount: Int
}

/// Pure presentation rules for provider labels (`MessageHeader.labels`).
///
/// System labels (`\Inbox`, `\Important`, `\Starred`, …) already surface
/// through folders and flags, so only user labels are shown or offered.
enum MessageLabelPresentation {
    /// Default number of chips a list row shows before collapsing to "+N".
    static let rowChipLimit = 2

    /// True for provider system labels, which are backslash-prefixed.
    static func isSystemLabel(_ label: String) -> Bool {
        label.hasPrefix("\\")
    }

    /// User labels in server order.
    static func displayLabels(from labels: [String]) -> [String] {
        labels.filter { !isSystemLabel($0) }
    }

    /// The row chip set: up to `limit` user labels plus the overflow count.
    static func rowChips(from labels: [String], limit: Int = rowChipLimit) -> MessageLabelRowChips {
        let display = displayLabels(from: labels)
        let visible = Array(display.prefix(max(limit, 0)))
        return MessageLabelRowChips(visible: visible, overflowCount: display.count - visible.count)
    }

    /// Labels a user can apply, derived from the folder list: Gmail exposes
    /// each user label as a mailbox whose path is the label name. Role folders
    /// and the `[Gmail]` system tree are excluded; sorted case-insensitively.
    static func candidateLabels(from folders: [Folder]) -> [String] {
        folders
            .filter { $0.role == .custom && !isGmailSystemTree($0.id) }
            .map(\.id)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func isGmailSystemTree(_ folderID: Folder.ID) -> Bool {
        folderID.hasPrefix("[Gmail]") || folderID.hasPrefix("[Google Mail]")
    }
}
