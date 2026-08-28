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

@Suite("MailExportFilename")
struct MailExportFilenameTests {
    @Test("sanitize maps path separators and reserved characters to underscore")
    func sanitizeRemovesPathSeparators() {
        #expect(MailExportFilename.sanitize("../../etc/passwd") == ".._.._etc_passwd")
        #expect(MailExportFilename.sanitize(#"a:b/c\d?e%f*g|h"i<j>k"#) == "a_b_c_d_e_f_g_h_i_j_k")
        #expect(!MailExportFilename.sanitize("re: hi/there").contains("/"))
    }

    @Test("unique de-duplicates same-subject filenames instead of overwriting")
    func uniqueDeduplicatesCollidingNames() {
        var used: Set<String> = []
        #expect(MailExportFilename.unique("Invoice", ext: "eml", used: &used) == "Invoice.eml")
        #expect(MailExportFilename.unique("Invoice", ext: "eml", used: &used) == "Invoice (2).eml")
        #expect(MailExportFilename.unique("Invoice", ext: "eml", used: &used) == "Invoice (3).eml")
        // Collision check is case-insensitive (case-folding filesystems).
        #expect(MailExportFilename.unique("invoice", ext: "eml", used: &used) == "invoice (4).eml")
    }

    @Test("unique falls back to a safe stem for empty or dot-only names")
    func uniqueHandlesEmptyAndDotNames() {
        var used: Set<String> = []
        #expect(MailExportFilename.unique("   ", ext: "eml", used: &used) == "message.eml")
        #expect(MailExportFilename.unique("..", ext: "eml", used: &used) == "message (2).eml")
    }
}
