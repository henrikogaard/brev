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

        private func hasThumb(_ control: UISwitch, in image: UIImage) throws -> Bool {
            let thumbX = control.frame.minX + control.frame.width * (control.isOn ? 0.75 : 0.25)
            let trackX = control.frame.minX + control.frame.width * (control.isOn ? 0.25 : 0.75)
            let thumb = try brightness(image, at: CGPoint(x: thumbX, y: control.frame.midY))
            let track = try brightness(image, at: CGPoint(x: trackX, y: control.frame.midY))
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
