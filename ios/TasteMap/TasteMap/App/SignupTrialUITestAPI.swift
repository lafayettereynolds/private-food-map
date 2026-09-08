#if DEBUG
import Foundation
// Explicit isolated UI-test transport. Never included in Release.
@MainActor
final class SignupTrialUITestAPI: PremiumEntitlementAPI {
    nonisolated static let start = Date()
    static let owner = TasteMapUITestFixtures.profileUserID
    var owner = SignupTrialUITestAPI.owner
    var apple = false
    var claimed = false
    var claimCount = 0
    var suspendClaim = false
    var pending: CheckedContinuation<PremiumTrialClaim, Error>?
    func entitlement() async throws -> PremiumEntitlementResponseV1 { membership(owner: owner, premium: claimed || apple) }
    func trialEligibility() async throws -> PremiumTrialEligibility { .init(apiVersion: 1, userId: owner, eligible: !claimed, trialDays: 7) }
    func claimTrial() async throws -> PremiumTrialClaim {
        claimCount += 1
        if suspendClaim { return try await withCheckedThrowingContinuation { pending = $0 } }
        claimed = true
        return claimResponse(owner: owner)
    }
    func claimResponse(owner: String) -> PremiumTrialClaim {
        .init(apiVersion: 1, userId: owner, isPremium: true, source: "signup_trial", expiresAt: Self.start.addingTimeInterval(7 * 86400).ISO8601Format(), membership: membership(owner: owner, premium: true))
    }
    func membership(owner: String, premium: Bool) -> PremiumEntitlementResponseV1 {
        .init(apiVersion: 1, userId: owner, entitlement: .init(state: premium ? .active : .free, isPremium: premium,
            source: premium ? (apple ? .appStoreAnnual : .signupTrial) : nil, kind: premium ? (apple ? .annualSubscription : .fixedTerm) : .unspecified,
            startsAt: premium ? Self.start.ISO8601Format() : nil,
            expiresAt: premium ? Self.start.addingTimeInterval(Double(apple ? 365 : 7) * 86400).ISO8601Format() : nil,
            isLifetime: false, updatedAt: Self.start.ISO8601Format()), verifiedAt: Self.start.ISO8601Format())
    }
}

#endif
