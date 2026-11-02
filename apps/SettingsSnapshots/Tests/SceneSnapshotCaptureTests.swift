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

import BrevSettings
import Testing
import UIKit

extension SettingsFormSnapshotTests {
    @Suite("Scene snapshot capture guards", .serialized)
    @MainActor
    struct SceneSnapshotCaptureTests {
        @Test("review launch selections are explicit and fail closed")
        func reviewSelection() throws {
            #expect(try SettingsReviewSelection.parse([:]) == nil)
            for pane in SettingsReviewPane.allCases {
                for variant in SettingsReviewVariant.allCases {
                    #expect(try SettingsReviewSelection.parse([
                        "BREV_SETTINGS_REVIEW_PANE": pane.rawValue,
                        "BREV_SETTINGS_REVIEW_VARIANT": variant.rawValue
                    ]) == SettingsReviewSelection(pane: pane, variant: variant))
                }
            }
            for environment in [
                ["BREV_SETTINGS_REVIEW_PANE": "appearance"],
                ["BREV_SETTINGS_REVIEW_VARIANT": "light"],
                ["BREV_SETTINGS_REVIEW_PANE": "unknown", "BREV_SETTINGS_REVIEW_VARIANT": "light"],
                ["BREV_SETTINGS_REVIEW_PANE": "appearance", "BREV_SETTINGS_REVIEW_VARIANT": "unknown"]
            ] {
                #expect(throws: SettingsReviewSelection.SelectionError.self) {
                    try SettingsReviewSelection.parse(environment)
                }
            }
        }

        @Test("native review defaults reset without touching another fixture")
        func fixtureIsolation() throws {
            let first = try SettingsReviewFixture(variant: .dark)
            let other = try SettingsReviewFixture(variant: .light)
            defer { first.cleanUp(); other.cleanUp() }
            first.defaults.set(true, forKey: "fixture-marker")
            other.defaults.set(true, forKey: "fixture-marker")
            let reopened = try SettingsReviewFixture(variant: .light, suite: first.suite)
            #expect(reopened.defaults.object(forKey: "fixture-marker") == nil)
            #expect(other.defaults.bool(forKey: "fixture-marker"))
            #expect(reopened.account.emailAddress == "henrik@ogard.example")
        }

        @Test("quiet-hours review does not alter the canonical default")
        func quietHoursFixture() throws {
            let canonical = try SettingsReviewFixture(variant: .ax3)
            let enabled = try SettingsReviewFixture(variant: .ax3, quietHoursEnabled: true)
            defer { canonical.cleanUp(); enabled.cleanUp() }
            #expect(!canonical.defaults.bool(forKey: "notifications.quietHoursEnabled"))
            #expect(enabled.defaults.bool(forKey: "notifications.quietHoursEnabled"))
        }

        @Test("PIM review data is seeded and network transport is denied")
        func pimFixture() async throws {
            let model = try await PIMSourcesFixture.model()
            #expect(Set(model.sources.map(\.id)) == ["g-cal", "g-con", "dav"])
            #expect(model.collectionsBySource["g-con"]?.count == 8)
            #expect(model.collectionsBySource["dav"]?.first?.displayName == "QA Calendar")
            #expect(!model.canEnableGoogleFeatures)
            for source in model.sources {
                #expect(!model.canSyncNow(sourceID: source.id))
            }
            let url = try #require(URL(string: "https://dav.example.com/"))
            await #expect(throws: URLError.self) {
                try await PIMSourcesFixture.DeniedTransport().send(URLRequest(url: url))
            }
        }

        @Test("bottom capture rejects missing and ambiguous scroll views", arguments: [0, 2])
        func missingScrollView(count: Int) async {
            let controller = UIViewController()
            for _ in 0 ..< count {
                controller.view.addSubview(UIScrollView())
            }
            await #expect(throws: SceneSnapshotCapture.CaptureError.ambiguousScrollView) {
                try await SceneSnapshotCapture.image(
                    of: controller, size: CGSize(width: 375, height: 812),
                    traits: UITraitCollection(displayScale: 2), name: "invalid-scroll", scrollToBottom: true
                )
            }
        }

        @Test("bottom capture includes the last control after content grows")
        func bottomCapture() async throws {
            let controller = UIViewController()
            let view = GrowingScrollDrawingView()
            controller.view = view
            let image = try await SceneSnapshotCapture.image(
                of: controller, size: CGSize(width: 375, height: 812),
                traits: UITraitCollection(traitsFrom: [
                    UITraitCollection(displayScale: 2), UITraitCollection(userInterfaceStyle: .light)
                ]), name: "bottom-control", scrollToBottom: true
            )
            #expect(view.scroll.contentOffset.y == CGFloat(2000 - 812))
            let frame = view.control.convert(view.control.bounds, to: view)
            #expect(view.bounds.contains(frame))
            #expect(try hasThumb(view.control, in: image, frame: frame))
        }

        @Test("host includes every app icon preview", arguments: AppIconVariant.allCases)
        func iconPreviews(variant: AppIconVariant) throws {
            let image = try #require(UIImage(named: variant.previewAssetName, in: .main, compatibleWith: nil))
            #expect(image.size.width > 0 && image.size.height > 0)
        }

        @Test("invalid dimensions cannot produce a baseline")
        func invalidSize() async {
            await #expect(throws: SceneSnapshotCapture.CaptureError.invalidSize) {
                try await SceneSnapshotCapture.image(
                    of: UIViewController(), size: .zero, traits: UITraitCollection(), name: "invalid"
                )
            }
        }

        @Test("failed hierarchy drawing is not silently accepted")
        func failedDrawing() async throws {
            let controller = UIViewController()
            controller.view = FailedDrawingView()
            let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first(where: \.isKeyWindow)
            await #expect(throws: SceneSnapshotCapture.CaptureError.drawingFailed) {
                try await SceneSnapshotCapture.image(
                    of: controller, size: CGSize(width: 375, height: 480),
                    traits: UITraitCollection(displayScale: 2), name: "failed-drawing"
                )
            }
            #expect(controller.parent == nil)
            #expect(controller.view.window == nil)
            #expect(previous?.isKeyWindow == true)
        }

        @Test("captures switches on ordinary and tall canvases", arguments: [812.0, 1800.0])
        func switches(height: Double) async throws {
            let controller = UIViewController()
            controller.view.backgroundColor = .systemBackground
            let enabled = UISwitch(frame: CGRect(x: 24, y: 24, width: 60, height: 40))
            enabled.sizeToFit()
            enabled.isOn = true
            let disabled = UISwitch(frame: CGRect(x: 24, y: height - 100, width: 60, height: 40))
            disabled.sizeToFit()
            controller.view.addSubview(enabled)
            controller.view.addSubview(disabled)
            let image = try await SceneSnapshotCapture.image(
                of: controller, size: CGSize(width: 375, height: height),
                traits: UITraitCollection(traitsFrom: [
                    UITraitCollection(displayScale: 2),
                    UITraitCollection(userInterfaceStyle: .light)
                ]), name: "switches-\(Int(height))"
            )
            #expect(image.cgImage?.width == 750)
            #expect(image.cgImage?.height == Int(height * 2))
            #expect(try hasThumb(enabled, in: image))
            #expect(try hasThumb(disabled, in: image))

            let blank = UIGraphicsImageRenderer(size: image.size).image { context in
                UIColor.systemBackground.setFill()
                context.fill(CGRect(origin: .zero, size: image.size))
            }
            #expect(try !hasThumb(enabled, in: blank))
            #expect(try !hasThumb(disabled, in: blank))
        }

        private func hasThumb(_ control: UISwitch, in image: UIImage, frame: CGRect? = nil) throws -> Bool {
            let frame = frame ?? control.frame
            let thumbX = frame.minX + frame.width * (control.isOn ? 0.75 : 0.25)
            let trackX = frame.minX + frame.width * (control.isOn ? 0.25 : 0.75)
            let thumb = try brightness(image, at: CGPoint(x: thumbX, y: frame.midY))
            let track = try brightness(image, at: CGPoint(x: trackX, y: frame.midY))
            return thumb > 0.8 && thumb - track > 0.1
        }

        private func brightness(_ image: UIImage, at point: CGPoint) throws -> Double {
            let source = try #require(image.cgImage)
            let pixel = try #require(source.cropping(to: CGRect(
                x: floor(point.x * image.scale), y: floor(point.y * image.scale),
                width: 1, height: 1
            )))
            let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            var rgba = [UInt8](repeating: 0, count: 4)
            try rgba.withUnsafeMutableBytes { bytes in
                let context = try #require(CGContext(
                    data: bytes.baseAddress, width: 1, height: 1,
                    bitsPerComponent: 8, bytesPerRow: 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            return (0.2126 * Double(rgba[0]) + 0.7152 * Double(rgba[1]) + 0.0722 * Double(rgba[2])) / 255
        }

        @Test("waits for pixels to settle across display boundaries")
        func settles() async throws {
            let controller = UIViewController()
            let view = ChangingDrawingView()
            controller.view = view
            _ = try await SceneSnapshotCapture.image(
                of: controller, size: CGSize(width: 375, height: 812),
                traits: UITraitCollection(displayScale: 2), name: "settling"
            )
            #expect(view.drawCount >= 5)
        }

        @Test("continuously changing pixels cannot become a baseline")
        func neverSettles() async throws {
            let controller = UIViewController()
            let view = ChangingDrawingView()
            view.changesContinuously = true
            controller.view = view
            await #expect(throws: SceneSnapshotCapture.CaptureError.unstableImage) {
                try await SceneSnapshotCapture.image(
                    of: controller, size: CGSize(width: 375, height: 812),
                    traits: UITraitCollection(displayScale: 2), name: "never-settling"
                )
            }
        }
    }
}

