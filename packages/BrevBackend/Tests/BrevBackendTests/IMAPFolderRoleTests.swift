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
import Foundation
import Testing

@Suite("IMAP folder role detection")
struct IMAPFolderRoleTests {
    @Test("the RFC 6154 special-use attribute wins regardless of folder name")
    func specialUseWins() {
        #expect(IMAPFolderListing.role(for: "Weird Name", flags: ["sent"]) == .sent)
        #expect(IMAPFolderListing.role(for: "X", flags: ["junk"]) == .spam)
        #expect(IMAPFolderListing.role(for: "X", flags: ["drafts"]) == .drafts)
    }

    @Test("provider Sent names are detected without special-use (#194)")
    func sentNamesDetected() {
        // Gmail: [Gmail]/Sent Mail  ·  Outlook: Sent Items  ·  iCloud: Sent Messages
        #expect(IMAPFolderListing.role(for: "[Gmail]/Sent Mail", flags: []) == .sent)
        #expect(IMAPFolderListing.role(for: "Sent Items", flags: []) == .sent)
        #expect(IMAPFolderListing.role(for: "Sent Messages", flags: []) == .sent)
        #expect(IMAPFolderListing.role(for: "Sent", flags: []) == .sent)
    }

    @Test("localized Gmail system folder names are detected without special-use (#282)")
    func localizedGmailSystemFolderNamesDetected() {
        // Norwegian Gmail UI localizes the [Gmail]/* leaf names while special-use
        // flags remain the primary signal. Keep name fallbacks so Sent/Drafts
        // still map when a provider omits \Sent/\Drafts.
        #expect(IMAPFolderListing.role(for: "[Gmail]/Sendt e-post", flags: []) == .sent)
        #expect(IMAPFolderListing.role(for: "[Gmail]/Utkast", flags: []) == .drafts)
    }

    @Test("provider names for other roles are detected")
    func otherRolesDetected() {
        #expect(IMAPFolderListing.role(for: "Deleted Items", flags: []) == .trash)
        #expect(IMAPFolderListing.role(for: "Junk E-mail", flags: []) == .spam)
        #expect(IMAPFolderListing.role(for: "Drafts", flags: []) == .drafts)
        #expect(IMAPFolderListing.role(for: "Archive", flags: []) == .archive)
        #expect(IMAPFolderListing.role(for: "INBOX", flags: []) == .inbox)
    }

    @Test("Gmail special-use folders map to existing semantic roles")
    func gmailSpecialUseRolesDetected() {
        #expect(IMAPFolderListing.role(for: "[Gmail]/All Mail", flags: ["all"]) == .allMail)
        #expect(IMAPFolderListing.role(for: "[Gmail]/Starred", flags: ["starred"]) == .starred)
    }

    @Test("Gmail All Mail name is detected when LIST omits special-use flags")
    func gmailAllMailNameDetected() {
        #expect(IMAPFolderListing.role(for: "[Gmail]/All Mail", flags: []) == .allMail)
    }

    @Test("Gmail Important remains custom because no dedicated folder role exists")
    func gmailImportantRemainsCustom() {
        #expect(IMAPFolderListing.role(for: "[Gmail]/Important", flags: ["important"]) == .custom)
    }

    @Test("an ordinary folder stays custom")
    func customFolder() {
        #expect(IMAPFolderListing.role(for: "Receipts", flags: []) == .custom)
        #expect(IMAPFolderListing.role(for: "Work/Clients", flags: []) == .custom)
    }
}
