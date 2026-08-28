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

import CryptoKit
import Foundation

#if canImport(Contacts)
import Contacts
#endif

protocol AvatarContactPhotoProviding: Sendable {
    func photoData(for email: String) async -> Data?
}

struct NoContactPhotoProvider: AvatarContactPhotoProviding {
    func photoData(for email: String) async -> Data? {
        nil
    }
}

#if canImport(Contacts)
final class SystemContactPhotoProvider: AvatarContactPhotoProviding, @unchecked Sendable {
    private let storeFactory: @Sendable () -> CNContactStore

    init(storeFactory: @escaping @Sendable () -> CNContactStore = { CNContactStore() }) {
        self.storeFactory = storeFactory
    }

    func photoData(for email: String) async -> Data? {
        guard AvatarPermissionPolicy.allowsSystemContactsAccess else { return nil }
        let store = storeFactory()
        guard await canReadContacts(store: store) else { return nil }

        let keys: [CNKeyDescriptor] = [
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]
        let predicate = CNContact.predicateForContacts(matchingEmailAddress: email)
        do {
            let contacts = try store.unifiedContacts(
                matching: predicate,
                keysToFetch: keys
            )
            return contacts.lazy.compactMap { contact in
                contact.imageData ?? contact.thumbnailImageData
            }.first
        } catch {
            return nil
        }
    }

