import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("P3-A User Profile foundation", .serialized)
@MainActor
struct P3AProfileTests {
    @Test("Homepage visibility propagates to only the owner's footprint and queues once")
    func linkedFootprintVisibility() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let profile = UserProfile(tasteMapUserID: "tm_scope", displayName: "Owner")
        profile.visibility = .public
        let restaurant = Restaurant(ownerUserID: "tm_scope", name: "Owned", address: "", latitude: 0, longitude: 0, remoteID: "restaurant_scope")
        let visit = Visit(ownerUserID: "tm_scope", restaurantId: restaurant.id, rating: 4.5)
        let other = Visit(ownerUserID: "tm_other", restaurantId: restaurant.id, rating: 4.5)
        context.insert(profile); context.insert(restaurant); context.insert(visit); context.insert(other)
        try context.save()
        let store = LocalUserProfileStore(context: context)
        #expect(try store.synchronizeFootprintVisibility(profile) == 1)
        #expect(visit.visibility == .public)
        #expect(other.visibility == .private)
        #expect(try store.synchronizeFootprintVisibility(profile) == 0)
        profile.visibility = .friends
        #expect(try store.synchronizeFootprintVisibility(profile) == 1)
        #expect(visit.visibility == .friends)
        profile.visibility = .private
        #expect(try store.synchronizeFootprintVisibility(profile) == 1)
        #expect(visit.visibility == .private)
    }

    @Test("Numeric public user ID stays aligned with the Web projection")
    func numericPublicUserID() {
        #expect(TasteMapPublicUserID.numeric(from: "tm_contract") == "395932615433")
        #expect(TasteMapPublicUserID.numeric(from: "tm_hybrid_debug") == "601372693425")
    }

    @Test("Profile initialization is one-to-one and idempotent")
    func initializationIsIdempotent() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let store = LocalUserProfileStore(context: container.mainContext)

        let first = try store.ensureProfile(
            tasteMapUserID: "tm_profile_test",
            suggestedDisplayName: "  小林 🍜  "
        )
        let second = try store.ensureProfile(
            tasteMapUserID: "tm_profile_test",
            suggestedDisplayName: "不能覆盖"
        )

        #expect(first.id == second.id)
        #expect(first.tasteMapUserID == "tm_profile_test")
        #expect(first.displayName == "小林 🍜")
        #expect(first.avatarPreset == .polarBear)
        #expect(first.visibility == .private)
        #expect(try container.mainContext.fetch(FetchDescriptor<UserProfile>()).count == 1)
        #expect(try profileMutations(in: container.mainContext).count == 1)
    }

    @Test("Display Name, Bio and City validation is explicit and Unicode-safe")
    func validationRules() throws {
        #expect(try ValidatedUserProfileInput(
            displayName: "  Alex 🍣  ", bio: "  周末找小店  ", city: "  杭州  "
        ) == ValidatedUserProfileInput(displayName: "Alex 🍣", bio: "周末找小店", city: "杭州"))
        #expect(throws: UserProfileValidationError.emptyDisplayName) {
            _ = try ValidatedUserProfileInput(displayName: " \n ", bio: "", city: "")
        }
        #expect(throws: UserProfileValidationError.displayNameTooLong) {
            _ = try ValidatedUserProfileInput(displayName: String(repeating: "🍜", count: 31), bio: "", city: "")
        }
        #expect(throws: UserProfileValidationError.bioTooLong) {
            _ = try ValidatedUserProfileInput(displayName: "Alex", bio: String(repeating: "介", count: 161), city: "")
        }
        #expect(throws: UserProfileValidationError.cityTooLong) {
            _ = try ValidatedUserProfileInput(displayName: "Alex", bio: "", city: String(repeating: "城", count: 31))
        }
        let legacy = String(repeating: "旧昵称", count: 20)
        #expect(try ValidatedUserProfileInput(
            displayName: legacy, bio: "可以只改简介", city: "",
            unchangedLegacyDisplayName: legacy
        ).displayName == legacy)
    }

    @Test("Offline profile edit and queue survive app restart")
    func offlineEditSurvivesRestart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("profile.store")
        var container: ModelContainer? = try TasteMapPersistence.makeContainer(storageURL: storeURL)
        let firstContext = try #require(container?.mainContext)
        let profile = try LocalUserProfileStore(context: firstContext).ensureProfile(
            tasteMapUserID: "tm_profile_restart"
        )
        try LocalUserProfileStore(context: firstContext).update(
            profile,
            displayName: "  离线小王  ",
            bio: "  断网也能保存  ",
            city: " 上海 ",
            avatarPhotoID: nil,
            avatarPreset: .otter,
            visibility: .friends
        )
        #expect(profile.displayName == "离线小王")
        #expect(profile.syncStatus == .pending)
        #expect(try profileMutations(in: firstContext).count == 1)
        container = nil

        let reopened = try TasteMapPersistence.makeContainer(storageURL: storeURL)
        let restored = try #require(reopened.mainContext.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(restored.displayName == "离线小王")
        #expect(restored.bio == "断网也能保存")
        #expect(restored.city == "上海")
        #expect(restored.avatarPreset == .otter)
        #expect(restored.visibility == .friends)
        #expect(try profileMutations(in: reopened.mainContext).count == 1)
    }

    @Test("Profile waits for its custom Avatar Photo before entering sync queue")
    func avatarDependencyOrder() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = LocalUserProfileStore(context: context)
        let profile = try store.ensureProfile(tasteMapUserID: "tm_avatar_test")
        for mutation in try profileMutations(in: context) { context.delete(mutation) }
        let avatar = PhotoAsset(
            ownerUserID: "tm_avatar_test",
            kind: .avatar,
            storageProvider: .r2,
            storageKey: "users/tm_avatar_test/avatar.jpg",
            thumbnailStorageKey: "users/tm_avatar_test/avatar-thumb.jpg",
            mimeType: "image/jpeg",
            byteSize: 128,
            visibility: .private,
            uploadState: .queued,
            syncStatus: .pending
        )
        context.insert(avatar)

        try store.update(
            profile, displayName: "Avatar User", bio: "", city: "",
            avatarPhotoID: avatar.remoteID, avatarPreset: .cat, visibility: .public
        )
        #expect(try profileMutations(in: context).isEmpty)

        avatar.uploadState = .uploaded
        try store.enqueueIfReady(profile)
        let mutation = try #require(try profileMutations(in: context).first)
        let record = try #require(mutation.payload).decoded(as: OwnProfileSyncContractV1.self)
        #expect(record.avatarPhotoId == avatar.remoteID)
        #expect(record.avatarPresetId == .cat)
        #expect(avatar.kind == .avatar)
        #expect(avatar.thumbnailStorageKey != nil)
    }

    @Test("Own and Public Profile JSON have different exact shapes")
    func contractBoundaries() throws {
        let own = OwnProfileSyncContractV1(
            schemaVersion: 1,
            userId: "tm_contract",
            displayName: "Lafayette 🍜",
            bio: "认真吃饭",
            city: "杭州",
            avatarPhotoId: nil,
            avatarPresetId: .whale,
            visibility: .public,
            createdAt: instant,
            updatedAt: instant,
            deletedAt: nil
        )
        let ownObject = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(own)) as? [String: Any])
        #expect(Set(ownObject.keys) == [
            "schemaVersion", "userId", "displayName", "bio", "city", "avatarPhotoId",
            "avatarPresetId", "visibility", "createdAt", "updatedAt", "deletedAt",
        ])
        #expect(ownObject.keys.contains("email") == false)
        #expect(ownObject.keys.contains("appleSub") == false)
        #expect(ownObject.keys.contains("session") == false)

        let publicProfile = PublicUserProfileV1(
            apiVersion: 1,
            userId: "tm_contract",
            displayName: "Lafayette 🍜",
            bio: nil,
            city: "杭州",
            avatarPhotoId: nil,
            avatarPresetId: .whale,
            joinedAt: instant,
            statistics: PublicProfileStatisticsV1(publicRestaurantCount: 2, publicVisitCount: 3)
        )
        let publicData = try JSONEncoder().encode(publicProfile)
        let publicObject = try #require(JSONSerialization.jsonObject(with: publicData) as? [String: Any])
        #expect(Set(publicObject.keys) == [
            "apiVersion", "userId", "displayName", "bio", "city", "avatarPhotoId",
            "avatarPresetId", "joinedAt", "statistics",
        ])
        #expect(try JSONDecoder().decode(PublicUserProfileV1.self, from: publicData) == publicProfile)

        var leaked = publicObject
        leaked["email"] = "private@icloud.com"
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(
                PublicUserProfileV1.self,
                from: JSONSerialization.data(withJSONObject: leaked)
            )
        }
        var missingNullable = ownObject
        missingNullable.removeValue(forKey: "avatarPhotoId")
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(
                OwnProfileSyncContractV1.self,
                from: JSONSerialization.data(withJSONObject: missingNullable)
            )
        }
    }

    @Test("Offline edit reconnects and a fresh client pulls the same Profile")
    func syncAndFreshClient() async throws {
        let api = ProfileMemorySyncAPI()
        let source = try TasteMapPersistence.makeContainer(inMemory: true)
        let sourceStore = LocalUserProfileStore(context: source.mainContext)
        let profile = try sourceStore.ensureProfile(tasteMapUserID: "tm_sync_profile")
        try sourceStore.update(
            profile, displayName: "同步小林", bio: "fresh client", city: "杭州",
            avatarPhotoID: nil, avatarPreset: .panda, visibility: .public
        )

        try await SyncEngine(
            context: source.mainContext,
            api: api,
            ownerUserID: "tm_sync_profile"
        ).synchronize()
        #expect(profile.serverVersion == 1)
        #expect(profile.syncStatus == .synced)
        #expect(try profileMutations(in: source.mainContext).isEmpty)

        let fresh = try TasteMapPersistence.makeContainer(inMemory: true)
        try await SyncEngine(
            context: fresh.mainContext,
            api: api,
            ownerUserID: "tm_sync_profile"
        ).synchronize()
        let pulled = try #require(fresh.mainContext.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(pulled.tasteMapUserID == "tm_sync_profile")
        #expect(pulled.displayName == "同步小林")
        #expect(pulled.bio == "fresh client")
        #expect(pulled.avatarPreset == .panda)
        #expect(pulled.visibility == .public)
        #expect(pulled.serverVersion == 1)
    }

    @Test("A server-version conflict keeps the local Profile edit and server snapshot")
    func conflictPreservesLocalEdit() async throws {
        let server = OwnProfileSyncContractV1(
            schemaVersion: 1, userId: "tm_conflict", displayName: "远端名字",
            bio: "server", city: "北京", avatarPhotoId: nil, avatarPresetId: .fox,
            visibility: .private, createdAt: instant, updatedAt: instant, deletedAt: nil
        )
        let api = ProfileMemorySyncAPI(record: server, version: 2)
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let local = UserProfile(
            tasteMapUserID: "tm_conflict", displayName: "同步前",
            serverVersion: 1, syncStatus: .synced
        )
        context.insert(local)
        try LocalUserProfileStore(context: context).update(
            local, displayName: "我的离线修改", bio: "local", city: "上海",
            avatarPhotoID: nil, avatarPreset: .otter, visibility: .friends
        )

        try await SyncEngine(
            context: context,
            api: api,
            ownerUserID: "tm_conflict"
        ).synchronize()

        #expect(local.displayName == "我的离线修改")
        #expect(local.bio == "local")
        #expect(local.syncStatus == .failed)
        let mutation = try #require(try profileMutations(in: context).first)
        #expect(mutation.state == .conflicted)
        let snapshot = try #require(local.remoteRecordData).decoded(as: OwnProfileSyncContractV1.self)
        #expect(snapshot.displayName == "远端名字")
        #expect(snapshot.bio == "server")
    }

    @Test("The additive P3-A schema opens a P2 store without wiping records")
    func additiveSchemaMigration() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy-p2.store")
        let p2Schema = Schema([
            Restaurant.self, Visit.self, Dish.self, VisitDish.self, PhotoAsset.self,
            DiningCompanion.self, RecommendationSource.self,
            SyncMutation.self, SyncCheckpoint.self,
        ])
        var old: ModelContainer? = try ModelContainer(
            for: p2Schema,
            configurations: [ModelConfiguration(
                "TasteMap", schema: p2Schema, url: url, cloudKitDatabase: .none
            )]
        )
        old?.mainContext.insert(Restaurant(
            name: "P2 保留餐厅", address: "杭州", latitude: 30, longitude: 120
        ))
        try old?.mainContext.save()
        old = nil

        let migrated = try TasteMapPersistence.makeContainer(storageURL: url)
        #expect(try migrated.mainContext.fetch(FetchDescriptor<Restaurant>()).first?.name == "P2 保留餐厅")
        #expect(try migrated.mainContext.fetch(FetchDescriptor<UserProfile>()).isEmpty)
        _ = try LocalUserProfileStore(context: migrated.mainContext)
            .ensureProfile(tasteMapUserID: "tm_after_migration")
        #expect(try migrated.mainContext.fetch(FetchDescriptor<UserProfile>()).count == 1)
    }

    @Test("Basic own statistics use real local records and ignore nil ratings")
    func basicStatistics() {
        let firstRestaurant = Restaurant(name: "A", address: "", latitude: 0, longitude: 0)
        let secondRestaurant = Restaurant(
            name: "B", address: "", latitude: 0, longitude: 0, status: .wantToGo
        )
        let visits = [
            Visit(restaurantId: firstRestaurant.id, rating: 4.5, myActualSpend: 80),
            Visit(restaurantId: firstRestaurant.id, rating: nil, myActualSpend: nil),
        ]
        let statistics = ProfileBasicStatistics(
            restaurants: [firstRestaurant, secondRestaurant], visits: visits
        )
        #expect(statistics.visitedRestaurantCount == 1)
        #expect(statistics.wantToGoRestaurantCount == 1)
        #expect(statistics.visitCount == 2)
        #expect(statistics.averageRating == 4.5)
        #expect(statistics.totalSpend == 80)
    }

    private var instant: String { "2026-08-28T08:00:00.000Z" }

    private func profileMutations(in context: ModelContext) throws -> [SyncMutation] {
        try context.fetch(FetchDescriptor<SyncMutation>()).filter { $0.entityType == .profile }
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TasteMap-P3A-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
private final class ProfileMemorySyncAPI: SyncAPI {
    private var record: OwnProfileSyncContractV1?
    private var version: Int64
    private var revision: Int64
    private var receipts: [String: SyncMutationAcknowledgementV1] = [:]

    init(record: OwnProfileSyncContractV1? = nil, version: Int64 = 0) {
        self.record = record
        self.version = version
        revision = version
    }

    func push(_ request: SyncPushRequestV1) async throws -> SyncPushResponseV1 {
        let acknowledgements = request.mutations.map { mutation in
            if let receipt = receipts[mutation.mutationId] {
                return SyncMutationAcknowledgementV1(
                    mutationId: receipt.mutationId,
                    entityType: receipt.entityType,
                    entityId: receipt.entityId,
                    status: receipt.status,
                    duplicate: true,
                    serverVersion: receipt.serverVersion,
                    revision: receipt.revision,
                    conflictReason: receipt.conflictReason
                )
            }
            let acknowledgement: SyncMutationAcknowledgementV1
            if mutation.entityType != .profile || mutation.entityId != profileUserID(mutation) {
                acknowledgement = SyncMutationAcknowledgementV1(
                    mutationId: mutation.mutationId, entityType: mutation.entityType,
                    entityId: mutation.entityId, status: .conflict, duplicate: false,
                    serverVersion: version, revision: nil, conflictReason: "owner_mismatch"
                )
            } else if mutation.baseVersion != version {
                acknowledgement = SyncMutationAcknowledgementV1(
                    mutationId: mutation.mutationId, entityType: .profile,
                    entityId: mutation.entityId, status: .conflict, duplicate: false,
                    serverVersion: version, revision: nil, conflictReason: "server_version_mismatch"
                )
            } else if case .profile(let profile)? = mutation.payload {
                version += 1
                revision += 1
                record = profile
                acknowledgement = SyncMutationAcknowledgementV1(
                    mutationId: mutation.mutationId, entityType: .profile,
                    entityId: mutation.entityId, status: .applied, duplicate: false,
                    serverVersion: version, revision: revision, conflictReason: nil
                )
            } else {
                acknowledgement = SyncMutationAcknowledgementV1(
                    mutationId: mutation.mutationId, entityType: .profile,
                    entityId: mutation.entityId, status: .conflict, duplicate: false,
                    serverVersion: version, revision: nil, conflictReason: "missing_payload"
                )
            }
            receipts[mutation.mutationId] = acknowledgement
            return acknowledgement
        }
        return SyncPushResponseV1(
            apiVersion: 1,
            acknowledgements: acknowledgements,
            serverTime: "2026-08-28T08:00:00.000Z"
        )
    }

    func pull(cursor: String, limit: Int) async throws -> SyncPullResponseV1 {
        let cursorValue = Int64(cursor) ?? 0
        let profiles = cursorValue < revision ? record.map {
            [ProfileSyncRecordEnvelopeV1(serverVersion: version, record: $0)]
        } ?? [] : []
        return SyncPullResponseV1(
            apiVersion: 1, schemaVersion: 1, restaurants: [], visits: [],
            profiles: profiles, tombstones: [], nextCursor: String(revision),
            hasMore: false, serverTime: "2026-08-28T08:00:00.000Z"
        )
    }

    private func profileUserID(_ mutation: SyncMutationRequestV1) -> String? {
        guard case .profile(let profile)? = mutation.payload else { return nil }
        return profile.userId
    }
}

private extension Data {
    func decoded<T: Decodable>(as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: self)
    }
}
