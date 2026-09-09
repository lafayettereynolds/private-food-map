import Foundation
import ImageIO
import SwiftData
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import TasteMap

@Suite("P2-B Photo selection and transfer")
@MainActor
struct P2BPhotoFlowTests {
    @Test("Shared legacy/development photo root is not orphan-cleaned from one store")
    func sharedStoreCleanupPreservesFiles() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("TasteMap/Photos")
        let files = try LocalPhotoFileStore(rootURL: root)
        let path = try await files.save(Data([1, 2, 3]), photoID: UUID(), mimeType: "image/jpeg")
        try Data().write(to: directory.appendingPathComponent("TasteMap.store"))
        try Data().write(to: directory.appendingPathComponent("TasteMapDevelopment.store"))
        try await files.cleanupOrphans(retaining: [])
        #expect(await files.fileExists(relativePath: path))
        try await files.delete(relativePath: path)
        #expect(await files.fileExists(relativePath: path) == false)
        let single = try await files.save(Data([4]), photoID: UUID(), mimeType: "image/jpeg")
        try FileManager.default.removeItem(at: directory.appendingPathComponent("TasteMapDevelopment.store"))
        try await files.cleanupOrphans(retaining: [])
        #expect(await files.fileExists(relativePath: single) == false)
    }
    @Test("Large oriented input is normalized, compressed, and stored in three local variants")
    func processingAndOrientation() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try LocalPhotoFileStore(rootURL: directory)
        let source = try orientedJPEG(width: 2_600, height: 1_400, orientation: 6)

        let prepared = try await PhotoImportService(files: files).prepare(
            data: source,
            suggestedContentType: "image/jpeg",
            originalFileName: "portrait.jpg"
        )

        #expect(prepared.height > prepared.width)
        #expect(max(prepared.width, prepared.height) <= PhotoImportService.maximumDisplayPixel)
        #expect(prepared.displayByteSize < Int64(source.count))
        #expect(await files.fileExists(relativePath: prepared.originalFileRelativePath))
        #expect(await files.fileExists(relativePath: prepared.displayFileRelativePath))
        #expect(await files.fileExists(relativePath: prepared.thumbnailFileRelativePath))
        #expect(prepared.displayContentHash.count == 64)
    }

    @Test("PNG and HEIC originals are accepted while display variants stay optimized JPEG")
    func supportedOriginalFormats() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try LocalPhotoFileStore(rootURL: directory)

        for (type, mimeType) in [(UTType.png, "image/png"), (UTType.heic, "image/heic")] {
            let prepared = try await PhotoImportService(files: files).prepare(
                data: try encodedImage(type: type),
                suggestedContentType: mimeType
            )
            #expect(prepared.originalMimeType == mimeType)
            #expect(prepared.displayMimeType == "image/jpeg")
            #expect(await files.fileExists(relativePath: prepared.originalFileRelativePath))
            #expect(await files.fileExists(relativePath: prepared.thumbnailFileRelativePath))
        }
    }

    @Test("Offline photo metadata and queue survive an app restart")
    func restartPersistence() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("photo.store")
        let files = try LocalPhotoFileStore(rootURL: directory.appendingPathComponent("files"))
        var container: ModelContainer? = try TasteMapPersistence.makeContainer(storageURL: databaseURL)
        let firstContext = try #require(container?.mainContext)
        let parents = insertParents(firstContext)
        let prepared = try await PhotoImportService(files: files).prepare(data: sampleJPEG())
        let store = LocalDishPhotoStore(context: firstContext, photoFiles: files)
        _ = try store.createLocalPhoto(
            prepared: prepared,
            kind: .visit,
            restaurantId: parents.restaurant.id,
            visitId: parents.visit.id,
            queueForUpload: true
        )
        container = nil

        let reopened = try TasteMapPersistence.makeContainer(storageURL: databaseURL)
        let restored = try #require(reopened.mainContext.fetch(FetchDescriptor<PhotoAsset>()).first)
        #expect(restored.uploadState == .queued)
        #expect(restored.uploadMutationID != nil)
        #expect(try await files.load(relativePath: try #require(restored.thumbnailFileRelativePath)).isEmpty == false)
    }

    @Test("Lost upload response retries without creating duplicate objects")
    func responseLossAndRetry() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let parents = insertParents(context)
        let files = try LocalPhotoFileStore(rootURL: directory)
        let api = MockPhotoBinaryAPI(failFirstUploadResponse: true)
        let coordinator = PhotoTransferCoordinator(
            context: context,
            api: api,
            files: files,
            hasAuthenticatedSession: { true }
        )
        let prepared = try await coordinator.preparePhoto(data: sampleJPEG())
        let photo = try coordinator.attachPreparedPhoto(
            prepared,
            restaurantID: parents.restaurant.id,
            visitID: parents.visit.id,
            sortOrder: 0,
            queueForUpload: true
        )

        await coordinator.processNowForTesting()
        #expect(photo.uploadState == .failed)
        try coordinator.retry(photo)
        await coordinator.processNowForTesting()

        #expect(photo.uploadState == .uploaded)
        #expect(photo.storageProvider == .r2)
        #expect(photo.thumbnailStorageKey != nil)
        #expect(await api.uniqueObjectCount() == 2)
        #expect(await api.uploadCallCount() == 3)
        #expect(try context.fetch(FetchDescriptor<SyncMutation>()).contains { $0.entityType == .photo })
    }

    @Test("Permanent photo 4xx does not loop automatically and remains manually retryable")
    func permanentFailureDoesNotLoop() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let parents = insertParents(context)
        let files = try LocalPhotoFileStore(rootURL: directory)
        let api = PermanentlyRejectingPhotoBinaryAPI()
        let coordinator = PhotoTransferCoordinator(
            context: context,
            api: api,
            files: files,
            hasAuthenticatedSession: { true }
        )
        let prepared = try await coordinator.preparePhoto(data: sampleJPEG())
        let photo = try coordinator.attachPreparedPhoto(
            prepared,
            restaurantID: parents.restaurant.id,
            visitID: parents.visit.id,
            sortOrder: 0,
            queueForUpload: true
        )

        await coordinator.processNowForTesting()
        #expect(photo.uploadState == .failed)
        #expect(photo.uploadLastError?.hasPrefix("permanent:") == true)
        #expect(photo.uploadRetryAfter == nil)
        #expect(await api.uploadCallCount() == 1)

        await coordinator.processNowForTesting()
        #expect(await api.uploadCallCount() == 1)

        try coordinator.retry(photo)
        await coordinator.processNowForTesting()
        #expect(await api.uploadCallCount() == 2)
    }

    @Test("Authorized download uses the local cache after the first request")
    func downloadCache() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let api = MockPhotoBinaryAPI()
        await api.seedDownload(Data([1, 2, 3, 4]), variant: .thumbnail)
        let files = try LocalPhotoFileStore(rootURL: directory)
        let photo = PhotoAsset(
            kind: .visit,
            storageProvider: .r2,
            storageKey: "users/a/photos/id/display.jpg",
            thumbnailStorageKey: "users/a/photos/id/thumbnail.jpg",
            mimeType: "image/jpeg",
            byteSize: 4,
            uploadState: .uploaded,
            syncStatus: .synced
        )
        context.insert(photo)
        try context.save()
        let coordinator = PhotoTransferCoordinator(
            context: context,
            api: api,
            files: files,
            hasAuthenticatedSession: { true }
        )

        #expect(try await coordinator.imageData(for: photo, variant: .thumbnail) == Data([1, 2, 3, 4]))
        #expect(try await coordinator.imageData(for: photo, variant: .thumbnail) == Data([1, 2, 3, 4]))
        #expect(await api.downloadCallCount() == 1)
        #expect(photo.thumbnailFileRelativePath != nil)
        // A new coordinator (memory-cache loss) still reads the persisted file.
        let reopened = PhotoTransferCoordinator(context: context, api: api, files: files, hasAuthenticatedSession: { true })
        #expect(try await reopened.imageData(for: photo, variant: .thumbnail) == Data([1, 2, 3, 4]))
        #expect(await api.downloadCallCount() == 1)
        // A stale file path must fall back to the authenticated download again.
        try await files.delete(relativePath: try #require(photo.thumbnailFileRelativePath))
        let missing = PhotoTransferCoordinator(context: context, api: api, files: files, hasAuthenticatedSession: { true })
        #expect(try await missing.imageData(for: photo, variant: .thumbnail) == Data([1, 2, 3, 4]))
        #expect(await api.downloadCallCount() == 2)
    }

    @Test("A synced tombstone removes private binary content without removing the Visit")
    func deletionCleanup() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let parents = insertParents(context)
        let api = MockPhotoBinaryAPI()
        let files = try LocalPhotoFileStore(rootURL: directory)
        let photo = PhotoAsset(
            restaurantId: parents.restaurant.id,
            visitId: parents.visit.id,
            kind: .visit,
            storageProvider: .r2,
            storageKey: "users/a/photos/id/display.jpg",
            thumbnailStorageKey: "users/a/photos/id/thumbnail.jpg",
            mimeType: "image/jpeg",
            byteSize: 4,
            uploadState: .uploaded,
            serverVersion: 1,
            syncStatus: .synced
        )
        context.insert(photo)
        try context.save()
        try LocalDishPhotoStore(context: context, photoFiles: files).delete(photo)
        photo.syncStatus = .synced
        let coordinator = PhotoTransferCoordinator(
            context: context,
            api: api,
            files: files,
            hasAuthenticatedSession: { true }
        )
        await coordinator.processNowForTesting()

        #expect(photo.binaryDeletedAt != nil)
        #expect(await api.deleteCallCount() == 1)
        #expect(try context.fetch(FetchDescriptor<Visit>()).contains { $0.id == parents.visit.id })
    }

    @Test("Owner deletion hides a cached image immediately and retains tombstone across cleanup retries")
    func localFirstDeleteAndRetry() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let parents = insertParents(context)
        let files = try LocalPhotoFileStore(rootURL: directory)
        let api = MockPhotoBinaryAPI()
        let coordinator = PhotoTransferCoordinator(context: context, api: api, files: files, hasAuthenticatedSession: { true })
        let prepared = try await coordinator.preparePhoto(data: sampleJPEG())
        let photo = try LocalDishPhotoStore(context: context, photoFiles: files).createLocalPhoto(
            prepared: prepared, kind: .visit, restaurantId: parents.restaurant.id,
            visitId: parents.visit.id, queueForUpload: false)
        let paths = prepared.allRelativePaths
        photo.serverVersion = 1
        photo.syncStatus = .synced
        _ = try await coordinator.imageData(for: photo, variant: .thumbnail)
        await api.failDeletes(true)
        try await coordinator.delete(photo)
        #expect(photo.deletedAt != nil)
        #expect(photo.uploadState == .deleted)
        #expect(photo.binaryDeletedAt == nil)
        #expect(try SwiftDataSyncQueue(context: context).allMutations().contains { $0.entityType == .photo && $0.operation == .delete })
        do {
            _ = try await coordinator.imageData(for: photo, variant: .thumbnail)
            Issue.record("Deleted cached photo was returned")
        } catch { }
        photo.syncStatus = .synced
        await coordinator.processNowForTesting()
        #expect(photo.binaryDeletedAt == nil)
        #expect(photo.uploadRetryCount > 0)
        #expect(photo.uploadLastError != nil)
        await api.failDeletes(false)
        photo.uploadRetryAfter = nil
        await coordinator.processNowForTesting()
        #expect(photo.binaryDeletedAt != nil)
        #expect(photo.deletedAt != nil)
        for path in paths { #expect(await files.fileExists(relativePath: path) == false) }
        #expect(try context.fetch(FetchDescriptor<Visit>()).contains { $0.id == parents.visit.id })
    }

    @Test("Photo deletion checks owner before tombstone or binary mutation")
    func rejectsForeignPhotoDeletion() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let photo = PhotoAsset(ownerUserID: "another-owner", kind: .avatar, mimeType: "image/jpeg", byteSize: 1)
        container.mainContext.insert(photo)
        let api = MockPhotoBinaryAPI()
        let coordinator = PhotoTransferCoordinator(context: container.mainContext, api: api,
            files: try LocalPhotoFileStore(rootURL: directory), hasAuthenticatedSession: { true })
        do { try await coordinator.delete(photo); Issue.record("Foreign deletion was accepted") } catch { }
        #expect(photo.deletedAt == nil)
        #expect(await api.deleteCallCount() == 0)
    }

    @Test("A display-only QA owner without a session cannot authorize photo deletion")
    func rejectsMissingSessionDeletion() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let photo = PhotoAsset(kind: .avatar, mimeType: "image/jpeg", byteSize: 1)
        container.mainContext.insert(photo)
        let api = MockPhotoBinaryAPI()
        let coordinator = PhotoTransferCoordinator(context: container.mainContext, api: api,
            files: try LocalPhotoFileStore(rootURL: directory), hasAuthenticatedSession: { false })
        do { try await coordinator.delete(photo); Issue.record("Missing session authorized deletion") }
        catch { #expect(error as? PhotoBinaryAPIError == .server(status: 403, message: "只能删除自己上传的照片。")) }
        #expect(photo.deletedAt == nil)
        #expect(try SwiftDataSyncQueue(context: container.mainContext).allMutations().isEmpty)
        #expect(await api.deleteCallCount() == 0)
    }

    @Test("Restaurant bridge exposes delete authority only for active current-owner photo IDs")
    func bridgePhotoDeleteAuthority() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let parents = insertParents(context)
        parents.restaurant.ownerUserID = "tm_photo_owner"
        parents.visit.ownerUserID = "tm_photo_owner"
        let own = PhotoAsset(ownerUserID: "tm_photo_owner", restaurantId: parents.restaurant.id,
            visitId: parents.visit.id, kind: .visit, mimeType: "image/jpeg", byteSize: 1)
        let foreign = PhotoAsset(ownerUserID: "tm_someone_else", restaurantId: parents.restaurant.id,
            visitId: parents.visit.id, kind: .visit, mimeType: "image/jpeg", byteSize: 1)
        context.insert(own); context.insert(foreign)
        try context.save()
        let before = try TasteMapHybridBridgeService(container: container, ownerUserID: "tm_photo_owner")
            .restaurantDetail(id: parents.restaurant.id.uuidString)
        #expect(before.deletablePhotoIDs?.contains(own.id.uuidString.lowercased()) == true)
        #expect(before.deletablePhotoIDs?.contains(foreign.id.uuidString.lowercased()) == false)
        own.deletedAt = .now
        try context.save()
        let after = try TasteMapHybridBridgeService(container: container, ownerUserID: "tm_photo_owner")
            .restaurantDetail(id: parents.restaurant.id.uuidString)
        #expect(after.deletablePhotoIDs?.isEmpty == true)
    }

    private func insertParents(_ context: ModelContext) -> (restaurant: Restaurant, visit: Visit) {
        let restaurant = Restaurant(
            name: "照片测试餐厅",
            address: "杭州",
            latitude: 30,
            longitude: 120,
            appleMapItemIdentifier: "p2b-apple-map",
            remoteID: UUID().uuidString.lowercased()
        )
        let visit = Visit(
            restaurantId: restaurant.id,
            remoteID: UUID().uuidString.lowercased()
        )
        context.insert(restaurant)
        context.insert(visit)
        try? context.save()
        return (restaurant, visit)
    }

    private func sampleJPEG() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1_200, height: 900), format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 900))
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 180, y: 180, width: 840, height: 540))
        }
        return image.jpegData(compressionQuality: 0.95)!
    }

    private func orientedJPEG(width: Int, height: Int, orientation: Int) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(
            destination,
            try #require(image.cgImage),
            [kCGImagePropertyOrientation: orientation] as CFDictionary
        )
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func encodedImage(type: UTType) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 640, height: 480),
            format: format
        ).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        }
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output,
            type.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, try #require(image.cgImage), nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private actor MockPhotoBinaryAPI: PhotoBinaryAPI {
    private var objects: [PhotoBinaryVariant: Data] = [:]
    private var uploads = 0
    private var downloads = 0
    private var deletes = 0
    private var shouldLoseFirstResponse: Bool
    private var deleteFailure = false

    init(failFirstUploadResponse: Bool = false) {
        shouldLoseFirstResponse = failFirstUploadResponse
    }

    func upload(
        photoID: UUID,
        mutationID: UUID,
        variant: PhotoBinaryVariant,
        data: Data,
        contentType: String,
        checksum: String
    ) async throws -> PhotoBinaryUploadResponse {
        uploads += 1
        let duplicate = objects[variant] != nil
        objects[variant] = data
        if shouldLoseFirstResponse {
            shouldLoseFirstResponse = false
            throw URLError(.networkConnectionLost)
        }
        return PhotoBinaryUploadResponse(
            apiVersion: 1,
            photoId: photoID.uuidString.lowercased(),
            variant: variant,
            storageProvider: .r2,
            storageKey: "users/test/photos/\(photoID.uuidString.lowercased())/\(variant.rawValue).jpg",
            contentType: contentType,
            byteSize: Int64(data.count),
            checksum: checksum,
            duplicate: duplicate
        )
    }

    func download(photoID: UUID, variant: PhotoBinaryVariant) async throws -> Data {
        downloads += 1
        guard let data = objects[variant] else { throw URLError(.fileDoesNotExist) }
        return data
    }

    func delete(photoID: UUID) async throws {
        deletes += 1
        if deleteFailure { throw URLError(.timedOut) }
        objects.removeAll()
    }

    func failDeletes(_ value: Bool) { deleteFailure = value }

    func seedDownload(_ data: Data, variant: PhotoBinaryVariant) { objects[variant] = data }
    func uniqueObjectCount() -> Int { objects.count }
    func uploadCallCount() -> Int { uploads }
    func downloadCallCount() -> Int { downloads }
    func deleteCallCount() -> Int { deletes }
}

private actor PermanentlyRejectingPhotoBinaryAPI: PhotoBinaryAPI {
    private var uploads = 0

    func upload(
        photoID: UUID,
        mutationID: UUID,
        variant: PhotoBinaryVariant,
        data: Data,
        contentType: String,
        checksum: String
    ) async throws -> PhotoBinaryUploadResponse {
        uploads += 1
        throw PhotoBinaryAPIError.server(status: 422, message: "invalid photo contract")
    }

    func download(photoID: UUID, variant: PhotoBinaryVariant) async throws -> Data {
        throw PhotoBinaryAPIError.server(status: 404, message: "not found")
    }

    func delete(photoID: UUID) async throws {}

    func uploadCallCount() -> Int { uploads }
}
