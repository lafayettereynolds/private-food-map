import Foundation

nonisolated enum PremiumEntitlementContract {
    static let apiVersion = 1
}

nonisolated enum PremiumEntitlementSource: String, Codable, CaseIterable, Sendable {
    case appStoreMonthly = "app_store_monthly"
    case appStoreAnnual = "app_store_annual"
    case giftAnnual = "gift_annual"
    case giftLifetime = "gift_lifetime"
    case appStoreSubscription = "app_store_subscription"
    case promotion = "promotion"
    case signupTrial = "signup_trial"
    case referralReward = "referral_reward"
    case appStoreYearly = "app_store_yearly"
    case appStoreLifetime = "app_store_lifetime"
    case adminGrant = "admin_grant"
    case promo
    case redeemCode = "redeem_code"
    case development

    var isAppStoreSubscription: Bool {
        self == .appStoreSubscription || self == .appStoreMonthly || self == .appStoreYearly || self == .appStoreAnnual
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
        if response.entitlement.source == .giftLifetime {
            guard response.entitlement.kind == .lifetime, expiresAt == nil, startsAt != nil else {
                throw PremiumEntitlementContractError.invalidResponse
            }
        }
        if response.entitlement.source == .giftAnnual || response.entitlement.source == .referralReward || response.entitlement.source == .signupTrial {
            guard response.entitlement.kind == .fixedTerm, let startsAt, let expiresAt, expiresAt > startsAt else {
                throw PremiumEntitlementContractError.invalidResponse
            }
        }
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
        guard startsAt.map({ $0 <= date }) ?? true else { return false }
        if isLifetime { return true }
        guard let expiresAt else { return state == .gracePeriod }
        return expiresAt > date || state == .gracePeriod
    }

    var giftStatusText: String? {
        if source == .giftLifetime { return "永久会员 · 由 Taste Map 赠送" }
        guard source == .giftAnnual || source == .referralReward || source == .signupTrial, let expiresAt else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy年MM月dd日"
        return "\(source == .signupTrial ? "新用户 7 天体验" : source == .referralReward ? "邀请奖励" : "赠送会员") · 有效期至 \(formatter.string(from: expiresAt))"
    }

    private static func optionalDate(_ value: String?) throws -> Date? {
        guard let value else { return nil }
        guard let date = date(value) else { throw PremiumEntitlementContractError.invalidResponse }
        return date
    }

    static func date(_ value: String) -> Date? {
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

nonisolated struct PremiumTrialEligibility: Codable, Sendable {
    let apiVersion: Int
    let userId: String
    let eligible: Bool
    let trialDays: Int
}

nonisolated struct PremiumTrialClaim: Codable, Sendable {
    let apiVersion: Int
    let userId: String
    let isPremium: Bool
    let source: String
    let expiresAt: String
    let membership: PremiumEntitlementResponseV1
}
