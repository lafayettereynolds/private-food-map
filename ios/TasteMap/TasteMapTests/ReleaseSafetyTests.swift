import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("Release Safety")
struct ReleaseSafetyTests {
    @Test("Pending account deletion credentials round-trip without plaintext persistence outside the store")
    func pendingDeletionCredentialRoundTrip() throws {
        let store = InMemoryAccountDeletionCredentialStore()
        let credential = PendingAccountDeletionCredential(
            userID: "tm_release_user",
            requestID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            statusToken: "tm_delete_opaque_status_token",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try store.save(credential)
        #expect(try store.load() == credential)
        try store.delete()
        #expect(try store.load() == nil)
    }

    @Test("Account deletion contracts decode required status and counts")
    func contractDecoding() throws {
        let previewJSON = #"{"apiVersion":1,"userId":"tm_a","requiresFreshAuthentication":true,"pendingMutationCount":2,"entityCounts":{"restaurants":3,"visits":7},"photoObjectCount":4}"#
        let jobJSON = #"{"apiVersion":1,"jobId":"delete_1","status":"deleting_objects","requestedAt":"2026-08-30T00:00:00.000Z","updatedAt":"2026-08-30T00:00:01.000Z","completedAt":null,"retryable":false,"errorCode":null}"#
        let preview = try JSONDecoder().decode(AccountDeletionPreviewV1.self, from: Data(previewJSON.utf8))
        let job = try JSONDecoder().decode(AccountDeletionJobV1.self, from: Data(jobJSON.utf8))

        #expect(preview.requiresFreshAuthentication)
        #expect(preview.entityCounts["visits"] == 7)
        #expect(job.status == .deletingObjects)
    }

    @Test("Local purge removes current business state and files without deleting other scoped directories")
    @MainActor
    func localPurgeIsolation() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let currentID = "tm_current"
        let otherID = "tm_other"
        let currentProfile = UserProfile(tasteMapUserID: currentID, displayName: "Current")
        let otherProfile = UserProfile(tasteMapUserID: otherID, displayName: "Other")
        let restaurant = Restaurant(
            ownerUserID: currentID,
            name: "Local", address: "Road", latitude: 30, longitude: 120
        )
        let visit = Visit(ownerUserID: currentID, restaurantId: restaurant.id)
        let photo = PhotoAsset(
            ownerUserID: currentID,
            restaurantId: restaurant.id,
            visitId: visit.id,
            kind: .visit,
            mimeType: "image/jpeg",
            byteSize: 3,
            localFileRelativePath: "originals/current.jpg",
            displayFileRelativePath: "display/current.jpg"
        )
        let currentCompanion = DiningCompanion(ownerUserId: currentID, displayName: "Current Friend")
        let otherCompanion = DiningCompanion(ownerUserId: otherID, displayName: "Other Friend")
        let mutation = SyncMutation(
            ownerUserID: currentID,
            entityType: .visit, entityID: visit.remoteID!, operation: .upsert,
            payload: Data("{}".utf8), baseVersion: 0
        )
        context.insert(currentProfile)
        context.insert(otherProfile)
        context.insert(restaurant)
        context.insert(visit)
        context.insert(photo)
        context.insert(currentCompanion)
        context.insert(otherCompanion)
        context.insert(mutation)
        try context.save()
        let files = MemoryPhotoFileStore(paths: ["originals/current.jpg", "display/current.jpg"])

        let result = try await LocalAccountDataPurger(context: context, photoFileStore: files)
            .purgeCurrentAccount(userID: currentID)

        #expect(result.deletedPhotoFileCount == 2)
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Visit>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PhotoAsset>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<UserProfile>()).map(\.tasteMapUserID) == [otherID])
        #expect(try context.fetch(FetchDescriptor<DiningCompanion>()).map(\.ownerUserId) == [otherID])
        #expect(await files.remainingPaths().isEmpty)
    }

    @Test("Local content clear preserves account profile, avatar, sync checkpoint and other accounts")
    @MainActor
    func localContentClearPreservesIdentityAndCloudBoundary() async throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let currentID = "tm_current"
        let otherID = "tm_other"
        let avatar = PhotoAsset(
            ownerUserID: currentID,
            kind: .avatar,
            mimeType: "image/jpeg",
            byteSize: 3,
            localFileRelativePath: "originals/avatar.jpg"
        )
        let profile = UserProfile(
            tasteMapUserID: currentID,
            displayName: "Current",
            avatarPhotoID: avatar.id.uuidString.lowercased()
        )
        let restaurant = Restaurant(
            ownerUserID: currentID,
            name: "Local", address: "Road", latitude: 30, longitude: 120
        )
        let visit = Visit(ownerUserID: currentID, restaurantId: restaurant.id)
        let visitPhoto = PhotoAsset(
            ownerUserID: currentID,
            restaurantId: restaurant.id,
            visitId: visit.id,
            kind: .visit,
            mimeType: "image/jpeg",
            byteSize: 3,
            localFileRelativePath: "originals/visit.jpg"
        )
        let otherRestaurant = Restaurant(
            ownerUserID: otherID,
            name: "Other", address: "Road", latitude: 31, longitude: 121
        )
        context.insert(profile)
        context.insert(avatar)
        context.insert(restaurant)
        context.insert(visit)
        context.insert(visitPhoto)
        context.insert(otherRestaurant)
        context.insert(SyncCheckpoint(ownerUserID: currentID, cursor: "42"))
        context.insert(SyncMutation(
            ownerUserID: currentID, entityType: .profile, entityID: currentID,
            operation: .upsert, payload: Data("{}".utf8), baseVersion: 0
        ))
        context.insert(SyncMutation(
            ownerUserID: currentID, entityType: .photo,
            entityID: avatar.id.uuidString.lowercased(),
            operation: .upsert, payload: Data("{}".utf8), baseVersion: 0
        ))
        context.insert(SyncMutation(
            ownerUserID: currentID, entityType: .visit, entityID: visit.remoteID!,
            operation: .upsert, payload: Data("{}".utf8), baseVersion: 0
        ))
        try context.save()
        let files = MemoryPhotoFileStore(paths: ["originals/avatar.jpg", "originals/visit.jpg"])

        let result = try await LocalAccountDataPurger(context: context, photoFileStore: files)
            .clearCurrentAccountContent(userID: currentID)

        #expect(result.deletedPhotoFileCount == 1)
        #expect(try context.fetch(FetchDescriptor<UserProfile>()).map(\.tasteMapUserID) == [currentID])
        #expect(try context.fetch(FetchDescriptor<PhotoAsset>()).map(\.kind) == [.avatar])
        #expect(try context.fetch(FetchDescriptor<Restaurant>()).map(\.ownerUserID) == [otherID])
        #expect(try context.fetch(FetchDescriptor<Visit>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SyncCheckpoint>()).map(\.cursor) == ["42"])
        #expect(Set(try context.fetch(FetchDescriptor<SyncMutation>()).map(\.entityType)) == [.profile, .photo])
        #expect(await files.remainingPaths() == ["originals/avatar.jpg"])
    }

    @Test("Moderation reason labels remain explicit and user-facing")
    func moderationReasons() {
        #expect(ModerationReasonV1.allCases.count == 7)
        #expect(ModerationReasonV1.privacy.title == "泄露隐私")
        #expect(ModerationReasonV1.harassment.title == "骚扰或欺凌")
    }
}

