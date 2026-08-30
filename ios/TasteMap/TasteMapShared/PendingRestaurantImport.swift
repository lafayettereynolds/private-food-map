import CryptoKit
import Foundation

nonisolated struct PendingRestaurantImport: Codable, Identifiable, Equatable, Sendable {
    static let schemaVersion = 1
    static let lifetime: TimeInterval = 7 * 24 * 60 * 60

    let schemaVersion: Int
    let id: String
    let sharedText: String
    let sharedURL: URL?
    let createdAt: Date
    let expiresAt: Date

    var acquisitionText: String {
        [sharedText, sharedURL?.absoluteString]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var isExpired: Bool { expiresAt <= .now }
}

nonisolated struct PendingRestaurantImportStore {
    static let appGroupIdentifier = "group.com.lafayette.tastemap"
    static let maximumPayloadBytes = 32 * 1_024

    private let directoryURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    static func live(fileManager: FileManager = .default) throws -> Self {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { throw PendingRestaurantImportStoreError.appGroupUnavailable }
        return Self(
            directoryURL: container
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent("PendingRestaurantImports/v1", isDirectory: true),
            fileManager: fileManager
        )
    }

    @discardableResult
    func enqueue(text: String?, url: URL?, now: Date = .now) throws -> PendingRestaurantImport {
        let normalizedText = Self.normalized(text ?? "")
        let normalizedURL = try Self.normalizedURL(url)
        guard !normalizedText.isEmpty || normalizedURL != nil else {
            throw PendingRestaurantImportStoreError.emptyPayload
        }
        let canonical = "\(normalizedURL?.absoluteString ?? "")\n\(normalizedText)"
        guard canonical.utf8.count <= Self.maximumPayloadBytes else {
            throw PendingRestaurantImportStoreError.payloadTooLarge
        }
        try prepareDirectory()
        try cleanupExpired(now: now)
        let id = Self.fingerprint(canonical)
        let fileURL = self.fileURL(for: id)
        if let existing = try? decode(fileURL), existing.expiresAt > now { return existing }
        let pending = PendingRestaurantImport(
            schemaVersion: PendingRestaurantImport.schemaVersion,
            id: id,
            sharedText: normalizedText,
            sharedURL: normalizedURL,
            createdAt: now,
            expiresAt: now.addingTimeInterval(PendingRestaurantImport.lifetime)
        )
        try Self.encoder().encode(pending).write(to: fileURL, options: .atomic)
        return pending
    }

    func pending(now: Date = .now) throws -> [PendingRestaurantImport] {
        try prepareDirectory()
        try cleanupExpired(now: now)
        return try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .compactMap { try? decode($0) }
        .filter { $0.schemaVersion == PendingRestaurantImport.schemaVersion && $0.expiresAt > now }
        .sorted { $0.createdAt < $1.createdAt }
    }

    func consume(id: String) throws {
        guard Self.isFingerprint(id) else { throw PendingRestaurantImportStoreError.invalidIdentifier }
        let url = fileURL(for: id)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    func cleanupExpired(now: Date = .now) throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        for url in try fileManager.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) where url.pathExtension == "json" {
            guard let value = try? decode(url),
                  value.schemaVersion == PendingRestaurantImport.schemaVersion,
                  value.expiresAt > now else {
                try? fileManager.removeItem(at: url)
                continue
            }
        }
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func fileURL(for id: String) -> URL {
        directoryURL.appendingPathComponent(id).appendingPathExtension("json")
    }

    private func decode(_ url: URL) throws -> PendingRestaurantImport {
        try Self.decoder().decode(PendingRestaurantImport.self, from: Data(contentsOf: url))
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\0", with: "")
    }

    private static func normalizedURL(_ url: URL?) throws -> URL? {
        guard let url else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil else {
            throw PendingRestaurantImportStoreError.insecureURL
        }
        return components.url
    }

    private static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func isFingerprint(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    private static func encoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        value.outputFormatting = [.sortedKeys]
        return value
    }

    private static func decoder() -> JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }
}

nonisolated enum PendingRestaurantImportStoreError: Error, Equatable {
    case appGroupUnavailable
    case emptyPayload
    case payloadTooLarge
    case insecureURL
    case invalidIdentifier
}
