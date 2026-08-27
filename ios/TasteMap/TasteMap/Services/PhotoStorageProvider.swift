import Foundation

struct PhotoMetadata: Codable, Hashable, Sendable {
    var contentType: String
    var pixelWidth: Int?
    var pixelHeight: Int?
    var createdAt: Date
}

struct StoredPhotoReference: Codable, Hashable, Sendable {
    var storageProvider: String
    var storageKey: String
    var metadata: PhotoMetadata
}

protocol PhotoStorageProvider: Sendable {
    func upload(data: Data, metadata: PhotoMetadata) async throws -> StoredPhotoReference
    func load(storageKey: String) async throws -> Data
    func delete(storageKey: String) async throws
}
