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

struct MailAuxiliaryPresentationModifier: ViewModifier {
    @Binding var sheet: MailNavigationState.Sheet?
    let makeContent: (MailNavigationState.Sheet, @escaping () -> Void) -> AnyView

    func body(content base: Content) -> some View {
        #if os(macOS)
        base.background {
            MacMailAuxiliaryWindowPresenter(
                sheet: $sheet,
                makeContent: makeContent
            )
            .frame(width: 0, height: 0)
        }
        #else
        base.sheet(item: $sheet) { sheet in
            makeContent(sheet) {
                self.sheet = nil
            }
        }
        #endif
    }
}
