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

import Foundation

struct ComposeBodyTextSelection: Equatable, Sendable {
    let nsRange: NSRange
    let selectedText: String

    init?(bodyText: String, nsRange: NSRange) {
        guard nsRange.location != NSNotFound, nsRange.length > 0 else {
            return nil
        }
        guard let range = Range(nsRange, in: bodyText) else {
            return nil
        }
        let selectedText = String(bodyText[range])
        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        self.nsRange = nsRange
        self.selectedText = selectedText
    }

    func replacingSelection(in bodyText: String, with replacement: String) -> String? {
        guard let range = Range(nsRange, in: bodyText) else {
            return nil
        }
        var updated = bodyText
        updated.replaceSubrange(range, with: replacement)
        return updated
    }
}

struct ComposeBodyInsertionPoint: Equatable, Sendable {
    let nsRange: NSRange

    init?(bodyText: String, nsRange: NSRange) {
        guard nsRange.location != NSNotFound, nsRange.length == 0 else {
            return nil
        }
        guard Range(nsRange, in: bodyText) != nil else {
            return nil
        }
        self.nsRange = nsRange
    }

    func insertingText(_ insertion: String, in bodyText: String) -> String? {
        guard let range = Range(nsRange, in: bodyText) else {
            return nil
        }
        var updated = bodyText
        updated.replaceSubrange(range, with: insertion)
        return updated
    }
}
