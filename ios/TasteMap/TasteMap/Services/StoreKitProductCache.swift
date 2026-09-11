import Foundation

/// In-memory StoreKit catalog only. No account, entitlement, or persistence authority.
actor StoreKitProductCache<Value: Sendable> {
    private let load: @Sendable () async throws -> [Value]
    private let storefront: @Sendable () async -> String?
    private var storefrontID: String?
    private var revision = UUID()
    private var cached: [Value]?
    private var inFlight: Task<[Value], Error>?

    init(load: @escaping @Sendable () async throws -> [Value],
         storefront: @escaping @Sendable () async -> String?) {
        self.load = load
        self.storefront = storefront
    }

    func invalidate() {
        revision = UUID()
        cached = nil
        inFlight?.cancel()
        inFlight = nil
    }

    func values() async throws -> (values: [Value], cacheHit: Bool) {
        let entryRevision = revision
        let currentStorefront = await storefront()
        guard revision == entryRevision else { throw CancellationError() }
        if storefrontID != currentStorefront {
            invalidate()
            storefrontID = currentStorefront
        }
        if let cached { return (cached, true) }
        let requestRevision = revision
        let task: Task<[Value], Error>
        if let inFlight {
            task = inFlight
        } else {
            task = Task { try await load() }
            inFlight = task
        }
        do {
            let values = try await task.value
            let latestStorefront = await storefront()
            guard revision == requestRevision else { throw CancellationError() }
            guard latestStorefront == currentStorefront else {
                invalidate()
                storefrontID = latestStorefront
                throw CancellationError()
            }
            // An empty/failed lookup is retryable, never a permanent empty catalog.
            cached = values.isEmpty ? nil : values
            inFlight = nil
            return (values, false)
        } catch {
            if revision == requestRevision { inFlight = nil }
            throw error
        }
    }
}
