import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("P0-B1 offline Sync Engine", .serialized)
@MainActor
struct SyncEngineTests {
    @Test("Legacy canonicalization preserves identity and rejects unsafe equivalence", arguments: [
        "success", "foreign", "deleted-parent", "pending-parent", "different-order", "changed-snapshot", "edited-peer", "missing-parent"
    ])
    func legacyCanonicalization(scenario: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Canonical-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store")
        let container = try TasteMapPersistence.makeContainer(storageURL: url)
        let context = container.mainContext
        let store = LocalTasteMapStore(context: context)
        let restaurant = try store.restaurant(for: appleCandidate(), among: [])
        let visit = try store.createVisit(restaurantId: restaurant.id, rating: nil, note: "fixture")
        try await SyncEngine(context: context, api: EchoSyncAPI()).synchronize()
        let owner = visit.ownerUserID
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let dish = Dish(ownerUserID: owner, restaurantId: restaurant.id, visitId: visit.id,
                        name: "Fixture", createdAt: date, updatedAt: date, serverVersion: 1, syncStatus: .synced)
        context.insert(dish)
        let localID = UUID()
        let local = VisitDish(id: localID, ownerUserID: owner, restaurantId: restaurant.id,
                              visitId: visit.id, dishId: dish.id, createdAt: date, updatedAt: date,
                              remoteID: localID.uuidString.lowercased())
        let canonicalID = "legacy:\(dish.remoteID!):\(visit.remoteID!)"
        let peer = VisitDish(ownerUserID: owner, restaurantId: restaurant.id, visitId: visit.id,
                             dishId: dish.id, createdAt: date, updatedAt: date, remoteID: canonicalID,
                             serverVersion: 1, syncStatus: .synced)
        context.insert(local); context.insert(peer)
        let queue = SwiftDataSyncQueue(context: context, ownerUserID: owner)
        let payload = try SyncRecordMapper.visitDishPayload(local, restaurantRemoteID: restaurant.remoteID!,
                                                            visitRemoteID: visit.remoteID!, dishRemoteID: dish.remoteID!)
        let mutation = try queue.enqueueUpsert(entityType: .visitDish, entityID: local.remoteID!, baseVersion: 0, payload: payload)
        mutation.state = .uploading
        let record = try JSONDecoder().decode(VisitDishSyncContractV1.self, from: SyncRecordMapper.visitDishPayload(
            peer, restaurantRemoteID: restaurant.remoteID!, visitRemoteID: visit.remoteID!, dishRemoteID: dish.remoteID!))
        var approved = SyncConflictSnapshotV1(apiVersion: 1, entityType: .visitDish, entityId: canonicalID,
                                               visit: nil, restaurantList: nil, restaurantListItems: [])
        approved.visitDish = .init(serverVersion: 1, record: record)
        approved.associationParents = .init(restaurantVersion: restaurant.serverVersion,
                                             visitVersion: visit.serverVersion, dishVersion: 1)
        var returned = approved
        switch scenario {
        case "deleted-parent": visit.deletedAt = date
        case "pending-parent":
            _ = try queue.enqueueUpsert(entityType: .dish, entityID: dish.remoteID!, baseVersion: 1, payload: Data())
        case "different-order": local.sortOrder = 1
        case "changed-snapshot": returned.visitDish = .init(serverVersion: 2, record: record)
        case "edited-peer": peer.updatedAt = date.addingTimeInterval(1)
        case "missing-parent": dish.remoteID = "different-parent"
        default: break
        }
        try context.save()
        let ids = try queue.allMutations().map(\.mutationID)
        let api = ConflictSnapshotAPI(snapshot: returned)
        let engine = SyncEngine(context: context, api: api, ownerUserID: scenario == "foreign" ? "foreign" : owner)
        if scenario == "success" {
            try await engine.acceptServerVersion(mutationID: mutation.mutationID, approvedSnapshot: approved)
            try await engine.acceptServerVersion(mutationID: mutation.mutationID, approvedSnapshot: approved)
            #expect(api.fetches == 1)
            #expect(local.id == localID && local.ownerUserID == owner && local.remoteID == canonicalID)
            #expect(local.serverVersion == 1 && local.syncStatus == .synced)
            #expect(local.restaurantId == restaurant.id && local.visitId == visit.id && local.dishId == dish.id)
            #expect(mutation.resolution == "canonicalized" && mutation.state == .resolved)
            #expect(mutation.payload == payload && mutation.baseVersion == 0 && mutation.resolvedServerVersion == 1)
            #expect(try context.fetch(FetchDescriptor<VisitDish>()).count == 1)
            #expect(try context.fetch(FetchDescriptor<SyncMutation>()).count == 1)
            #expect(try queue.allMutations().isEmpty)
            let reopened = try TasteMapPersistence.makeContainer(storageURL: url)
            #expect(try SwiftDataSyncQueue(context: reopened.mainContext, ownerUserID: owner).allMutations().isEmpty)
            try await SyncEngine(context: context, api: EchoSyncAPI(), ownerUserID: owner).synchronize()
            #expect(try queue.allMutations().isEmpty)
            #expect(try context.fetch(FetchDescriptor<VisitDish>()).count == 1)
        } else {
            do {
                try await engine.acceptServerVersion(mutationID: mutation.mutationID, approvedSnapshot: approved)
                Issue.record("Unsafe canonicalization accepted")
            } catch {}
            #expect(try queue.allMutations().map(\.mutationID) == ids)
            #expect(mutation.payload == payload && mutation.resolution == nil)
            #expect(local.remoteID == localID.uuidString.lowercased())
            #expect(try context.fetch(FetchDescriptor<VisitDish>()).count == 2)
        }
    }

