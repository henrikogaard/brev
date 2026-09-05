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

public extension IMAPAccountConnector {
    typealias IMAPTransportFactory = @Sendable () -> any IMAPSessionTransport
    typealias SMTPTransportFactory = @Sendable () -> any SMTPSessionTransport
    typealias ManageSieveTransportFactory = @Sendable () -> any ManageSieveSessionTransport

    /// Creates a fully wired connector using real IMAP/SMTP transports and
    /// file-backed persistent caches by default. Pass `nil` to disable a cache
    /// or an explicit implementation to override.
    static func standard(
        accountStore: any AccountStore,
        configurationStore: any IMAPAccountConfigurationStore,
        credentialStore: any MailCredentialStore,
        folderCache: (any IMAPFolderSnapshotCache)? = FileBackedIMAPFolderSnapshotCache(),
        headerCache: (any IMAPMailboxHeaderCache)? = FileBackedIMAPMailboxHeaderCache(),
        sourceCache: (any IMAPMessageSourceCache)? = FileBackedIMAPMessageSourceCache(),
        bodyCache: (any IMAPMessageBodyCache)? = FileBackedIMAPMessageBodyCache(),
        localSearchIndex: IMAPAccountConnector.LocalSearchIndexFactory? = nil,
        draftStagingStore: (any IMAPDraftStagingStore)? = nil,
        offlineMutationQueue: (@Sendable (BrevAccount.ID) -> (any OfflineMutationQueue))? = nil,
        offlineMutationConflictStore: (@Sendable (BrevAccount.ID) -> (any OfflineMutationConflictStore))? = nil,
        tokenStore: (any TokenStore)? = nil,
        outboundMessagePreparer: (any OutboundMessagePreparing)? = nil,
        imapTransportFactory: @escaping IMAPTransportFactory = {
            NetworkIMAPSessionTransport()
        },
        smtpTransportFactory: @escaping SMTPTransportFactory = {
            NetworkSMTPSessionTransport()
        },
        manageSieveTransportFactory: @escaping ManageSieveTransportFactory = {
            NetworkManageSieveSessionTransport()
        }
    ) -> IMAPAccountConnector {
        let imapSessionPool = StandardIMAPSessionPool(
            transportFactory: imapTransportFactory
        )
        return IMAPAccountConnector(
            accountStore: accountStore,
            configurationStore: configurationStore,
            credentialStore: credentialStore,
            listFolders: { configuration, credential in
                let client = await imapSessionPool.client(for: configuration)
                // Counts feed the dock badge and sidebar folder badges;
                // without STATUS every real account reads as zero unread.
                return try await client.loginAndListFolders(
                    configuration: configuration,
                    credential: credential,
                    includingUnreadCounts: true
                )
            },
            validateOutgoingServer: { configuration, credential in
                let client = SMTPSessionClient(transport: smtpTransportFactory())
                try await client.loginAndValidateCredentials(
                    configuration: configuration,
                    credential: credential
                )
            },
            createFolder: { configuration, credential, folderID in
                let client = await imapSessionPool.client(for: configuration)
                try await client.loginAndCreateFolder(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID
                )
            },
            renameFolder: { configuration, credential, folderID, newFolderID in
                let client = await imapSessionPool.client(for: configuration)
                try await client.loginAndRenameFolder(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    newFolderPath: newFolderID
                )
            },
            deleteFolder: { configuration, credential, folderID in
                let client = await imapSessionPool.client(for: configuration)
                try await client.loginAndDeleteFolder(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID
                )
            },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                let client = await imapSessionPool.client(for: configuration)
                return try await client.loginAndListMessages(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            searchMessages: { configuration, credential, folderID, query, limit in
                let client = await imapSessionPool.client(for: configuration)
                return try await client.loginAndSearchMessages(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    query: query,
                    limit: limit
                )
            },
            searchMessagePage: { configuration, credential, folderID, query, pageToken, limit in
                let client = await imapSessionPool.client(for: configuration)
                return try await client.loginAndSearchMessagePage(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    query: query,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            fetchMessageSource: { configuration, credential, folderID, uid in
                let client = await imapSessionPool.client(for: configuration)
                return try await client.loginAndFetchMessageSource(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    uid: uid
                )
            },
            fetchMessageBody: { configuration, credential, folderID, uid in
                let client = await imapSessionPool.client(for: configuration)
                return try await client.loginAndFetchMessageBody(
                    configuration: configuration,
                    credential: credential,
                    messageID: "\(folderID):\(uid)",
                    folderPath: folderID,
                    uid: uid
                )
            },
            fetchMessagePart: { configuration, credential, folderID, uid, section, transferEncoding in
                let client = await imapSessionPool.client(for: configuration)
                return try await client.loginAndFetchMessagePart(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    uid: uid,
                    section: section,
                    transferEncoding: transferEncoding
                )
            },
            setMessageFlag: { configuration, credential, folderID, uids, flag, isEnabled in
                let client = await imapSessionPool.client(for: configuration)
                try await client.loginAndSetMessageFlag(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    uids: uids,
                    flag: flag,
                    isEnabled: isEnabled
                )
            },
            setMessageKeyword: { configuration, credential, folderID, uids, keyword, isEnabled in
                let client = await imapSessionPool.client(for: configuration)
                try await client.loginAndSetMessageKeyword(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    uids: uids,
                    keyword: keyword,
                    isEnabled: isEnabled
                )
            },
            setMessageLabels: { configuration, credential, folderID, uids, labels, isEnabled in
                let client = await imapSessionPool.client(for: configuration)
                try await client.loginAndSetMessageLabels(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    uids: uids,
                    labels: labels,
                    isEnabled: isEnabled
                )
            },
            moveMessages: { configuration, credential, sourceFolderID, uids, destinationFolderID in
                let client = await imapSessionPool.client(for: configuration)
                try await client.loginAndMoveMessages(
                    configuration: configuration,
                    credential: credential,
                    sourceFolderPath: sourceFolderID,
                    uids: uids,
                    destinationFolderPath: destinationFolderID
                )
            },
            moveMessagesWithResult: { configuration, credential, sourceFolderID, uids, destinationFolderID, generation in
                let client = await imapSessionPool.client(for: configuration)
                return try await client.loginAndMoveMessagesWithResult(
                    configuration: configuration, credential: credential, sourceFolderPath: sourceFolderID,
                    uids: uids, destinationFolderPath: destinationFolderID, expectedSourceUIDValidity: generation
                )
            },
            copyMessages: { configuration, credential, sourceFolderID, uids, destinationFolderID in
                let client = await imapSessionPool.client(for: configuration)
                try await client.loginAndCopyMessages(
                    configuration: configuration,
                    credential: credential,
                    sourceFolderPath: sourceFolderID,
                    uids: uids,
                    destinationFolderPath: destinationFolderID
                )
            },
            permanentlyDeleteMessages: { configuration, credential, folderID, uids in
                let client = await imapSessionPool.client(for: configuration)
                try await client.loginAndPermanentlyDeleteMessages(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    uids: uids
                )
            },
            sendMessage: { configuration, credential, submission in
                let client = SMTPSessionClient(transport: smtpTransportFactory())
                try await client.loginAndSubmitMessage(
                    configuration: configuration,
                    credential: credential,
                    submission: submission
                )
                return SendResult()
            },
            appendSentMessage: { configuration, credential, folderID, messageData, flags in
                let client = await imapSessionPool.client(for: configuration)
                let result = try await client.loginAndAppendMessage(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    messageData: messageData,
                    flags: flags
                )
                return result.uid
            },
            appendDraftMessage: { configuration, credential, folderID, messageData, flags in
                let client = await imapSessionPool.client(for: configuration)
                let result = try await client.loginAndAppendMessage(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    messageData: messageData,
                    flags: flags
                )
                guard let uid = result.uid else {
                    throw IMAPClientError.malformedResponse("APPEND missing APPENDUID")
                }
                return uid
            },
            idleEvents: { configuration, credential, folderID in
                // Dedicated idle lease (max one) so IDLE never steals the command
                // session and never opens unbounded fresh clients.
                let client = await imapSessionPool.idleClient(for: configuration)
                return await client.loginAndIdleEvents(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID
                )
            },
            condstoreSync: { configuration, credential, folderID, sinceModSeq in
                let client = await imapSessionPool.client(for: configuration)
                return try await client.loginAndCONDSTORESync(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    since: sinceModSeq
                )
            },
            manageSieveRuleSync: { configuration, credential, rules, scriptName in
                guard let server = configuration.manageSieve else {
                    throw MailBackendError.notSupported(.manageSieve)
                }
                let sync = ManageSieveRuleSync(
                    transportFactory: { manageSieveTransportFactory() }
                )
                return try await sync.sync(
                    rules: rules,
                    server: server,
                    username: credential.incomingUsername,
                    password: credential.secret,
                    scriptName: scriptName
                )
            },
            disconnectSession: { configuration in
                await imapSessionPool.disconnect(accountID: configuration.accountID)
            },
            folderCache: folderCache,
            headerCache: headerCache,
            sourceCache: sourceCache,
            bodyCache: bodyCache,
            localSearchIndex: localSearchIndex,
            draftStagingStore: draftStagingStore,
            offlineMutationQueue: offlineMutationQueue,
            offlineMutationConflictStore: offlineMutationConflictStore,
            tokenStore: tokenStore,
            outboundMessagePreparer: outboundMessagePreparer
        )
    }
}

/// Per-account IMAP connection budget.
///
/// Hard cap: one command session + one IDLE session. All command operations
/// share the command session; IDLE never opens a third connection.
private actor StandardIMAPSessionPool {
    private let transportFactory: IMAPAccountConnector.IMAPTransportFactory
    private var commandClientsByAccountID: [BrevAccount.ID: IMAPSessionClient] = [:]
    private var idleClientsByAccountID: [BrevAccount.ID: IMAPSessionClient] = [:]

    init(transportFactory: @escaping IMAPAccountConnector.IMAPTransportFactory) {
        self.transportFactory = transportFactory
    }

    func client(for configuration: IMAPAccountConfiguration) -> IMAPSessionClient {
        if let client = commandClientsByAccountID[configuration.accountID] {
            return client
        }
        let client = IMAPSessionClient(
            transport: transportFactory(),
            reusesAuthenticatedSession: true
        )
        commandClientsByAccountID[configuration.accountID] = client
        return client
    }

    func idleClient(for configuration: IMAPAccountConfiguration) -> IMAPSessionClient {
        if let client = idleClientsByAccountID[configuration.accountID] {
            return client
        }
        let client = IMAPSessionClient(
            transport: transportFactory(),
            reusesAuthenticatedSession: true
        )
        idleClientsByAccountID[configuration.accountID] = client
        return client
    }

    func disconnect(accountID: BrevAccount.ID) async {
        if let command = commandClientsByAccountID.removeValue(forKey: accountID) {
            await command.disconnect()
        }
        if let idle = idleClientsByAccountID.removeValue(forKey: accountID) {
            await idle.disconnect()
        }
    }
}
