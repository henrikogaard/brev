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

#if canImport(UIKit)
import BrevBackend
@testable import BrevMail
import BrevThemes
import Darwin
import SwiftUI
import UIKit
import XCTest

/// Exercises the mailbox launch path with the stack budget from the device crash.
final class BrevMailRootLaunchTests: XCTestCase {
    @MainActor
    func testMailboxFitsPhoneMainThreadStack() throws {
        // Simulator normally has an 8 MiB main-thread stack. Build 6 overflowed
        // the physical phone's 1 MiB stack before its first mailbox frame.
        // A temporary guard page makes that failure reproducible in Release
        // simulator tests without changing application code or thread affinity.
        let restoreStack = try installPhoneStackGuard()
        defer { restoreStack() }

        let root = BrevMailRootView(backend: MockBackend(), onChangeTheme: { _ in })
            .brevTheme(.brevMonoLight)
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertGreaterThan(host.view.bounds.width, 0)
        XCTAssertFalse(host.view.subviews.isEmpty)
    }

    @MainActor
    private func installPhoneStackGuard() throws -> () -> Void {
        XCTAssertTrue(Thread.isMainThread)
        #if targetEnvironment(simulator)
        let stackTop = UInt(bitPattern: pthread_get_stackaddr_np(pthread_self()))
        let stackSize = pthread_get_stacksize_np(pthread_self())
        let budget: UInt = 1024 * 1024
        let pageSize = Int(getpagesize())
        guard stackSize > budget else { return {} }
        let guardAddress = (stackTop - budget) & ~UInt(pageSize - 1)
        var marker = UInt8(0)
        let currentAddress = withUnsafePointer(to: &marker) { UInt(bitPattern: $0) }
        guard currentAddress > guardAddress + UInt(pageSize) + 128 * 1024 else {
            throw XCTSkip("Test harness already occupies most of the phone stack budget")
        }
        let page = try XCTUnwrap(UnsafeMutableRawPointer(bitPattern: guardAddress))
        guard mprotect(page, pageSize, PROT_NONE) == 0 else {
            XCTFail("Could not install phone-sized stack guard: \(errno)")
            return {}
        }
        return { XCTAssertEqual(mprotect(page, pageSize, PROT_READ | PROT_WRITE), 0) }
        #else
        // Physical devices already enforce the budget; never change their stack.
        return {}
        #endif
    }
}
#endif
