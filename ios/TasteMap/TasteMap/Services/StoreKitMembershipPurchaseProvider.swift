import Foundation
import StoreKit
import UIKit

actor StoreKitMembershipPurchaseProvider: MembershipPurchaseProviding {
    nonisolated let capabilities: MembershipPurchaseCapabilities = [.purchase, .restore, .manageSubscription]

    private let commerceAPI: any PremiumCommerceAPI
    private var configuration: PremiumCommerceConfigurationV1?
    private var activeUserID: String?
    private var updatesTask: Task<Void, Never>?

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
            activeUserID = userID
            configuration = nil
        }
        do {
            configuration = try await commerceAPI.configuration()
            try await reconcileCurrentEntitlements()
        } catch {
            // Store commerce must never block sign-in or local-first usage.
        }
    }

    func sessionDidEnd(userID: String?) async {
        guard userID == nil || activeUserID == userID else { return }
        activeUserID = nil
        configuration = nil
    }

    func products() async throws -> [MembershipProduct] {
        let configuration = try await loadConfiguration()
        guard configuration.configured, !configuration.products.isEmpty else {
            throw MembershipPurchaseError.notConfigured
        }
        let references = Dictionary(uniqueKeysWithValues: configuration.products.map { ($0.id, $0) })
        return try await Product.products(for: Array(references.keys))
            .compactMap { product in
                guard let reference = references[product.id] else { return nil }
                return MembershipProduct(
                    id: product.id,
                    displayName: product.displayName,
                    valueDescription: product.description,
                    displayPrice: product.displayPrice,
                    period: reference.period,
                    billingPeriodDescription: Self.billingDescription(for: product.subscription?.subscriptionPeriod)
                )
            }
            .sorted { lhs, rhs in lhs.period == .annual && rhs.period != .annual }
    }

    func purchase(productID: String) async throws -> MembershipPurchaseResult {
        let configuration = try await loadConfiguration()
        guard configuration.products.contains(where: { $0.id == productID }) else {
            throw MembershipPurchaseError.productUnavailable
        }
        guard let product = try await Product.products(for: [productID]).first else {
            throw MembershipPurchaseError.productUnavailable
        }
        switch try await product.purchase(options: [.appAccountToken(configuration.appAccountToken)]) {
        case .success(let verification):
            let transaction = try Self.verified(verification)
            try await reconcileAndFinish(transaction)
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
        try await AppStore.sync()
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
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await verification in Transaction.updates {
                guard !Task.isCancelled, let self else { return }
                guard case .verified(let transaction) = verification else { continue }
                try? await self.reconcileAndFinish(transaction)
            }
        }
    }

    private func loadConfiguration() async throws -> PremiumCommerceConfigurationV1 {
        if let configuration { return configuration }
        guard activeUserID != nil else { throw MembershipPurchaseError.notConfigured }
        let value = try await commerceAPI.configuration()
        configuration = value
        return value
    }

    @discardableResult
    private func reconcileCurrentEntitlements() async throws -> Int {
        guard activeUserID != nil else { return 0 }
        var count = 0
        for await verification in Transaction.currentEntitlements {
            let transaction = try Self.verified(verification)
            try await reconcileAndFinish(transaction)
            count += 1
        }
        return count
    }

    private func reconcileAndFinish(_ transaction: Transaction) async throws {
        guard activeUserID != nil else { return }
        _ = try await commerceAPI.reconcile(transactionID: transaction.id)
        await transaction.finish()
        NotificationCenter.default.post(name: .tasteMapPremiumEntitlementChanged, object: activeUserID)
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
    nonisolated static let tasteMapPremiumEntitlementChanged = Notification.Name(
        "com.lafayette.tastemap.premium-entitlement-changed"
    )
}
