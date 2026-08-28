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

public enum ComposeCompletion: Sendable, Hashable {
    case savedDraft(Draft)
    case sentMessage(draft: Draft, result: SendResult, relatedHeader: MessageHeader?)
}

public enum ComposeCompletionRefreshPolicy {
    public static func events(
        for completion: ComposeCompletion,
        folders: [Folder]
    ) -> [MailEvent] {
        switch completion {
        case .savedDraft:
            return folderEvents(for: [.drafts], folders: folders)
        case .sentMessage(_, _, let relatedHeader):
            var events = folderEvents(for: [.drafts, .sent], folders: folders)
            if let relatedHeader {
                events.append(MessageCommandRefreshPolicy.updated(relatedHeader))
            }
            return events
        }
    }

    private static func folderEvents(for roles: [FolderRole], folders: [Folder]) -> [MailEvent] {
        roles.compactMap { role in
            folders.first { $0.role == role }
                .map { .folderRefreshed(folderID: $0.id) }
        }
    }
}
