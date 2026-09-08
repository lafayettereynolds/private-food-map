import Foundation
import Testing
@testable import TasteMap

@Suite("Referral reward contracts")
@MainActor
struct ReferralRewardTests {
    @Test func rewardUsesAuthoritativeFixedTermContract() throws {
        let response = PremiumEntitlementResponseV1(apiVersion: 1,userId: "A",
            entitlement: .init(state: .active,isPremium: true,source: .referralReward,kind: .fixedTerm,
                startsAt: "2026-09-07T00:00:00Z",expiresAt: "2026-10-07T00:00:00Z",isLifetime: false,updatedAt: nil),verifiedAt: "2026-09-07T00:00:00Z")
        let snapshot = try PremiumEntitlementSnapshot(response: response)
        #expect(snapshot.isUsable(at: Date(timeIntervalSince1970: 1788825600)))
        #expect(snapshot.source?.isAppStoreSubscription == false)
        #expect(snapshot.giftStatusText == "邀请奖励 · 有效期至 2026年10月07日")
        #expect(!snapshot.isUsable(at: Date(timeIntervalSince1970: 1800000000)))
        let cache = InMemoryPremiumEntitlementCache()
        try cache.save(snapshot)
        #expect(try cache.load(userID: "B") == nil)
    }
    @Test func invitationHintIsNotEntitlementAndCanBeCleared() throws {
        defer { ReferralInvitationStore.clear() }
        try ReferralInvitationStore.prepare("ABCDEF0123456789ABCDEF01")
        #expect(ReferralInvitationStore.code == "abcdef0123456789abcdef01")
        #expect(throws: (any Error).self) { try ReferralInvitationStore.prepare("<script>") }
        #expect(!ReferralInvitationStore.receive(URL(string:"https://attacker.example/invite/abcdef0123456789abcdef01")!))
        ReferralInvitationStore.clear()
        #expect(ReferralInvitationStore.code == nil)
    }
}
