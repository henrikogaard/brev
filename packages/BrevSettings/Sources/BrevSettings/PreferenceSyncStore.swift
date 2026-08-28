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
import OSLog

/// Cross-device mirror for a small allowlist of local preferences (ADR-0056).
///
/// The seam that lets a future self-hosted sync backend replace iCloud
/// Key-Value Storage without touching callers. Implementations mirror
/// `PreferenceSyncAllowlist.keys` between `UserDefaults` and a remote
/// store; they never see mail content or credentials.
public protocol PreferenceSyncStore: AnyObject {
    /// `true` while the store is observing and mirroring changes.
    var isActive: Bool { get }
    /// Reconcile once with the remote store and begin observing both
    /// local and remote changes. Idempotent.
    func start()
    /// Stop observing. Remote copies are left in place.
    func stop()
}

/// The default store: nothing leaves the device.
public final class LocalOnlyPreferenceSyncStore: PreferenceSyncStore {
    public private(set) var isActive = false

    public init() {}

    public func start() {}

    public func stop() {}
}

/// Minimal surface of a remote key-value store.
///
/// `NSUbiquitousKeyValueStore` satisfies it as-is; tests provide an
/// in-memory fake. External changes are announced by posting
/// `NSUbiquitousKeyValueStore.didChangeExternallyNotification` with the
/// transport as the notification object.
public protocol PreferenceSyncTransport: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    var dictionaryRepresentation: [String: Any] { get }
    @discardableResult
    func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: PreferenceSyncTransport {}

/// Notification surface for consumers that keep synced state in memory.
public enum PreferenceSync {
    /// Posted after remote values were written into `UserDefaults`.
    /// `userInfo[changedKeysUserInfoKey]` is the `[String]` of local keys.
    public static let didApplyRemoteChangesNotification = Notification.Name(
        "eu.brevmail.brev.preferenceSync.didApplyRemoteChanges"
    )
    public static let changedKeysUserInfoKey = "changedKeys"
}

/// Mirrors allowlisted `UserDefaults` keys through iCloud Key-Value Storage.
///
/// Conflict policy is last-writer-wins as provided by KVS (ADR-0056):
/// local changes are pushed as whole values, remote changes overwrite
/// local values, and remote *absence* never deletes local state.
public final class ICloudKeyValuePreferenceSyncStore: PreferenceSyncStore, @unchecked Sendable {
    /// KVS key prefix; the `v1` segment isolates future format changes.
    public static let keyPrefix = "brev.prefs.v1."
    /// KVS allows 1 MB in total; refuse single values near that ceiling.
    static let maximumValueSize = 900_000

    private static let logger = Logger(subsystem: "eu.brevmail.brev", category: "PreferenceSync")

    private let defaults: UserDefaults
    private let transport: PreferenceSyncTransport
    private let allowlist: [String]
    private let notificationCenter: NotificationCenter
    private let debounceInterval: TimeInterval
    /// Deferred local reconciliations run on a private serial executor. This
    /// is the actor-like boundary for Foundation notifications, which may be
    /// delivered on any thread and do not include changed-key information.
    private let reconciliationQueue: DispatchQueue

    private let lock = NSRecursiveLock()
    private var lastPushed: [String: Any] = [:]
    private var isApplyingRemote = false
    private var observers: [NSObjectProtocol] = []
    private var active = false
    private var pendingLocalChange: DispatchWorkItem?
    private var localChangeGeneration = 0

    public var isActive: Bool {
        lock.withLock { active }
    }

    /// - Parameters:
    ///   - defaults: the local store to mirror.
    ///   - transport: the remote store; `NSUbiquitousKeyValueStore.default` in the apps.
    ///   - allowlist: local keys to mirror; defaults to `PreferenceSyncAllowlist.keys`.
    ///   - notificationCenter: where change notifications are observed and posted.
    ///   - debounceInterval: delay used to coalesce a burst of local defaults notifications.
    ///     The production default avoids a full allowlist scan for every individual write.
    public init(
        defaults: UserDefaults = .standard,
        transport: PreferenceSyncTransport = NSUbiquitousKeyValueStore.default,
        allowlist: [String] = PreferenceSyncAllowlist.keys,
        notificationCenter: NotificationCenter = .default,
        debounceInterval: TimeInterval = 0.05
    ) {
        self.defaults = defaults
        self.transport = transport
        self.allowlist = allowlist
        self.notificationCenter = notificationCenter
        self.debounceInterval = max(0, debounceInterval)
        reconciliationQueue = DispatchQueue(
            label: "eu.brevmail.brev.preference-sync-reconciliation",
            qos: .utility
        )
    }

