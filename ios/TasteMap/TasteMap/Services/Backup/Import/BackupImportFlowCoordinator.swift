import Foundation
import Observation
import SwiftData

nonisolated enum BackupImportFlowStage: String, Equatable, Sendable {
    case preparing
    case writing
    case verifying

    var title: String {
        switch self {
        case .preparing: "准备数据"
        case .writing: "正在完成安全导入…"
        case .verifying: "验证本地数据"
        }
    }
}

nonisolated struct BackupImportFailurePresentation: Equatable, Sendable {
    let code: String
    let message: String
    let existingDataUnchanged: Bool
}

nonisolated enum BackupImportFlowState: Equatable, Sendable {
    case idle
    case selectingFile
    case reading
    case preflighting
    case preflightReady
    case planning
    case reviewRequired(completed: Int, total: Int)
    case readyToImport
    case confirming
    case importing(BackupImportFlowStage)
    case verifying
    case completed
    case failed(BackupImportFailurePresentation)
    case cancelled
    case planStale

    var transactionHasStarted: Bool {
        switch self {
        case .importing, .verifying, .completed: true
        default: false
        }
    }
}

nonisolated struct BackupImportEntityResult: Equatable, Sendable {
    let entityType: BackupImportEntityKind
    let created: Int
    let merged: Int
    let duplicate: Int
    let skipped: Int
}

nonisolated enum BackupImportLocalSyncStatus: Equatable, Sendable {
    case noChanges
    case queued(Int)
}

nonisolated struct BackupImportResult: Equatable, Sendable {
    let planID: UUID
    let sourceFileSHA256: String
    let sourceFormat: BackupImportSourceFormat
    let importedAt: Date
    let currentTasteMapUserID: String
    let entities: [BackupImportEntityResult]
    let writtenEntityCount: Int
    let mutationCount: Int
    let warningCount: Int
    let photoSkippedCount: Int
    let deprecatedSkippedCount: Int
    let securityDiscardedCount: Int
    let transactionSeconds: Double
    let verificationSeconds: Double
    let syncStatus: BackupImportLocalSyncStatus

    func entity(_ type: BackupImportEntityKind) -> BackupImportEntityResult {
        entities.first(where: { $0.entityType == type })
            ?? BackupImportEntityResult(
                entityType: type,
                created: 0,
                merged: 0,
                duplicate: 0,
                skipped: 0
            )
    }
}

nonisolated struct BackupImportLocalVerification: Equatable, Sendable {
    let verifiedEntityCount: Int
    let verifiedMutationCount: Int
    let verificationSeconds: Double
}

/// Owns one import attempt from file selection through the local commit result.
/// It never talks to the Worker and never writes entities itself.
@MainActor
@Observable
final class BackupImportFlowCoordinator {
    private(set) var state: BackupImportFlowState = .idle
    private(set) var preflightRun: BackupImportPreflightRun?
    private(set) var sourceGraph: BackupImportSourceGraph?
    private(set) var localSnapshot: BackupImportLocalSnapshot?
    private(set) var plan: BackupImportPlan?
    private(set) var decisions: [String: BackupImportReviewDecision] = [:]
    private(set) var result: BackupImportResult?

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let fileReader: BackupImportFileReader
    @ObservationIgnored private let preflightService: BackupImportPreflightService
    #if DEBUG
    @ObservationIgnored private let injectedFailurePoint: BackupImportFailurePoint?
    #endif
    @ObservationIgnored private var operationTask: Task<Void, Never>?

    let currentTasteMapUserID: String?

    #if DEBUG
    init(
        container: ModelContainer,
        currentTasteMapUserID: String?,
        fileReader: BackupImportFileReader = BackupImportFileReader(),
        preflightService: BackupImportPreflightService = BackupImportPreflightService(),
        injectedFailurePoint: BackupImportFailurePoint? = nil
    ) {
        self.container = container
        self.currentTasteMapUserID = currentTasteMapUserID
        self.fileReader = fileReader
        self.preflightService = preflightService
        self.injectedFailurePoint = injectedFailurePoint
    }
    #else
    init(
        container: ModelContainer,
        currentTasteMapUserID: String?,
        fileReader: BackupImportFileReader = BackupImportFileReader(),
        preflightService: BackupImportPreflightService = BackupImportPreflightService()
    ) {
        self.container = container
        self.currentTasteMapUserID = currentTasteMapUserID
        self.fileReader = fileReader
        self.preflightService = preflightService
    }
    #endif