@MainActor
private final class GrowingScrollDrawingView: UIView {
    let scroll = UIScrollView()
    let control = UISwitch()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentSize = CGSize(width: 375, height: 1800)
        control.isOn = true
        control.sizeToFit()
        control.frame.origin = CGPoint(x: 24, y: 1700)
        scroll.addSubview(control)
        addSubview(scroll)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
    }

    override func drawHierarchy(in rect: CGRect, afterScreenUpdates afterUpdates: Bool) -> Bool {
        scroll.contentSize.height = 2000
        control.frame.origin.y = 1900
        return super.drawHierarchy(in: rect, afterScreenUpdates: afterUpdates)
    }
}

@MainActor
private final class ChangingDrawingView: UIView {
    var drawCount = 0
    var changesContinuously = false

    override func drawHierarchy(in rect: CGRect, afterScreenUpdates afterUpdates: Bool) -> Bool {
        drawCount += 1
        let phase = changesContinuously ? drawCount : min(drawCount, 3)
        backgroundColor = phase.isMultiple(of: 2) ? .systemBackground : .secondarySystemBackground
        return super.drawHierarchy(in: rect, afterScreenUpdates: afterUpdates)
    }
}

@MainActor
private final class FailedDrawingView: UIView {
    override func drawHierarchy(in _: CGRect, afterScreenUpdates _: Bool) -> Bool { false }
}