    deinit {
        stop()
    }

    public func start() {
        lock.withLock {
            guard !active else { return }
            active = true
            reconcileOnStart()
            observers = [
                notificationCenter.addObserver(
                    forName: UserDefaults.didChangeNotification,
                    object: defaults,
                    queue: nil
                ) { [weak self] _ in
                    self?.enqueueLocalChange()
                },
                notificationCenter.addObserver(
                    forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                    object: transport,
                    queue: nil
                ) { [weak self] note in
                    self?.handleExternalChange(note)
                }
            ]
        }
    }

    public func stop() {
        lock.withLock {
            guard active else { return }
            active = false
            pendingLocalChange?.cancel()
            pendingLocalChange = nil
            localChangeGeneration &+= 1
            observers.forEach(notificationCenter.removeObserver)
            observers.removeAll()
            lastPushed.removeAll()
        }
    }

    /// Delete every Brev-namespaced value from the remote store.
    ///
    /// Not wired to UI in phase 1; kept for a future "Remove from iCloud"
    /// action so users can withdraw data without turning off iCloud.
    public func removeAllRemoteValues() {
        lock.withLock {
            for key in transport.dictionaryRepresentation.keys where key.hasPrefix(Self.keyPrefix) {
                transport.removeObject(forKey: key)
            }
            transport.synchronize()
        }
    }

    // MARK: - Reconciliation

    /// Coalesce local `UserDefaults` notifications before scanning the
    /// allowlist. Foundation gives us no changed-key set, so the deferred
    /// pass remains a full scan, but a burst of writes pays for one pass.
    private func enqueueLocalChange() {
        if debounceInterval == 0 {
            handleLocalChange()
            return
        }

        lock.withLock {
            guard active, !isApplyingRemote else { return }
            pendingLocalChange?.cancel()
            localChangeGeneration &+= 1
            let generation = localChangeGeneration
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                // Keep the deferred path on its serial executor. The lock
                // below still protects callers that inject a zero debounce
                // interval in synchronous tests.
                dispatchPrecondition(condition: .onQueue(reconciliationQueue))
                lock.withLock {
                    guard self.active,
                          !self.isApplyingRemote,
                          self.localChangeGeneration == generation
                    else {
                        if self.localChangeGeneration == generation {
                            self.pendingLocalChange = nil
                        }
                        return
                    }
                    self.pendingLocalChange = nil
                }
                handleLocalChange()
            }
            pendingLocalChange = work
            reconciliationQueue.asyncAfter(
                deadline: .now() + debounceInterval,
                execute: work
            )
        }
    }

    /// First-enable policy: cloud values win where the cloud has them;
    /// keys only this device has are pushed.
    private func reconcileOnStart() {
        transport.synchronize()
        var appliedKeys: [String] = []
        var pushed = false
        isApplyingRemote = true
        for key in allowlist {
            let remote = transport.object(forKey: Self.keyPrefix + key)
            let local = defaults.object(forKey: key)
            if let remote {
                if !Self.isEqual(remote, local) {
                    defaults.set(remote, forKey: key)
                    appliedKeys.append(key)
                }
                lastPushed[key] = remote
            } else if let local {
                if push(local, forKey: key) {
                    pushed = true
                }
                lastPushed[key] = local
            }
        }
        isApplyingRemote = false
        if pushed {
            transport.synchronize()
        }
        postApplied(appliedKeys)
    }

    private func handleLocalChange() {
        lock.withLock {
            guard active, !isApplyingRemote else { return }
            var pushed = false
            for key in allowlist {
                let local = defaults.object(forKey: key)
                guard !Self.isEqual(local, lastPushed[key]) else { continue }
                if let local {
                    if push(local, forKey: key) {
                        pushed = true
                    }
                    lastPushed[key] = local
                } else {
                    // A removed local value is withdrawn from the cloud but,
                    // by policy, never propagates as a deletion elsewhere.
                    transport.removeObject(forKey: Self.keyPrefix + key)
                    lastPushed.removeValue(forKey: key)
                    pushed = true
                }
            }
            if pushed {
                transport.synchronize()
            }
        }
    }

    private func handleExternalChange(_ note: Notification) {
        lock.withLock {
            guard active else { return }
            if let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
               reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
                Self.logger.error("iCloud key-value quota exceeded; preference sync paused until values shrink")
            }
            let changedRemoteKeys = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String])
                ?? allowlist.map { Self.keyPrefix + $0 }
            var appliedKeys: [String] = []
            isApplyingRemote = true
            for remoteKey in changedRemoteKeys where remoteKey.hasPrefix(Self.keyPrefix) {
                let key = String(remoteKey.dropFirst(Self.keyPrefix.count))
                guard allowlist.contains(key) else { continue }
                // Remote absence never deletes local state (ADR-0056).
                guard let remote = transport.object(forKey: remoteKey) else { continue }
                lastPushed[key] = remote
                guard !Self.isEqual(remote, defaults.object(forKey: key)) else { continue }
                defaults.set(remote, forKey: key)
                appliedKeys.append(key)
            }
            isApplyingRemote = false
            postApplied(appliedKeys)
        }
    }

    /// Returns `true` when the value was written to the transport.
    private func push(_ value: Any, forKey key: String) -> Bool {
        guard Self.serializedSize(of: value) <= Self.maximumValueSize else {
            Self.logger.error("Skipping preference sync for \(key, privacy: .public): value exceeds the size guard")
            return false
        }
        transport.set(value, forKey: Self.keyPrefix + key)
        return true
    }

    private func postApplied(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        notificationCenter.post(
            name: PreferenceSync.didApplyRemoteChangesNotification,
            object: self,
            userInfo: [PreferenceSync.changedKeysUserInfoKey: keys]
        )
    }

    private static func serializedSize(of value: Any) -> Int {
        if let data = value as? Data { return data.count }
        if let string = value as? String { return string.utf8.count }
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: value,
            format: .binary,
            options: 0
        ) else {
            return Int.max
        }
        return data.count
    }

    /// Property-list values bridge to Foundation classes with value equality.
    private static func isEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (let lhs?, let rhs?):
            return (lhs as AnyObject).isEqual(rhs)
        default:
            return false
        }
    }
}

