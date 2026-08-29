import Foundation

nonisolated enum MembershipProductPeriod: String, Codable, Sendable {
    case monthly
    case annual
    case lifetime
}

nonisolated struct MembershipProduct: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let valueDescription: String
    let displayPrice: String
    let period: MembershipProductPeriod
    let billingPeriodDescription: String
}

nonisolated enum MembershipPurchaseOutcome: Equatable, Sendable {
    case completed
    case pending
    case userCancelled
}

nonisolated struct MembershipPurchaseResult: Equatable, Sendable {
    let transactionID: String?
    let requiresEntitlementRefresh: Bool
    let outcome: MembershipPurchaseOutcome
}

nonisolated struct MembershipPurchaseCapabilities: OptionSet, Sendable {
    let rawValue: Int
    static let purchase = Self(rawValue: 1 << 0)
    static let restore = Self(rawValue: 1 << 1)
    static let manageSubscription = Self(rawValue: 1 << 2)
}

nonisolated protocol MembershipPurchaseProviding: Sendable {
    var capabilities: MembershipPurchaseCapabilities { get }
    func startObserving()
    func activate(userID: String) async
    func sessionDidEnd(userID: String?) async
    func products() async throws -> [MembershipProduct]
    func purchase(productID: String) async throws -> MembershipPurchaseResult
    func restore() async throws -> MembershipPurchaseResult
    func manageSubscription() async throws
}

extension MembershipPurchaseProviding {
    func startObserving() {}
    func activate(userID: String) async {}
    func sessionDidEnd(userID: String?) async {}
}

nonisolated struct UnconfiguredMembershipPurchaseProvider: MembershipPurchaseProviding {
    let capabilities: MembershipPurchaseCapabilities = []

    func products() async throws -> [MembershipProduct] { [] }
    func purchase(productID: String) async throws -> MembershipPurchaseResult {
        throw MembershipPurchaseError.notConfigured
    }
    func restore() async throws -> MembershipPurchaseResult {
        throw MembershipPurchaseError.notConfigured
    }
    func manageSubscription() async throws {
        throw MembershipPurchaseError.notConfigured
    }
}

nonisolated enum MembershipPurchaseError: LocalizedError, Equatable {
    case notConfigured
    case productUnavailable
    case purchaseNotCompleted
    case restoreUnavailable
    case unverifiedTransaction

    var errorDescription: String? {
        switch self {
        case .notConfigured: "订阅信息暂时不可用，请稍后再试。"
        case .productUnavailable: "这个方案暂时不可用。"
        case .purchaseNotCompleted: "购买没有完成。"
        case .restoreUnavailable: "当前没有可恢复的购买。"
        case .unverifiedTransaction: "App Store 无法验证这笔交易。"
        }
    }
}
