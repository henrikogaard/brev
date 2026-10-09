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
import Testing

@Suite("BrevHitTarget")
struct BrevHitTargetTests {
    @Test("a scaled value below the platform floor resolves to the floor")
    func smallScaledValueResolvesToFloor() {
        #expect(BrevHitTarget.resolved(scaled: 0) == BrevHitTarget.minimum)
    }

    @Test("a scaled value above the floor is kept so targets grow with Dynamic Type")
    func largeScaledValueIsKept() {
        #expect(BrevHitTarget.resolved(scaled: 90) == 90)
    }

    @Test("touch platforms keep the 44 pt floor")
    func touchFloor() {
        #if os(iOS)
        #expect(BrevHitTarget.minimum == 44)
        #else
        #expect(BrevHitTarget.minimum == 0)
        #endif
    }
}