    @Test("Accept server resolves two Visits and one List without replaying the four other mutations")
    func acceptServerThreeConflicts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AcceptServer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("TasteMap.store")
        let container = try TasteMapPersistence.makeContainer(storageURL: storageURL)
        let context = container.mainContext
        let store = LocalTasteMapStore(context: context)
        let restaurant = try store.restaurant(for: appleCandidate(), among: [])
        let first = try store.createVisit(restaurantId: restaurant.id, rating: nil, note: "first")
        let second = try store.createVisit(restaurantId: restaurant.id, rating: nil, note: "second")
        let echo = EchoSyncAPI()
        try await SyncEngine(context: context, api: echo).synchronize()
        let owner = first.ownerUserID
        let list = RestaurantList(ownerUserID: owner, title: "全球十佳", serverVersion: 1)
        context.insert(list)
        var listItems: [RestaurantListItem] = []
        var serverItems: [RestaurantListItemSyncRecordEnvelopeV1] = []
        for index in 0..<2 {
            let referenceID = "fixture-restaurant-\(index)"
            let place = try RestaurantListPlaceContractV1(globalKey: "apple_maps:\(referenceID)",
                restaurantId: referenceID, placeIdentities: [.init(provider: .appleMaps, externalId: referenceID, isPrimary: true)],
                name: "Fixture \(index)", address: "", city: "", latitude: 30, longitude: 120,
                markerPhotoId: nil, merchantImageUrl: nil, markerEmoji: "")
            let item = try RestaurantListItem(ownerUserID: owner, listID: list.id,
                listRemoteID: try #require(list.remoteID), restaurantReferenceID: referenceID,
                localRestaurantID: nil, restaurantGlobalKey: place.globalKey, restaurantSnapshot: place,
                position: index, serverVersion: 1, syncStatus: .synced)
            context.insert(item)
            listItems.append(item)
            var json = try #require(JSONSerialization.jsonObject(with: SyncRecordMapper.restaurantListItemPayload(item)) as? [String: Any])
            json["position"] = 1 - index
            let record = try JSONDecoder().decode(RestaurantListItemSyncContractV1.self, from: JSONSerialization.data(withJSONObject: json))
            serverItems.append(.init(serverVersion: 2, record: record))
        }
        let originalItemIDs = listItems.map(\.id)
        let queue = SwiftDataSyncQueue(context: context, ownerUserID: owner)
        var decisions: [(SyncMutation, SyncConflictSnapshotV1)] = []
        for (index, visit) in [first, second].enumerated() {
            let remoteID = try #require(visit.remoteID)
            let record = try #require(echo.visitRecords.first { $0.id == remoteID })
            var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
            json["visibility"] = "public"
            json["partySize"] = 2
            json["pricePerPerson"] = 71
            json["myActualSpend"] = 141
            let server = try JSONDecoder().decode(VisitSyncContractV1.self, from: JSONSerialization.data(withJSONObject: json))
            visit.visibility = .private
            let payload = try SyncRecordMapper.visitPayload(visit, restaurantRemoteID: try #require(restaurant.remoteID))
            let mutation = try queue.enqueueUpsert(entityType: .visit, entityID: remoteID, baseVersion: 0, payload: payload)
            mutation.state = .conflicted
            decisions.append((mutation, SyncConflictSnapshotV1(apiVersion: 1, entityType: .visit,
                entityId: remoteID, visit: .init(serverVersion: Int64(index + 2), record: server),
                restaurantList: nil, restaurantListItems: [])))
        }
        let listPayload = try SyncRecordMapper.restaurantListPayload(list)
        var serverList = try #require(JSONSerialization.jsonObject(with: listPayload) as? [String: Any])
        serverList["visibility"] = "public"
        let listRecord = try JSONDecoder().decode(RestaurantListSyncContractV1.self, from: JSONSerialization.data(withJSONObject: serverList))
        let listMutation = try queue.enqueueUpsert(entityType: .restaurantList, entityID: try #require(list.remoteID), baseVersion: 1, payload: listPayload)
        listMutation.state = .conflicted
        decisions.append((listMutation, .init(apiVersion: 1, entityType: .restaurantList, entityId: try #require(list.remoteID),
            visit: nil, restaurantList: .init(serverVersion: 4, record: listRecord), restaurantListItems: serverItems)))
        var protected: [SyncMutation] = []
        for index in 0..<4 {
            protected.append(try queue.enqueueUpsert(entityType: .visitDish, entityID: "protected-\(index)", baseVersion: 0, payload: Data("unchanged".utf8)))
        }
        try context.save()
        #expect(try queue.allMutations().count == 7)
        for (mutation, snapshot) in decisions {
            if mutation.entityType == .restaurantList {
                var changedJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(serverItems[0].record)) as? [String: Any])
                changedJSON["position"] = 9
                let changedItem = try JSONDecoder().decode(RestaurantListItemSyncContractV1.self,
                    from: JSONSerialization.data(withJSONObject: changedJSON))
                let changed = SyncConflictSnapshotV1(apiVersion: 1, entityType: .restaurantList,
                    entityId: snapshot.entityId, visit: nil, restaurantList: snapshot.restaurantList,
                    restaurantListItems: [.init(serverVersion: serverItems[0].serverVersion, record: changedItem), serverItems[1]])
                do {
                    try await SyncEngine(context: context, api: ConflictSnapshotAPI(snapshot: changed), ownerUserID: owner)
                        .acceptServerVersion(mutationID: mutation.mutationID, approvedSnapshot: snapshot)
                    Issue.record("Changed list membership/order must require a new decision even when list version is unchanged")
                } catch { #expect(error as? SyncEngineError == .conflictSnapshotChanged) }
                #expect(mutation.state == .conflicted && list.serverVersion == 1)
                #expect(listItems.map(\.position) == [0, 1])
            }
            let api = ConflictSnapshotAPI(snapshot: snapshot)
            let original = mutation.payload
            let engine = SyncEngine(context: context, api: api, ownerUserID: owner)
            try await engine.acceptServerVersion(mutationID: mutation.mutationID, approvedSnapshot: snapshot)
            try await engine.acceptServerVersion(mutationID: mutation.mutationID, approvedSnapshot: snapshot)
            #expect(api.fetches == 1)
            #expect(mutation.state == .resolved)
            #expect(mutation.resolution == "accept_server")
            #expect(mutation.payload == original)
            #expect(mutation.resolvedServerVersion == snapshot.serverVersion)
        }
        #expect(first.visibility == .public && second.visibility == .public)
        #expect(first.partySize == 2 && first.pricePerPerson == 71 && first.myActualSpend == 141)
        #expect(first.serverVersion == 2 && second.serverVersion == 3 && list.serverVersion == 4)
        #expect(list.id == UUID(uuidString: listRecord.id) && list.ownerUserID == owner)
        #expect(list.activeItemCount == 2 && list.visibility == .public && list.deletedAt == nil)
        #expect(listItems.map(\.id) == originalItemIDs)
        #expect(listItems.map(\.position) == [1, 0])
        #expect(listItems.allSatisfy { $0.ownerUserID == owner && $0.serverVersion == 2 && $0.deletedAt == nil })
        #expect(try queue.allMutations().count == 4)
        #expect(protected.allSatisfy { $0.state == .queued && $0.payload == Data("unchanged".utf8) && $0.baseVersion == 0 })
        #expect(try context.fetch(FetchDescriptor<Visit>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).count == 7)
        let reopenedContainer = try TasteMapPersistence.makeContainer(storageURL: storageURL)
        let reopened = reopenedContainer.mainContext
        #expect(try SwiftDataSyncQueue(context: reopened, ownerUserID: owner).allMutations().count == 4)
        #expect(try reopened.fetch(FetchDescriptor<SyncMutation>()).filter { $0.resolution == "accept_server" }.count == 3)
    }

