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

enum MailDenseChromeDynamicType {
    static let compactRange: PartialRangeThrough<DynamicTypeSize> = ...DynamicTypeSize.large
    static let range: PartialRangeThrough<DynamicTypeSize> = ...DynamicTypeSize.xxxLarge
}

extension View {
    /// Caps dense list chrome (date headers, row status icons, category tabs) at `.large`
    /// on macOS. On iOS the chrome follows the user's Dynamic Type setting, including the
    /// accessibility sizes (audit L9); the phone rows switch to their accessibility layout.
    @ViewBuilder
    func mailDenseListChromeDynamicType() -> some View {
        #if os(iOS)
        self
        #else
        dynamicTypeSize(MailDenseChromeDynamicType.compactRange)
        #endif
    }
}
