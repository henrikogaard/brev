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

@testable import BrevSettings
import Testing

@Suite("AboutSectionPresentation")
struct AboutSectionPresentationTests {
    @Test("About metadata credits the author and Brev repository")
    func aboutMetadataCreditsAuthorAndRepository() {
        let rows = AboutSectionPresentation.infoRows(version: "1.2.3 (45)")

        #expect(rows == [
            AboutSectionInfoRow(label: "Version", value: "1.2.3 (45)"),
            AboutSectionInfoRow(label: "License", value: "MIT"),
            AboutSectionInfoRow(label: "Author", value: "Henrik Øgård")
        ])
        #expect(AboutSectionPresentation.authorName == "Henrik Øgård")
        #expect(AboutSectionPresentation.repositoryDisplayName == "henrikogaard/brev")
        #expect(AboutSectionPresentation.repositoryURL.absoluteString == "https://github.com/henrikogaard/brev")
    }
}