    @Test("Accept server refuses changed snapshots, foreign owners, competing edits, unsaved work and invalidated sessions", arguments: ["changed", "foreign", "competing", "unsaved", "invalidated"])
    func acceptServerRejectsUnsafeDecision(scenario: String) async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let owner = "tm_accept_owner"
        let list = RestaurantList(ownerUserID: owner, title: "全球十佳", serverVersion: 1)
        context.insert(list)
        let payload = try SyncRecordMapper.restaurantListPayload(list)
        let record = try JSONDecoder().decode(RestaurantListSyncContractV1.self, from: payload)
        let entityID = try #require(list.remoteID)
        let snapshot = SyncConflictSnapshotV1(apiVersion: 1, entityType: .restaurantList, entityId: entityID,
            visit: nil, restaurantList: .init(serverVersion: 2, record: record), restaurantListItems: [])
        let mutation = SyncMutation(ownerUserID: owner, entityType: .restaurantList, entityID: entityID,
            operation: .upsert, payload: payload, baseVersion: 1, state: .conflicted)
        context.insert(mutation)
        if scenario == "competing" {
            context.insert(SyncMutation(ownerUserID: owner, entityType: .restaurantList, entityID: entityID,
                operation: .upsert, payload: payload, baseVersion: 1))
        }
        try context.save()
        if scenario == "unsaved" { list.title = "未保存的本地编辑" }
        let fresh = scenario == "changed"
            ? SyncConflictSnapshotV1(apiVersion: 1, entityType: .restaurantList, entityId: entityID,
                visit: nil, restaurantList: .init(serverVersion: 3, record: record), restaurantListItems: [])
            : snapshot
        let api = ConflictSnapshotAPI(snapshot: fresh)
        let engine = SyncEngine(context: context, api: api, ownerUserID: scenario == "foreign" ? "tm_other" : owner)
        do {
            try await engine.acceptServerVersion(mutationID: mutation.mutationID, approvedSnapshot: snapshot,
                decisionIsCurrent: { scenario != "invalidated" })
            Issue.record("Unsafe accept-server decision was accepted")
        } catch {
            #expect(error is SyncEngineError)
        }
        #expect(mutation.state == .conflicted && mutation.resolution == nil)
        #expect(mutation.payload == payload && mutation.baseVersion == 1)
        #expect(list.serverVersion == 1 && list.ownerUserID == owner)
        #expect(list.title == (scenario == "unsaved" ? "未保存的本地编辑" : "全球十佳"))
        #expect(try context.fetchCount(FetchDescriptor<RestaurantList>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SyncMutation>()) == (scenario == "competing" ? 2 : 1))
        if scenario == "foreign" || scenario == "unsaved" { #expect(api.fetches == 0) }
    }
    @Test("Deleting a zero-visit Restaurant after repeated HTTP 500 retries stays deleted through pull")
    func deleteAfterRepeatedUploadFailures() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalTasteMapStore(context: context)
        let restaurant = try store.restaurant(for: appleCandidate(), among: [])
        restaurant.status = .visited
        let record = try SyncRecordMapper.restaurantRecord(restaurant)
        let upload = try #require(context.fetch(FetchDescriptor<SyncMutation>()).first)
        upload.retryCount = 35
        upload.lastError = "retryable:http_500"
        upload.nextRetryAt = .distantFuture
        let originalID = upload.mutationID
        let originalPayload = upload.payload
        try store.delete(restaurant)
        let queue = SwiftDataSyncQueue(context: context)
        let deletion = try #require(queue.allMutations().first { $0.operation == .delete })
        #expect(deletion.mutationID != originalID)
        #expect(try queue.nextReadyMutation() == nil)
        #expect(RestaurantVisitStatePolicy.partition(restaurants: [restaurant], visits: []).visited.isEmpty)
        try await SyncEngine(context: context, api: EchoSyncAPI(restaurantRecords: [record], restaurantVersion: 1)).synchronize()
        #expect(restaurant.deletedAt != nil)
        #expect(upload.mutationID == originalID)
        #expect(upload.payload == originalPayload)
        #expect(deletion.baseVersion == 1)
        #expect(RestaurantVisitStatePolicy.partition(restaurants: [restaurant], visits: []).visited.isEmpty)
    }

    @Test("Deleting during an unacknowledged Restaurant upload retains a tombstone and a later delete")
    func deleteDuringUpload() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalTasteMapStore(context: context)
        let restaurant = try store.restaurant(for: appleCandidate(), among: [])
        let upload = try #require(context.fetch(FetchDescriptor<SyncMutation>()).first)
        upload.state = .uploading
        let uploadID = upload.mutationID
        try store.delete(restaurant)
        #expect(restaurant.deletedAt != nil)
        let mutations = try context.fetch(FetchDescriptor<SyncMutation>())
        #expect(mutations.contains { $0.mutationID == uploadID && $0.operation == .upsert })
        #expect(mutations.contains { $0.operation == .delete && $0.entityID == restaurant.remoteID })
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).count == 1)
    }

    @Test("A newer pull cannot restore a Restaurant whose local delete is waiting for retry")
    func pullPreservesPendingDelete() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = syncedRestaurant()
        context.insert(restaurant)
        let serverRecord = try SyncRecordMapper.restaurantRecord(restaurant)
        try LocalTasteMapStore(context: context).delete(restaurant)
        let deletion = try #require(context.fetch(FetchDescriptor<SyncMutation>()).first)
        deletion.nextRetryAt = Date.distantFuture
        try context.save()
        try await SyncEngine(context: context, api: EchoSyncAPI(restaurantRecords: [serverRecord], restaurantVersion: 2)).synchronize()
        #expect(restaurant.deletedAt != nil)
        #expect(restaurant.serverVersion == 2)
        #expect(deletion.operation == .delete)
        #expect(deletion.baseVersion == 2)
        #expect(deletion.state == .queued)
    }

    @Test("Local Restaurant and Visit push then pull with their relationship intact")
    func localCreatePushPullRoundTrip() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalTasteMapStore(context: context)
        let restaurant = try store.restaurant(for: appleCandidate(), among: [])
        let visit = try store.createVisit(restaurantId: restaurant.id, rating: nil, note: "真实记录")
        let api = EchoSyncAPI()

        try await SyncEngine(context: context, api: api).synchronize()

        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
        #expect(restaurant.serverVersion == 1)
        #expect(visit.serverVersion == 1)
        #expect(api.restaurantRecords.first?.placeIdentities.first?.provider == .appleMaps)
        #expect(api.restaurantRecords.first?.amapPoiId == nil)
        #expect(api.visitRecords.first?.restaurantId == restaurant.remoteID)
        #expect(api.visitRecords.first?.rating == nil)
    }

    @Test("P1-C Visit fields survive push and pull without duplication")
    func visitCoreFieldsRoundTrip() async throws {
        let sourceContainer = try TasteMapPersistence.makeContainer(inMemory: true)
        let sourceContext = sourceContainer.mainContext
        let store = LocalTasteMapStore(context: sourceContext)
        let restaurant = try store.restaurant(for: appleCandidate(), among: [])
        let visitedAt = Date(timeIntervalSince1970: 1_787_592_000)
        let visit = try store.createVisit(
            restaurantId: restaurant.id,
            draft: VisitDraft(
                visitedAt: visitedAt,
                diningMode: .takeout,
                partySize: 2,
                rating: 4.5,
                myActualSpend: 96.5,
                note: "P1-C sync"
            )
        )
        let api = EchoSyncAPI()
        try await SyncEngine(context: sourceContext, api: api).synchronize()

        #expect(api.visitRecords.first?.diningMode == .takeout)
        #expect(api.visitRecords.first?.partySize == 2)
        #expect(api.visitRecords.first?.visitedAt == SyncRecordMapper.dateString(visitedAt))
        #expect(visit.serverVersion == 1)

        let receivingContainer = try TasteMapPersistence.makeContainer(inMemory: true)
        let receivingContext = receivingContainer.mainContext
        try await SyncEngine(context: receivingContext, api: api).synchronize()
        let pulled = try #require(receivingContext.fetch(FetchDescriptor<Visit>()).first)

        #expect(pulled.diningMode == .takeout)
        #expect(pulled.partySize == 2)
        #expect(pulled.rating == 4.5)
        #expect(pulled.myActualSpend == Decimal(string: "96.5"))
        #expect(pulled.note == "P1-C sync")
        #expect(pulled.visitedAt == visitedAt)
        #expect(try receivingContext.fetch(FetchDescriptor<Visit>()).count == 1)
    }

    @Test("Want-to-go Restaurant survives push and pull without creating a Visit")
    func wantToGoRoundTripPreservesStatus() async throws {
        let sourceContainer = try TasteMapPersistence.makeContainer(inMemory: true)
        let sourceContext = sourceContainer.mainContext
        let restaurant = try LocalTasteMapStore(context: sourceContext).addToWantToGo(
            candidate: appleCandidate(),
            among: []
        )
        let api = EchoSyncAPI()

        try await SyncEngine(context: sourceContext, api: api).synchronize()

        #expect(restaurant.status == .wantToGo)
        #expect(api.restaurantRecords.first?.status == .wantToGo)
        #expect(try sourceContext.fetch(FetchDescriptor<Visit>()).isEmpty)

        let receivingContainer = try TasteMapPersistence.makeContainer(inMemory: true)
        let receivingContext = receivingContainer.mainContext
        try await SyncEngine(context: receivingContext, api: api).synchronize()
        let pulled = try #require(receivingContext.fetch(FetchDescriptor<Restaurant>()).first)

        #expect(pulled.status == .wantToGo)
        #expect(pulled.appleMapItemIdentifier == "apple-place-only")
        #expect(try receivingContext.fetch(FetchDescriptor<Visit>()).isEmpty)
    }

    @Test("Offline queue survives process restart and interrupted upload")
    func persistentQueueSurvivesRestart() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TasteMapSyncTests-(UUID().uuidString)")
            .appendingPathExtension("store")
        defer { removeStoreFiles(at: url) }

        do {
            let container = try persistentContainer(at: url)
            let context = container.mainContext
            let restaurant = try LocalTasteMapStore(context: context).restaurant(for: appleCandidate(), among: [])
            _ = try LocalTasteMapStore(context: context).createVisit(restaurantId: restaurant.id)
            let mutations = try context.fetch(FetchDescriptor<SyncMutation>())
            #expect(mutations.count == 2)
            mutations.first?.state = .uploading
            try context.save()
        }

        let reopened = try persistentContainer(at: url)
        let context = reopened.mainContext
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).count == 2)
        try await SyncEngine(context: context, api: EchoSyncAPI()).synchronize()
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
    }

    @Test("Lost push response retries the exact same mutation ID")
    func lostResponseKeepsMutationIdentity() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = try LocalTasteMapStore(context: context).restaurant(for: appleCandidate(), among: [])
        _ = try LocalTasteMapStore(context: context).createVisit(restaurantId: restaurant.id)
        let api = ResponseLostOnceAPI()
        let firstAttempt = Date(timeIntervalSince1970: 1_800_000_000)

        do {
            try await SyncEngine(context: context, api: api, now: { firstAttempt }).synchronize()
            Issue.record("Expected the simulated lost push response to fail")
        } catch let failure as SyncStageFailure {
            #expect(failure.stage == .mutationPush)
            #expect(failure.underlyingError is ResponseLostOnceAPI.ExpectedFailure)
        } catch {
            Issue.record("Expected a stage-aware Sync failure, got \(type(of: error))")
        }
        let retainedID = try #require(
            context.fetch(FetchDescriptor<SyncMutation>()).first(where: { $0.retryCount == 1 })?.mutationID
        )
        try await SyncEngine(
            context: context,
            api: api,
            now: { firstAttempt.addingTimeInterval(10) }
        ).synchronize()

        #expect(api.firstMutationID == retainedID.uuidString.lowercased())
        #expect(api.retriedMutationID == api.firstMutationID)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
    }

    @Test("Server tombstone deletes locally without hard deleting history")
    func serverTombstoneAppliesLocally() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = syncedRestaurant()
        context.insert(restaurant)
        try context.save()
        let api = EchoSyncAPI(tombstones: [SyncTombstoneV1(
            entityType: .restaurant,
            entityId: restaurant.remoteID!,
            serverVersion: 2,
            deletedAt: "2026-08-27T08:00:00.000Z"
        )])

        try await SyncEngine(context: context, api: api).synchronize()

        #expect(restaurant.deletedAt != nil)
        #expect(restaurant.serverVersion == 2)
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).count == 1)
    }

    @Test("Stale local update conflicts and cannot resurrect a server deletion")
    func staleUpdateCannotResurrectDeletion() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = syncedRestaurant()
        context.insert(restaurant)
        try LocalTasteMapStore(context: context).update(
            restaurant,
            name: "离线旧设备改名",
            address: restaurant.address,
            latitude: restaurant.latitude,
            longitude: restaurant.longitude
        )
        let api = ConflictThenTombstoneAPI(tombstone: SyncTombstoneV1(
            entityType: .restaurant,
            entityId: restaurant.remoteID!,
            serverVersion: 2,
            deletedAt: "2026-08-27T08:00:00.000Z"
        ))

        try await SyncEngine(context: context, api: api).synchronize()

        #expect(restaurant.deletedAt != nil)
        #expect(restaurant.serverVersion == 2)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).first?.state == .conflicted)
    }

    private func appleCandidate() -> RestaurantCandidate {
        RestaurantCandidate(
            name: "Apple 地图真实餐厅",
            address: "中山路 1 号",
            latitude: 30.25,
            longitude: 120.16,
            appleMapItemIdentifier: "apple-place-only"
        )
    }

    private func syncedRestaurant() -> Restaurant {
        Restaurant(
            name: "已同步餐厅",
            address: "同步地址",
            latitude: 30,
            longitude: 120,
            appleMapItemIdentifier: "apple-synced",
            remoteID: "remote-restaurant",
            serverVersion: 1,
            lastSyncedAt: .now,
            syncStatus: .synced
        )
    }

    private func persistentContainer(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "TasteMapSyncTests",
            schema: TasteMapPersistence.schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: TasteMapPersistence.schema, configurations: [configuration])
    }

    private func removeStoreFiles(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
    }
}

