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

import Network
import SwiftUI

/// Observes the system network path and reports whether Brev is
/// likely able to reach its mail backends.
///
/// Started from the app scene root and injected into the environment
/// so every view can react to reachability changes without importing
/// `Network` directly.
@Observable
@MainActor
public final class NetworkReachabilityMonitor {
    public private(set) var isOnline = true
    public private(set) var connectionType = "unknown"

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    public nonisolated init() {
        monitor = NWPathMonitor()
        queue = DispatchQueue(label: "brev.network-reachability", qos: .utility)
    }

    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { @MainActor in
                self.isOnline = path.status == .satisfied
                self.connectionType = self.describe(path)
            }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }

    private func describe(_ path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) {
            return "wifi"
        } else if path.usesInterfaceType(.cellular) {
            return "cellular"
        } else if path.usesInterfaceType(.wiredEthernet) {
            return "wired"
        }
        return "unknown"
    }
}

private struct NetworkReachabilityMonitorKey: EnvironmentKey {
    static let defaultValue = NetworkReachabilityMonitor()
}

public extension EnvironmentValues {
    var networkMonitor: NetworkReachabilityMonitor {
        get { self[NetworkReachabilityMonitorKey.self] }
        set { self[NetworkReachabilityMonitorKey.self] = newValue }
    }
}

public extension View {
    func networkMonitor(_ monitor: NetworkReachabilityMonitor) -> some View {
        environment(\.networkMonitor, monitor)
    }
}
