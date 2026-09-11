import Foundation
import StoreKit
import UIKit

nonisolated enum StoreKitPurchaseTiming {
    @TaskLocal static var tappedAtMilliseconds: Double?
}

actor StoreKitMembershipPurchaseProvider: MembershipPurchaseProviding {
    nonisolated let capabilities: MembershipPurchaseCapabilities = [.purchase, .restore, .manageSubscription]

    private let commerceAPI: any PremiumCommerceAPI
    private var configuration: PremiumCommerceConfigurationV1?
    private var activeUserID: String?
    private var sessionGeneration = UUID()
    private var updatesTask: Task<Void, Never>?
    private var storefrontTask: Task<Void, Never>?
    private let productCache = StoreKitProductCache<Product>(
        load: { try await Product.products(for: [
            "com.lafayette.tastemap.premium.monthly.v1",
            "com.lafayette.tastemap.premium.annual.v1",
        ]) },
        storefront: { await Storefront.current?.id }
    )

    init(commerceAPI: any PremiumCommerceAPI) {
        self.commerceAPI = commerceAPI
    }

    nonisolated func startObserving() {
        Task { await self.beginTransactionUpdatesIfNeeded() }
    }

    func activate(userID: String) async {
        let userID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userID.isEmpty else { return }
        if activeUserID != userID {
            sessionGeneration = UUID()
            activeUserID = userID
            configuration = nil
        }
        let generation = sessionGeneration
        do {
            let value = try await commerceAPI.configuration()
            guard activeUserID == userID, sessionGeneration == generation else { return }
            configuration = value
            try await reconcileCurrentEntitlements()
        } catch {
            // Store commerce must never block sign-in or local-first usage.
        }
    }

    func sessionDidEnd(userID: String?) async {
        guard userID == nil || activeUserID == userID else { return }
        sessionGeneration = UUID()
        activeUserID = nil
        configuration = nil
    }

    func products() async throws -> [MembershipProduct] {
        beginStorefrontUpdatesIfNeeded()
        let started = ContinuousClock.now
        // Product metadata is public; displaying prices must not depend on a Taste Map session.
        let references: [String: MembershipProductPeriod] = [
            "com.lafayette.tastemap.premium.monthly.v1": .monthly,
            "com.lafayette.tastemap.premium.annual.v1": .annual,
        ]
        let country = await Storefront.current?.countryCode ?? "unknown"
        let result = try await currentCatalog()
        for product in result.values {
            DeviceAcceptanceLog.record("TasteMapDiagnostic category=storekit event=product_preload country=\(country) product=\(product.id) displayPrice=\(product.displayPrice) cache=\(result.cacheHit ? "HIT" : "MISS") duration_ms=\(Self.milliseconds(since: started))")
        }
        return result.values
            .compactMap { product in
                guard let reference = references[product.id] else { return nil }
                return MembershipProduct(
                    id: product.id,
                    displayName: product.displayName,
                    valueDescription: product.description,
                    displayPrice: product.displayPrice,
                    period: reference,
                    billingPeriodDescription: Self.billingDescription(for: product.subscription?.subscriptionPeriod)
                )
            }
            .sorted { lhs, rhs in lhs.period == .annual && rhs.period != .annual }
    }

    func purchase(productID: String) async throws -> MembershipPurchaseResult {
        let started = ContinuousClock.now
        beginStorefrontUpdatesIfNeeded()
        let generation = sessionGeneration
        let configuration = try await loadConfiguration(forceRefresh: true)
        guard configuration.purchaseReady == true else {
            throw MembershipPurchaseError.notConfigured
        }
        guard configuration.products.contains(where: { $0.id == productID }) else {
            throw MembershipPurchaseError.productUnavailable
        }
        var catalog = try await currentCatalog()
        if !catalog.values.contains(where: { $0.id == productID }) {
            await productCache.invalidate()
            catalog = try await currentCatalog()
        }
        guard let product = catalog.values.first(where: { $0.id == productID }) else {
            throw MembershipPurchaseError.productUnavailable
        }
        guard activeUserID != nil, sessionGeneration == generation else { throw MembershipPurchaseError.notConfigured }
        if let tappedAt = StoreKitPurchaseTiming.tappedAtMilliseconds {
            let elapsed = Date.now.timeIntervalSince1970 * 1_000 - tappedAt
            if elapsed.isFinite, (0...120_000).contains(elapsed) {
                DeviceAcceptanceLog.record("TasteMapDiagnostic category=storekit event=tap_to_purchase duration_ms=\(Int(elapsed))")
            }
        }
        DeviceAcceptanceLog.record("TasteMapDiagnostic category=storekit event=purchase_invoke product=\(product.id) cache=\(catalog.cacheHit ? "HIT" : "MISS") provider_entry_to_purchase_ms=\(Self.milliseconds(since: started))")
        switch try await product.purchase(options: [.appAccountToken(configuration.appAccountToken)]) {
        case .success(let verification):
            guard activeUserID != nil, sessionGeneration == generation else { throw MembershipPurchaseError.notConfigured }
            let transaction = try Self.verified(verification)
            try await reconcileAndFinish(transaction, signedTransactionInfo: verification.jwsRepresentation)
            return .init(transactionID: String(transaction.id), requiresEntitlementRefresh: true, outcome: .completed)
        case .pending:
            return .init(transactionID: nil, requiresEntitlementRefresh: false, outcome: .pending)
        case .userCancelled:
            return .init(transactionID: nil, requiresEntitlementRefresh: false, outcome: .userCancelled)
        @unknown default:
            throw MembershipPurchaseError.purchaseNotCompleted
        }
    }

    func restore() async throws -> MembershipPurchaseResult {
        let generation = sessionGeneration
        guard activeUserID != nil else { throw MembershipPurchaseError.notConfigured }
        try await AppStore.sync()
        guard activeUserID != nil, sessionGeneration == generation else { throw MembershipPurchaseError.notConfigured }
        let count = try await reconcileCurrentEntitlements()
        guard count > 0 else { throw MembershipPurchaseError.restoreUnavailable }
        return .init(transactionID: nil, requiresEntitlementRefresh: true, outcome: .completed)
    }

    func manageSubscription() async throws {
        guard let scene = await Self.foregroundScene() else {
            throw MembershipPurchaseError.restoreUnavailable
        }
        try await AppStore.showManageSubscriptions(in: scene)
    }

    private func beginTransactionUpdatesIfNeeded() {
        beginStorefrontUpdatesIfNeeded()
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await verification in Transaction.updates {
                guard !Task.isCancelled, let self else { return }
                guard case .verified(let transaction) = verification else { continue }
                try? await self.reconcileAndFinish(transaction, signedTransactionInfo: verification.jwsRepresentation)
            }
        }
    }

    private func beginStorefrontUpdatesIfNeeded() {
        guard storefrontTask == nil else { return }
        storefrontTask = Task { [weak self] in
            for await storefront in Storefront.updates {
                guard !Task.isCancelled, let self else { return }
                await self.storefrontDidChange(country: storefront.countryCode)
            }
        }
    }

    private func currentCatalog() async throws -> (values: [Product], cacheHit: Bool) {
        // A storefront transition can cancel a shared preload without cancelling
        // its caller. Retry the new storefront, never return that stale catalog.
        for _ in 0..<3 {
            try Task.checkCancellation()
            do { return try await productCache.values() }
            catch is CancellationError { try Task.checkCancellation() }
        }
        throw MembershipPurchaseError.productUnavailable
    }

    private func storefrontDidChange(country: String) async {
        await productCache.invalidate()
        DeviceAcceptanceLog.record("TasteMapDiagnostic category=storekit event=storefront_invalidated country=\(country)")
        // Both Hybrid and rollback paywalls discard their display DTOs and reload.
        NotificationCenter.default.post(name: .tasteMapStoreKitProductsChanged, object: nil)
        _ = try? await products()
    }

    private nonisolated static func milliseconds(since start: ContinuousClock.Instant) -> Int64 {
        let duration = start.duration(to: .now).components
        return duration.seconds * 1_000 + duration.attoseconds / 1_000_000_000_000_000
    }

    private func loadConfiguration(forceRefresh: Bool = false) async throws -> PremiumCommerceConfigurationV1 {
        if !forceRefresh, let configuration { return configuration }
        guard let userID = activeUserID else { throw MembershipPurchaseError.notConfigured }
        let generation = sessionGeneration
        let value = try await commerceAPI.configuration()
        guard activeUserID == userID, sessionGeneration == generation else { throw MembershipPurchaseError.notConfigured }
        configuration = value
        return value
    }

    @discardableResult
    private func reconcileCurrentEntitlements() async throws -> Int {
        guard activeUserID != nil else { return 0 }
        let generation = sessionGeneration
        var count = 0
        for await verification in Transaction.currentEntitlements {
            guard sessionGeneration == generation else { throw MembershipPurchaseError.notConfigured }
            let transaction = try Self.verified(verification)
            try await reconcileAndFinish(transaction, signedTransactionInfo: verification.jwsRepresentation)
            count += 1
        }
        return count
    }

    private func reconcileAndFinish(_ transaction: Transaction, signedTransactionInfo: String) async throws {
        guard let userID = activeUserID else { throw MembershipPurchaseError.notConfigured }
        let generation = sessionGeneration
        _ = try await commerceAPI.reconcile(transactionID: transaction.id, signedTransactionInfo: signedTransactionInfo)
        guard activeUserID == userID, sessionGeneration == generation else { throw MembershipPurchaseError.notConfigured }
        await transaction.finish()
        guard activeUserID == userID, sessionGeneration == generation else { return }
        NotificationCenter.default.post(name: .tasteMapPremiumEntitlementChanged, object: userID)
    }

    private nonisolated static func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): value
        case .unverified: throw MembershipPurchaseError.unverifiedTransaction
        }
    }

    private nonisolated static func billingDescription(for period: Product.SubscriptionPeriod?) -> String {
        guard let period else { return "" }
        let unit = switch period.unit {
        case .day: "天"
        case .week: "周"
        case .month: "个月"
        case .year: "年"
        @unknown default: "个周期"
        }
        return period.value == 1 ? "每\(unit)续订" : "每 \(period.value) \(unit)续订"
    }

    @MainActor
    private static func foregroundScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
    }
}

extension Notification.Name {
    nonisolated static let tasteMapStoreKitProductsChanged = Notification.Name(
        "com.lafayette.tastemap.storekit-products-changed"
    )
    nonisolated static let tasteMapPremiumEntitlementChanged = Notification.Name(
        "com.lafayette.tastemap.premium-entitlement-changed"
    )
}
