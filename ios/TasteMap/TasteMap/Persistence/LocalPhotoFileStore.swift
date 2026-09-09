import Foundation

enum LocalPhotoFileStoreError: Error, Equatable {
    case unsupportedFileType
    case invalidRelativePath
    case fileMissing
}

enum LocalPhotoFileVariant: String, Sendable {
    case original = "originals"
    case display = "display"
    case thumbnail = "thumbnails"
}

protocol LocalPhotoFileStoring: Sendable {
    func save(_ data: Data, photoID: UUID, mimeType: String) async throws -> String
    func save(_ data: Data, photoID: UUID, mimeType: String, variant: LocalPhotoFileVariant) async throws -> String
    func load(relativePath: String) async throws -> Data
    func delete(relativePath: String) async throws
    func fileExists(relativePath: String) async -> Bool
    func cleanupOrphans(retaining relativePaths: Set<String>) async throws
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
        try save(data, photoID: photoID, mimeType: mimeType, variant: .original)
    }

    func save(
        _ data: Data,
        photoID: UUID,
        mimeType: String,
        variant: LocalPhotoFileVariant
    ) throws -> String {
        let fileManager = FileManager.default
        let path = "\(variant.rawValue)/\(photoID.uuidString.lowercased()).\(try fileExtension(for: mimeType))"
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

    func cleanupOrphans(retaining relativePaths: Set<String>) throws {
        let fileManager = FileManager.default
        // The legacy and Development stores share TasteMap/Photos. One store's
        // reference set cannot prove another store's files are orphaned. Retain
        // unreferenced files in this case; explicit tombstone deletion remains
        // independent and still removes the authorized photo's sandbox copies.
        let support = rootURL.deletingLastPathComponent().deletingLastPathComponent()
        if rootURL.lastPathComponent == "Photos",
           rootURL.deletingLastPathComponent().lastPathComponent == "TasteMap",
           fileManager.fileExists(atPath: support.appendingPathComponent("TasteMap.store").path),
           fileManager.fileExists(atPath: support.appendingPathComponent("TasteMapDevelopment.store").path) {
            return
        }
        for variant in [LocalPhotoFileVariant.original, .display, .thumbnail] {
            let directory = rootURL.appendingPathComponent(variant.rawValue, isDirectory: true)
            guard let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for file in files {
                let relativePath = "\(variant.rawValue)/\(file.lastPathComponent)"
                if !relativePaths.contains(relativePath) {
                    try fileManager.removeItem(at: file)
                }
            }
        }
    }

    private func fileExtension(for mimeType: String) throws -> String {
        switch mimeType.lowercased() {
        case "image/jpeg", "image/jpg": "jpg"
        case "image/heic", "image/heif": "heic"
        case "image/png": "png"
        default: throw LocalPhotoFileStoreError.unsupportedFileType
        }
    }

    nonisolated static func supports(mimeType: String) -> Bool {
        switch mimeType.lowercased() {
        case "image/jpeg", "image/jpg", "image/heic", "image/heif", "image/png": true
        default: false
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