    var currentReviewItem: ImportPlanReviewItem? {
        plan?.reviewItems.first
    }

    var unresolvedReviewCount: Int {
        plan?.reviewItems.count ?? 0
    }

    var canCancel: Bool {
        !state.transactionHasStarted
    }

    func beginFileSelection() {
        guard !state.transactionHasStarted else { return }
        invalidateSourceAndPlan()
        state = .selectingFile
    }

    func fileSelectionCancelled() {
        guard state == .selectingFile else { return }
        state = .cancelled
    }

    func fileSelectionFailed() {
        state = .failed(BackupImportFailurePresentation(
            code: "file_selection_failed",
            message: "文件选择未完成，请重新选择。",
            existingDataUnchanged: true
        ))
    }

    func readAndPreflight(url: URL) {
        runReadAndPreflight { [fileReader] in
            try await fileReader.read(from: url)
        }
    }

    #if DEBUG
    func readAndPreflight(
        data: Data,
        fileName: String,
        fixtureDelay: Duration? = nil
    ) {
        runReadAndPreflight { [fileReader] in
            if let fixtureDelay { try await Task.sleep(for: fixtureDelay) }
            return try await fileReader.read(data: data, fileName: fileName)
        }
    }
    #endif

    func cancelBeforeTransaction() {
        guard canCancel else { return }
        operationTask?.cancel()
        operationTask = nil
        state = .cancelled
    }