private final class InMemoryAccountDeletionCredentialStore: AccountDeletionCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credential: PendingAccountDeletionCredential?

    func load() throws -> PendingAccountDeletionCredential? {
        lock.withLock { credential }
    }

    func save(_ credential: PendingAccountDeletionCredential) throws {
        lock.withLock { self.credential = credential }
    }

    func delete() throws {
        lock.withLock { credential = nil }
    }
}

private actor MemoryPhotoFileStore: LocalPhotoFileStoring {
    private var paths: Set<String>
    init(paths: Set<String>) { self.paths = paths }

    func save(_ data: Data, photoID: UUID, mimeType: String) throws -> String {
        try save(data, photoID: photoID, mimeType: mimeType, variant: .original)
    }
    func save(_ data: Data, photoID: UUID, mimeType: String, variant: LocalPhotoFileVariant) throws -> String {
        let path = "\(variant.rawValue)/\(photoID.uuidString).jpg"
        paths.insert(path)
        return path
    }
    func load(relativePath: String) throws -> Data {
        guard paths.contains(relativePath) else { throw LocalPhotoFileStoreError.fileMissing }
        return Data()
    }
    func delete(relativePath: String) { paths.remove(relativePath) }
    func fileExists(relativePath: String) -> Bool { paths.contains(relativePath) }
    func cleanupOrphans(retaining relativePaths: Set<String>) {
        paths.formIntersection(relativePaths)
    }
    func remainingPaths() -> Set<String> { paths }
}
