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
@testable import BrevMail
import SwiftUI
import Testing

@Suite("Reader Dynamic Type layout")
@MainActor
struct ReaderDynamicTypeLayoutTests {
    @Test("Actual accessibility environments retain leading, bounded, scrollable macOS body geometry",
          arguments: [DynamicTypeSize.large, .accessibility3, .accessibility5])
    func readingColumn(size: DynamicTypeSize) throws {
        let narrow = try measure(width: 320, size: size)
        let wide = try measure(width: 1200, size: size)
        for (measurement, width) in [(narrow, CGFloat(320)), (wide, CGFloat(1200))] {
            #expect(measurement.dynamicTypeSize == size)
            #expect(abs(measurement.frame.minX - 24) < 1)
            #expect(abs(measurement.frame.minY - 24) < 1)
            #expect(abs(measurement.frame.width - min(540, width - 48)) < 1)
            #expect(measurement.frame.maxX <= width - 24 + 1)
            #expect(measurement.frame.height > 0)
            #expect(measurement.bodyPointSize == 15)
        }
        #expect(narrow.frame.height > wide.frame.height)
        #expect(narrow.frame.maxY > 480)
        let ordinary = try measure(width: 1200, size: .large)
        #expect(wide.frame == ordinary.frame)
    }

    private func measure(width: CGFloat, size: DynamicTypeSize) throws -> Measurement {
        var measured = Measurement()
        let view = ScrollView {
            BodyProbe().padding(24)
        }
        .frame(width: width, height: 480)
        .coordinateSpace(name: "reader")
        .environment(\.dynamicTypeSize, size)
        .environment(\.locale, Locale(identifier: "en_US"))
        .onPreferenceChange(MeasurementKey.self) { measured = $0 }
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: width, height: 480)
        host.layoutSubtreeIfNeeded()
        for _ in 0 ..< 20 where measured.frame.isEmpty {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            host.layoutSubtreeIfNeeded()
        }
        try #require(!measured.frame.isEmpty, "Offscreen SwiftUI layout must produce geometry")
        return measured
    }

    private struct BodyProbe: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            // macOS readers use mailbox typography; only iOS applies ScaledMetric.
            let style = MessageBodyStyle.resolve(theme: .brevMonoLight, fontFamily: .system,
                                                 textSize: .medium, renderingMode: .original, bodyInsetPoints: 0)
            Text(String(repeating: "A readable message preserves every word while wrapping within its column. ", count: 40))
                .font(style.swiftUIBodyFont)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: MeasurementKey.self, value: Measurement(
                            frame: proxy.frame(in: .named("reader")), dynamicTypeSize: dynamicTypeSize,
                            bodyPointSize: style.bodyPointSize
                        ))
                    }
                }
                .modifier(MessageReadingColumn(style: style))
        }
    }

    private struct Measurement: Equatable {
        var frame: CGRect = .zero
        var dynamicTypeSize: DynamicTypeSize = .large
        var bodyPointSize: CGFloat = 0
    }

    private struct MeasurementKey: PreferenceKey {
        static let defaultValue = Measurement()

        static func reduce(value: inout Measurement, nextValue: () -> Measurement) {
            value = nextValue()
        }
    }
}
#endif