@MainActor
private final class ConflictSnapshotAPI: SyncAPI {
    let snapshot: SyncConflictSnapshotV1
    var fetches = 0
    init(snapshot: SyncConflictSnapshotV1) { self.snapshot = snapshot }
    func conflictSnapshot(entityType: SyncEntityType, entityID: String) async throws -> SyncConflictSnapshotV1 {
        fetches += 1
        return snapshot
    }
    func push(_ request: SyncPushRequestV1) async throws -> SyncPushResponseV1 {
        Issue.record("Resolution must not push")
        throw SyncAPIError.invalidResponse
    }
    func pull(cursor: String, limit: Int) async throws -> SyncPullResponseV1 {
        Issue.record("Resolution must not run a normal pull pass")
        throw SyncAPIError.invalidResponse
    }
}

private final class EchoSyncAPI: SyncAPI {
    private let restaurantVersion: Int64
    private(set) var restaurantRecords: [RestaurantJSONContractV1]
    private(set) var visitRecords: [VisitSyncContractV1]
    private var tombstones: [SyncTombstoneV1]
    private var revision: Int64 = 0

    init(
        restaurantRecords: [RestaurantJSONContractV1] = [],
        visitRecords: [VisitSyncContractV1] = [],
        tombstones: [SyncTombstoneV1] = [],
        restaurantVersion: Int64 = 1
    ) {
        self.restaurantRecords = restaurantRecords
        self.visitRecords = visitRecords
        self.tombstones = tombstones
        self.restaurantVersion = restaurantVersion
    }

