import CryptoKit
import Foundation

nonisolated struct BackupImportSourceFile: Equatable, Sendable {
    let data: Data
    let fileName: String
    let fileSize: Int
    let sourceFileSHA256: String
}

nonisolated struct BackupImportSecurityScopedAccess: Sendable {
    let start: @Sendable (URL) -> Bool
    let stop: @Sendable (URL) -> Void

    static let system = BackupImportSecurityScopedAccess(
        start: { $0.startAccessingSecurityScopedResource() },
        stop: { $0.stopAccessingSecurityScopedResource() }
    )
}

nonisolated struct BackupImportFileReader: Sendable {
    static let maximumByteCount = 25 * 1_024 * 1_024

    let maximumByteCount: Int
    let chunkSize: Int
    let securityScopedAccess: BackupImportSecurityScopedAccess

    init(
        maximumByteCount: Int = Self.maximumByteCount,
        chunkSize: Int = 64 * 1_024,
        securityScopedAccess: BackupImportSecurityScopedAccess = .system
    ) {
        self.maximumByteCount = maximumByteCount
        self.chunkSize = max(1, chunkSize)
        self.securityScopedAccess = securityScopedAccess
    }

    func read(from url: URL) async throws -> BackupImportSourceFile {
        guard url.isFileURL else { throw BackupImportPreflightError.localFileRequired }
        try Task.checkCancellation()
        let hasSecurityScope = securityScopedAccess.start(url)
        defer {
            if hasSecurityScope { securityScopedAccess.stop(url) }
        }

        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > maximumByteCount {
            throw BackupImportPreflightError.fileTooLarge(maximumBytes: maximumByteCount)
        }
        guard let stream = InputStream(url: url) else {
            throw BackupImportPreflightError.unreadableFile
        }
        stream.open()
        defer { stream.close() }

        var data = Data()
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            data.reserveCapacity(min(size, maximumByteCount))
        }
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while true {
            do { try Task.checkCancellation() }
            catch { throw BackupImportPreflightError.cancelled }
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw BackupImportPreflightError.unreadableFile }
            if count == 0 { break }
            guard data.count <= maximumByteCount - count else {
                throw BackupImportPreflightError.fileTooLarge(maximumBytes: maximumByteCount)
            }
            data.append(buffer, count: count)
            await Task.yield()
        }
        return try sourceFile(data: data, fileName: url.lastPathComponent)
    }

    #if DEBUG
    func read(data: Data, fileName: String) async throws -> BackupImportSourceFile {
        do { try Task.checkCancellation() }
        catch { throw BackupImportPreflightError.cancelled }
        guard data.count <= maximumByteCount else {
            throw BackupImportPreflightError.fileTooLarge(maximumBytes: maximumByteCount)
        }
        await Task.yield()
        return try sourceFile(data: data, fileName: fileName)
    }
    #endif

    private func sourceFile(data: Data, fileName: String) throws -> BackupImportSourceFile {
        guard String(data: data, encoding: .utf8) != nil else {
            throw BackupImportPreflightError.invalidUTF8
        }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return BackupImportSourceFile(
            data: data,
            fileName: fileName.isEmpty ? "TasteMap-Backup.json" : fileName,
            fileSize: data.count,
            sourceFileSHA256: hash
        )
    }
}
