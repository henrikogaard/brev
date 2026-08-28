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

private struct MessageListRefreshArrivalEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isArrival: Bool
    let delay: TimeInterval

    @State private var hasEntered = false

    func body(content: Content) -> some View {
        content
            .opacity(shouldAnimate && !hasEntered ? 0 : 1)
            .offset(y: shouldAnimate && !hasEntered ? -12 : 0)
            .onAppear {
                enterIfNeeded()
            }
            .onChange(of: isArrival) { _, isArrival in
                hasEntered = !isArrival
                enterIfNeeded()
            }
            .onChange(of: reduceMotion) {
                enterIfNeeded()
            }
    }

    private var shouldAnimate: Bool {
        isArrival && !reduceMotion
    }

    private func enterIfNeeded() {
        guard shouldAnimate else {
            hasEntered = true
            return
        }
        withAnimation(.easeOut(duration: 0.28).delay(delay)) {
            hasEntered = true
        }
    }
}

extension View {
    func messageListRefreshArrival(isArrival: Bool, delay: TimeInterval) -> some View {
        modifier(MessageListRefreshArrivalEffect(isArrival: isArrival, delay: delay))
    }
}