    func push(_ request: SyncPushRequestV1) async throws -> SyncPushResponseV1 {
        let acknowledgements = request.mutations.map { mutation in
            revision += 1
            if case .restaurant(let record) = mutation.payload {
                restaurantRecords.removeAll { $0.id == record.id }
                restaurantRecords.append(record)
            }
            if case .visit(let record) = mutation.payload {
                visitRecords.removeAll { $0.id == record.id }
                visitRecords.append(record)
            }
            return SyncMutationAcknowledgementV1(
                mutationId: mutation.mutationId,
                entityType: mutation.entityType,
                entityId: mutation.entityId,
                status: .applied,
                duplicate: false,
                serverVersion: mutation.baseVersion + 1,
                revision: revision,
                conflictReason: nil
            )
        }
        return SyncPushResponseV1(apiVersion: 1, acknowledgements: acknowledgements, serverTime: "2026-08-27T08:00:00.000Z")
    }

    func pull(cursor: String, limit: Int) async throws -> SyncPullResponseV1 {
        let restaurantEnvelopes = restaurantRecords.map { RestaurantSyncRecordEnvelopeV1(serverVersion: restaurantVersion, record: $0) }
        let visitEnvelopes = visitRecords.map { VisitSyncRecordEnvelopeV1(serverVersion: 1, record: $0) }
        return SyncPullResponseV1(
            apiVersion: 1,
            schemaVersion: 1,
            restaurants: restaurantEnvelopes,
            visits: visitEnvelopes,
            tombstones: tombstones,
            nextCursor: String(max(revision, Int64(tombstones.count))),
            hasMore: false,
            serverTime: "2026-08-27T08:00:00.000Z"
        )
    }
}

