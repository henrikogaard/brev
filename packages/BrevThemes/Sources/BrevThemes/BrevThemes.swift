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

import Foundation

/// `BrevThemes` namespace marker — see ADR-0002.
///
/// The real surface lives in `BrevTheme`, `BrevColor`, the
/// `\.brevTheme` environment value, and the built-in palette set in
/// `BuiltIns.swift`.
public enum BrevThemes {
    /// Convenience: the bundled themes in display order.
    public static let builtIns: [BrevTheme] = BrevTheme.brevBuiltIns
}
