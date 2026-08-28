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

enum ComposeTextCheckingMode: Equatable, Sendable {
    case native
    case disabled
}

struct ComposeTextCheckingConfiguration: Equatable, Sendable {
    let spellChecking: ComposeTextCheckingMode
    let grammarChecking: ComposeTextCheckingMode
    let autocorrection: ComposeTextCheckingMode
}

enum ComposeTextCheckingPolicy {
    static let storageKey = "compose.textChecking.enabled"
    static let defaultIsEnabled = true
    static let settingsTitle = "Check spelling while typing"
    static let settingsSubtitle = "Use the system spell-check, grammar, and autocorrect helpers in the compose body."

    static func configuration(isEnabled: Bool) -> ComposeTextCheckingConfiguration {
        let mode: ComposeTextCheckingMode = isEnabled ? .native : .disabled
        return ComposeTextCheckingConfiguration(
            spellChecking: mode,
            grammarChecking: mode,
            autocorrection: mode
        )
    }
}
