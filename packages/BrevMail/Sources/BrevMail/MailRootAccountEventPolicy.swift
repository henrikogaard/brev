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

enum MailRootAccountEventPolicy {
    struct MailboxEventEffects: Equatable, Sendable {
        let refreshVisibleContent: Bool
        let refreshBackgroundAccountState: Bool
        let postNewMailNotification: Bool
    }

    enum Action: Equatable, Sendable {
        case ignore
        case signOut
    }

    static func mailboxEventEffects(
        for event: MailEvent,
        eventAccountID: BrevAccount.ID,
        selectedAccountID: BrevAccount.ID
    ) -> MailboxEventEffects {
        switch event {
        case .folderRefreshed,
             .messagesAdded,
             .messagesRemoved,
             .messagesUpdated:
            let isSelectedAccount = eventAccountID == selectedAccountID
            let postNewMailNotification: Bool
            if case .messagesAdded = event {
                postNewMailNotification = true
            } else {
                postNewMailNotification = false
            }
            return MailboxEventEffects(
                refreshVisibleContent: isSelectedAccount,
                refreshBackgroundAccountState: !isSelectedAccount,
                postNewMailNotification: postNewMailNotification
            )
        case .accountConnected,
             .accountDisconnected,
             .mailboxChanged,
             .outboxChanged,
             .syncProgress:
            return MailboxEventEffects(
                refreshVisibleContent: false,
                refreshBackgroundAccountState: false,
                postNewMailNotification: false
            )
        }
    }

    static func action(
        for event: MailEvent,
        currentAccountID: BrevAccount.ID,
        hasSignOutHandler: Bool
    ) -> Action {
        guard hasSignOutHandler else { return .ignore }

        switch event {
        case .accountDisconnected(let accountID) where accountID == currentAccountID:
            return .signOut
        case .accountConnected,
             .accountDisconnected,
             .folderRefreshed,
             .messagesAdded,
             .messagesRemoved,
             .messagesUpdated,
             .mailboxChanged,
             .outboxChanged,
             .syncProgress:
            return .ignore
        }
    }
}
