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

import BrevBackend

enum MessageListHeaderMutation {
    static func updating(
        _ headers: [MessageHeader],
        ids: Set<MessageHeader.ID>,
        mutate: (inout MessageHeader) -> Void
    ) -> [MessageHeader] {
        guard !ids.isEmpty else { return headers }
        var updated = headers
        for index in updated.indices where ids.contains(updated[index].id) {
            mutate(&updated[index])
        }
        return updated
    }

    static func removing(
        _ headers: [MessageHeader],
        ids: Set<MessageHeader.ID>
    ) -> [MessageHeader] {
        guard !ids.isEmpty else { return headers }
        return headers.filter { !ids.contains($0.id) }
    }
}
