import Foundation
import SwiftData

@MainActor
struct BackupExportService {
    let context: ModelContext
    let source: BackupExportSourceInfo
    let temporaryFiles: BackupExportTemporaryFileStore
    let now: () -> Date
    let makeExportID: () -> UUID

    init(
        context: ModelContext,
        source: BackupExportSourceInfo? = nil,
        temporaryFiles: BackupExportTemporaryFileStore? = nil,
        now: @escaping () -> Date = { .now },
        makeExportID: @escaping () -> UUID = UUID.init
    ) throws {
        self.context = context
        self.source = try source ?? .current()
        self.temporaryFiles = temporaryFiles ?? BackupExportTemporaryFileStore()
        self.now = now
        self.makeExportID = makeExportID
    }

    func export(authSessionManager: AuthSessionManager) async throws -> BackupExportArtifact {
        guard let user = await authSessionManager.restoredUser() else {
            throw BackupExportError.unauthenticated
        }
        return try export(currentUserID: user.id)
    }

    func export(currentUserID: String) throws -> BackupExportArtifact {
        try Task.checkCancellation()
        let exportedAt = now()
        let exportID = makeExportID()
        let envelope = try makeEnvelope(
            input: fetchInput(),
            currentUserID: currentUserID,
            exportedAt: exportedAt,
            exportID: exportID
        )
        try Task.checkCancellation()
        let data = try encodeAndVerify(envelope)
        try Task.checkCancellation()
        let fileURL = try temporaryFiles.write(data, exportedAt: exportedAt, exportID: exportID)
        return BackupExportArtifact(
            id: exportID,
            fileURL: fileURL,
            exportedAt: exportedAt,
            metadata: envelope.metadata
        )
    }

    func makeEnvelope(
        input: BackupExportInput,
        currentUserID: String,
        exportedAt: Date,
        exportID: UUID
    ) throws -> BackupEnvelopeV1 {
        var mapper = BackupExportMapper(input: input, currentUserID: currentUserID)
        let graph = try mapper.map()
        let counts = BackupEntityCountsV1(
            restaurants: graph.entities.restaurants.count,
            visits: graph.entities.visits.count,
            dishes: graph.entities.dishes.count,
            visitDishes: graph.entities.visitDishes.count,
            photos: graph.entities.photos.count,
            companions: graph.entities.companions.count,
            recommendationSources: graph.entities.recommendationSources.count,
            profiles: graph.entities.profiles.count,
            restaurantLists: graph.entities.restaurantLists.count,
            restaurantListItems: graph.entities.restaurantListItems.count
        )
        let metadata = BackupMetadataV1(
            entityCounts: counts,
            tombstoneCount: graph.tombstones.count
        )
        let exportedTimestamp = try timestamp(exportedAt)
        let payload = BackupIntegrityPayloadV1(
            format: BackupV1Contract.format,
            schemaVersion: BackupV1Contract.schemaVersion,
            exportId: exportID.uuidString.lowercased(),
            exportedAt: exportedTimestamp,
            source: source.contractValue,
            scope: BackupScopeV1(),
            entities: graph.entities,
            tombstones: graph.tombstones,
            metadata: metadata
        )
        let canonical = try BackupCanonicalJSONV1.canonicalString(for: payload)
        let digest = BackupCanonicalJSONV1.sha256Hex(of: canonical)
        let envelope = BackupEnvelopeV1(
            format: payload.format,
            schemaVersion: payload.schemaVersion,
            exportId: payload.exportId,
            exportedAt: payload.exportedAt,
            source: payload.source,
            scope: payload.scope,
            entities: payload.entities,
            tombstones: payload.tombstones,
            metadata: payload.metadata,
            integrity: try BackupIntegrityV1(digest: digest)
        )
        guard try verifyIntegrity(envelope) else { throw BackupExportError.integrityMismatch }
        return envelope
    }

    func encodeAndVerify(_ envelope: BackupEnvelopeV1) throws -> Data {
        guard try verifyIntegrity(envelope) else { throw BackupExportError.integrityMismatch }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(envelope)
            let decoded = try JSONDecoder().decode(BackupEnvelopeV1.self, from: data)
            guard decoded == envelope, try verifyIntegrity(decoded) else {
                throw BackupExportError.integrityMismatch
            }
            return data
        } catch let error as BackupExportError {
            throw error
        } catch {
            throw BackupExportError.encodingFailed
        }
    }

    func verifyIntegrity(_ envelope: BackupEnvelopeV1) throws -> Bool {
        let canonical = try BackupCanonicalJSONV1.canonicalString(for: envelope.integrityPayload)
        return BackupCanonicalJSONV1.sha256Hex(of: canonical) == envelope.integrity.digest
    }

    func cleanupTemporaryExports() throws {
        try temporaryFiles.cleanup(now: now())
    }

    func removeTemporaryExport(_ artifact: BackupExportArtifact) throws {
        try temporaryFiles.removeArtifact(at: artifact.fileURL)
    }

    private func fetchInput() throws -> BackupExportInput {
        do {
            return BackupExportInput(
                restaurants: try context.fetch(FetchDescriptor<Restaurant>()),
                visits: try context.fetch(FetchDescriptor<Visit>()),
                dishes: try context.fetch(FetchDescriptor<Dish>()),
                visitDishes: try context.fetch(FetchDescriptor<VisitDish>()),
                photos: try context.fetch(FetchDescriptor<PhotoAsset>()),
                companions: try context.fetch(FetchDescriptor<DiningCompanion>()),
                recommendationSources: try context.fetch(FetchDescriptor<RecommendationSource>()),
                profiles: try context.fetch(FetchDescriptor<UserProfile>()),
                restaurantLists: try context.fetch(FetchDescriptor<RestaurantList>()),
                restaurantListItems: try context.fetch(FetchDescriptor<RestaurantListItem>())
            )
        } catch {
            throw BackupExportError.encodingFailed
        }
    }

    private func timestamp(_ date: Date) throws -> BackupTimestampV1 {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let value = BackupTimestampV1(rawValue: formatter.string(from: date)) else {
            throw BackupExportError.invalidTimestamp(
                entityType: .profile,
                entityID: "envelope",
                field: "exportedAt"
            )
        }
        return value
    }
}
