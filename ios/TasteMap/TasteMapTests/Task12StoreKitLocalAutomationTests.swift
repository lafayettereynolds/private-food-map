import Foundation
import Testing
@testable import TasteMap

@MainActor
@Suite("Task 12 StoreKit configuration hardening")
struct Task12StoreKitLocalAutomationTests {
    @Test("Development catalog contains localized monthly and annual subscriptions")
    func developmentCatalog() throws {
        let root = try fixtureRoot()
        let groups = try #require(root["subscriptionGroups"] as? [[String: Any]])
        let subscriptions = groups.flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }

        #expect(Set(subscriptions.compactMap { $0["productID"] as? String }) == [
            "dev.tastemap.storekit.monthly",
            "dev.tastemap.storekit.yearly",
        ])
        #expect(Set(subscriptions.compactMap { $0["recurringSubscriptionPeriod"] as? String }) == ["P1M", "P1Y"])
        #expect(subscriptions.allSatisfy { (($0["displayPrice"] as? String) ?? "").isEmpty == false })
        #expect(subscriptions.allSatisfy { subscription in
            let localizations = subscription["localizations"] as? [[String: Any]] ?? []
            return localizations.contains { localization in
                ((localization["displayName"] as? String) ?? "").isEmpty == false
                    && ((localization["description"] as? String) ?? "").isEmpty == false
            }
        })
    }

    @Test("Development catalog is isolated from formal product configuration")
    func catalogIsolation() throws {
        let data = try fixtureData()
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("dev.tastemap.storekit.monthly"))
        #expect(text.contains("dev.tastemap.storekit.yearly"))
        #expect(text.contains("APP_STORE_") == false)
        #expect(text.contains("BEGIN PRIVATE KEY") == false)
        #expect(text.contains("Issuer ID") == false)
        #expect(text.contains("Key ID") == false)
    }

    @Test("Unconfigured Release provider fails closed for products purchase and restore")
    func unconfiguredProviderFailsClosed() async {
        let provider = UnconfiguredMembershipPurchaseProvider()
        #expect(provider.capabilities.isEmpty)
        let products = try? await provider.products()
        #expect(products == [])
        await #expect(throws: MembershipPurchaseError.notConfigured) {
            _ = try await provider.purchase(productID: "anything")
        }
        await #expect(throws: MembershipPurchaseError.notConfigured) {
            _ = try await provider.restore()
        }
    }

    private func fixtureRoot() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: fixtureData()) as? [String: Any])
    }

    private func fixtureData() throws -> Data {
        let url = try #require(Bundle(for: Task12StoreKitBundleProbe.self).url(
            forResource: "TasteMapDevelopment",
            withExtension: "storekit"
        ))
        return try Data(contentsOf: url)
    }
}

private final class Task12StoreKitBundleProbe {}
