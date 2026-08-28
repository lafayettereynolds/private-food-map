import Foundation
import Testing
@testable import TasteMap

@Suite("P4-H Premium entitlement foundation")
@MainActor
struct P4HPremiumEntitlementTests {
    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    @Test("1-3 contract represents free, Premium, unknown/loading, expired and grace states")
    func membershipStatesAndContract() throws {
        #expect(Set(MembershipStatus.allCases) == Set([
            .loading, .unknown, .free, .premium, .expired, .gracePeriod,
        ]))
        let premium = try PremiumEntitlementSnapshot(response: response(
            userID: "tm_a", state: .active, source: .appStoreYearly,
            kind: .annualSubscription, expiresAt: now.addingTimeInterval(86_400)
        ))
        #expect(premium.userID == "tm_a")
        #expect(premium.isUsable(at: now))
        #expect(premium.kind == .annualSubscription)

        #expect(throws: PremiumEntitlementContractError.invalidResponse) {
            _ = try PremiumEntitlementSnapshot(response: response(
                userID: "tm_a", state: .free, source: .adminGrant,
                kind: .fixedTerm, forcePremium: true
            ))
        }
    }

    @Test("4 cache is scoped by Taste Map user ID")
    func userScopedCache() throws {
        let cache = InMemoryPremiumEntitlementCache()
        let a = premiumSnapshot(userID: "tm_a")
        let b = PremiumEntitlementSnapshot(userID: "tm_b", state: .free, verifiedAt: now)
        try cache.save(a); try cache.save(b)
        #expect(try cache.load(userID: "tm_a") == a)
        #expect(try cache.load(userID: "tm_b") == b)
        #expect(try cache.load(userID: "tm_c") == nil)
    }

    @Test("5-6 logout clears active state and user switch cannot inherit Premium")
    func logoutAndUserSwitch() async {
        let api = SequencePremiumAPI(values: [
            .success(response(userID: "tm_a", state: .active, source: .adminGrant, kind: .lifetime)),
            .success(response(userID: "tm_b", state: .free)),
        ])
        let service = service(api: api)
        await service.activate(userID: "tm_a")
        #expect(service.membershipStatus == .premium)
        service.sessionDidEnd()
        #expect(service.activeUserID == nil)
        #expect(service.membershipStatus == .unknown)
        await service.activate(userID: "tm_b")
        #expect(service.membershipStatus == .free)
        #expect(service.snapshot?.userID == "tm_b")
    }

    @Test("7 recently verified Premium stays available offline")
    func offlineVerifiedPremium() async throws {
        let cache = InMemoryPremiumEntitlementCache(values: ["tm_a": premiumSnapshot(userID: "tm_a")])
        let service = service(api: SequencePremiumAPI(values: [.failure(TestError.offline)]), cache: cache)
        await service.activate(userID: "tm_a")
        #expect(service.membershipStatus == .premium)
        #expect(service.isUsingOfflineCache)
        #expect(service.access(for: .annualRecap) == .allowed)
    }

    @Test("8 stale cache is not trusted indefinitely")
    func staleCachePolicy() async {
        let stale = PremiumEntitlementSnapshot(
            userID: "tm_a", state: .active, source: .adminGrant, kind: .lifetime,
            startsAt: now.addingTimeInterval(-900_000), updatedAt: now.addingTimeInterval(-900_000),
            verifiedAt: now.addingTimeInterval(-8 * 86_400)
        )
        let cache = InMemoryPremiumEntitlementCache(values: ["tm_a": stale])
        let service = service(api: SequencePremiumAPI(values: [.failure(TestError.offline)]), cache: cache)
        await service.activate(userID: "tm_a")
        #expect(service.membershipStatus == .unknown)
        #expect(service.access(for: .annualRecap) == .loading)
    }

    @Test("9-10 authoritative online Free overrides cached Premium")
    func serverFreeOverridesCache() async throws {
        let cache = InMemoryPremiumEntitlementCache(values: ["tm_a": premiumSnapshot(userID: "tm_a")])
        let service = service(
            api: SequencePremiumAPI(values: [.success(response(userID: "tm_a", state: .free))]),
            cache: cache
        )
        await service.activate(userID: "tm_a")
        #expect(service.membershipStatus == .free)
        #expect(service.access(for: .fullTasteProfile) == .denied)
        #expect(try cache.load(userID: "tm_a")?.isPremium == false)
    }

    @Test("11-12 Development override is policy-isolated from Release and Production")
    func developmentOverrideSafety() {
        #expect(DevelopmentPremiumOverridePolicy.isAvailable(buildIsDebug: true, environment: .development))
        #expect(!DevelopmentPremiumOverridePolicy.isAvailable(buildIsDebug: false, environment: .development))
        #expect(!DevelopmentPremiumOverridePolicy.isAvailable(buildIsDebug: true, environment: .production))
    }

    @Test("13-15 every formally confirmed Premium feature has one stable registry entry")
    func featureRegistryAndAccess() {
        #expect(PremiumFeatureRegistry.definitions.count == PremiumFeature.allCases.count)
        #expect(Set(PremiumFeatureRegistry.definitions.map(\.feature)) == Set(PremiumFeature.allCases))
        for feature in PremiumFeature.allCases {
            #expect(!feature.rawValue.isEmpty)
            #expect(PremiumFeatureAccessPolicy.decision(
                for: feature, membershipStatus: .free
            ) == .denied)
            #expect(PremiumFeatureAccessPolicy.decision(
                for: feature, membershipStatus: .premium
            ) == .allowed)
        }
        #expect(!PremiumFeature.allCases.map(\.rawValue).contains("restaurant_search"))
        #expect(!PremiumFeature.allCases.map(\.rawValue).contains("restaurant_lists"))
        #expect(!PremiumFeature.allCases.map(\.rawValue).contains("restaurant_roulette"))
    }

    @Test("16-20 UI, direct navigation, analyzer and Poster operations share the same policy")
    func noAccessBypass() {
        for operation in [
            PremiumProtectedOperation.view, .analyze, .deepLink,
            .posterRender, .posterSave, .posterShare,
        ] {
            #expect(PremiumFeatureAccessPolicy.decision(
                for: .annualRecap, operation: operation, membershipStatus: .free
            ) == .denied)
            #expect(PremiumFeatureAccessPolicy.decision(
                for: .annualRecap, operation: operation, membershipStatus: .premium
            ) == .allowed)
        }
        #expect(PremiumFeatureRegistry.definition(for: .annualRecap).posterProtected)
        #expect(PremiumFeatureRegistry.definition(for: .fullTasteProfile).posterProtected)
    }

    @Test("Photo entitlement keeps the formal 3/20 limits")
    func photoLimits() {
        #expect(PremiumFeatureAccessPolicy.visitPhotoLimit(membershipStatus: .free) == 3)
        #expect(PremiumFeatureAccessPolicy.visitPhotoLimit(membershipStatus: .premium) == 20)
        #expect(PremiumFeatureAccessPolicy.visitPhotoLimit(membershipStatus: .unknown) == 3)
    }

    @Test("21-30 unconfigured Store provider has no fake products, price, purchase, or restore success")
    func unconfiguredPurchaseProvider() async {
        let provider = UnconfiguredMembershipPurchaseProvider()
        #expect(provider.capabilities.isEmpty)
        await #expect(throws: MembershipPurchaseError.notConfigured) {
            _ = try await provider.purchase(productID: "not-a-real-product")
        }
        await #expect(throws: MembershipPurchaseError.notConfigured) {
            _ = try await provider.restore()
        }
        do {
            #expect(try await provider.products().isEmpty)
        } catch {
            Issue.record("Unconfigured product loading should be an explicit empty state: \(error)")
        }
    }

    @Test("37-42 two devices refresh the same user independently and revoke wins on reconnect")
    func multiDeviceAndRevoke() async {
        let premium = response(userID: "tm_a", state: .active, source: .adminGrant, kind: .lifetime)
        let free = response(userID: "tm_a", state: .free)
        let deviceOne = service(api: SequencePremiumAPI(values: [.success(premium), .success(free)]))
        let deviceTwo = service(api: SequencePremiumAPI(values: [.success(premium), .success(free)]))
        await deviceOne.activate(userID: "tm_a")
        await deviceTwo.activate(userID: "tm_a")
        #expect(deviceOne.membershipStatus == .premium)
        #expect(deviceTwo.membershipStatus == .premium)
        await deviceOne.refresh(); await deviceTwo.refresh()
        #expect(deviceOne.membershipStatus == .free)
        #expect(deviceTwo.membershipStatus == .free)
    }

    private func service(
        api: SequencePremiumAPI,
        cache: any PremiumEntitlementCaching = InMemoryPremiumEntitlementCache()
    ) -> PremiumEntitlementService {
        PremiumEntitlementService(
            api: api,
            cache: cache,
            environment: .development,
            cacheMaximumAge: 7 * 86_400,
            now: { now }
        )
    }

    private func premiumSnapshot(userID: String) -> PremiumEntitlementSnapshot {
        PremiumEntitlementSnapshot(
            userID: userID, state: .active, source: .adminGrant, kind: .lifetime,
            startsAt: now.addingTimeInterval(-86_400), updatedAt: now, verifiedAt: now
        )
    }

    private func response(
        userID: String,
        state: PremiumEntitlementState,
        source: PremiumEntitlementSource? = nil,
        kind: PremiumEntitlementKind = .unspecified,
        expiresAt: Date? = nil,
        forcePremium: Bool? = nil
    ) -> PremiumEntitlementResponseV1 {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return PremiumEntitlementResponseV1(
            apiVersion: 1,
            userId: userID,
            entitlement: PremiumEntitlementDTO(
                state: state,
                isPremium: forcePremium ?? state.isAccessActive,
                source: source,
                kind: kind,
                startsAt: state.isAccessActive ? formatter.string(from: now.addingTimeInterval(-86_400)) : nil,
                expiresAt: expiresAt.map(formatter.string),
                isLifetime: kind == .lifetime,
                updatedAt: formatter.string(from: now)
            ),
            verifiedAt: formatter.string(from: now)
        )
    }
}

@MainActor
private final class SequencePremiumAPI: PremiumEntitlementAPI, @unchecked Sendable {
    private var values: [Result<PremiumEntitlementResponseV1, Error>]

    init(values: [Result<PremiumEntitlementResponseV1, Error>]) {
        self.values = values
    }

    func entitlement() async throws -> PremiumEntitlementResponseV1 {
        guard !values.isEmpty else { throw TestError.noResponse }
        return try values.removeFirst().get()
    }
}

private enum TestError: Error {
    case offline
    case noResponse
}
