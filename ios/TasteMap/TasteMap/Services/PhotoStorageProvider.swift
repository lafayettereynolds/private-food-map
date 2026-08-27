import Foundation

enum PhotoStorageProviderID: String, Codable, CaseIterable, Sendable {
    case googleDrive = "google-drive"
    case cloudKit = "cloudkit"
    case r2
    case oss
    case cos
}

struct PhotoMetadata: Codable, Hashable, Sendable {
    var contentType: String
    var pixelWidth: Int?
    var pixelHeight: Int?
    var byteSize: Int64
    var originalFileName: String?
    var createdAt: Date
}

struct StoredPhotoReference: Codable, Hashable, Sendable {
    var storageProvider: PhotoStorageProviderID
    var storageKey: String
    var providerAccountId: String?
    var thumbnailStorageKey: String?
    var metadata: PhotoMetadata
}

protocol PhotoStorageProvider: Sendable {
    func upload(data: Data, metadata: PhotoMetadata) async throws -> StoredPhotoReference
    func load(storageKey: String) async throws -> Data
    func delete(storageKey: String) async throws
}
