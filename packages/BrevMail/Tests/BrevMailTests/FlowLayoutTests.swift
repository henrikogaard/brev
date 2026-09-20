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
@testable import BrevMail
import SwiftUI
import Testing
import UIKit

@Suite("Recipient flow bounds", .serialized)
@MainActor
struct FlowLayoutTests {
    @Test("a long recipient input stays within its proposed phone width")
    func longInputFits() {
        let host = UIHostingController(rootView:
            FlowLayout {
                TextField("long.recipient.address@example.org", text: .constant(""))
                    .font(.body)
            }
            .environment(\.dynamicTypeSize, .accessibility5)
            .frame(width: 240))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 240, height: 400))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        let fields = descendants(of: host.view).compactMap { $0 as? UITextField }
        #expect(!fields.isEmpty)
        for field in fields {
            #expect(field.bounds.width <= 240)
        }
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
#endif