    func generatePlan() {
        guard let preflightRun, preflightRun.result.blockingCount == 0 else {
            fail(code: "preflight_blocked", message: "文件仍有阻塞问题，不能生成匹配计划。")
            return
        }
        guard let currentTasteMapUserID else {
            fail(code: "not_authenticated", message: "请先登录 Taste Map，再导入到当前账户。")
            return
        }
        operationTask?.cancel()
        state = .planning
        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            do {
                let source = try BackupImportPlanningSourceMapper.graph(from: preflightRun)
                let snapshot = try BackupImportLocalSnapshotBuilder(context: container.mainContext)
                    .make(currentTasteMapUserID: currentTasteMapUserID)
                let generated = try BackupImportPlanEngine().makePlan(source: source, local: snapshot)
                sourceGraph = source
                localSnapshot = snapshot
                plan = generated
                decisions = [:]
                updatePlanState()
            } catch {
                failFromPlanning(error)
            }
            operationTask = nil
        }
    }

    func select(_ option: BackupImportReviewOption, for item: ImportPlanReviewItem) {
        guard let sourceGraph, let localSnapshot, let plan,
              plan.reviewItems.contains(where: { $0.id == item.id }),
              item.options.contains(option) else { return }
        decisions[item.id] = BackupImportReviewDecision(
            reviewItemID: item.id,
            selectedOptionID: option.id,
            sourceFileSHA256: sourceGraph.sourceFileSHA256,
            sourceID: item.sourceID,
            targetID: option.targetID,
            localSnapshotRevision: localSnapshot.revision
        )
        recalculatePlan(generatedAt: plan.generatedAt)
    }

    /// Safe convenience for large queues. It never selects Merge.
    func makeAllRemainingNewWhereAvailable() {
        var safetyLimit = 10_000
        while let item = currentReviewItem,
              let option = item.options.first(where: { $0.kind == .create }),
              safetyLimit > 0 {
            safetyLimit -= 1
            select(option, for: item)
        }
    }

    /// Observes the same asynchronous operation used by the UI. Focused
    /// integration tests use this instead of introducing timing sleeps.
    func waitForCurrentOperation() async {
        let task = operationTask
        await task?.value
    }

    func prepareFinalConfirmation() {
        guard let plan, plan.canBeConfirmed else { return }
        state = .confirming
    }

    func returnToPlan() {
        guard plan != nil else { return }
        updatePlanState()
    }

    func execute(currentUserIDAtConfirmation: String?) {
        guard state == .confirming, operationTask == nil,
              let currentUserIDAtConfirmation,
              let plan, let sourceGraph else { return }

        let confirmed = ConfirmedBackupImportPlan(
            plan: plan,
            sourceGraph: sourceGraph,
            decisions: Array(decisions.values)
        )
        state = .importing(.preparing)
        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            do {
                guard currentUserIDAtConfirmation == currentTasteMapUserID else {
                    throw BackupImportPlanningError.userChanged
                }
                state = .importing(.writing)
                await Task.yield()
                #if DEBUG
                let transactionWriter = BackupImportTransactionWriter(
                    container: container,
                    injectedFailurePoint: injectedFailurePoint
                )
                #else
                let transactionWriter = BackupImportTransactionWriter(container: container)
                #endif
                let transaction = try transactionWriter.execute(
                    confirmed,
                    currentTasteMapUserID: currentUserIDAtConfirmation
                )

                state = .verifying
                let verification = try BackupImportLocalVerifier(container: container).verify(
                    confirmed: confirmed,
                    transaction: transaction,
                    currentTasteMapUserID: currentUserIDAtConfirmation
                )
                result = makeResult(
                    plan: plan,
                    preflight: preflightRun?.result,
                    transaction: transaction,
                    verification: verification,
                    currentUserID: currentUserIDAtConfirmation
                )
                state = .completed
            } catch BackupImportPlanningError.planStale {
                state = .planStale
            } catch BackupImportPlanningError.userChanged {
                state = .failed(BackupImportFailurePresentation(
                    code: "user_changed",
                    message: "当前登录账户已变化，需要重新选择文件并检查。",
                    existingDataUnchanged: true
                ))
            } catch BackupImportPlanningError.sourceHashMismatch {
                state = .failed(BackupImportFailurePresentation(
                    code: "source_changed",
                    message: "文件内容已变化，需要重新选择并检查。",
                    existingDataUnchanged: true
                ))
            } catch {
                state = .failed(BackupImportFailurePresentation(
                    code: Self.safeErrorCode(error),
                    message: "导入失败，没有修改你的现有数据。",
                    existingDataUnchanged: true
                ))
            }
            operationTask = nil
        }
    }

    func regenerateAfterStalePlan() {
        guard preflightRun != nil else {
            state = .idle
            return
        }
        decisions = [:]
        plan = nil
        localSnapshot = nil
        generatePlan()
    }

    func startAnotherImport() {
        guard !state.transactionHasStarted || state == .completed else { return }
        invalidateSourceAndPlan()
        state = .idle
    }

    func viewDidDisappear() {
        guard !state.transactionHasStarted else { return }
        operationTask?.cancel()
        operationTask = nil
    }

    private func runReadAndPreflight(
        _ read: @escaping @Sendable () async throws -> BackupImportSourceFile
    ) {
        guard !state.transactionHasStarted else { return }
        invalidateSourceAndPlan()
        state = .reading
        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            let readStart = clock.now
            do {
                let source = try await read()
                let readSeconds = Self.seconds(readStart.duration(to: clock.now))
                try Task.checkCancellation()
                state = .preflighting
                let run = try await preflightService.preflight(
                    source,
                    fileReadSeconds: readSeconds
                )
                try Task.checkCancellation()
                preflightRun = run
                state = .preflightReady
            } catch is CancellationError {
                state = .cancelled
            } catch let error as BackupImportPreflightError {
                state = .failed(BackupImportFailurePresentation(
                    code: Self.safePreflightCode(error),
                    message: error.localizedDescription,
                    existingDataUnchanged: true
                ))
            } catch {
                fail(code: "preflight_failed", message: "无法安全检查这个文件。")
            }
            operationTask = nil
        }
    }

    private func recalculatePlan(generatedAt: Date) {
        guard let sourceGraph, let localSnapshot else { return }
        do {
            plan = try BackupImportPlanEngine().makePlan(
                source: sourceGraph,
                local: localSnapshot,
                decisions: Array(decisions.values),
                generatedAt: generatedAt
            )
            updatePlanState()
        } catch {
            failFromPlanning(error)
        }
    }

    private func updatePlanState() {
        guard let plan else { return }
        if !plan.reviewItems.isEmpty {
            state = .reviewRequired(
                completed: decisions.count,
                total: decisions.count + plan.reviewItems.count
            )
        } else if plan.canBeConfirmed {
            state = .readyToImport
        } else {
            fail(code: "plan_blocked", message: "匹配计划仍有阻塞项，不能继续导入。")
        }
    }

    private func failFromPlanning(_ error: Error) {
        if let planning = error as? BackupImportPlanningError {
            switch planning {
            case .planStale:
                state = .planStale
            case .userChanged:
                fail(code: "user_changed", message: planning.localizedDescription)
            default:
                fail(code: "planning_failed", message: planning.localizedDescription)
            }
        } else {
            fail(code: "planning_failed", message: "无法建立安全匹配计划。")
        }
    }

    private func fail(code: String, message: String) {
        state = .failed(BackupImportFailurePresentation(
            code: code,
            message: message,
            existingDataUnchanged: true
        ))
    }

    private func invalidateSourceAndPlan() {
        operationTask?.cancel()
        operationTask = nil
        preflightRun = nil
        sourceGraph = nil
        localSnapshot = nil
        plan = nil
        decisions = [:]
        result = nil
    }

    private func makeResult(
        plan: BackupImportPlan,
        preflight: ImportPreflightResult?,
        transaction: BackupImportTransactionResult,
        verification: BackupImportLocalVerification,
        currentUserID: String
    ) -> BackupImportResult {
        let entities = BackupImportEntityKind.allCases.map { type in
            let actions = plan.actions.filter { $0.entityType == type }
            return BackupImportEntityResult(
                entityType: type,
                created: actions.filter { $0.action == .create }.count,
                merged: actions.filter { $0.action == .exactMerge }.count,
                duplicate: actions.filter { $0.action == .exactDuplicate }.count,
                skipped: actions.filter { $0.action == .skip }.count
            )
        }
        return BackupImportResult(
            planID: plan.planID,
            sourceFileSHA256: plan.sourceFileSHA256,
            sourceFormat: plan.sourceFormat,
            importedAt: .now,
            currentTasteMapUserID: currentUserID,
            entities: entities,
            writtenEntityCount: transaction.writtenEntityCount,
            mutationCount: transaction.queuedMutationCount,
            warningCount: plan.summary.warningCount,
            photoSkippedCount: sourceGraph?.photos.count ?? 0,
            deprecatedSkippedCount: preflight?.deprecatedFieldCount ?? 0,
            securityDiscardedCount: preflight?.securityDiscardCount ?? 0,
            transactionSeconds: transaction.transactionSeconds,
            verificationSeconds: verification.verificationSeconds,
            syncStatus: transaction.queuedMutationCount == 0
                ? .noChanges
                : .queued(transaction.queuedMutationCount)
        )
    }

    private static func safePreflightCode(_ error: BackupImportPreflightError) -> String {
        switch error {
        case .cancelled: "cancelled"
        case .fileTooLarge: "file_too_large"
        case .invalidUTF8: "invalid_utf8"
        case .malformedJSON: "malformed_json"
        case .rootMustBeObject: "invalid_json_root"
        case .unsupportedFormat: "unsupported_format"
        default: "preflight_rejected"
        }
    }

    private static func safeErrorCode(_ error: Error) -> String {
        if let planning = error as? BackupImportPlanningError {
            switch planning {
            #if DEBUG
            case .injectedFailure:
                return "transaction_injected_failure"
            #endif
            case .transactionFailed:
                return "transaction_failed"
            case .invalidDecision, .unresolvedReview:
                return "review_invalid"
            default:
                return "import_safety_check_failed"
            }
        }
        return "transaction_failed"
    }

    private static func seconds(_ duration: Duration) -> Double {
        let value = duration.components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
}

