/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included
 in all copies or substantial portions of the Software.
 */

import BrevBackend

/// Resolves the mailbox scope Settings displays so scoped controls (Folder
/// Sync and friends) match Mail's effective selection. The bug it guards
/// against: with the mailbox list visible, Mail's selected source is nil
/// even though the window still shows a default section, so Settings
/// received an empty scope ("Choose mailbox" with no folders) instead of the
/// mailbox Mail was effectively showing.
enum MailRootSettingsScopePolicy {
    /// The source Settings should scope to: Mail's explicit selection when
    /// there is one, otherwise the default section Mail itself falls back to.
    static func effectiveSourceID(
        selectedSourceID: MailSourceID?,
        defaultSectionID: MailSourceID?
    ) -> MailSourceID? {
        selectedSourceID ?? defaultSectionID
    }
}