/// Owns the active `PreferenceSyncStore` and follows the opt-in toggle.
///
/// Apps call `activate()` once at launch. The controller watches
/// `UserDefaults` for the `PreferenceSyncSettings` toggle and swaps
/// between the local-only store and the iCloud store accordingly.
public final class PreferenceSyncController: @unchecked Sendable {
    /// Process-wide controller bound to `UserDefaults.standard` and iCloud KVS.
    public static let standard = PreferenceSyncController(defaults: .standard) {
        ICloudKeyValuePreferenceSyncStore()
    }

    private let defaults: UserDefaults
    private let makeICloudStore: () -> PreferenceSyncStore
    private let notificationCenter: NotificationCenter
    private let lock = NSRecursiveLock()
    private var observer: NSObjectProtocol?
    private var store: PreferenceSyncStore = LocalOnlyPreferenceSyncStore()

    /// The store currently in charge; local-only unless the toggle is on.
    public var activeStore: PreferenceSyncStore {
        lock.withLock { store }
    }

    /// - Parameters:
    ///   - defaults: where the opt-in toggle lives.
    ///   - notificationCenter: where toggle changes are observed.
    ///   - makeICloudStore: builds the iCloud-backed store on first opt-in.
    public init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        makeICloudStore: @escaping () -> PreferenceSyncStore
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.makeICloudStore = makeICloudStore
    }

    /// Apply the current toggle and follow later changes. Idempotent.
    public func activate() {
        lock.withLock {
            guard observer == nil else { return }
            observer = notificationCenter.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: defaults,
                queue: nil
            ) { [weak self] _ in
                self?.reconcile()
            }
            reconcile()
        }
    }

    private func reconcile() {
        lock.withLock {
            let wantsICloud = PreferenceSyncSettings.load(from: defaults).isICloudSyncEnabled
            let hasICloud = !(store is LocalOnlyPreferenceSyncStore)
            guard wantsICloud != hasICloud else { return }
            store.stop()
            if wantsICloud {
                store = makeICloudStore()
                store.start()
            } else {
                store = LocalOnlyPreferenceSyncStore()
            }
        }
    }
}
