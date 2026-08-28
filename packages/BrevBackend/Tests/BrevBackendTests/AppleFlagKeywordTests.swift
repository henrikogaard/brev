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

@testable import BrevBackend
import Testing

@Suite("AppleFlagKeyword") struct AppleFlagKeywordTests {
    @Test("every color round-trips through keyword encoding")
    func roundTripsAllColors() {
        for color in FlagColor.allCases {
            let keywords = AppleFlagKeyword.keywords(for: color)
            #expect(AppleFlagKeyword.flagColor(from: keywords) == color)
        }
    }

    @Test("distinct colors produce distinct keyword sets")
    func distinctColorsDistinctKeywords() {
        let sets = FlagColor.allCases.map { AppleFlagKeyword.keywords(for: $0) }
        #expect(Set(sets).count == FlagColor.allCases.count)
    }

    @Test("bit math matches the Apple ordinal")
    func bitMathMatchesOrdinal() {
        // $MailFlagBit0=1, Bit1=2, Bit2=4; the set bits must sum to the ordinal.
        for color in FlagColor.allCases {
            let ordinal = AppleFlagKeyword.appleOrdinal(for: color)
            let keywords = AppleFlagKeyword.keywords(for: color)
            var sum = 0
            for (bit, keyword) in AppleFlagKeyword.bitKeywords.enumerated() where keywords.contains(keyword) {
                sum |= (1 << bit)
            }
            #expect(sum == ordinal)
        }
    }

    @Test("no flag bits decodes to nil")
    func noBitsIsNil() {
        #expect(AppleFlagKeyword.flagColor(from: ["$Forwarded", "\\Seen"]) == nil)
        #expect(AppleFlagKeyword.flagColor(from: [String]()) == nil)
    }
}
