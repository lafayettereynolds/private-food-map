import Foundation

nonisolated struct BackupImportPreflightService: Sendable {
    let jsonInspector: BackupImportJSONInspector
    let backupV1Validator: BackupV1PreflightValidator
    let legacyDecoder: LegacyWebBackupV4Decoder
    let legacyAdapter: LegacyV4PreflightAdapter

    init(
        jsonInspector: BackupImportJSONInspector = BackupImportJSONInspector(),
        backupV1Validator: BackupV1PreflightValidator = BackupV1PreflightValidator(),
        legacyDecoder: LegacyWebBackupV4Decoder = LegacyWebBackupV4Decoder(),
        legacyAdapter: LegacyV4PreflightAdapter = LegacyV4PreflightAdapter()
    ) {
        self.jsonInspector = jsonInspector
        self.backupV1Validator = backupV1Validator
        self.legacyDecoder = legacyDecoder
        self.legacyAdapter = legacyAdapter
    }

    func preflight(
        _ sourceFile: BackupImportSourceFile,
        inspectedAt: Date = .now,
        fileReadSeconds: Double = 0
    ) async throws -> BackupImportPreflightRun {
        let clock = ContinuousClock()
        let totalStart = clock.now
        try checkCancellation()

        let inspectionStart = clock.now
        let root = try jsonInspector.inspect(sourceFile.data)
        let detected = try BackupImportFormatDetector.detect(root)
        let inspectionEnd = clock.now
        try checkCancellation()

        let decodeStart = clock.now
        let decoded: DecodedSource
        switch detected.format {
        case .backupV1:
            do {
                decoded = .backupV1(
                    try JSONDecoder().decode(BackupEnvelopeV1.self, from: sourceFile.data)
                )
            } catch {
                throw BackupImportPreflightError.backupV1DecodeFailed
            }
        case .legacyWebV4:
            do {
                decoded = .legacyWebV4(try legacyDecoder.decode(sourceFile.data))
            } catch {
                throw BackupImportPreflightError.legacyV4DecodeFailed
            }
        }
        let decodeEnd = clock.now
        try checkCancellation()

        let validationStart = clock.now
        let result: ImportPreflightResult
        switch decoded {
        case let .backupV1(envelope):
            result = try backupV1Validator.validate(
                sourceFile: sourceFile,
                root: root,
                envelope: envelope,
                inspectedAt: inspectedAt
            )
        case let .legacyWebV4(graph):
            result = legacyAdapter.result(
                sourceFile: sourceFile,
                graph: graph,
                inspectedAt: inspectedAt
            )
        }
        let validationEnd = clock.now
        try checkCancellation()
        let totalEnd = clock.now
        return BackupImportPreflightRun(
            result: result,
            timing: BackupImportPreflightTiming(
                fileReadSeconds: max(0, fileReadSeconds),
                inspectionSeconds: Self.seconds(inspectionStart.duration(to: inspectionEnd)),
                decodeAndNormalizeSeconds: Self.seconds(decodeStart.duration(to: decodeEnd)),
                validationSeconds: Self.seconds(validationStart.duration(to: validationEnd)),
                totalSeconds: max(0, fileReadSeconds)
                    + Self.seconds(totalStart.duration(to: totalEnd))
            )
        )
    }

    private func checkCancellation() throws {
        do { try Task.checkCancellation() }
        catch { throw BackupImportPreflightError.cancelled }
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

private nonisolated enum DecodedSource {
    case backupV1(BackupEnvelopeV1)
    case legacyWebV4(LegacyBackupStagingGraph)
}
