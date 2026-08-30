import Foundation
import StoreKitTest
import Testing
@testable import TasteMap

@Suite("Task 08 Premium commerce")
@MainActor
struct Task08PremiumCommerceTests {
    @Test("Worker catalog contract carries appAccountToken and product references without price")
    func catalogContract() throws {
        let data = Data(#"""
        {
          "apiVersion":1,
          "configured":true,
          "appAccountToken":"11111111-1111-4111-8111-111111111111",
          "products":[
            {"id":"dev.tastemap.storekit.monthly","period":"monthly"},
            {"id":"dev.tastemap.storekit.yearly","period":"annual"}
          ]
        }
        """#.utf8)
        let value = try JSONDecoder().decode(PremiumCommerceConfigurationV1.self, from: data)
        #expect(value.apiVersion == 1)
        #expect(value.appAccountToken.uuidString.lowercased() == "11111111-1111-4111-8111-111111111111")
        #expect(value.products.map(\.period) == [.monthly, .annual])
        #expect(!String(decoding: data, as: UTF8.self).contains("price"))
    }

    @Test("purchase outcomes distinguish completed, pending, and cancellation")
    func purchaseOutcomes() {
        let values: [MembershipPurchaseOutcome] = [.completed, .pending, .userCancelled]
        #expect(Set(values).count == 3)
        let pending = MembershipPurchaseResult(
            transactionID: nil, requiresEntitlementRefresh: false, outcome: .pending
        )
        #expect(pending.outcome == .pending)
        #expect(!pending.requiresEntitlementRefresh)
    }

    @Test("service activates and clears exactly one purchase provider across user switch and logout")
    func lifecycleIsolation() async {
        let provider = PurchaseProviderSpy()
        let service = PremiumEntitlementService(
            api: CommercePremiumAPI(),
            cache: InMemoryPremiumEntitlementCache(),
            purchaseProvider: provider,
            environment: .development
        )
        await service.activate(userID: "tm_a")
        await service.activate(userID: "tm_b")
        service.sessionDidEnd()
        await Task.yield()
        #expect(await provider.activations == ["tm_a", "tm_b"])
        #expect(await provider.logoutCount == 1)
        #expect(service.activeUserID == nil)
    }

    @Test("local StoreKit fixture is Development-only and declares no formal production product ID")
    func storeKitFixture() throws {
        let url = try #require(Bundle(for: BundleProbe.self).url(
            forResource: "TasteMapDevelopment", withExtension: "storekit"
        ))
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let groups = try #require(object["subscriptionGroups"] as? [[String: Any]])
        let subscriptions = groups.flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }
        #expect(Set(subscriptions.compactMap { $0["productID"] as? String }) == [
            "dev.tastemap.storekit.monthly", "dev.tastemap.storekit.yearly",
        ])
        #expect(subscriptions.allSatisfy { (($0["productID"] as? String) ?? "").hasPrefix("dev.") })
    }

    @Test("local StoreKit session opens the Development fixture and clears simulated transactions")
    func localStoreKitSession() throws {
        let configurationURL = try #require(Bundle(for: BundleProbe.self).url(
            forResource: "TasteMapDevelopment", withExtension: "storekit"
        ))
        let session = try SKTestSession(contentsOf: configurationURL)
        session.disableDialogs = true
        session.clearTransactions()
        defer {
            session.clearTransactions()
            session.resetToDefaultState()
        }

        #expect(session.allTransactions().isEmpty)
        session.resetToDefaultState()
        session.clearTransactions()
        #expect(session.allTransactions().isEmpty)
    }
}

private final class BundleProbe {}

@MainActor
private struct CommercePremiumAPI: PremiumEntitlementAPI {
    func entitlement() async throws -> PremiumEntitlementResponseV1 {
        PremiumEntitlementResponseV1(
            apiVersion: 1,
            userId: "tm_a",
            entitlement: PremiumEntitlementDTO(
                state: .free, isPremium: false, source: nil, kind: .unspecified,
                startsAt: nil, expiresAt: nil, isLifetime: false, updatedAt: nil
            ),
            verifiedAt: ISO8601DateFormatter().string(from: .now)
        )
    }
}

private actor PurchaseProviderSpy: MembershipPurchaseProviding {
    nonisolated let capabilities: MembershipPurchaseCapabilities = []
    private(set) var activations: [String] = []
    private(set) var logoutCount = 0

    func activate(userID: String) async { activations.append(userID) }
    func sessionDidEnd(userID: String?) async { logoutCount += 1 }
    func products() async throws -> [MembershipProduct] { [] }
    func purchase(productID: String) async throws -> MembershipPurchaseResult {
        throw MembershipPurchaseError.notConfigured
    }
    func restore() async throws -> MembershipPurchaseResult { throw MembershipPurchaseError.notConfigured }
    func manageSubscription() async throws { throw MembershipPurchaseError.notConfigured }
}
