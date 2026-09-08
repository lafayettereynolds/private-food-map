import Foundation
import Testing
@testable import TasteMap

@Suite("Signup trial service")
@MainActor
struct SignupTrialTests {
    @Test("Claim immediately applies server union, hides eligibility, and exposes an expiry message")
    func claimAndExpire() async throws {
        let api = TrialTestAPI()
        let clock = TrialTestClock()
        let service = PremiumEntitlementService(api: api, cache: InMemoryPremiumEntitlementCache(), environment: .production, now: { clock.now })
        await service.activate(userID: "a")
        await service.refreshTrialEligibility()
        #expect(service.trialEligibility?.eligible == true)
        _ = try await service.claimTrial()
        #expect(service.membershipStatus == .premium)
        #expect(service.trialEligibility?.eligible == false)
        #expect(service.trialMessage?.contains("领取成功") == true)
        #expect(service.snapshot?.source == .signupTrial)
        #expect(service.snapshot?.source?.isAppStoreSubscription == false)
        #expect(service.snapshot?.giftStatusText?.hasPrefix("新用户 7 天体验") == true)
        clock.now = TrialTestAPI.start.addingTimeInterval(7 * 86400)
        #expect(service.membershipStatus == .expired)
        #expect(service.access(for: .annualRecap) == .denied)
        #expect(api.claimCount == 1)
    }

    @Test("Apple entitlement in claim response remains the membership authority")
    func appleUnion() async throws {
        let api = TrialTestAPI(); api.apple = true
        let service = PremiumEntitlementService(api: api, cache: InMemoryPremiumEntitlementCache(), environment: .production, now: { TrialTestAPI.start })
        await service.activate(userID: "a")
        _ = try await service.claimTrial()
        #expect(service.snapshot?.source == .appStoreAnnual)
        #expect(service.snapshot?.source?.isAppStoreSubscription == true)
        #expect(service.snapshot?.expiresAt == TrialTestAPI.start.addingTimeInterval(365 * 86400))
    }

    @Test("In-flight duplicate click is rejected and account switch drops a late claim")
    func concurrentAndAccountSwitch() async throws {
        let api = TrialTestAPI(); api.suspendClaim = true
        let service = PremiumEntitlementService(api: api, cache: InMemoryPremiumEntitlementCache(), environment: .production, now: { TrialTestAPI.start })
        await service.activate(userID: "a")
        let first = Task { try await service.claimTrial() }
        while api.pending == nil { await Task.yield() }
        do { _ = try await service.claimTrial(); Issue.record("Duplicate claim must fail") } catch {}
        #expect(api.claimCount == 1)
        service.sessionDidEnd()
        api.owner = "b"
        await service.activate(userID: "b")
        api.pending?.resume(returning: api.claimResponse(owner: "a"))
        _ = try? await first.value
        #expect(service.membershipStatus == .free)
        #expect(service.activeUserID == "b")
        #expect(service.trialMessage == nil)
        #expect(service.trialEligibility == nil)
    }
}

private final class TrialTestClock: @unchecked Sendable { var now = TrialTestAPI.start }
@MainActor
private final class TrialTestAPI: PremiumEntitlementAPI {
    nonisolated static let start = Date(timeIntervalSince1970: 1_788_000_000)
    var owner = "a"
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
