import Foundation
import SwiftData

enum PhotoAssetKind: String, Codable, CaseIterable, Sendable {
    case restaurantMarker = "restaurant-marker"
    case visit
    case dish
    case avatar
}

enum PhotoVisibility: String, Codable, CaseIterable, Sendable {
    case `private`
    case friends
    case `public`
}

enum PhotoUploadState: String, Codable, CaseIterable, Sendable {
    case localOnly
    case queued
    case uploading
    case uploaded
    case failed
    case deleted
}

@Model
final class PhotoAsset {
    @Attribute(.unique) var id: UUID
    var restaurantId: UUID?
    var visitId: UUID?
    var dishId: UUID?
    private var kindValue: String
    private var storageProviderValue: String?
    var storageKey: String?
    var providerAccountId: String?
    var thumbnailStorageKey: String?
    var fileName: String?
    var mimeType: String
    var byteSize: Int64
    var width: Int?
    var height: Int?
    var sortOrder: Int
    private var visibilityValue: String
    var localFileRelativePath: String?
    var displayFileRelativePath: String?
    var thumbnailFileRelativePath: String?
    var displayContentHash: String?
    var thumbnailContentHash: String?
    var cachedStorageKey: String?
    var cachedThumbnailStorageKey: String?
    private var uploadStateValue: String
    var uploadRetryCount: Int
    var uploadLastError: String?
    var uploadRetryAfter: Date?
    var uploadMutationID: UUID?
    var binaryDeletedAt: Date?
    var draftSessionID: UUID?
    var createdAt: Date
    var updatedAt: Date
    @Attribute(.unique) var remoteID: String?
    var deletedAt: Date?
    var serverVersion: Int64
    var lastSyncedAt: Date?
    var remoteRecordData: Data?
    private var syncStatusValue: String

    var kind: PhotoAssetKind {
        get { PhotoAssetKind(rawValue: kindValue) ?? .visit }
        set { kindValue = newValue.rawValue }
    }

    var storageProvider: PhotoStorageProviderID? {
        get { storageProviderValue.flatMap(PhotoStorageProviderID.init(rawValue:)) }
        set { storageProviderValue = newValue?.rawValue }
    }

    var visibility: PhotoVisibility {
        get { PhotoVisibility(rawValue: visibilityValue) ?? .private }
        set { visibilityValue = newValue.rawValue }
    }

    var uploadState: PhotoUploadState {
        get { PhotoUploadState(rawValue: uploadStateValue) ?? .localOnly }
        set { uploadStateValue = newValue.rawValue }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusValue) ?? .pending }
        set { syncStatusValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        restaurantId: UUID? = nil,
        visitId: UUID? = nil,
        dishId: UUID? = nil,
        kind: PhotoAssetKind,
        storageProvider: PhotoStorageProviderID? = nil,
        storageKey: String? = nil,
        providerAccountId: String? = nil,
        thumbnailStorageKey: String? = nil,
        fileName: String? = nil,
        mimeType: String,
        byteSize: Int64,
        width: Int? = nil,
        height: Int? = nil,
        sortOrder: Int = 0,
        visibility: PhotoVisibility = .private,
        localFileRelativePath: String? = nil,
        displayFileRelativePath: String? = nil,
        thumbnailFileRelativePath: String? = nil,
        displayContentHash: String? = nil,
        thumbnailContentHash: String? = nil,
        cachedStorageKey: String? = nil,
        cachedThumbnailStorageKey: String? = nil,
        uploadState: PhotoUploadState = .localOnly,
        uploadRetryCount: Int = 0,
        uploadLastError: String? = nil,
        uploadRetryAfter: Date? = nil,
        uploadMutationID: UUID? = nil,
        binaryDeletedAt: Date? = nil,
        draftSessionID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        remoteID: String? = nil,
        deletedAt: Date? = nil,
        serverVersion: Int64 = 0,
        lastSyncedAt: Date? = nil,
        syncStatus: SyncStatus = .pending,
        remoteRecordData: Data? = nil
    ) {
        self.id = id
        self.restaurantId = restaurantId
        self.visitId = visitId
        self.dishId = dishId
        self.kindValue = kind.rawValue
        self.storageProviderValue = storageProvider?.rawValue
        self.storageKey = storageKey
        self.providerAccountId = providerAccountId
        self.thumbnailStorageKey = thumbnailStorageKey
        self.fileName = fileName
        self.mimeType = mimeType
        self.byteSize = max(0, byteSize)
        self.width = width.flatMap { $0 > 0 ? $0 : nil }
        self.height = height.flatMap { $0 > 0 ? $0 : nil }
        self.sortOrder = max(0, sortOrder)
        self.visibilityValue = visibility.rawValue
        self.localFileRelativePath = localFileRelativePath
        self.displayFileRelativePath = displayFileRelativePath
        self.thumbnailFileRelativePath = thumbnailFileRelativePath
        self.displayContentHash = displayContentHash
        self.thumbnailContentHash = thumbnailContentHash
        self.cachedStorageKey = cachedStorageKey
        self.cachedThumbnailStorageKey = cachedThumbnailStorageKey
        self.uploadStateValue = uploadState.rawValue
        self.uploadRetryCount = max(0, uploadRetryCount)
        self.uploadLastError = uploadLastError
        self.uploadRetryAfter = uploadRetryAfter
        self.uploadMutationID = uploadMutationID
        self.binaryDeletedAt = binaryDeletedAt
        self.draftSessionID = draftSessionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.remoteID = remoteID ?? id.uuidString.lowercased()
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.lastSyncedAt = lastSyncedAt
        self.syncStatusValue = syncStatus.rawValue
        self.remoteRecordData = remoteRecordData
    }
}
