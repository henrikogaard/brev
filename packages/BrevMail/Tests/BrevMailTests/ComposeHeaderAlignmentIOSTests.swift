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

#if os(iOS)
import BrevBackend
@testable import BrevMail
import BrevThemes
import SwiftUI
import Testing
import UIKit

/// Reads the rendered phone compose sheet: the header labels and the body text
/// must start on one left edge, and every header row, Cc and Bcc included, has
/// the same height and ends in one hairline. The macOS twin is
/// `ComposeHeaderAlignmentTests` (#279 QA).
@Suite("Compose header alignment on iOS", .serialized)
@MainActor
struct ComposeHeaderAlignmentIOSTests {
    private static let phone = CGSize(width: 390, height: 844)
    /// Narrowest supported phone width, matching `ComposeAccessibilityBoundsTests`;
    /// tall enough to show every stacked row at accessibility sizes.
    private static let narrowPhone = CGSize(width: 320, height: 1600)

    @Test("header labels and body text share one left edge and rows match",
          arguments: [false, true], [UIContentSizeCategory.large, .extraExtraExtraLarge])
    func labelsBodyAndRowsLineUp(expanded: Bool, textSize: UIContentSizeCategory) {
        let header = render(expanded: expanded, textSize: textSize, size: Self.phone)

        // To, (Cc, Bcc, From | the collapsed row,) Subject and the body line.
        #expect(header.edges.count >= (expanded ? 6 : 4), "left edges: \(header.edges)")
        let spread = (header.edges.max() ?? 0) - (header.edges.min() ?? 0)
        #expect(spread <= 2, "left edges: \(header.edges)")
        #expect(abs((header.edges.first ?? 0) - 24) <= 2, "left edges: \(header.edges)")

        // One line below each header row, running to the sheet's right edge. A
        // doubled line carries twice the ink of a single one.
        #expect(header.dividers.count == (expanded ? 5 : 3), "dividers: \(header.dividers)")
        let lightest = header.dividers.map(\.ink).min() ?? 0
        #expect(header.dividers.allSatisfy { $0.ink <= lightest * 1.5 }, "dividers: \(header.dividers)")

        // Rows with address chips and rows of plain text are equally tall.
        let bottoms = header.dividers.map(\.y)
        let heights = zip(bottoms, bottoms.dropFirst()).map { $1 - $0 }
        #expect((heights.max() ?? 0) - (heights.min() ?? 0) <= 1, "row heights: \(heights)")
        // The sheet's toolbar hides the top of the To row, so compare the room
        // below the To and Subject labels, which have the same font.
        let toRoom = (bottoms.first ?? 0) - (header.labelTops.first ?? 0)
        let subjectRoom = (bottoms.last ?? 0) - (header.labelTops.last ?? 0)
        #expect(abs(toRoom - subjectRoom) <= 1, "label tops: \(header.labelTops), dividers: \(bottoms)")
    }

    /// Chips sit on their own line at accessibility sizes and their fill starts
    /// on the same edge, so the expanded case only counts hairlines.
    @Test("accessibility layout keeps one left edge and one hairline per row on a narrow phone",
          arguments: [false, true])
    func accessibilityLayoutOnNarrowPhone(expanded: Bool) {
        let header = render(
            expanded: expanded,
            textSize: .accessibilityExtraExtraExtraLarge,
            size: Self.narrowPhone
        )

        #expect(header.dividers.count == (expanded ? 5 : 3), "dividers: \(header.dividers)")
        let lightest = header.dividers.map(\.ink).min() ?? 0
        #expect(header.dividers.allSatisfy { $0.ink <= lightest * 1.5 }, "dividers: \(header.dividers)")
        if !expanded {
            let spread = (header.edges.max() ?? 0) - (header.edges.min() ?? 0)
            #expect(header.edges.count >= 4, "left edges: \(header.edges)")
            #expect(spread <= 3, "left edges: \(header.edges)")
        }
    }

