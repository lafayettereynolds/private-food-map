import Foundation

@MainActor
struct BackupExportTemporaryFileStore {
    static let rootDirectoryName = "TasteMapBackupExports"
    static let exportDirectoryPrefix = "export-"
    static let filePrefix = "TasteMap-Backup-"

    let fileManager: FileManager
    let rootDirectoryURL: URL
    let maximumAge: TimeInterval
    let maximumExportCount: Int

    init(
        fileManager: FileManager = .default,
        rootDirectoryURL: URL? = nil,
        maximumAge: TimeInterval = 24 * 60 * 60,
        maximumExportCount: Int = 3
    ) {
        self.fileManager = fileManager
        self.rootDirectoryURL = rootDirectoryURL
            ?? fileManager.temporaryDirectory.appendingPathComponent(Self.rootDirectoryName, isDirectory: true)
        self.maximumAge = maximumAge
        self.maximumExportCount = max(1, maximumExportCount)
    }

    func write(_ data: Data, exportedAt: Date, exportID: UUID) throws -> URL {
        try ensureProtectedDirectory(rootDirectoryURL)
        try cleanup(now: exportedAt)

        let exportDirectory = rootDirectoryURL.appendingPathComponent(
            Self.exportDirectoryPrefix + exportID.uuidString.lowercased(),
            isDirectory: true
        )
        do {
            try ensureProtectedDirectory(exportDirectory)
            let fileURL = exportDirectory.appendingPathComponent(Self.fileName(for: exportedAt))
            try data.write(to: fileURL, options: [.atomic])
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: fileURL.path
            )
            return fileURL
        } catch {
            try? removeExportDirectory(exportDirectory)
            throw BackupExportError.temporaryFileFailed
        }
    }

    func removeArtifact(at fileURL: URL) throws {
        guard isManagedFile(fileURL) else { return }
        let exportDirectory = fileURL.deletingLastPathComponent()
        try? fileManager.removeItem(at: fileURL)
        try removeExportDirectory(exportDirectory)
    }

    func cleanup(now: Date = .now) throws {
        guard fileManager.fileExists(atPath: rootDirectoryURL.path) else { return }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .creationDateKey]
        let children = try fileManager.contentsOfDirectory(
            at: rootDirectoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        var managed: [(url: URL, date: Date)] = []
        for child in children where isManagedExportDirectory(child) {
            let values = try child.resourceValues(forKeys: keys)
            guard values.isDirectory == true else { continue }
            managed.append((child, values.contentModificationDate ?? values.creationDate ?? .distantPast))
        }

        managed.sort { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.url.lastPathComponent < rhs.url.lastPathComponent
        }
        for (index, item) in managed.enumerated() {
            if now.timeIntervalSince(item.date) > maximumAge || index >= maximumExportCount {
                try removeExportDirectory(item.url)
            }
        }
    }

    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(filePrefix)\(formatter.string(from: date)).json"
    }

    private func ensureProtectedDirectory(_ url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    private func isManagedFile(_ url: URL) -> Bool {
        let standardizedRoot = rootDirectoryURL.standardizedFileURL.path + "/"
        let standardizedFile = url.standardizedFileURL.path
        return standardizedFile.hasPrefix(standardizedRoot)
            && url.lastPathComponent.hasPrefix(Self.filePrefix)
            && url.pathExtension.lowercased() == "json"
            && isManagedExportDirectory(url.deletingLastPathComponent())
    }

    private func isManagedExportDirectory(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL == rootDirectoryURL.standardizedFileURL
            && url.lastPathComponent.hasPrefix(Self.exportDirectoryPrefix)
    }

    private func removeExportDirectory(_ url: URL) throws {
        guard isManagedExportDirectory(url), fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