    private func canReadContacts(store: CNContactStore) async -> Bool {
        guard AvatarPermissionPolicy.allowsSystemContactsAccess else { return false }
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return true
        case .notDetermined:
            // Passive avatar/recipient rendering must never trigger the
            // system permission prompt. An explicit user action can grant
            // Contacts in Settings; a later render will then observe
            // `.authorized` and use the local photo.
            return false
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
#else
typealias SystemContactPhotoProvider = NoContactPhotoProvider
#endif

/// Resolves sender avatars via the ADR-0003 cascade.
///
/// First light scope:
/// - In-memory cache keyed by lowercased email.
/// - `.contacts` reads local Contacts photos and never leaves the
///   device.
/// - `.bimi`, `.gravatar`, and `.favicon` are wired and gated behind
///   `AvatarPreferences` opt-in toggles.
/// - Negative results are cached so we don't hammer external avatar
///   providers with misses on every render pass.
public actor AvatarResolver {
    public static let shared = AvatarResolver()

    private struct CacheEntry: Sendable {
        let avatar: ResolvedAvatar
        let expiresAt: Date
        var lastAccessedAt: Date
    }

    /// Maximum raw byte count accepted for a BIMI SVG logo.
    ///
    /// Mirrors `bimiMaximumSVGByteCount` from `BIMIRecordResolver` so
    /// callers and tests can refer to it without importing the internal symbol.
    public static let maximumSVGByteCount = bimiMaximumSVGByteCount

    private var preferences: AvatarPreferences
    private var preferenceVersion = 0
    private var cache: [String: CacheEntry] = [:]
    private var inFlight: [String: Task<ResolvedAvatar, Never>] = [:]
    private let urlSession: URLSession
    private let contactPhotoProvider: any AvatarContactPhotoProviding
    private let bimiRecordResolver: any AvatarBIMIRecordResolving
    private let dmarcPolicyResolver: any AvatarDMARCPolicyResolving
    private let avatarCache: any AvatarCacheStoring
    // Concurrency limiter: caps the number of simultaneous avatar
    // resolutions (contacts lookups, network fetches) so a large
    // message list rendering 100+ unique senders doesn't thunder-herd
    // the CNContactStore or network on first render. Cached results
    // bypass the limiter entirely.
    private let maxConcurrentResolutions: Int
    private let maxInMemoryCacheEntries: Int
    private var activeResolutions = 0
    private var resolutionWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        preferences: AvatarPreferences = .default,
        urlSession: URLSession = .shared
    ) {
        self.preferences = preferences
        self.urlSession = urlSession
        maxConcurrentResolutions = 6
        maxInMemoryCacheEntries = 2048
        contactPhotoProvider = SystemContactPhotoProvider()
        bimiRecordResolver = SystemBIMIRecordResolver()
        dmarcPolicyResolver = SystemDMARCPolicyResolver()
        avatarCache = Self.defaultAvatarCache()
    }

    init(
        preferences: AvatarPreferences = .default,
        urlSession: URLSession = .shared,
        contactPhotoProvider: any AvatarContactPhotoProviding,
        bimiRecordResolver: any AvatarBIMIRecordResolving = SystemBIMIRecordResolver(),
        dmarcPolicyResolver: any AvatarDMARCPolicyResolving = SystemDMARCPolicyResolver(),
        avatarCache: any AvatarCacheStoring = NoAvatarCache(),
        maxConcurrentResolutions: Int = 6,
        maxInMemoryCacheEntries: Int = 2048
    ) {
        self.preferences = preferences
        self.urlSession = urlSession
        self.contactPhotoProvider = contactPhotoProvider
        self.bimiRecordResolver = bimiRecordResolver
        self.dmarcPolicyResolver = dmarcPolicyResolver
        self.avatarCache = avatarCache
        self.maxConcurrentResolutions = maxConcurrentResolutions
        self.maxInMemoryCacheEntries = max(1, maxInMemoryCacheEntries)
    }

    public func updatePreferences(_ preferences: AvatarPreferences) {
        guard preferences != self.preferences else { return }
        self.preferences = preferences
        invalidateCachedWork()
    }

    /// Resolve an avatar for `email`. Returns immediately from cache
    /// if present; otherwise walks the cascade and caches the result.
    public func resolve(email: String, displayName: String?) async -> ResolvedAvatar {
        let key = Self.normalize(email)
        let now = Date()
        if var entry = cache[key] {
            guard entry.expiresAt > now else {
                cache.removeValue(forKey: key)
                return await resolve(email: email, displayName: displayName)
            }
            entry.lastAccessedAt = now
            cache[key] = entry
            return entry.avatar
        }
        if let pending = inFlight[key] {
            return await pending.value
        }
        // Concurrency limiter: wait for a slot before starting new work.
        // Cached results and in-flight dedup bypass this, so the limit
        // only applies to unique emails doing actual cascade work.
        await acquireResolutionSlot()

        // Re-check after the acquire suspension point. Another caller may
        // have finished (or registered inFlight) while we waited for a slot.
        // Release before joining an in-flight task so we don't hold a slot
        // while only waiting on someone else's cascade.
        let resumedAt = Date()
        if var entry = cache[key] {
            if entry.expiresAt > resumedAt {
                entry.lastAccessedAt = resumedAt
                cache[key] = entry
                releaseResolutionSlot()
                return entry.avatar
            }
            cache.removeValue(forKey: key)
        }
        if let pending = inFlight[key] {
            releaseResolutionSlot()
            return await pending.value
        }

        defer { releaseResolutionSlot() }

        let prefs = preferences
        let version = preferenceVersion
        let taskURLSession = urlSession
        let taskContactPhotoProvider = contactPhotoProvider
        let taskBIMIRecordResolver = bimiRecordResolver
        let taskDMARCPolicyResolver = dmarcPolicyResolver
        let taskAvatarCache = avatarCache
        let task = Task<ResolvedAvatar, Never> {
            // 1. Contacts.
            if AvatarPermissionPolicy.allowsSystemContactsAccess,
               prefs.useContacts,
               let data = await taskContactPhotoProvider.photoData(for: key) {
                return ResolvedAvatar(email: key, source: .contacts, imageData: data)
            }
            // 2. Local SQLite cache.
            if let cachedAvatar = await taskAvatarCache.cachedAvatar(
                for: key,
                preferences: prefs,
                now: Date()
            ) {
                return cachedAvatar
            }
            // 3. BIMI.
            if prefs.useBIMI,
               let domain = Self.domain(from: key),
               let data = await Self.fetchBIMILogo(
                   domain: domain,
                   urlSession: taskURLSession,
                   recordResolver: taskBIMIRecordResolver,
                   dmarcPolicyResolver: taskDMARCPolicyResolver
               ) {
                return ResolvedAvatar(email: key, source: .bimi, imageData: data)
            }
            // 4. Gravatar.
            if prefs.useGravatar,
               let data = await Self.fetchGravatar(
                   email: key,
                   urlSession: taskURLSession
               ) {
                return ResolvedAvatar(email: key, source: .gravatar, imageData: data)
            }
            // 5. Favicon.
            if prefs.useFavicon,
               let domain = Self.domain(from: key),
               let data = await Self.fetchFavicon(
                   domain: domain,
                   urlSession: taskURLSession
               ) {
                return ResolvedAvatar(email: key, source: .favicon, imageData: data)
            }
            // 6. Initials. Always available.
            return ResolvedAvatar(email: key, source: .initials, imageData: nil)
        }
        inFlight[key] = task
        let avatar = await task.value
        if preferenceVersion == version {
            inFlight[key] = nil
            let ttl = Self.cacheTTL(for: avatar.source)
            let expiresAt = Date().addingTimeInterval(ttl)
            let cachedAt = Date()
            if cache.count >= maxInMemoryCacheEntries {
                evictExpiredEntries(now: cachedAt)
                evictLeastRecentlyUsedEntry()
            }
            cache[key] = CacheEntry(
                avatar: avatar,
                expiresAt: expiresAt,
                lastAccessedAt: cachedAt
            )
            await avatarCache.store(
                avatar,
                preferences: prefs,
                expiresAt: expiresAt,
                now: Date()
            )
        }
        return avatar
    }

    /// Acquires a concurrency slot, suspending if the limit is reached.
    /// The slot is transferred from a releaser to a resumed waiter — no
    /// counter change on resume.
    private func acquireResolutionSlot() async {
        if activeResolutions < maxConcurrentResolutions {
            activeResolutions += 1
            return
        }
        await withCheckedContinuation { continuation in
            resolutionWaiters.append(continuation)
        }
    }

    /// Releases a concurrency slot, resuming the next waiter if one is
    /// queued (slot transfers, no counter change). Otherwise decrements
    /// the active count.
    private func releaseResolutionSlot() {
        if let next = resolutionWaiters.first {
            resolutionWaiters.removeFirst()
            next.resume()
        } else {
            activeResolutions -= 1
        }
    }

    /// Drop the cache without changing preferences.
    public func clearCache() async {
        await avatarCache.clear()
        invalidateCachedWork()
    }

    private func invalidateCachedWork() {
        preferenceVersion += 1
        // Cached initials from a stricter policy must not mask newly
        // enabled sources, and in-flight work may have captured stale
        // cache/preference state.
        cache.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }

    private func evictExpiredEntries(now: Date) {
        cache = cache.filter { $0.value.expiresAt > now }
    }

    private func evictLeastRecentlyUsedEntry() {
        guard let key = cache.min(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })?.key else {
            return
        }
        cache.removeValue(forKey: key)
    }

