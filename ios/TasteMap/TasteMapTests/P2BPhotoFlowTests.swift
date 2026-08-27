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
        objects.removeAll()
    }

    func seedDownload(_ data: Data, variant: PhotoBinaryVariant) { objects[variant] = data }
    func uniqueObjectCount() -> Int { objects.count }
    func uploadCallCount() -> Int { uploads }
    func downloadCallCount() -> Int { downloads }
    func deleteCallCount() -> Int { deletes }
}
