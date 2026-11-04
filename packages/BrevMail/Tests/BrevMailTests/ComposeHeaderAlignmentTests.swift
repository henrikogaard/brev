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
@testable import BrevMail
import SwiftUI
import Testing

/// Reads the rendered macOS compose window: the To, From and Subject labels
/// and the body text must start on one left edge, and every row divider is
/// one hairline (#279 QA).
@Suite("Compose header alignment")
@MainActor
struct ComposeHeaderAlignmentTests {
    @Test("header labels and body text share one left edge")
    func labelsAndBodyShareLeftEdge() async throws {
        let backend = MockBackend()
        let draft = try await backend.save(draft: Draft(id: UUID().uuidString, htmlBody: "Hello alignment"))
        let defaultsName = "ComposeHeaderAlignmentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.set("richText", forKey: "compose.messageFormat")

        var mounted: ComposeView?
        var view = ComposeView(
            backend: backend,
            sourceID: nil,
            from: Correspondent(email: "sender@example.invalid"),
            senderOptions: [],
            recoveredDraft: nil,
            existingDraft: draft,
            existingDraftAttachments: [],
            existingDraftIsServerSourced: false,
            recoveryDefaults: defaults,
            onClose: {},
            onCompletion: { _ in }
        )
        view.inspection = { mounted = $0 }
        let size = NSSize(width: 700, height: 600)
        let host = NSHostingView(rootView: AnyView(view.defaultAppStorage(defaults)))
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        defer { host.rootView = AnyView(EmptyView()) }
        await mounted?.restoreDraftIfNeeded()
        for _ in 0 ..< 500 where Self.editor(in: host)?.string != "Hello alignment" {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(Self.editor(in: host)?.string == "Hello alignment")

        let (edges, dividers) = Self.scan(host, size: size)
        // To, From, Subject and the body line.
        #expect(edges.count >= 4, "left edges: \(edges)")
        let spread = (edges.max() ?? 0) - (edges.min() ?? 0)
        #expect(spread <= 2, "left edges: \(edges)")
        // One line each below To, From and Subject. A doubled line carries
        // twice the ink of a single one, even when 1x rendering splits a
        // hairline across two pixel rows.
        #expect(dividers.count == 3, "divider ink: \(dividers)")
        let lightest = dividers.min() ?? 0
        #expect(dividers.allSatisfy { $0 <= lightest * 1.5 }, "divider ink: \(dividers)")
    }

    /// The leftmost inked pixel of each run of text rows in the left third of
    /// the view, and the total ink of each faint line across the empty middle
    /// of the view (dividers).
    private static func scan(_ view: NSView, size: NSSize) -> (edges: [Int], dividers: [CGFloat]) {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.size = size
        view.cacheDisplay(in: view.bounds, to: bitmap)

        func ink(_ x: Int, _ y: Int, against background: NSColor) -> CGFloat {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return 0 }
            return abs(color.redComponent - background.redComponent)
                + abs(color.greenComponent - background.greenComponent)
                + abs(color.blueComponent - background.blueComponent)
        }

        let width = Int(size.width)
        var edges: [Int] = []
        var dividers: [CGFloat] = []
        var runEdge: Int?
        var lineInk: CGFloat?
        for y in 0 ..< Int(size.height) {
            guard let background = bitmap.colorAt(x: 2, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            let leftmost = (4 ..< width / 3).first { ink($0, y, against: background) > 0.3 }
            // Hairlines are faint; sample the empty middle of the row.
            let isDivider = [300, 400, 500].allSatisfy { ink($0, y, against: background) > 0.05 }
            if isDivider {
                lineInk = (lineInk ?? 0) + ink(400, y, against: background)
            } else if let total = lineInk {
                dividers.append(total)
                lineInk = nil
            }
            if let leftmost, !isDivider {
                runEdge = min(runEdge ?? leftmost, leftmost)
            } else if let edge = runEdge {
                edges.append(edge)
                runEdge = nil
            }
        }
        if let runEdge { edges.append(runEdge) }
        return (edges, dividers)
    }

    private static func editor(in view: NSView) -> ComposeRichTextView? {
        if let editor = view as? ComposeRichTextView { return editor }
        return view.subviews.lazy.compactMap { editor(in: $0) }.first
    }
}
#endif
