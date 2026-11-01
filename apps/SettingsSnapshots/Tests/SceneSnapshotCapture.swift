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
import Testing
import UIKit

@MainActor
enum SceneSnapshotCapture {
    enum CaptureError: Error, Equatable {
        case missingScene
        case invalidSize
        case drawingFailed
        case unstableImage
        case displayTimeout
    }

    static func image(
        of controller: UIViewController,
        size: CGSize,
        traits: UITraitCollection,
        name: String
    ) async throws -> UIImage {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            throw CaptureError.invalidSize
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        guard scenes.count == 1, let scene = scenes.first else { throw CaptureError.missingScene }

        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = container
        window.overrideUserInterfaceStyle = traits.userInterfaceStyle
        let animationsEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer {
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
            UIView.setAnimationsEnabled(animationsEnabled)
        }

        container.addChild(controller)
        container.setOverrideTraitCollection(traits, forChild: controller)
        container.view.addSubview(controller.view)
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.didMove(toParent: container)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        CATransaction.flush()
        try await DisplayBoundary.wait()
        try await DisplayBoundary.wait()
        guard controller.view.window?.isKeyWindow == true,
              controller.view.window?.windowScene === scene,
              controller.view.bounds.size == size,
              controller.traitCollection.displayScale == traits.displayScale else {
            throw CaptureError.missingScene
        }

        var previous = try #require(draw(controller.view, traits: traits).pngData())
        var identicalFrames = 1
        for _ in 0 ..< 60 {
            try await DisplayBoundary.wait()
            let image = try draw(controller.view, traits: traits)
            let data = try #require(image.pngData())
            identicalFrames = data == previous ? identicalFrames + 1 : 1
            if identicalFrames == 3 {
                try Attachment.record(data, named: "\(name)-hierarchy.png")
                return image
            }
            previous = data
        }
        try Attachment.record(previous, named: "\(name)-unstable.png")
        throw CaptureError.unstableImage
    }

    private static func draw(_ view: UIView, traits: UITraitCollection) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat(for: traits)
        var succeeded = false
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            succeeded = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        guard succeeded else { throw CaptureError.drawingFailed }
        return image
    }
}

@MainActor
private final class DisplayBoundary: NSObject {
    private var continuation: CheckedContinuation<Void, Error>?
    private var displayLink: CADisplayLink?

    static func wait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let boundary = DisplayBoundary()
            boundary.continuation = continuation
            let link = CADisplayLink(target: boundary, selector: #selector(tick))
            boundary.displayLink = link
            link.add(to: .main, forMode: .common)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                boundary.finish(error: SceneSnapshotCapture.CaptureError.displayTimeout)
            }
        }
    }

    @objc private func tick() { finish() }

    private func finish(error: Error? = nil) {
        guard let continuation else { return }
        self.continuation = nil
        displayLink?.invalidate()
        displayLink = nil
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }
}
