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

/// Whether avatar resolution may access the system Contacts database.
///
/// See ADR-0055. Demo mode turns this off: its senders are invented, so a
/// Contacts match is impossible, so demo mode turns off both permission requests
/// and reads that would otherwise use access granted during an earlier run.
///
/// Deliberately a plain static rather than actor state. `AvatarResolver.shared`
/// is a lazily created singleton that starts from `AvatarPreferences.default`,
/// and preferences reach it asynchronously; anything that has to be *applied*
/// races the first screenful of avatar resolutions. Reading this cannot suspend
/// and cannot be reordered, so the gate holds however those tasks interleave.
public enum AvatarPermissionPolicy {
    /// Set at app launch, then disabled synchronously if the user enters the
    /// demo mailbox from the normal sign-in screen.
    public nonisolated(unsafe) static var allowsSystemContactsAccess = true
}
