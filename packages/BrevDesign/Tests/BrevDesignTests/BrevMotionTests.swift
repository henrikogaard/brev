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

import BrevDesign
import SwiftUI
import Testing

@Suite("BrevMotion")
struct BrevMotionTests {
    @Test("Reduce Motion removes the animation")
    func reduceMotionReturnsNil() {
        #expect(BrevMotion.animation(.easeInOut, reduceMotion: true) == nil)
    }

    @Test("Without Reduce Motion the requested animation is kept")
    func motionKeepsRequestedAnimation() {
        #expect(BrevMotion.animation(.easeInOut, reduceMotion: false) == .easeInOut)
        #expect(BrevMotion.animation(nil, reduceMotion: false) == nil)
    }

    @Test("withAnimation wrapper always runs the body")
    @MainActor
    func wrapperRunsBody() {
        var ran = 0
        brevWithAnimation(.default, reduceMotion: true) { ran += 1 }
        brevWithAnimation(.default, reduceMotion: false) { ran += 1 }
        #expect(ran == 2)
    }
}