@MainActor
private struct BackupImportLocalVerifier {
    let container: ModelContainer

    func verify(
        confirmed: ConfirmedBackupImportPlan,
        transaction: BackupImportTransactionResult,
        currentTasteMapUserID: String
    ) throws -> BackupImportLocalVerification {
        let clock = ContinuousClock()
        let started = clock.now
        let context = container.mainContext
        let snapshot = try BackupImportLocalSnapshotBuilder(context: context)
            .make(currentTasteMapUserID: currentTasteMapUserID)

        for action in confirmed.plan.actions where
            action.action == .create || action.action == .exactMerge || action.action == .exactDuplicate {
            guard let targetID = action.targetID,
                  snapshot.contains(action.entityType, targetID: targetID) else {
                throw BackupImportPlanningError.transactionFailed
            }
        }

        try verifyRelationships(snapshot)
        try verifyRestaurantIdentities(snapshot, context: context)
        try verifyQueuedCreates(confirmed.plan, currentUserID: currentTasteMapUserID, context: context)

        let seconds = Self.seconds(started.duration(to: clock.now))
        return BackupImportLocalVerification(
            verifiedEntityCount: transaction.writtenEntityCount,
            verifiedMutationCount: transaction.queuedMutationCount,
            verificationSeconds: seconds
        )
    }