    // MARK: - Sources

    /// Fetch a Gravatar PNG by SHA-256 (the post-2022 hash) of the
    /// lowercased email. `d=404` forces a 404 when the address has no
    /// avatar registered, letting us fall through to initials.
    private static func fetchGravatar(
        email: String,
        urlSession: URLSession
    ) async -> Data? {
        let hash = SHA256.hash(data: Data(email.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        guard let url = URL(
            string: "https://gravatar.com/avatar/\(hash)?d=404&s=128"
        ) else { return nil }
        do {
            let (data, response) = try await urlSession.data(
                for: URLRequest(url: url),
                delegate: AvatarRedirectGuard(maxBytes: 512 * 1024)
            )
            guard let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode),
                  !data.isEmpty
            else { return nil }
            return data
        } catch {
            return nil
        }
    }

    /// Resolve BIMI by querying the sender-domain TXT record for a
    /// HTTPS SVG logo URL, then fetching the logo only after opt-in.
    ///
    /// Guards applied in order:
    /// 1. The BIMI record must resolve to a valid HTTPS URL.
    /// 2. The sender domain must publish a DMARC policy of `quarantine`
    ///    or `reject` (RFC 9091 §4).
    /// 3. The SVG URL must be on the same eTLD+1 as the sender domain.
    /// 4. The fetched SVG must pass content validation including the 32 KB cap.
    private static func fetchBIMILogo(
        domain: String,
        urlSession: URLSession,
        recordResolver: any AvatarBIMIRecordResolving,
        dmarcPolicyResolver: any AvatarDMARCPolicyResolving
    ) async -> Data? {
        guard let logoURL = await recordResolver.logoURL(for: domain),
              isPermittedBIMILogoURL(logoURL) else {
            return nil
        }

        // DMARC policy gate — domains without quarantine/reject policy must not
        // display a brand logo because SPF/DKIM alone cannot prevent spoofing.
        let dmarcPolicy = await dmarcPolicyResolver.policy(for: domain)
        guard dmarcPolicy.isBIMIPermitted else {
            return nil
        }

        // Origin-domain cross-check — the SVG URL must be on the sender's
        // eTLD+1 or a subdomain of it, to prevent a third-party domain from
        // injecting a logo for an unrelated brand.
        guard isBIMILogoURLOnSenderDomain(logoURL, senderDomain: domain) else {
            return nil
        }

        do {
            var request = URLRequest(url: logoURL)
            request.timeoutInterval = 10
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("image/svg+xml,image/*;q=0.8", forHTTPHeaderField: "Accept")

            let (data, response) = try await urlSession.data(
                for: request,
                delegate: AvatarRedirectGuard(maxBytes: maximumSVGByteCount)
            )
            guard let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode),
                  isSupportedBIMILogo(data: data, contentType: http.value(forHTTPHeaderField: "Content-Type"))
            else { return nil }
            return data
        } catch {
            return nil
        }
    }