    private func render(
        expanded: Bool,
        textSize: UIContentSizeCategory,
        size: CGSize
    ) -> (edges: [CGFloat], labelTops: [CGFloat], dividers: [(y: CGFloat, ink: CGFloat)]) {
        let backend = MockBackend()
        let view = ComposeView(
            backend: backend,
            from: backend.account,
            prefill: ComposePrefill(
                cc: expanded ? ["team@acme.example"] : [],
                bcc: expanded ? ["audit@acme.example"] : [],
                bodyText: "Hello alignment"
            )
        )
        .background(BrevTheme.brevMonoLight.bgPrimary.color)
        .environment(\.horizontalSizeClass, .compact)
        .brevTheme(.brevMonoLight)
        .htmlBodyRenderTarget(.staticSnapshot)
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.traitOverrides.preferredContentSizeCategory = textSize
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        window.layoutIfNeeded()
        return Self.scan(host.view, size: size)
    }

    /// The leftmost inked point and top of each run of text rows in the left
    /// third of the sheet, and the first row and total ink of each faint line
    /// across the empty right side (dividers).
    private static func scan(
        _ view: UIView,
        size: CGSize
    ) -> (edges: [CGFloat], labelTops: [CGFloat], dividers: [(y: CGFloat, ink: CGFloat)]) {
        let scale: CGFloat = 2
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            view.layer.render(in: context.cgContext)
        }
        let bitmap = RGBABitmap(image: image)

        let width = Int(size.width * scale)
        // Hairlines are faint; sample the row's empty right side, ending close
        // enough to the edge that a line stopping at the text inset is missed.
        let lineSamples = [0.8, 0.9, 0.99].map { Int(CGFloat(width) * $0) }
        var runs: [(top: Int, edge: Int)] = []
        var dividers: [(y: Int, ink: CGFloat)] = []
        var run: (top: Int, edge: Int)?
        var line: (y: Int, ink: CGFloat)?
        for y in 0 ..< bitmap.height {
            let background = bitmap.pixel(x: 2, y: y)
            let leftmost = (Int(4 * scale) ..< width / 3).first { bitmap.ink(x: $0, y: y, against: background) > 0.3 }
            let isDivider = lineSamples.allSatisfy { bitmap.ink(x: $0, y: y, against: background) > 0.05 }
            if isDivider {
                line = (line?.y ?? y, (line?.ink ?? 0) + bitmap.ink(x: lineSamples[1], y: y, against: background))
            } else if let finished = line {
                dividers.append(finished)
                line = nil
            }
            if let leftmost, !isDivider {
                run = (run?.top ?? y, min(run?.edge ?? leftmost, leftmost))
            } else if let finished = run {
                runs.append(finished)
                run = nil
            }
        }

        // The lower part of the sheet holds the utility bar, and the first run
        // is the toolbar's Cancel button. The last run left is the body line.
        let headerDividers = dividers.filter { CGFloat($0.y) < size.height * scale * 0.75 }
        let lastLine = headerDividers.last?.y ?? 0
        let bodyAndLabels = runs.dropFirst().filter { $0.top < lastLine + Int(120 * scale) }
        let labels = Array(bodyAndLabels.dropLast())
        return (
            bodyAndLabels.map { CGFloat($0.edge) / scale },
            labels.map { CGFloat($0.top) / scale },
            headerDividers.map { (CGFloat($0.y) / scale, $0.ink) }
        )
    }
}

/// Fixed-layout pixel access for a rendered image.
private struct RGBABitmap {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init(image: UIImage) {
        let cgImage = image.cgImage!
        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        var data = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        }
        width = pixelWidth
        height = pixelHeight
        bytes = data
    }

    /// The red, green and blue components at a pixel counted from the top left.
    func pixel(x: Int, y: Int) -> (CGFloat, CGFloat, CGFloat) {
        let offset = (y * width + x) * 4
        return (CGFloat(bytes[offset]) / 255, CGFloat(bytes[offset + 1]) / 255, CGFloat(bytes[offset + 2]) / 255)
    }

    func ink(x: Int, y: Int, against background: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
        let color = pixel(x: x, y: y)
        return abs(color.0 - background.0) + abs(color.1 - background.1) + abs(color.2 - background.2)
    }
}
#endif