    private func verifyRelationships(_ snapshot: BackupImportLocalSnapshot) throws {
        let restaurants = Set(snapshot.restaurants.map(\.remoteID))
        let visits = Set(snapshot.visits.map(\.remoteID))
        let dishes = Set(snapshot.dishes.map(\.remoteID))
        let lists = Set(snapshot.restaurantLists.map(\.remoteID))

        guard snapshot.visits.allSatisfy({ restaurants.contains($0.value.sourceRestaurantID) }),
              snapshot.dishes.allSatisfy({
                  restaurants.contains($0.value.sourceRestaurantID)
                      && visits.contains($0.value.sourceVisitID)
              }),
              snapshot.visitDishes.allSatisfy({
                  restaurants.contains($0.value.sourceRestaurantID)
                      && visits.contains($0.value.sourceVisitID)
                      && dishes.contains($0.value.sourceDishID)
              }),
              snapshot.restaurantListItems.allSatisfy({
                  lists.contains($0.value.sourceListID)
                      && restaurants.contains($0.value.sourceRestaurantID)
                      && $0.value.position >= 0
              }) else {
            throw BackupImportPlanningError.transactionFailed
        }

        let positions = Dictionary(grouping: snapshot.restaurantListItems, by: { $0.value.sourceListID })
        guard positions.values.allSatisfy({ values in
            Set(values.map { $0.value.position }).count == values.count
        }) else {
            throw BackupImportPlanningError.transactionFailed
        }
    }

    private func verifyRestaurantIdentities(
        _ snapshot: BackupImportLocalSnapshot,
        context: ModelContext
    ) throws {
        let localIDs = Set(snapshot.restaurants.map(\.localID))
        let restaurants = try context.fetch(FetchDescriptor<Restaurant>())
            .filter { localIDs.contains($0.id) && $0.deletedAt == nil }
        for restaurant in restaurants {
            let contract = try SyncRecordMapper.restaurantRecord(restaurant)
            guard !contract.placeIdentities.isEmpty else {
                throw BackupImportPlanningError.transactionFailed
            }
        }
    }

    private func verifyQueuedCreates(
        _ plan: BackupImportPlan,
        currentUserID: String,
        context: ModelContext
    ) throws {
        let mutations = try context.fetch(FetchDescriptor<SyncMutation>())
        for action in plan.actions where action.action == .create {
            guard let entityType = action.entityType.syncEntityType else { continue }
            let entityID = entityType == .profile ? currentUserID : action.targetID
            guard let entityID, mutations.contains(where: {
                $0.entityType == entityType && $0.entityID == entityID && $0.operation == .upsert
            }) else {
                throw BackupImportPlanningError.transactionFailed
            }
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        let value = duration.components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
}

private extension BackupImportLocalSnapshot {
    func contains(_ type: BackupImportEntityKind, targetID: String) -> Bool {
        switch type {
        case .restaurant: recordsContain(restaurants, targetID)
        case .visit: recordsContain(visits, targetID)
        case .dish: recordsContain(dishes, targetID)
        case .visitDish: recordsContain(visitDishes, targetID)
        case .photo: recordsContain(photos, targetID)
        case .companion: recordsContain(companions, targetID)
        case .recommendationSource: recordsContain(recommendationSources, targetID)
        case .profile: recordsContain(profiles, targetID)
        case .restaurantList: recordsContain(restaurantLists, targetID)
        case .restaurantListItem: recordsContain(restaurantListItems, targetID)
        }
    }

    func recordsContain<Value>(_ records: [BackupImportLocalRecord<Value>], _ targetID: String) -> Bool {
        records.contains {
            $0.localID.uuidString.lowercased() == targetID.lowercased()
                || $0.remoteID == targetID
        }
    }
}

private extension BackupImportEntityKind {
    var syncEntityType: SyncEntityType? {
        switch self {
        case .restaurant: .restaurant
        case .visit: .visit
        case .dish: .dish
        case .visitDish: .visitDish
        case .photo: nil
        case .companion: .companion
        case .recommendationSource: .recommendationSource
        case .profile: .profile
        case .restaurantList: .restaurantList
        case .restaurantListItem: .restaurantListItem
        }
    }
}
