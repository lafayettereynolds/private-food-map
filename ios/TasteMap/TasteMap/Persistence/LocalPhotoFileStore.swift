import Foundation

enum LocalPhotoFileStoreError: Error, Equatable {
    case unsupportedFileType
    case invalidRelativePath
    case fileMissing
}

protocol LocalPhotoFileStoring: Sendable {
    func save(_ data: Data, photoID: UUID, mimeType: String) async throws -> String
    func load(relativePath: String) async throws -> Data
    func delete(relativePath: String) async throws
    func fileExists(relativePath: String) async -> Bool
}

actor LocalPhotoFileStore: LocalPhotoFileStoring {
    private let rootURL: URL

    init(rootURL: URL? = nil) throws {
        let fileManager = FileManager.default
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.rootURL = applicationSupport
                .appendingPathComponent("TasteMap", isDirectory: true)
                .appendingPathComponent("Photos", isDirectory: true)
        }
        try fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
    }

    func save(_ data: Data, photoID: UUID, mimeType: String) throws -> String {
        let fileManager = FileManager.default
        let path = "originals/\(photoID.uuidString.lowercased()).\(try fileExtension(for: mimeType))"
        let destination = try resolvedURL(relativePath: path)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: [.atomic])
        return path
    }

    func load(relativePath: String) throws -> Data {
        let fileManager = FileManager.default
        let url = try resolvedURL(relativePath: relativePath)
        guard fileManager.fileExists(atPath: url.path) else { throw LocalPhotoFileStoreError.fileMissing }
        return try Data(contentsOf: url)
    }

    func delete(relativePath: String) throws {
        let fileManager = FileManager.default
        let url = try resolvedURL(relativePath: relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func fileExists(relativePath: String) -> Bool {
        let fileManager = FileManager.default
        guard let url = try? resolvedURL(relativePath: relativePath) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    private func fileExtension(for mimeType: String) throws -> String {
        switch mimeType.lowercased() {
        case "image/jpeg", "image/jpg": "jpg"
        case "image/heic", "image/heif": "heic"
        case "image/png": "png"
        default: throw LocalPhotoFileStoreError.unsupportedFileType
        }
    }

    private func resolvedURL(relativePath: String) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else {
            throw LocalPhotoFileStoreError.invalidRelativePath
        }
        let resolved = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.path + "/"
        guard resolved.path.hasPrefix(rootPath) else { throw LocalPhotoFileStoreError.invalidRelativePath }
        return resolved
    }
}
