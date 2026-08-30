import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("F1-C4 formal backup import flow", .serialized)
@MainActor
struct BackupImportFlowTests {
    private let userID = "tm_f1c4_user"

    @Test("Backup v1 uses the formal state machine and imports linked Restaurant and Visit")
    func backupV1Import() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let coordinator = try await plannedCoordinator(
            container: container,
            fixture: .backupV1
        )

        #expect(coordinator.state == .readyToImport)
        coordinator.prepareFinalConfirmation()
        #expect(coordinator.state == .confirming)
        coordinator.execute(currentUserIDAtConfirmation: userID)
        await coordinator.waitForCurrentOperation()

        #expect(coordinator.state == .completed)
        let restaurants = try container.mainContext.fetch(FetchDescriptor<Restaurant>())
        let visits = try container.mainContext.fetch(FetchDescriptor<Visit>())
        #expect(coordinator.result?.writtenEntityCount == 2)
        #expect(coordinator.result?.syncStatus == .queued(2))
        #expect(restaurants.count == 1)
        #expect(visits.count == 1)
        #expect(visits.first?.restaurantId == restaurants.first?.id)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<SyncMutation>()) == 2)
    }

    @Test("Legacy Web v4 completes local Restaurant and Visit import before cloud sync")
    func legacyLocalImport() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let coordinator = try await plannedCoordinator(container: container)
        try await executeReadyPlan(coordinator)

        let restaurants = try container.mainContext.fetch(FetchDescriptor<Restaurant>())
        let visits = try container.mainContext.fetch(FetchDescriptor<Visit>())
        let mutations = try container.mainContext.fetch(FetchDescriptor<SyncMutation>())
        #expect(restaurants.count == 1)
        #expect(visits.count == 1)
        #expect(visits.first?.restaurantId == restaurants.first?.id)
        #expect(mutations.count == 2)
        #expect(mutations.allSatisfy { $0.state == .queued })
        #expect(coordinator.result?.entity(.restaurant).created == 1)
        #expect(coordinator.result?.entity(.visit).created == 1)
        #expect(coordinator.result?.syncStatus == .queued(2))

        let record = try #require(restaurants.first?.remoteRecordData)
        #expect(try JSONDecoder().decode(RestaurantJSONContractV1.self, from: record).userId == userID)
    }

    @Test("Review queue supports explicit merge, create, and skip with no default choice", arguments: [
        ("merge", 1),
        ("create", 2),
        ("skip", 1),
    ])
    func restaurantReviewChoices(optionID: String, expectedRestaurantCount: Int) async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        container.mainContext.insert(try probableLocalRestaurant())
        try container.mainContext.save()

        let coordinator = try await plannedCoordinator(container: container)
        guard case let .reviewRequired(completed, total) = coordinator.state else {
            Issue.record("Expected explicit Restaurant review")
            return
        }
        #expect(completed == 0)
        #expect(total >= 1)
        let item = try #require(coordinator.currentReviewItem)
        #expect(item.entityType == .restaurant)
        let option = try #require(item.options.first { $0.id == optionID })
        coordinator.select(option, for: item)
        coordinator.makeAllRemainingNewWhereAvailable()
        #expect(coordinator.state == .readyToImport)
        try await executeReadyPlan(coordinator)

        #expect(try container.mainContext.fetchCount(FetchDescriptor<Restaurant>()) == expectedRestaurantCount)
        if optionID == "skip" {
            #expect(try container.mainContext.fetchCount(FetchDescriptor<Visit>()) == 0)
        }
    }

    @Test("Double confirmation starts at most one transaction")
    func doubleExecuteIsSingleFlight() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let coordinator = try await plannedCoordinator(container: container)
        coordinator.prepareFinalConfirmation()
        coordinator.execute(currentUserIDAtConfirmation: userID)
        coordinator.execute(currentUserIDAtConfirmation: userID)
        await coordinator.waitForCurrentOperation()

        #expect(coordinator.state == .completed)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Restaurant>()) == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Visit>()) == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<SyncMutation>()) == 2)
    }

    @Test("Injected transaction failure leaves all existing business data unchanged")
    func transactionFailureIsAtomic() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let existing = DiningCompanion(ownerUserId: userID, displayName: "Existing")
        container.mainContext.insert(existing)
        try container.mainContext.save()
        let coordinator = try await plannedCoordinator(
            container: container,
            failurePoint: .beforeSave
        )
        coordinator.prepareFinalConfirmation()
        coordinator.execute(currentUserIDAtConfirmation: userID)
        await coordinator.waitForCurrentOperation()

        guard case let .failed(failure) = coordinator.state else {
            Issue.record("Expected a safe transaction failure")
            return
        }
        #expect(failure.existingDataUnchanged)
        #expect(failure.code == "transaction_injected_failure")
        #expect(try container.mainContext.fetchCount(FetchDescriptor<DiningCompanion>()) == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Restaurant>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Visit>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<SyncMutation>()) == 0)
    }

    @Test("Stale plan and switched account are rejected before imported records commit")
    func finalSafetyRevalidation() async throws {
        do {
            let container = try TasteMapPersistence.makeContainer(inMemory: true)
            let coordinator = try await plannedCoordinator(container: container)
            container.mainContext.insert(DiningCompanion(ownerUserId: userID, displayName: "Late change"))
            try container.mainContext.save()
            coordinator.prepareFinalConfirmation()
            coordinator.execute(currentUserIDAtConfirmation: userID)
            await coordinator.waitForCurrentOperation()
            #expect(coordinator.state == .planStale)
            #expect(try container.mainContext.fetchCount(FetchDescriptor<Restaurant>()) == 0)
            #expect(try container.mainContext.fetchCount(FetchDescriptor<Visit>()) == 0)
        }

        do {
            let container = try TasteMapPersistence.makeContainer(inMemory: true)
            let coordinator = try await plannedCoordinator(container: container)
            coordinator.prepareFinalConfirmation()
            coordinator.execute(currentUserIDAtConfirmation: "tm_other_user")
            await coordinator.waitForCurrentOperation()
            guard case let .failed(failure) = coordinator.state else {
                Issue.record("Expected switched-user failure")
                return
            }
            #expect(failure.code == "user_changed")
            #expect(try container.mainContext.fetchCount(FetchDescriptor<Restaurant>()) == 0)
            #expect(try container.mainContext.fetchCount(FetchDescriptor<Visit>()) == 0)
        }
    }

    @Test("Pre-transaction cancellation is allowed and writes nothing")
    func cancellationBeforeTransaction() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let input = BackupImportDevelopmentFixture.legacyValid.input
        let coordinator = BackupImportFlowCoordinator(
            container: container,
            currentTasteMapUserID: userID
        )
        coordinator.readAndPreflight(
            data: input.data,
            fileName: input.fileName,
            fixtureDelay: .seconds(10)
        )
        coordinator.cancelBeforeTransaction()
        #expect(coordinator.state == .cancelled)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Restaurant>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<SyncMutation>()) == 0)
    }

    @Test("Offline import and queued mutations survive an app-style persistent-store restart")
    func offlineRestart() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("F1C4-Restart-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("TasteMap.store")

        do {
            let container = try TasteMapPersistence.makeContainer(storageURL: storeURL)
            let coordinator = try await plannedCoordinator(container: container)
            try await executeReadyPlan(coordinator)
        }
        do {
            let restarted = try TasteMapPersistence.makeContainer(storageURL: storeURL)
            let restaurants = try restarted.mainContext.fetch(FetchDescriptor<Restaurant>())
            let visits = try restarted.mainContext.fetch(FetchDescriptor<Visit>())
            #expect(restaurants.count == 1)
            #expect(visits.count == 1)
            #expect(visits.first?.restaurantId == restaurants.first?.id)
            #expect(try restarted.mainContext.fetchCount(FetchDescriptor<SyncMutation>()) == 2)
        }
    }

    @Test("Import reads and writes only the authenticated Taste Map user's graph")
    func currentUserIsolation() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let other = DiningCompanion(ownerUserId: "tm_other_user", displayName: "Other User Record")
        container.mainContext.insert(other)
        try container.mainContext.save()

        let coordinator = try await plannedCoordinator(container: container)
        try await executeReadyPlan(coordinator)

        let companions = try container.mainContext.fetch(FetchDescriptor<DiningCompanion>())
        let restaurant = try #require(container.mainContext.fetch(FetchDescriptor<Restaurant>()).first)
        let record = try #require(restaurant.remoteRecordData)
        let contract = try JSONDecoder().decode(RestaurantJSONContractV1.self, from: record)
        #expect(companions.count == 1)
        #expect(companions.first?.ownerUserId == "tm_other_user")
        #expect(contract.userId == userID)
    }

    private func plannedCoordinator(
        container: ModelContainer,
        fixture: BackupImportDevelopmentFixture = .legacyValid,
        failurePoint: BackupImportFailurePoint? = nil
    ) async throws -> BackupImportFlowCoordinator {
        let input = fixture.input
        let coordinator = BackupImportFlowCoordinator(
            container: container,
            currentTasteMapUserID: userID,
            injectedFailurePoint: failurePoint
        )
        coordinator.readAndPreflight(data: input.data, fileName: input.fileName)
        await coordinator.waitForCurrentOperation()
        #expect(coordinator.state == .preflightReady)
        #expect(coordinator.preflightRun?.result.blockingCount == 0)
        coordinator.generatePlan()
        await coordinator.waitForCurrentOperation()
        return coordinator
    }

    private func executeReadyPlan(_ coordinator: BackupImportFlowCoordinator) async throws {
        #expect(coordinator.state == .readyToImport)
        coordinator.prepareFinalConfirmation()
        #expect(coordinator.state == .confirming)
        coordinator.execute(currentUserIDAtConfirmation: userID)
        await coordinator.waitForCurrentOperation()
        #expect(coordinator.state == .completed)
    }

    private func probableLocalRestaurant() throws -> Restaurant {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let timestamp = SyncRecordMapper.dateString(Date(timeIntervalSince1970: 1_700_000_000))
        let identity = try RestaurantPlaceIdentityContract(
            provider: .amap,
            externalId: "local-amap-candidate",
            isPrimary: true,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let contract = try RestaurantJSONContractV1(
            id: id.uuidString.lowercased(),
            userId: userID,
            placeIdentities: [identity],
            name: "P1-D 离线验收餐厅",
            address: "杭州市上城区湖滨路 18 号",
            city: "杭州",
            latitude: 30.25901,
            longitude: 120.168,
            status: .visited,
            preferenceLevel: .normal,
            overallRating: nil,
            foodRating: nil,
            environmentRating: nil,
            serviceRating: nil,
            valueRating: nil,
            tags: [],
            longTermNote: "",
            pricePerPerson: nil,
            phone: nil,
            openingHours: nil,
            markerType: .emoji,
            markerPhotoId: nil,
            merchantImageUrl: nil,
            markerEmoji: "🍽️",
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil
        )
        return Restaurant(
            id: id,
            ownerUserID: userID,
            name: contract.name,
            address: contract.address,
            latitude: contract.latitude,
            longitude: contract.longitude,
            city: contract.city,
            remoteID: contract.id,
            remoteRecordData: try JSONEncoder().encode(contract)
        )
    }
}
