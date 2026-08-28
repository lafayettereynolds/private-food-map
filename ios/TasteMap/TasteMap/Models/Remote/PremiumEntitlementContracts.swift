import Foundation

nonisolated enum PremiumEntitlementContract {
    static let apiVersion = 1
}

nonisolated enum PremiumEntitlementSource: String, Codable, CaseIterable, Sendable {
    case appStoreMonthly = "app_store_monthly"
    case appStoreYearly = "app_store_yearly"
    case appStoreLifetime = "app_store_lifetime"
    case adminGrant = "admin_grant"
    case promo
    case redeemCode = "redeem_code"
    case development

    var isAppStoreSubscription: Bool {
        self == .appStoreMonthly || self == .appStoreYearly
    }
}

nonisolated enum PremiumEntitlementKind: String, Codable, CaseIterable, Sendable {
    case monthlySubscription = "monthly_subscription"
    case annualSubscription = "annual_subscription"
    case lifetime
    case fixedTerm = "fixed_term"
    case unspecified
}

nonisolated enum PremiumEntitlementState: String, Codable, CaseIterable, Sendable {
    case free
    case active
    case expired
    case gracePeriod = "grace_period"
}

nonisolated struct PremiumEntitlementDTO: Codable, Equatable, Sendable {
    let state: PremiumEntitlementState
    let isPremium: Bool
    let source: PremiumEntitlementSource?
    let kind: PremiumEntitlementKind
    let startsAt: String?
    let expiresAt: String?
    let isLifetime: Bool
    let updatedAt: String?
}

nonisolated struct PremiumEntitlementResponseV1: Codable, Equatable, Sendable {
    let apiVersion: Int
    let userId: String
    let entitlement: PremiumEntitlementDTO
    let verifiedAt: String
}

nonisolated struct PremiumEntitlementSnapshot: Codable, Equatable, Sendable {
    let userID: String
    let state: PremiumEntitlementState
    let isPremium: Bool
    let source: PremiumEntitlementSource?
    let kind: PremiumEntitlementKind
    let startsAt: Date?
    let expiresAt: Date?
    let isLifetime: Bool
    let updatedAt: Date?
    let verifiedAt: Date

    init(response: PremiumEntitlementResponseV1) throws {
        guard response.apiVersion == PremiumEntitlementContract.apiVersion,
              !response.userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let verifiedAt = Self.date(response.verifiedAt) else {
            throw PremiumEntitlementContractError.invalidResponse
        }
        let startsAt = try Self.optionalDate(response.entitlement.startsAt)
        let expiresAt = try Self.optionalDate(response.entitlement.expiresAt)
        let updatedAt = try Self.optionalDate(response.entitlement.updatedAt)
        guard response.entitlement.isPremium == response.entitlement.state.isAccessActive,
              response.entitlement.isLifetime == (response.entitlement.kind == .lifetime),
              !response.entitlement.isLifetime || expiresAt == nil,
              response.entitlement.source != nil || !response.entitlement.isPremium else {
            throw PremiumEntitlementContractError.invalidResponse
        }
        userID = response.userId
        state = response.entitlement.state
        isPremium = response.entitlement.isPremium
        source = response.entitlement.source
        kind = response.entitlement.kind
        self.startsAt = startsAt
        self.expiresAt = expiresAt
        self.isLifetime = response.entitlement.isLifetime
        self.updatedAt = updatedAt
        self.verifiedAt = verifiedAt
    }

    init(
        userID: String,
        state: PremiumEntitlementState,
        source: PremiumEntitlementSource? = nil,
        kind: PremiumEntitlementKind = .unspecified,
        startsAt: Date? = nil,
        expiresAt: Date? = nil,
        updatedAt: Date? = nil,
        verifiedAt: Date = .now
    ) {
        self.userID = userID
        self.state = state
        isPremium = state.isAccessActive
        self.source = source
        self.kind = kind
        self.startsAt = startsAt
        self.expiresAt = expiresAt
        isLifetime = kind == .lifetime
        self.updatedAt = updatedAt
        self.verifiedAt = verifiedAt
    }

    func isUsable(at date: Date) -> Bool {
        guard isPremium else { return false }
        if isLifetime { return true }
        guard let expiresAt else { return state == .gracePeriod }
        return expiresAt > date || state == .gracePeriod
    }

    private static func optionalDate(_ value: String?) throws -> Date? {
        guard let value else { return nil }
        guard let date = date(value) else { throw PremiumEntitlementContractError.invalidResponse }
        return date
    }

    private static func date(_ value: String) -> Date? {
        ISO8601DateFormatter.premiumFractional.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
    }
}

nonisolated enum PremiumEntitlementContractError: Error, Equatable {
    case invalidResponse
}

nonisolated extension PremiumEntitlementState {
    var isAccessActive: Bool { self == .active || self == .gracePeriod }
}

nonisolated private extension ISO8601DateFormatter {
    static let premiumFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
