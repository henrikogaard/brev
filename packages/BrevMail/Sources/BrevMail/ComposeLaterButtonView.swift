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

/// Primary compose "Later" action chip placed adjacent to Send (#297).
struct ComposeLaterButtonView: View {
    let isScheduled: Bool
    let isEnabled: Bool
    let hitTargetSize: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(String(localized: "Later", bundle: .module), systemImage: "clock")
                .brevFont(.footnote)
                .brevChip(selected: isScheduled)
                .frame(minHeight: hitTargetSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(
            isScheduled
                ? String(localized: "Edit scheduled send", bundle: .module)
                : String(localized: "Later", bundle: .module)
        )
        .accessibilityAddTraits(isScheduled ? .isSelected : [])
        .help(
            isScheduled
                ? String(localized: "Edit scheduled send", bundle: .module)
                : ComposeToolbarAction.scheduleSend.accessibilityLabel
        )
    }
}