    /// Returns whether `logoURL`'s host is on the same eTLD+1 as `senderDomain`.
    ///
    /// Uses a best-effort two-label comparison (`domain.tld`). This is not a
    /// full Public Suffix List lookup — exotic ccTLD second-level domains (e.g.
    /// `co.uk`, `com.au`) will be mis-split. A full PSL integration can be
    /// added later if needed; for now the approximation is acceptable because
    /// BIMI is only used for established brands, which typically register under
    /// common TLDs.
    static func isBIMILogoURLOnSenderDomain(_ logoURL: URL, senderDomain: String) -> Bool {
        guard let host = logoURL.host?.lowercased() else { return false }
        let logoETLD1 = eTLD1(of: host)
        let senderETLD1 = eTLD1(of: senderDomain)
        return !logoETLD1.isEmpty && logoETLD1 == senderETLD1
    }

    /// Return a best-effort eTLD+1 (last two dot-separated labels) for `domain`.
    private static func eTLD1(of domain: String) -> String {
        let labels = domain.split(separator: ".", omittingEmptySubsequences: true)
        guard labels.count >= 2 else { return domain }
        return labels.suffix(2).joined(separator: ".")
    }

    /// Fetch a sender-domain favicon using the ADR-0003 probe order.
    /// This only runs when the user has explicitly enabled favicons.
    private static func fetchFavicon(
        domain: String,
        urlSession: URLSession
    ) async -> Data? {
        guard shouldAttemptFavicon(for: domain) else { return nil }

        for url in faviconURLs(for: domain) {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

                let (data, response) = try await urlSession.data(
                    for: request,
                    delegate: AvatarRedirectGuard(maxBytes: 512 * 1024)
                )
                guard let http = response as? HTTPURLResponse,
                      (200 ..< 300).contains(http.statusCode),
                      isSupportedFavicon(data: data, contentType: http.value(forHTTPHeaderField: "Content-Type"))
                else { continue }
                return data
            } catch {
                continue
            }
        }
        return nil
    }

    // MARK: - Helpers

    public static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func domain(from email: String) -> String? {
        let parts = email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let domain = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard domain.contains("."),
              !domain.hasPrefix("."),
              !domain.hasSuffix("."),
              domain.unicodeScalars.allSatisfy({ faviconDomainCharacters.contains($0) }),
              isPubliclyRoutableHost(domain)
        else { return nil }
        return domain
    }

    /// Rejects hosts that aren't a public, routable DNS name — IP-address
    /// literals (every dot-separated label numeric, e.g. `169.254.169.254`, the
    /// cloud-metadata endpoint, or `127.0.0.1`/`10.0.0.1`) and reserved/internal
    /// TLDs. A sender controls their own From-domain, so without this the
    /// favicon fetch is an SSRF primitive against internal/metadata services.
    static func isPubliclyRoutableHost(_ host: String) -> Bool {
        let labels = host.split(separator: ".")
        guard labels.count >= 2 else { return false }
        // All-numeric labels ⇒ a dotted IPv4 literal. (IPv6 literals contain ':',
        // already rejected by the character-set check.)
        if labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) {
            return false
        }
        // Internal/non-routable TLDs that resolve onto a private network. (The
        // RFC 2606 documentation TLDs .test/.example/.invalid are intentionally
        // NOT here — they don't resolve to internal hosts, so they're not an
        // SSRF vector.)
        let internalTLDs: Set<String> = [
            "local", "localhost", "internal", "intranet", "lan", "corp", "home"
        ]
        if let tld = labels.last.map(String.init), internalTLDs.contains(tld) {
            return false
        }
        return true
    }

    static func faviconURLs(for domain: String) -> [URL] {
        [
            URL(string: "https://\(domain)/apple-touch-icon.png"),
            URL(string: "https://\(domain)/favicon.ico"),
            URL(string: "https://www.\(domain)/favicon.ico")
        ].compactMap { $0 }
    }

    static func shouldAttemptFavicon(for domain: String) -> Bool {
        !publicMailProviderDomains.contains(domain)
    }

    static func isSupportedFavicon(data: Data, contentType: String?) -> Bool {
        guard !data.isEmpty,
              data.count <= 512 * 1024 else {
            return false
        }

        if hasPNGHeader(data)
            || hasJPEGHeader(data)
            || hasGIFHeader(data)
            || hasICOHeader(data) {
            return true
        }

        guard let contentType = contentType?.lowercased() else {
            return false
        }
        return contentType.hasPrefix("image/png")
            || contentType.hasPrefix("image/jpeg")
            || contentType.hasPrefix("image/gif")
            || contentType.hasPrefix("image/x-icon")
            || contentType.hasPrefix("image/vnd.microsoft.icon")
    }

    static func isPermittedBIMILogoURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
    }

    static func isSupportedBIMILogo(data: Data, contentType: String?) -> Bool {
        guard !data.isEmpty,
              data.count <= maximumSVGByteCount,
              let text = String(data: data, encoding: .utf8) else {
            return false
        }

        let lowercasedText = text.lowercased()
        guard lowercasedText.contains("<svg") else { return false }
        guard !lowercasedText.contains("<script"),
              !lowercasedText.contains("javascript:"),
              !containsRemoteSVGReference(lowercasedText) else {
            return false
        }

        guard let contentType = contentType?.lowercased() else {
            return true
        }
        return contentType.hasPrefix("image/svg+xml")
            || contentType.hasPrefix("application/octet-stream")
    }

    private static func containsRemoteSVGReference(_ lowercasedText: String) -> Bool {
        if lowercasedText.contains("<image") { return true }
        if lowercasedText.contains("@import") { return true }

        return remoteSVGReferencePatterns.contains { pattern in
            lowercasedText.contains(pattern)
        }
    }

    private static let faviconDomainCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-."
    )

    private static let publicMailProviderDomains: Set<String> = [
        "aol.com",
        "fastmail.com",
        "gmail.com",
        "gmx.com",
        "googlemail.com",
        "hey.com",
        "hotmail.com",
        "icloud.com",
        "live.com",
        "mac.com",
        "mail.com",
        "me.com",
        "msn.com",
        "outlook.com",
        "pm.me",
        "proton.me",
        "protonmail.com",
        "tutanota.com",
        "yahoo.com",
        "yandex.com",
        "zoho.com"
    ]

    private static let remoteSVGReferencePatterns = [
        "href=\"http://",
        "href=\"https://",
        "href='http://",
        "href='https://",
        "href=//",
        "url(http://",
        "url(https://",
        "url('http://",
        "url('https://",
        "url(\"http://",
        "url(\"https://",
        "url(//"
    ]

    private static func hasPNGHeader(_ data: Data) -> Bool {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47])
    }

    private static func hasJPEGHeader(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xD8, 0xFF])
    }

    private static func hasGIFHeader(_ data: Data) -> Bool {
        data.starts(with: Array("GIF".utf8))
    }

    private static func hasICOHeader(_ data: Data) -> Bool {
        data.starts(with: [0x00, 0x00, 0x01, 0x00])
            || data.starts(with: [0x00, 0x00, 0x02, 0x00])
    }

    private static func cacheTTL(for source: AvatarSource) -> TimeInterval {
        switch source {
        case .contacts, .gravatar, .favicon:
            return 30 * 86400
        case .bimi, .initials, .none:
            return 7 * 86400
        }
    }

    private static func defaultAvatarCache() -> any AvatarCacheStoring {
        (try? SQLiteAvatarCache(databaseURL: SQLiteAvatarCache.defaultDatabaseURL()))
            ?? NoAvatarCache()
    }
}

/// Guards an avatar/image fetch in two ways: (1) blocks a redirect away from a
/// public, routable HTTPS host — e.g. a public domain 302-ing the request to an
/// internal/cloud-metadata IP (SSRF via redirect); (2) rejects a response whose
/// declared `Content-Length` exceeds the per-source byte cap, before the body is
/// buffered into memory. Immutable, hence safe to share across tasks.
private final class AvatarRedirectGuard: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maxBytes: Int

    init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard request.url?.scheme?.lowercased() == "https",
              let host = request.url?.host?.lowercased(),
              AvatarResolver.isPubliclyRoutableHost(host)
        else { return nil }
        return request
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        // expectedContentLength is -1 when unknown (chunked); only reject a
        // declared over-cap length here. Unknown-length bodies are still bounded
        // by the post-read size check.
        response.expectedContentLength > Int64(maxBytes) ? .cancel : .allow
    }
}
