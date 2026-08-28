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
import Foundation

struct MessageListUnsubscribeActionPresentation: Equatable {
    let title: String
    let method: ListUnsubscribeMethod
    let confirmationTitle: String
    let confirmationMessage: String
    let confirmButtonTitle: String
}

struct MessageListUnsubscribePresentation: Equatable {
    let title: String
    let subtitle: String
    let warning: String?
    let requiresExplicitConfirmation: Bool
    let actions: [MessageListUnsubscribeActionPresentation]

    static func resolve(options: ListUnsubscribeOptions?) -> MessageListUnsubscribePresentation? {
        guard let options, !options.methods.isEmpty else { return nil }
        return MessageListUnsubscribePresentation(
            title: "Unsubscribe available",
            subtitle: "This message includes standard List-Unsubscribe headers.",
            warning: "No unsubscribe request is sent until you choose one of these actions.",
            requiresExplicitConfirmation: options.requiresExplicitConfirmation,
            actions: options.methods.map { method in
                MessageListUnsubscribeActionPresentation(
                    title: title(for: method),
                    method: method,
                    confirmationTitle: confirmationTitle(for: method),
                    confirmationMessage: confirmationMessage(for: method),
                    confirmButtonTitle: confirmButtonTitle(for: method)
                )
            }
        )
    }

    private static func title(for method: ListUnsubscribeMethod) -> String {
        switch method {
        case .https:
            return "Open unsubscribe page"
        case .mailto:
            return "Draft unsubscribe email"
        }
    }

    private static func confirmationTitle(for method: ListUnsubscribeMethod) -> String {
        switch method {
        case .https:
            return "Open unsubscribe page?"
        case .mailto:
            return "Draft unsubscribe email?"
        }
    }

    private static func confirmationMessage(for method: ListUnsubscribeMethod) -> String {
        switch method {
        case .https(_, let supportsOneClick):
            if supportsOneClick {
                return "This message advertises one-click unsubscribe. Opening the page may send an unsubscribe request to the list provider."
            }
            return "Brev will open the unsubscribe page in your browser. The site may learn your IP address and request time."
        case .mailto:
            return "Brev will open a draft addressed to the list provider. Review the message before sending."
        }
    }

    private static func confirmButtonTitle(for method: ListUnsubscribeMethod) -> String {
        switch method {
        case .https:
            return "Open Page"
        case .mailto:
            return "Draft Email"
        }
    }
}
