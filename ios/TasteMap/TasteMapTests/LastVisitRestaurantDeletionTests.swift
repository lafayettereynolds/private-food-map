import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite(.serialized)
@MainActor
struct LastVisitRestaurantDeletionTests {
    private let owner = "tm_last_delete"

    private func restaurant(version: Int64 = 1) -> Restaurant {
        Restaurant(ownerUserID: owner, name: "删除边界餐厅", address: "测试地址", latitude: 30, longitude: 120,
                   remoteID: UUID().uuidString.lowercased(), serverVersion: version, syncStatus: .synced)
    }

    @Test func lastVisitCascadesOwnedGraphAndQueuesAllSyncedChildren() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = restaurant()
        let visit = Visit(ownerUserID: owner, restaurantId: restaurant.id, remoteID: "last-v", serverVersion: 2)
        let dish = Dish(ownerUserID: owner, restaurantId: restaurant.id, visitId: visit.id, name: "菜品", remoteID: "last-d", serverVersion: 2)
        let association = VisitDish(ownerUserID: owner, restaurantId: restaurant.id, visitId: visit.id, dishId: dish.id, remoteID: "last-vd", serverVersion: 2)
        let photo = PhotoAsset(ownerUserID: owner, restaurantId: restaurant.id, visitId: visit.id, kind: .visit,
                               mimeType: "image/jpeg", byteSize: 1, remoteID: "last-p", serverVersion: 2)
        context.insert(restaurant); context.insert(visit); context.insert(dish); context.insert(association); context.insert(photo)
        try context.save()
        let result = try LocalTasteMapStore(context: context).delete(visit, actorUserID: owner)
        #expect(result == restaurant.id)
        #expect(restaurant.deletedAt != nil && visit.deletedAt != nil && dish.deletedAt != nil && association.deletedAt != nil)
        #expect(photo.deletedAt != nil && photo.uploadState == .deleted)
        let reopened = ModelContext(container)
        #expect(try reopened.fetch(FetchDescriptor<Restaurant>()).allSatisfy { $0.deletedAt != nil })
        let mutations = try SwiftDataSyncQueue(context: reopened, ownerUserID: owner).allMutations()
        #expect(Set(mutations.filter { $0.operation == .delete }.map(\.entityType)) == [.photo, .visitDish, .dish, .visit, .restaurant])
        #expect(!mutations.contains { $0.operation == .upsert })
    }

    @Test func otherVisitPreservesRestaurantWhileLastUnsyncedVisitRemovesGraphAndPendingUpserts() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = restaurant(version: 0)
        context.insert(restaurant)
        try context.save()
        let store = LocalTasteMapStore(context: context)
        let first = try store.createVisit(restaurantId: restaurant.id, draft: VisitDraft(), actorUserID: owner)
        let second = try store.createVisit(restaurantId: restaurant.id, draft: VisitDraft(rating: 4), actorUserID: owner)
        #expect(try store.delete(first, actorUserID: owner) == nil)
        #expect(restaurant.deletedAt == nil)
        let restaurantID = restaurant.id
        #expect(try store.delete(second, actorUserID: owner) == restaurantID)
        let reopened = ModelContext(container)
        #expect(try reopened.fetch(FetchDescriptor<Restaurant>()).isEmpty)
        #expect(try reopened.fetch(FetchDescriptor<Visit>()).isEmpty)
        #expect(try SwiftDataSyncQueue(context: reopened, ownerUserID: owner).allMutations().isEmpty)
    }

    @Test func deletionDoesNotSweepZeroVisitRestaurantsOrAnotherOwnersRecords() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let target = restaurant()
        let stale = restaurant()
        let visit = Visit(ownerUserID: owner, restaurantId: target.id, remoteID: "v", serverVersion: 1)
        let foreignVisit = Visit(ownerUserID: "tm_foreign", restaurantId: target.id, remoteID: "foreign-v", serverVersion: 1)
        let foreignDish = Dish(ownerUserID: "tm_foreign", restaurantId: target.id, visitId: foreignVisit.id, name: "foreign", remoteID: "foreign-d", serverVersion: 1)
        context.insert(target); context.insert(stale); context.insert(visit); context.insert(foreignVisit); context.insert(foreignDish)
        try context.save()
        #expect(throws: (any Error).self) { try LocalTasteMapStore(context: context).delete(visit, actorUserID: "tm_foreign") }
        #expect(target.deletedAt == nil && visit.deletedAt == nil)
        #expect(try LocalTasteMapStore(context: context).delete(visit, actorUserID: owner) == target.id)
        #expect(stale.deletedAt == nil && foreignVisit.deletedAt == nil && foreignDish.deletedAt == nil)
        #expect(try SwiftDataSyncQueue(context: context, ownerUserID: "tm_foreign").allMutations().isEmpty)
    }

    @Test func bridgeReturnsDeletedRestaurantOnlyForFinalVisitAndMaintainsOwnerAuthorization() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let target = restaurant()
        let first = Visit(ownerUserID: owner, restaurantId: target.id, remoteID: "first", serverVersion: 1)
        let last = Visit(ownerUserID: owner, restaurantId: target.id, remoteID: "last", serverVersion: 1)
        context.insert(target); context.insert(first); context.insert(last); try context.save()
        let service = try TasteMapHybridBridgeService(container: container, ownerUserID: owner)
        var completionCount = 0
        service.didDeleteRestaurantWithVisit = { restaurantIDs, visitIDs in
            #expect(restaurantIDs.contains(target.id.uuidString.lowercased()))
            #expect(visitIDs.contains("last"))
            completionCount += 1
        }
        #expect(try service.deleteVisit(id: "first").deletedRestaurantID == nil)
        #expect(completionCount == 0)
        let result = try service.deleteVisit(id: "last")
        #expect(result.deletedRestaurantID == target.remoteID)
        #expect(result.restaurantID == result.deletedRestaurantID && completionCount == 1)
        #expect(throws: (any Error).self) { try service.restaurantDetail(id: result.restaurantID) }
        #expect(throws: (any Error).self) { try service.deleteVisit(id: "last") }
        let legacy = Data(#"{"restaurantID":"r","visitID":"v","updatedAt":"2026-09-07T00:00:00Z"}"#.utf8)
        #expect(try JSONDecoder().decode(TasteMapHybridVisitMutationResultDTO.self, from: legacy).deletedRestaurantID == nil)
    }

    @Test func lastVisitNavigationPrunesAliasesEditorAndAvoidsLateUnrelatedDestinations() throws {
        let coordinator = TasteMapHybridNavigationCoordinator()
        let profile = try TasteMapHybridRouteDTO(surface: .profile)
        let detail = try TasteMapHybridRouteDTO(surface: .restaurant, identifier: "apple_maps:shop")
        let editor = try TasteMapHybridRouteDTO(surface: .visitEdit, identifier: "visit-remote")
        _ = try coordinator.openHybrid(profile); _ = try coordinator.openHybrid(detail); _ = try coordinator.openHybrid(editor)
        let result = coordinator.completeVisitDeletion(restaurantIDs: ["local-shop", "apple_maps:shop"], visitIDs: ["visit-remote"])
        #expect(result.route == profile && result.completedAction == .restaurantDelete)
        #expect(coordinator.back().route.surface == .map)
        let cold = TasteMapHybridNavigationCoordinator(initialRoute: editor)
        #expect(cold.completeVisitDeletion(restaurantIDs: ["shop"], visitIDs: ["visit-remote"]).route.surface == .map)
        _ = try coordinator.openHybrid(detail); _ = try coordinator.openHybrid(editor)
        let other = try TasteMapHybridRouteDTO(surface: .restaurant, identifier: "unrelated")
        _ = try coordinator.openHybrid(other)
        #expect(coordinator.completeVisitDeletion(restaurantIDs: ["apple_maps:shop"], visitIDs: ["visit-remote"]).route == other)
        #expect(coordinator.back().route.surface == .map)
    }

    @Test func confirmationCopyDistinguishesLastVisitFromOrdinaryVisit() {
        #expect(RestaurantDeletionPresentation.visitMessage(isLast: true).contains("最后一次到访"))
        #expect(RestaurantDeletionPresentation.visitMessage(isLast: true).contains("一起删除"))
        #expect(RestaurantDeletionPresentation.visitMessage(isLast: false).contains("保留这家餐厅"))
        #expect(RestaurantDeletionPresentation.restaurantMessage.contains("照片"))
    }
}
