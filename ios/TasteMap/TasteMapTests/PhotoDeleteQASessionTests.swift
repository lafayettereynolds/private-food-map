import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("Isolated authenticated Photo Delete QA")
@MainActor
struct PhotoDeleteQASessionTests {
    @Test("Hybrid owner resource downloads without local cache and rejects deleted/foreign/signed-out reads")
    func hybridOwnerRemoteResource() async throws {
        let owner = PhotoDeleteQASessionFixture.ownerID
        let auth = try services(owner: owner)
        #expect(await auth.restoreLocalAccountScope()?.id == owner)
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try LocalPhotoFileStore(rootURL: directory)
        let sync = SyncCoordinator(context: context, api: auth.syncAPI, sessionManager: auth.sessionManager, networkObserver: nil)
        let photos = PhotoTransferCoordinator(context: context, api: auth.photoAPI, files: files,
            sessionManager: auth.sessionManager, syncCoordinator: sync, networkObserver: nil)
        let premium = PremiumEntitlementService(api: auth.premiumAPI, cache: InMemoryPremiumEntitlementCache())
        let runtime = TasteMapHybridRuntime(mode: .hybridPrimary, container: container, authServices: auth,
            premiumEntitlementService: premium, syncCoordinator: sync, photoFiles: files, photoTransferCoordinator: photos)
        let own = PhotoAsset(ownerUserID: owner, kind: .visit, storageProvider: .r2,
            storageKey: "owner/display.jpg", thumbnailStorageKey: "owner/thumbnail.jpg",
            mimeType: "image/jpeg", byteSize: 4, uploadState: .uploaded, syncStatus: .synced)
        let foreign = PhotoAsset(ownerUserID: PhotoDeleteQASessionFixture.otherID, kind: .visit,
            mimeType: "image/jpeg", byteSize: 4)
        context.insert(own); context.insert(foreign); try context.save()
        PhotoDeleteQATestService.shared.register(photoID: own.id.uuidString.lowercased(), owner: owner)
        PhotoDeleteQATestService.shared.register(photoID: foreign.id.uuidString.lowercased(), owner: foreign.ownerUserID)
        func url(_ id: UUID) -> URL { URL(string: "tastemap-resource://photo/\(id.uuidString.lowercased())/thumbnail")! }
        #expect(try await runtime.resourceData(for: url(own.id)).data == Data([1, 2, 3, 4]))
        let path = try #require(own.thumbnailFileRelativePath)
        #expect(await files.fileExists(relativePath: path))
        #expect(try await runtime.resourceData(for: url(own.id)).data == Data([1, 2, 3, 4]))
        do { _ = try await runtime.resourceData(for: url(foreign.id)); Issue.record("Foreign owner resource allowed") } catch {}
        do { _ = try await runtime.resourceData(for: url(UUID())); Issue.record("Unknown resource allowed") } catch {}
        own.deletedAt = .now; try context.save()
        do { _ = try await runtime.resourceData(for: url(own.id)); Issue.record("Deleted resource allowed") } catch {}
        own.deletedAt = nil; try context.save()
        auth.endLocalAccountSession()
        do { _ = try await runtime.resourceData(for: url(own.id)); Issue.record("Signed-out cached resource allowed") } catch {}
    }
    @Test("Rich photo QA snapshot visibility reconciliation")
    func richSnapshotInitialization() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        container.mainContext.insert(UserProfile(tasteMapUserID: PhotoDeleteQASessionFixture.ownerID,
            displayName: "Lafayette · 丰富美食档案", visibility: .public, serverVersion: 1, syncStatus: .synced))
        try TasteMapVisualQAFixtures.insert(mode: .rich, into: container)
        let profile = try #require(container.mainContext.fetch(FetchDescriptor<UserProfile>()).first { $0.tasteMapUserID == PhotoDeleteQASessionFixture.ownerID })
        // The old display-only seed is not a valid sync-upload fixture.
        #expect(throws: RichRecordContractError.invalidPhoto) {
            _ = try LocalUserProfileStore(context: container.mainContext).synchronizeFootprintVisibility(profile)
        }
        try PhotoDeleteQASessionFixture.registerPhotos(in: container)
        #expect(try LocalUserProfileStore(context: container.mainContext).synchronizeFootprintVisibility(profile) == 0)
        let photo = try #require(container.mainContext.fetch(FetchDescriptor<PhotoAsset>()).first)
        let deletedAt = Date(timeIntervalSince1970: 100)
        photo.deletedAt = deletedAt
        try container.mainContext.save()
        try PhotoDeleteQASessionFixture.registerPhotos(in: container)
        #expect(photo.deletedAt == deletedAt)
        #expect(try LocalUserProfileStore(context: container.mainContext).synchronizeFootprintVisibility(profile) == 0)
    }

    private func services(owner: String?, expired: Bool = false) throws -> NativeAuthServices {
        let store = IsolatedAuthCredentialStore()
        if let owner {
            let response = PhotoDeleteQATestService.shared.issue(owner: owner)
            var value = try AuthCredential(response: response)
            if expired {
                value = AuthCredential(user: value.user, accessToken: value.accessToken,
                    accessTokenExpiresAt: .distantPast, refreshToken: value.refreshToken,
                    refreshTokenExpiresAt: .distantPast)
            }
            value.appleUserIdentifier = PhotoDeleteQATestService.appleIdentifier
            try store.save(value)
        }
        return NativeAuthServices(configuration: try PhotoDeleteQASessionFixture.configuration(),
            session: PhotoDeleteQASessionFixture.session(), credentialStore: store,
            socialOutboxFileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            appleState: { $0 == PhotoDeleteQATestService.appleIdentifier ? .authorized : .notFound })
    }

    @Test("Normal session restore, refresh and authenticated owner binary delete")
    func authenticatedOwner() async throws {
        let owner = PhotoDeleteQASessionFixture.ownerID
        let service = try services(owner: owner)
        #expect(await service.restoreLocalAccountScope()?.id == owner)
        #expect(service.localAccountScope == .authenticated(owner))
        // Real URLSessionAuthAPIClient -> local /auth/refresh -> accepted contract.
        #expect(try await service.sessionManager.forceRefresh().id == owner)
        let id = UUID()
        PhotoDeleteQATestService.shared.register(photoID: id.uuidString.lowercased(), owner: owner)
        try await service.photoAPI.delete(photoID: id)
        #expect(PhotoDeleteQATestService.shared.isDeleted(id.uuidString.lowercased()))
    }

    @Test("A valid other-user session cannot delete an owner's photo")
    func otherUserRejected() async throws {
        let service = try services(owner: PhotoDeleteQASessionFixture.otherID)
        #expect(await service.restoreLocalAccountScope()?.id == PhotoDeleteQASessionFixture.otherID)
        let id = UUID()
        PhotoDeleteQATestService.shared.register(photoID: id.uuidString.lowercased(), owner: PhotoDeleteQASessionFixture.ownerID)
        do { try await service.photoAPI.delete(photoID: id); Issue.record("Cross-owner deletion accepted") }
        catch { #expect(error as? PhotoBinaryAPIError == .server(status: 404, message: "Photo unavailable")) }
        #expect(!PhotoDeleteQATestService.shared.isDeleted(id.uuidString.lowercased()))
    }

    @Test("Missing and expired session cannot authorize deletion")
    func absentOrExpired() async throws {
        for (owner, expired) in [(nil as String?, false), (PhotoDeleteQASessionFixture.ownerID, true)] {
            let service = try services(owner: owner, expired: expired)
            #expect(await service.restoreLocalAccountScope() == nil)
            do { try await service.photoAPI.delete(photoID: UUID()); Issue.record("Invalid session accepted") }
            catch { }
        }
    }

    @Test("Authenticated detail exposes only owner delete IDs and rejects a crafted foreign photo delete")
    func detailOwnerBoundary() async throws {
        let owner = PhotoDeleteQASessionFixture.ownerID
        let service = try services(owner: owner)
        let restored = try #require(await service.restoreLocalAccountScope())
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let restaurant = Restaurant(ownerUserID: owner, name: "QA", address: "QA", latitude: 30, longitude: 120, city: "QA", status: .visited)
        let visit = Visit(ownerUserID: owner, restaurantId: restaurant.id, visitedAt: .now)
        let own = PhotoAsset(ownerUserID: owner, restaurantId: restaurant.id, visitId: visit.id,
            kind: .visit, mimeType: "image/jpeg", byteSize: 12)
        let foreign = PhotoAsset(ownerUserID: PhotoDeleteQASessionFixture.otherID, restaurantId: restaurant.id,
            kind: .visit, mimeType: "image/jpeg", byteSize: 12)
        foreign.visibility = .public
        context.insert(restaurant); context.insert(visit); context.insert(own); context.insert(foreign)
        try context.save()
        let detail = try TasteMapHybridBridgeService(container: container, ownerUserID: restored.id)
            .restaurantDetail(id: restaurant.id.uuidString)
        let deletable = try #require(detail.deletablePhotoIDs)
        #expect(deletable.contains(own.id.uuidString.lowercased()))
        #expect(!deletable.contains(foreign.id.uuidString.lowercased()))
        PhotoDeleteQATestService.shared.register(photoID: foreign.id.uuidString.lowercased(), owner: foreign.ownerUserID)
        do { try await service.photoAPI.delete(photoID: foreign.id); Issue.record("Owner deleted foreign photo") }
        catch { #expect(error as? PhotoBinaryAPIError == .server(status: 404, message: "Photo unavailable")) }
        #expect(!PhotoDeleteQATestService.shared.isDeleted(foreign.id.uuidString.lowercased()))
    }

    @Test("Forged owner headers and invalid Bearer tokens are rejected by the local service")
    func forgedTokenRejected() async throws {
        let id = UUID().uuidString.lowercased()
        let owner = PhotoDeleteQASessionFixture.ownerID
        PhotoDeleteQATestService.shared.register(photoID: id, owner: owner)
        for bearer in [nil, "Bearer \(owner)", "Bearer invalid"] {
            var request = URLRequest(url: URL(string: "https://photo-delete.qa.invalid/api/v1/photos/\(id)/content")!)
            request.httpMethod = "DELETE"
            request.setValue(bearer, forHTTPHeaderField: "Authorization")
            request.setValue(owner, forHTTPHeaderField: "X-Taste-Map-Test-User")
            let (_, response) = try await PhotoDeleteQASessionFixture.session().data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 401)
        }
        #expect(!PhotoDeleteQATestService.shared.isDeleted(id))
    }

    @Test("The fixture denies unexpected origins instead of forwarding network traffic")
    func networkIsolation() async throws {
        let request = URLRequest(url: URL(string: "https://unexpected.invalid/health")!)
        let (_, response) = try await PhotoDeleteQASessionFixture.session().data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 403)
        #expect(PhotoDeleteQASessionFixture.enabled == false)
    }
}
