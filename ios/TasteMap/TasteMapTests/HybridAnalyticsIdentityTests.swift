import Foundation
import SwiftData
import Testing
@testable import TasteMap

@MainActor
@Suite("Hybrid Analytics identity projection", .serialized)
struct HybridAnalyticsIdentityTests {
    @Test("Profile sends only the current owner's formal directories and exact Visit association")
    func ownedDirectoriesAndVisitAssociation() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        context.insert(UserProfile(tasteMapUserID: "tm_analysis", displayName: "分析测试"))
        let companion = DiningCompanion(ownerUserId: "tm_analysis", displayName: "同名", linkedTasteMapUserId: "private-linked-user", remoteID: "remote-companion")
        let otherCompanion = DiningCompanion(ownerUserId: "tm_other", displayName: "绝不可读的目录")
        let source = RecommendationSource(ownerUserId: "tm_analysis", displayName: "同名", sourceType: .friend, linkedTasteMapUserId: "another-private-linked-user", remoteID: "formal-source")
        context.insert(companion); context.insert(otherCompanion); context.insert(source)
        context.insert(RecommendationSource(ownerUserId: "tm_other", displayName: "其他账户来源"))
        let restaurant = Restaurant(ownerUserID: "tm_analysis", name: "测试餐厅", address: "", latitude: 0, longitude: 0)
        context.insert(restaurant)
        let ownVisit = Visit(ownerUserID: "tm_analysis", restaurantId: restaurant.id,
            companionIDs: [companion.remoteID!], companionNames: ["旧名字"],
            recommendationSourceID: source.remoteID, recommendationSourceUserID: "not-the-source-id", remoteID: "own-visit")
        context.insert(ownVisit)
        context.insert(Visit(ownerUserID: "tm_other", restaurantId: restaurant.id, recommendationSourceID: "foreign-source", remoteID: "foreign-visit"))
        try context.save()
        let result = try TasteMapHybridBridgeService(container: container, ownerUserID: "tm_analysis").profileDashboard()
        let identity = try #require(result.analyticsIdentity)
        #expect(identity.ownerUserID == "tm_analysis")
        #expect(identity.recordOwnerID == "tm_analysis")
        #expect(identity.companions?.count == 1)
        #expect(identity.companions?.first?.id == companion.id.uuidString.lowercased())
        #expect(identity.companions?.first?.identifiers.contains("remote-companion") == true)
        #expect(identity.sources?.count == 1)
        #expect(identity.sources?.first?.sourceType == "friend")
        #expect(identity.visitSourceLinks?.map(\.visitID) == ["own-visit"])
        #expect(identity.visitSourceLinks?.first?.sourceID == "formal-source")
        let json = String(decoding: try JSONEncoder().encode(identity), as: UTF8.self)
        #expect(!json.contains("private-linked-user"))
        #expect(!json.contains("another-private-linked-user"))
        #expect(!json.contains("not-the-source-id"))
        #expect(!json.contains("绝不可读的目录"))
    }

    @Test("Rename, tombstone and an ID-less Visit remain distinguishable on the next snapshot")
    func renamedAndDeletedIdentityRefresh() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        context.insert(UserProfile(tasteMapUserID: "tm_analysis"))
        let companion = DiningCompanion(ownerUserId: "tm_analysis", displayName: "旧名字")
        context.insert(companion)
        let restaurant = Restaurant(ownerUserID: "tm_analysis", name: "测试餐厅", address: "", latitude: 0, longitude: 0)
        context.insert(restaurant)
        context.insert(Visit(ownerUserID: "tm_analysis", restaurantId: restaurant.id, recommendationSourceText: "旧来源文字", remoteID: "legacy-visit"))
        try context.save()
        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: "tm_analysis")
        let first = try #require(service.profileDashboard().analyticsIdentity)
        #expect(first.companions?.first?.displayName == "旧名字")
        #expect(first.sources?.isEmpty == true)
        #expect(first.visitSourceLinks?.count == 1)
        #expect(first.visitSourceLinks?.first?.sourceID == nil)
        companion.displayName = "新名字"
        companion.deletedAt = Date(timeIntervalSince1970: 1_800_000_000)
        companion.updatedAt = companion.deletedAt!
        try context.save()
        let second = try #require(service.profileDashboard().analyticsIdentity)
        #expect(second.companions?.first?.id == first.companions?.first?.id)
        #expect(second.companions?.first?.displayName == "新名字")
        #expect(second.companions?.first?.deletedAt != nil)
    }

    @Test("Bridge-v1 profile JSON without additive analytics identity still decodes")
    func oldProfileRemainsDecodable() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        container.mainContext.insert(UserProfile(tasteMapUserID: "tm_analysis"))
        try container.mainContext.save()
        let profile = try TasteMapHybridBridgeService(container: container, ownerUserID: "tm_analysis").profileDashboard()
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        object.removeValue(forKey: "analyticsIdentity")
        let decoded = try JSONDecoder().decode(TasteMapHybridProfileDTO.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.analyticsIdentity == nil)
        #expect(decoded.user.id == "tm_analysis")
    }
}
