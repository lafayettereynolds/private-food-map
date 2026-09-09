import Foundation
import Network
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class PhotoTransferCoordinator {
    private(set) var isProcessing = false

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let api: any PhotoBinaryAPI
    @ObservationIgnored private let files: any LocalPhotoFileStoring
    @ObservationIgnored private let authenticatedUserIDProvider: @Sendable () async -> String?
    @ObservationIgnored private let synchronizeMetadata: @MainActor () async -> Void
    @ObservationIgnored private let networkObserver: NetworkPathObserver?
    @ObservationIgnored private var networkAvailable = true
    @ObservationIgnored private var started = false
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var authObserver: NSObjectProtocol?
    @ObservationIgnored private var manualRetryObserver: NSObjectProtocol?
    @ObservationIgnored private var imageLoads: [String: Task<Data, Error>] = [:]
    @ObservationIgnored private var uploadingPhotoIDs: Set<UUID> = []
    /// NSCache is thread-safe and automatically responds to memory pressure.
    /// The coordinator is MainActor-isolated, so this is a bounded decoded-
    /// source-data cache rather than a second persistent photo store.
    @ObservationIgnored private let imageDataCache = NSCache<NSString, NSData>()
    @ObservationIgnored private var imageCacheKeys: [UUID: Set<NSString>] = [:]
    @ObservationIgnored private var rerunAfterProcessing = false

    init(
        context: ModelContext,
        api: any PhotoBinaryAPI,
        files: any LocalPhotoFileStoring,
        sessionManager: AuthSessionManager,
        syncCoordinator: SyncCoordinator,
        networkObserver: NetworkPathObserver?
    ) {
        self.context = context
        self.api = api
        self.files = files
        self.networkObserver = networkObserver
        authenticatedUserIDProvider = { await sessionManager.restoredUser()?.id }
        synchronizeMetadata = { await syncCoordinator.synchronizeNow() }
        configureImageDataCache()
    }

    init(
        context: ModelContext,
        api: any PhotoBinaryAPI,
        files: any LocalPhotoFileStoring,
        hasAuthenticatedSession: @escaping @Sendable () async -> Bool,
        synchronizeMetadata: @escaping @MainActor () async -> Void = {},
        networkObserver: NetworkPathObserver? = nil
    ) {
        self.context = context
        self.api = api
        self.files = files
        authenticatedUserIDProvider = {
            await hasAuthenticatedSession() ? LocalAccountOwner.guest : nil
        }
        self.synchronizeMetadata = synchronizeMetadata
        self.networkObserver = networkObserver
        configureImageDataCache()
    }

    func start() {
        guard !started else { return }
        started = true
        authObserver = NotificationCenter.default.addObserver(
            forName: .tasteMapAuthSessionAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.prepareAuthenticationRetry()
                self?.scheduleProcessing()
            }
        }
        manualRetryObserver = NotificationCenter.default.addObserver(
            forName: .tasteMapManualSyncRetryRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.prepareManualRetry()
                self?.scheduleProcessing()
            }
        }
        networkObserver?.start { [weak self] available in
            Task { @MainActor [weak self] in
                self?.networkAvailable = available
                if available { self?.scheduleProcessing() }
            }
        }
        Task { @MainActor [weak self] in
            guard let self, let ownerUserID = await self.authenticatedUserIDProvider() else { return }
            self.recoverInterruptedUploads(ownerUserID: ownerUserID)
            await self.cleanupAbandonedDraftPhotos(ownerUserID: ownerUserID)
            await self.cleanupOrphanedFiles()
            self.scheduleProcessing()
        }
    }

    func handleAppBecameActive() {
        if !started { start() }
        scheduleProcessing()
    }

    func processNowForTesting() async {
        await processPending()
    }

    func enqueue(_ photo: PhotoAsset) throws {
        try LocalDishPhotoStore(context: context, photoFiles: files).queueUpload(photo)
        scheduleProcessing()
    }

    func retry(_ photo: PhotoAsset) throws {
        DeviceAcceptanceLog.record("TasteMapDiagnostic category=photo event=manual_retry")
        if photo.deletedAt != nil {
            photo.uploadLastError = nil
            photo.uploadRetryAfter = nil
            try context.save()
            scheduleProcessing()
            return
        }
        try enqueue(photo)
    }

    func setDishRelationship(_ photo: PhotoAsset, dish: Dish?) throws {
        try LocalDishPhotoStore(context: context, photoFiles: files)
            .setDishRelationship(photo, dish: dish)
    }

    func resumePendingTransfers() {
        scheduleProcessing()
    }

    func preparePhoto(
        data: Data,
        suggestedContentType: String? = nil,
        originalFileName: String? = nil
    ) async throws -> PreparedLocalPhoto {
        try await PhotoImportService(files: files).prepare(
            data: data,
            suggestedContentType: suggestedContentType,
            originalFileName: originalFileName
        )
    }

    @discardableResult
    func attachPreparedPhoto(
        _ prepared: PreparedLocalPhoto,
        restaurantID: UUID,
        visitID: UUID,
        sortOrder: Int,
        visibility: PhotoVisibility = .private,
        queueForUpload: Bool,
        draftSessionID: UUID? = nil
    ) throws -> PhotoAsset {
        try LocalDishPhotoStore(context: context, photoFiles: files).createLocalPhoto(
            prepared: prepared,
            kind: .visit,
            restaurantId: restaurantID,
            visitId: visitID,
            sortOrder: sortOrder,
            visibility: visibility,
            queueForUpload: queueForUpload,
            draftSessionID: draftSessionID
        )
    }

    @discardableResult
    func attachPreparedRestaurantMarker(
        _ prepared: PreparedLocalPhoto,
        restaurantID: UUID,
        queueForUpload: Bool = true
    ) throws -> PhotoAsset {
        try LocalDishPhotoStore(context: context, photoFiles: files).createLocalPhoto(
            prepared: prepared,
            kind: .restaurantMarker,
            restaurantId: restaurantID,
            visibility: .private,
            queueForUpload: queueForUpload
        )
    }

    @discardableResult
    func attachPreparedAvatar(
        _ prepared: PreparedLocalPhoto,
        queueForUpload: Bool = true,
        ownerUserID: String = LocalAccountOwner.guest
    ) throws -> PhotoAsset {
        try LocalDishPhotoStore(context: context, photoFiles: files).createLocalPhoto(
            prepared: prepared,
            kind: .avatar,
            visibility: .private,
            queueForUpload: queueForUpload,
            ownerUserID: ownerUserID
        )
    }

    func delete(_ photo: PhotoAsset) async throws {
        DeviceAcceptanceLog.record("TasteMapDiagnostic category=photo event=delete_requested")
        guard await authenticatedUserIDProvider() == photo.ownerUserID else {
            throw PhotoBinaryAPIError.server(status: 403, message: "只能删除自己上传的照片。")
        }
        let cacheKeys = [PhotoBinaryVariant.display, .thumbnail].map { imageCacheKey(for: photo, variant: $0) }
        try LocalDishPhotoStore(context: context, photoFiles: files).delete(photo)
        for key in cacheKeys { imageDataCache.removeObject(forKey: key) }
        invalidatePhotoMemory(photo.id)
        for variant in [PhotoBinaryVariant.display, .thumbnail] {
            imageLoads["\(photo.id.uuidString):\(variant.rawValue)"]?.cancel()
        }
        NotificationCenter.default.post(name: .tasteMapLocalDataDidChange, object: nil)
        // The persisted local tombstone is the UI acknowledgement, not cloud
        // completion. A restart resumes the same durable queue/cleanup state.
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.purgeDeletedLocalFiles(photo)
            await self.synchronizeMetadata()
            self.scheduleProcessing()
        }
    }

    func discardLocalPhoto(_ photo: PhotoAsset) async throws {
        try await LocalDishPhotoStore(context: context, photoFiles: files).discardLocalPhoto(photo)
    }

    func discardPrepared(_ prepared: PreparedLocalPhoto) async {
        for path in prepared.allRelativePaths { try? await files.delete(relativePath: path) }
    }

    func imageData(for photo: PhotoAsset, variant: PhotoBinaryVariant) async throws -> Data {
        guard photo.deletedAt == nil else { throw PhotoBinaryAPIError.server(status: 404, message: "照片已删除。") }
        let cacheKey = imageCacheKey(for: photo, variant: variant)
        if let cached = imageDataCache.object(forKey: cacheKey) {
            return cached as Data
        }
        let localPath = variant == .thumbnail
            ? (photo.thumbnailFileRelativePath ?? photo.displayFileRelativePath ?? photo.localFileRelativePath)
            : (photo.displayFileRelativePath ?? photo.localFileRelativePath)
        if let localPath, let data = try? await files.load(relativePath: localPath) {
            guard photo.deletedAt == nil else { throw CancellationError() }
            imageDataCache.setObject(data as NSData, forKey: cacheKey, cost: data.count)
            imageCacheKeys[photo.id, default: []].insert(cacheKey)
            return data
        }

        let remoteVariant: PhotoBinaryVariant = variant == .thumbnail && photo.thumbnailStorageKey == nil
            ? .display
            : variant
        let key = "\(photo.id.uuidString):\(remoteVariant.rawValue)"
        if let task = imageLoads[key] {
            let data = try await task.value
            guard photo.deletedAt == nil else { throw CancellationError() }
            return data
        }
        let api = self.api
        let photoID = photo.id
        let task = Task<Data, Error> { try await api.download(photoID: photoID, variant: remoteVariant) }
        imageLoads[key] = task
        defer { imageLoads[key] = nil }
        let data = try await task.value
        guard photo.deletedAt == nil else { throw CancellationError() }
        let path = try await files.save(
            data,
            photoID: photo.id,
            mimeType: photo.mimeType,
            variant: variant == .thumbnail ? .thumbnail : .display
        )
        guard photo.deletedAt == nil else {
            try? await files.delete(relativePath: path)
            throw CancellationError()
        }
        if variant == .thumbnail {
            photo.thumbnailFileRelativePath = path
            photo.cachedThumbnailStorageKey = photo.thumbnailStorageKey ?? photo.storageKey
        } else {
            photo.displayFileRelativePath = path
            photo.cachedStorageKey = photo.storageKey
        }
        try context.save()
        imageDataCache.setObject(data as NSData, forKey: cacheKey, cost: data.count)
        imageCacheKeys[photo.id, default: []].insert(cacheKey)
        return data
    }

    func localData(relativePath: String) async throws -> Data {
        try await files.load(relativePath: relativePath)
    }

    func purgeTransientImageDataCache() {
        imageDataCache.removeAllObjects()
        imageCacheKeys.removeAll()
    }

    private func configureImageDataCache() {
        imageDataCache.countLimit = 192
        imageDataCache.totalCostLimit = 32 * 1_024 * 1_024
    }

    private func imageCacheKey(for photo: PhotoAsset, variant: PhotoBinaryVariant) -> NSString {
        let sourceVersion = variant == .thumbnail
            ? (photo.thumbnailContentHash ?? photo.cachedThumbnailStorageKey ?? photo.thumbnailStorageKey)
            : (photo.displayContentHash ?? photo.cachedStorageKey ?? photo.storageKey)
        return "\(photo.id.uuidString):\(variant.rawValue):\(sourceVersion ?? "local"):\(photo.updatedAt.timeIntervalSince1970)" as NSString
    }

    private func scheduleProcessing() {
        guard networkAvailable else { return }
        if processingTask != nil {
            rerunAfterProcessing = true
            return
        }
        processingTask = Task { @MainActor [weak self] in
            await self?.processPending()
            self?.processingTask = nil
            if self?.rerunAfterProcessing == true {
                self?.rerunAfterProcessing = false
                self?.scheduleProcessing()
            }
        }
    }

    private func processPending() async {
        guard let ownerUserID = await authenticatedUserIDProvider() else { return }
        isProcessing = true
        defer { isProcessing = false }
        let now = Date()
        let photos = (try? context.fetch(FetchDescriptor<PhotoAsset>())) ?? []
        let pending = photos
            .filter {
                $0.ownerUserID == ownerUserID &&
                $0.deletedAt == nil &&
                ($0.uploadState == .queued || $0.uploadState == .failed) &&
                automaticRetryAllowed($0) &&
                ($0.uploadRetryAfter == nil || $0.uploadRetryAfter! <= now)
            }
            .sorted { $0.createdAt < $1.createdAt }
        var uploadedAny = false
        for photo in pending {
            guard !Task.isCancelled, networkAvailable else { break }
            do {
                try await upload(photo)
                DeviceAcceptanceLog.record("TasteMapDiagnostic category=photo event=upload_complete")
                uploadedAny = true
            } catch {
                let disposition = SyncErrorClassifier.disposition(for: error)
                DeviceAcceptanceLog.record("TasteMapDiagnostic category=photo event=upload_failed disposition=\(disposition.rawValue)")
                if disposition == .cancelled { continue }
                let retryAfter = disposition == .retryable
                    ? Date().addingTimeInterval(min(pow(2, Double(photo.uploadRetryCount)) * 5, 300))
                    : nil
                try? LocalDishPhotoStore(context: context, photoFiles: files).markUploadFailed(
                    photo,
                    reason: "\(disposition.rawValue):\(friendlyMessage(error))",
                    retryAfter: retryAfter
                )
            }
        }
        if uploadedAny { await synchronizeMetadata() }
        for photo in photos where photo.ownerUserID == ownerUserID &&
            photo.deletedAt != nil && photo.binaryDeletedAt == nil {
            await cleanupDeletedBinary(photo)
        }
        scheduleRetryIfNeeded(ownerUserID: ownerUserID)
    }

    private func upload(_ photo: PhotoAsset) async throws {
        guard photo.deletedAt == nil else { return }
        uploadingPhotoIDs.insert(photo.id)
        defer { uploadingPhotoIDs.remove(photo.id) }
        guard let displayPath = photo.displayFileRelativePath ?? photo.localFileRelativePath,
              let thumbnailPath = photo.thumbnailFileRelativePath else {
            throw PhotoImportError.invalidImage
        }
        try LocalDishPhotoStore(context: context, photoFiles: files).markUploading(photo)
        let displayData = try await files.load(relativePath: displayPath)
        let thumbnailData = try await files.load(relativePath: thumbnailPath)
        guard photo.deletedAt == nil else { return }
        let displayHash = photo.displayContentHash ?? PhotoImportService.sha256(displayData)
        let thumbnailHash = photo.thumbnailContentHash ?? PhotoImportService.sha256(thumbnailData)
        let mutationID = photo.uploadMutationID ?? UUID()
        photo.uploadMutationID = mutationID
        try context.save()
        let display = try await api.upload(
            photoID: photo.id,
            mutationID: mutationID,
            variant: .display,
            data: displayData,
            contentType: "image/jpeg",
            checksum: displayHash
        )
        guard photo.deletedAt == nil else { return }
        let thumbnail = try await api.upload(
            photoID: photo.id,
            mutationID: mutationID,
            variant: .thumbnail,
            data: thumbnailData,
            contentType: "image/jpeg",
            checksum: thumbnailHash
        )
        try LocalDishPhotoStore(context: context, photoFiles: files).markUploaded(
            photo,
            reference: StoredPhotoReference(
                storageProvider: display.storageProvider,
                storageKey: display.storageKey,
                providerAccountId: nil,
                thumbnailStorageKey: thumbnail.storageKey,
                metadata: PhotoMetadata(
                    contentType: display.contentType,
                    pixelWidth: photo.width,
                    pixelHeight: photo.height,
                    byteSize: display.byteSize,
                    originalFileName: photo.fileName,
                    createdAt: photo.createdAt
                )
            )
        )
    }

    private func cleanupDeletedBinary(_ photo: PhotoAsset) async {
        if photo.deletedAt != nil { invalidatePhotoMemory(photo.id) }
        guard photo.deletedAt != nil, photo.binaryDeletedAt == nil,
              !uploadingPhotoIDs.contains(photo.id),
              automaticRetryAllowed(photo),
              photo.uploadRetryAfter == nil || photo.uploadRetryAfter! <= Date(),
              photo.storageProvider == nil || photo.storageProvider == .r2,
              photo.serverVersion == 0 || photo.syncStatus == .synced else { return }
        guard await authenticatedUserIDProvider() == photo.ownerUserID else { return }
        do {
            try await api.delete(photoID: photo.id)
            try await purgeDeletedLocalFiles(photo)
            photo.binaryDeletedAt = .now
            photo.uploadLastError = nil
            photo.uploadRetryAfter = nil
            try context.save()
        } catch {
            let disposition = SyncErrorClassifier.disposition(for: error)
            photo.uploadRetryCount += 1
            photo.uploadLastError = "\(disposition.rawValue):照片删除尚未同步成功，请重试。"
            photo.uploadRetryAfter = disposition == .retryable
                ? Date().addingTimeInterval(min(pow(2, Double(photo.uploadRetryCount)) * 5, 300)) : nil
            try? context.save()
        }
    }

    private func purgeDeletedLocalFiles(_ photo: PhotoAsset) async throws {
        guard photo.deletedAt != nil else { return }
        // Only sandbox copies. Never call Photos/PHAsset deletion APIs.
        for path in Set([photo.localFileRelativePath, photo.displayFileRelativePath, photo.thumbnailFileRelativePath].compactMap { $0 }) {
            try await files.delete(relativePath: path)
            if photo.localFileRelativePath == path { photo.localFileRelativePath = nil }
            if photo.displayFileRelativePath == path { photo.displayFileRelativePath = nil }
            if photo.thumbnailFileRelativePath == path { photo.thumbnailFileRelativePath = nil }
            try context.save()
        }
    }

    private func invalidatePhotoMemory(_ id: UUID) {
        for key in imageCacheKeys.removeValue(forKey: id) ?? [] {
            imageDataCache.removeObject(forKey: key)
        }
    }

    private func recoverInterruptedUploads(ownerUserID: String) {
        let photos = (try? context.fetch(FetchDescriptor<PhotoAsset>())) ?? []
        for photo in photos where photo.ownerUserID == ownerUserID && photo.uploadState == .uploading {
            photo.uploadState = .queued
            photo.uploadRetryAfter = nil
        }
        try? context.save()
    }

    private func cleanupOrphanedFiles() async {
        guard let referenced = try? LocalDishPhotoStore(
            context: context,
            photoFiles: files
        ).referencedLocalPaths() else { return }
        try? await files.cleanupOrphans(retaining: referenced)
    }

    private func cleanupAbandonedDraftPhotos(ownerUserID: String) async {
        let photos = (try? context.fetch(FetchDescriptor<PhotoAsset>())) ?? []
        let store = LocalDishPhotoStore(context: context, photoFiles: files)
        for photo in photos where photo.ownerUserID == ownerUserID &&
            photo.draftSessionID != nil && photo.serverVersion == 0 {
            try? await store.discardLocalPhoto(photo)
        }
    }

    private func scheduleRetryIfNeeded(ownerUserID: String) {
        retryTask?.cancel()
        let photos = (try? context.fetch(FetchDescriptor<PhotoAsset>())) ?? []
        guard let date = photos.compactMap({ photo in
            photo.ownerUserID == ownerUserID &&
                ((photo.deletedAt == nil && photo.uploadState == .failed)
                 || (photo.deletedAt != nil && photo.binaryDeletedAt == nil)) && automaticRetryAllowed(photo)
                ? photo.uploadRetryAfter
                : nil
        }).min() else { return }
        let delay = max(0, date.timeIntervalSinceNow)
        retryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.scheduleProcessing()
        }
    }

    private func friendlyMessage(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let message = localized.errorDescription {
            return message
        }
        if error is URLError { return "网络暂时不可用，照片会在联网后自动继续上传。" }
        return "照片暂时没有上传成功，稍后会自动重试。"
    }

    private func automaticRetryAllowed(_ photo: PhotoAsset) -> Bool {
        guard photo.uploadState == .failed || photo.deletedAt != nil else { return true }
        return photo.uploadLastError?.hasPrefix("permanent:") != true
            && photo.uploadLastError?.hasPrefix("authentication:") != true
    }

    private func prepareAuthenticationRetry() async {
        guard let ownerUserID = await authenticatedUserIDProvider() else { return }
        let photos = (try? context.fetch(FetchDescriptor<PhotoAsset>())) ?? []
        let store = LocalDishPhotoStore(context: context, photoFiles: files)
        for photo in photos where photo.ownerUserID == ownerUserID && photo.deletedAt != nil
            && photo.binaryDeletedAt == nil && photo.uploadLastError?.hasPrefix("authentication:") == true {
            photo.uploadLastError = nil
            photo.uploadRetryAfter = nil
        }
        try? context.save()
        for photo in photos where photo.ownerUserID == ownerUserID && photo.deletedAt == nil
            && photo.uploadState == .failed
            && photo.uploadLastError?.hasPrefix("authentication:") == true {
            try? store.queueUpload(photo)
        }
    }

    private func prepareManualRetry() async {
        guard let ownerUserID = await authenticatedUserIDProvider() else { return }
        let photos = (try? context.fetch(FetchDescriptor<PhotoAsset>())) ?? []
        let store = LocalDishPhotoStore(context: context, photoFiles: files)
        for photo in photos where photo.ownerUserID == ownerUserID && photo.deletedAt != nil && photo.binaryDeletedAt == nil {
            photo.uploadLastError = nil
            photo.uploadRetryAfter = nil
        }
        try? context.save()
        for photo in photos where photo.ownerUserID == ownerUserID &&
            photo.deletedAt == nil && photo.uploadState == .failed {
            try? store.queueUpload(photo)
        }
    }
}

extension Notification.Name {
    static let tasteMapAuthSessionAvailable = Notification.Name("TasteMapAuthSessionAvailable")
}

private struct PhotoTransferCoordinatorEnvironmentKey: EnvironmentKey {
    static let defaultValue: PhotoTransferCoordinator? = nil
}

extension EnvironmentValues {
    var photoTransferCoordinator: PhotoTransferCoordinator? {
        get { self[PhotoTransferCoordinatorEnvironmentKey.self] }
        set { self[PhotoTransferCoordinatorEnvironmentKey.self] = newValue }
    }
}
