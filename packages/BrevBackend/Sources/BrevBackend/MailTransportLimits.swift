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

/// Memory bounds shared by the line-based mail transports (IMAP, SMTP,
/// ManageSieve).
enum MailTransportLimits {
    /// Upper bound on a single CRLF-delimited protocol line. Bulk payloads
    /// arrive as length-prefixed literals (capped separately), so any real
    /// IMAP/SMTP/ManageSieve line is far smaller than this; the limit only
    /// stops a server that never sends a line terminator from growing the read
    /// buffer without bound (OOM).
    static let maxLineByteCount = 8 * 1024 * 1024

    /// Maximum number of continuation lines accepted in one SMTP reply.
    ///
    /// EHLO capability replies are normally only a handful of lines. This
    /// leaves generous room for provider extensions while preventing a
    /// malicious server from making the client retain an unbounded reply.
    static let maxSMTPReplyLineCount = 128

    /// Maximum UTF-8 bytes retained while collecting one SMTP reply.
    static let maxSMTPReplyByteCount = 64 * 1024
}