@MainActor
private final class ConflictThenTombstoneAPI: SyncAPI {
    let tombstone: SyncTombstoneV1

    init(tombstone: SyncTombstoneV1) {
        self.tombstone = tombstone
    }

    func push(_ request: SyncPushRequestV1) async throws -> SyncPushResponseV1 {
        let mutation = request.mutations[0]
        return SyncPushResponseV1(
            apiVersion: 1,
            acknowledgements: [SyncMutationAcknowledgementV1(
                mutationId: mutation.mutationId,
                entityType: mutation.entityType,
                entityId: mutation.entityId,
                status: .conflict,
                duplicate: false,
                serverVersion: tombstone.serverVersion,
                revision: nil,
                conflictReason: "server_version_mismatch"
            )],
            serverTime: tombstone.deletedAt
        )
    }

    func pull(cursor: String, limit: Int) async throws -> SyncPullResponseV1 {
        SyncPullResponseV1(
            apiVersion: 1, schemaVersion: 1, restaurants: [], visits: [],
            tombstones: [tombstone], nextCursor: "2", hasMore: false, serverTime: tombstone.deletedAt
        )
    }
}

@MainActor
private final class ResponseLostOnceAPI: SyncAPI {
    struct ExpectedFailure: Error {}

    private(set) var firstMutationID: String?
    private(set) var retriedMutationID: String?
    private var shouldLoseResponse = true

    func push(_ request: SyncPushRequestV1) async throws -> SyncPushResponseV1 {
        let mutation = request.mutations[0]
        if shouldLoseResponse {
            shouldLoseResponse = false
            firstMutationID = mutation.mutationId
            throw ExpectedFailure()
        }
        if mutation.mutationId == firstMutationID { retriedMutationID = mutation.mutationId }
        return SyncPushResponseV1(
            apiVersion: 1,
            acknowledgements: [SyncMutationAcknowledgementV1(
                mutationId: mutation.mutationId,
                entityType: mutation.entityType,
                entityId: mutation.entityId,
                status: .applied,
                duplicate: mutation.mutationId == firstMutationID,
                serverVersion: mutation.baseVersion + 1,
                revision: 1,
                conflictReason: nil
            )],
            serverTime: "2027-01-15T08:00:00.000Z"
        )
    }

    func pull(cursor: String, limit: Int) async throws -> SyncPullResponseV1 {
        SyncPullResponseV1(
            apiVersion: 1, schemaVersion: 1, restaurants: [], visits: [], tombstones: [],
            nextCursor: cursor, hasMore: false, serverTime: "2027-01-15T08:00:00.000Z"
        )
    }
}
