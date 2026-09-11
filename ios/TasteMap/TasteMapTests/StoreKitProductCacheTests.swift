import Foundation
import Testing
@testable import TasteMap

@Suite("StoreKit product cache and storefront fences")
struct StoreKitProductCacheTests {
    @Test("Monthly and annual preload share the exact cached localized values")
    func preloadAndReuse() async throws {
        let probe = CatalogProbe()
        let cache = makeCache(probe)
        let first = try await cache.values()
        let purchase = try await cache.values()
        #expect(first.values == ["monthly ¥8.00", "annual ¥80.00"])
        #expect(!first.cacheHit)
        #expect(purchase.cacheHit)
        #expect(purchase.values == first.values)
        #expect(await probe.calls == 1)
    }

    @Test("Storefront identity change invalidates even if no notification was delivered")
    func storefrontChanged() async throws {
        let probe = CatalogProbe()
        let cache = makeCache(probe)
        _ = try await cache.values()
        await probe.change("USA", values: ["monthly $0.99", "annual $9.99"])
        let next = try await cache.values()
        #expect(!next.cacheHit)
        #expect(next.values == ["monthly $0.99", "annual $9.99"])
        #expect(await probe.calls == 2)
    }

    @Test("Explicit invalidation reloads instead of purchasing an old Product")
    func explicitInvalidation() async throws {
        let probe = CatalogProbe()
        let cache = makeCache(probe)
        _ = try await cache.values()
        await cache.invalidate()
        #expect(try await cache.values().cacheHit == false)
        #expect(await probe.calls == 2)
    }

    @Test("A delayed old storefront load cannot resurrect invalidated prices")
    func lateLoad() async throws {
        let probe = CatalogProbe()
        await probe.suspendNext()
        let cache = makeCache(probe)
        let old = Task { try await cache.values() }
        while await !probe.isSuspended { await Task.yield() }
        await cache.invalidate()
        await probe.change("USA", values: ["monthly $0.99", "annual $9.99"])
        let fresh = try await cache.values()
        await probe.resume()
        await #expect(throws: CancellationError.self) { _ = try await old.value }
        #expect(try await cache.values().values == fresh.values)
        #expect(fresh.values.first == "monthly $0.99")
    }

    @Test("An unannounced storefront change during fetch rejects that response")
    func changeDuringFetch() async throws {
        let probe = CatalogProbe()
        await probe.suspendNext()
        let cache = makeCache(probe)
        let request = Task { try await cache.values() }
        while await !probe.isSuspended { await Task.yield() }
        await probe.change("USA", values: ["new"])
        await probe.resume()
        await #expect(throws: CancellationError.self) { _ = try await request.value }
        #expect(try await cache.values().values == ["new"])
    }

    @Test("Empty catalogs and failures remain retryable")
    func retries() async throws {
        let probe = CatalogProbe()
        await probe.change("CHN", values: [])
        let cache = makeCache(probe)
        #expect(try await cache.values().values.isEmpty)
        await probe.failNext()
        await #expect(throws: URLError.self) { _ = try await cache.values() }
        await probe.change("CHN", values: ["recovered"])
        #expect(try await cache.values().values == ["recovered"])
        #expect(await probe.calls == 3)
    }

    @Test("Recreated cache reloads without persisted stale catalog")
    func restart() async throws {
        let probe = CatalogProbe()
        _ = try await makeCache(probe).values()
        #expect(try await makeCache(probe).values().cacheHit == false)
        #expect(await probe.calls == 2)
    }

    private func makeCache(_ probe: CatalogProbe) -> StoreKitProductCache<String> {
        StoreKitProductCache(load: { try await probe.load() }, storefront: { await probe.country })
    }
}

private actor CatalogProbe {
    var country = "CHN"
    var values = ["monthly ¥8.00", "annual ¥80.00"]
    var calls = 0
    var isSuspended: Bool { continuation != nil }
    private var suspend = false
    private var fail = false
    private var continuation: CheckedContinuation<Void, Never>?
    func change(_ country: String, values: [String]) { self.country = country; self.values = values }
    func suspendNext() { suspend = true }
    func failNext() { fail = true }
    func resume() { continuation?.resume(); continuation = nil }
    func load() async throws -> [String] {
        calls += 1
        let snapshot = values
        if fail { fail = false; throw URLError(.notConnectedToInternet) }
        if suspend { suspend = false; await withCheckedContinuation { continuation = $0 } }
        return snapshot
    }
}
