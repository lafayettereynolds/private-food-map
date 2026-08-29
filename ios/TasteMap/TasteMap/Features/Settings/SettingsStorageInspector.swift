import Foundation

nonisolated struct SettingsStorageSnapshot: Equatable, Sendable {
    let originalPhotoBytes: Int64
    let displayPhotoBytes: Int64
    let thumbnailPhotoBytes: Int64

    static let empty = SettingsStorageSnapshot(
        originalPhotoBytes: 0,
        displayPhotoBytes: 0,
        thumbnailPhotoBytes: 0
    )

    var totalPhotoBytes: Int64 {
        originalPhotoBytes + displayPhotoBytes + thumbnailPhotoBytes
    }

    static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

actor SettingsStorageInspector {
    private let photoRootURL: URL

    init(photoRootURL: URL? = nil) {
        self.photoRootURL = photoRootURL ?? URL.applicationSupportDirectory
            .appending(path: "TasteMap", directoryHint: .isDirectory)
            .appending(path: "Photos", directoryHint: .isDirectory)
    }

    func snapshot() throws -> SettingsStorageSnapshot {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: photoRootURL.path) else { return .empty }
        guard let enumerator = fileManager.enumerator(
            at: photoRootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return .empty }

        var originals: Int64 = 0
        var displays: Int64 = 0
        var thumbnails: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            let relativePath = fileURL.path.replacingOccurrences(
                of: photoRootURL.standardizedFileURL.path + "/",
                with: ""
            )
            switch relativePath.split(separator: "/").first.map(String.init) {
            case LocalPhotoFileVariant.original.rawValue: originals += size
            case LocalPhotoFileVariant.display.rawValue: displays += size
            case LocalPhotoFileVariant.thumbnail.rawValue: thumbnails += size
            default: continue
            }
        }
        return SettingsStorageSnapshot(
            originalPhotoBytes: originals,
            displayPhotoBytes: displays,
            thumbnailPhotoBytes: thumbnails
        )
    }
}
