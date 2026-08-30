import Foundation
import Network
import Observation
import OSLog
import SwiftData

enum SyncPresentationPhase: String, Equatable, Sendable {
    case signedOut
    case synced
    case pending
    case waitingForNetwork
    case syncing
    case failed
    case conflicted
}

struct SyncPresentation: Equatable, Sendable {
    var phase: SyncPresentationPhase
    var pendingCount: Int
    var pendingPhotoCount: Int
    var failedPhotoCount: Int
    var conflictCount: Int
    var lastSyncedAt: Date?
    var diagnostic: SyncFailureDiagnostic? = nil

    static let signedOut = SyncPresentation(
        phase: .signedOut,
        pendingCount: 0,
        pendingPhotoCount: 0,
        failedPhotoCount: 0,
        conflictCount: 0,
        lastSyncedAt: nil
    )

    var title: String {
        switch phase {
        case .signedOut: "登录后同步"
        case .synced: "已同步"
        case .pending: "等待同步"
        case .waitingForNetwork: "离线，等待联网"
        case .syncing: "正在同步"
        case .failed: "同步失败"
        case .conflicted: "存在需要处理的同步冲突"
        }
    }

    var message: String {
        switch phase {
        case .signedOut:
            "本地记录会继续保留，登录后再同步到 Taste Map。"
        case .synced:
            lastSyncedAt.map { "最近同步：\($0.formatted(date: .abbreviated, time: .shortened))" }
                ?? "本地与云端记录已保持一致。"
        case .pending:
            pendingSummary(suffix: "等待上传。")
        case .waitingForNetwork:
            pendingSummary(suffix: "安全保存在本机，联网后会自动重试。")
        case .syncing:
            pendingCount > 0 || pendingPhotoCount > 0
                ? pendingSummary(suffix: "正在处理。")
                : "正在检查云端更新。"
        case .failed:
            failedPhotoCount > 0
                ? "有 \(failedPhotoCount) 张照片尚未上传，记录仍安全保存在本机。你可以稍后重试同步。"
                : "记录仍安全保存在本机。你可以稍后重试同步。"
        case .conflicted:
            "有 \(conflictCount) 项记录在其他设备发生了变化，本地修改没有被覆盖。"
        }
    }

    var systemImage: String {
        switch phase {
        case .signedOut: "person.crop.circle.badge.questionmark"
        case .synced: "checkmark.icloud.fill"
        case .pending: "clock.arrow.circlepath"
        case .waitingForNetwork: "wifi.slash"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .failed: "exclamationmark.icloud.fill"
        case .conflicted: "exclamationmark.triangle.fill"
        }
    }

    var allowsRetry: Bool {
        phase == .failed || phase == .pending || phase == .waitingForNetwork
    }

    private func pendingSummary(suffix: String) -> String {
        var parts: [String] = []
        if pendingCount > 0 { parts.append("\(pendingCount) 项记录") }
        if pendingPhotoCount > 0 { parts.append("\(pendingPhotoCount) 张照片") }
        return "有 \(parts.isEmpty ? "本地修改" : parts.joined(separator: "、"))\(suffix)"
    }
}

@MainActor
@Observable
final class SyncCoordinator {
    private(set) var presentation: SyncPresentation = .signedOut

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let api: any SyncAPI
    @ObservationIgnored private let authenticatedUserIDProvider: @Sendable () async -> String?
    @ObservationIgnored private let networkObserver: NetworkPathObserver?
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let automaticSyncInterval: TimeInterval
    @ObservationIgnored private let networkRecoveryDelay: Duration
    @ObservationIgnored private let retryBaseDelay: TimeInterval
    @ObservationIgnored private var mutationObserver: NSObjectProtocol?
    @ObservationIgnored private var photoTransferObserver: NSObjectProtocol?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var networkDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isAuthenticated = false
    @ObservationIgnored private var currentOwnerUserID: String?
    @ObservationIgnored private var isNetworkAvailable = true
    @ObservationIgnored private var rerunAfterCurrentPass = false
    @ObservationIgnored private var forceRetryAfterCurrentPass = false
    @ObservationIgnored private var lastAutomaticSyncAt: Date?
    @ObservationIgnored private var lastFailureDisposition: SyncFailureDisposition?
    @ObservationIgnored private var lastFailureDiagnostic: SyncFailureDiagnostic?
    @ObservationIgnored private var consecutiveRetryableFailures = 0

    init(
        context: ModelContext,
        api: any SyncAPI,
        sessionManager: AuthSessionManager,
        networkObserver: NetworkPathObserver?
    ) {
        self.context = context
        self.api = api
        self.networkObserver = networkObserver
        authenticatedUserIDProvider = { await sessionManager.restoredUser()?.id }
        now = { .now }
        automaticSyncInterval = 15
        networkRecoveryDelay = .milliseconds(350)
        retryBaseDelay = 5
    }

    init(
        context: ModelContext,
        api: any SyncAPI,
        hasAuthenticatedSession: @escaping @Sendable () async -> Bool,
        ownerUserID: String = LocalAccountOwner.guest,
        now: @escaping @MainActor () -> Date = { .now },
        automaticSyncInterval: TimeInterval = 0,
        networkRecoveryDelay: Duration = .zero,
        retryBaseDelay: TimeInterval = 0.01
    ) {
        self.context = context
        self.api = api
        authenticatedUserIDProvider = {
            await hasAuthenticatedSession() ? ownerUserID : nil
        }
        networkObserver = nil
        self.now = now
        self.automaticSyncInterval = automaticSyncInterval
        self.networkRecoveryDelay = networkRecoveryDelay
        self.retryBaseDelay = retryBaseDelay
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        recoverInterruptedQueue()

        mutationObserver = NotificationCenter.default.addObserver(
            forName: .tasteMapSyncMutationQueued,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.requestSync(trigger: .localMutation)
            }
        }
        photoTransferObserver = NotificationCenter.default.addObserver(
            forName: .tasteMapPhotoTransferStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPresentation() }
        }
        networkObserver?.start { [weak self] isAvailable in
            Task { @MainActor [weak self] in
                self?.networkAvailabilityChanged(isAvailable)
            }
        }
        Task { @MainActor [weak self] in
            await self?.restoreSessionAndSync()
        }
    }

    func handleAppBecameActive() {
        if !isStarted { start() }
        Task { @MainActor [weak self] in
            await self?.requestSync(trigger: .foreground)
        }
    }

    func sessionDidBecomeAvailable(userID: String? = nil) async {
        let previousOwnerUserID = currentOwnerUserID
        if let userID {
            currentOwnerUserID = userID
        } else {
            currentOwnerUserID = await authenticatedUserIDProvider()
        }
        if currentOwnerUserID != previousOwnerUserID {
            lastFailureDisposition = nil
            lastFailureDiagnostic = nil
            consecutiveRetryableFailures = 0
        }
        isAuthenticated = currentOwnerUserID != nil
        guard let currentOwnerUserID else {
            refreshPresentation()
            return
        }
        NotificationCenter.default.post(name: .tasteMapAuthSessionAvailable, object: nil)
        do {
            let queue = SwiftDataSyncQueue(context: context, ownerUserID: currentOwnerUserID)
            try queue.resetAuthenticationFailures()
            try context.save()
        } catch {
            syncDebug("Unable to reset authentication failures: \(String(describing: error))")
        }
        await requestSync(trigger: .sessionRestored)
    }

    func sessionDidEnd() {
        isAuthenticated = false
        currentOwnerUserID = nil
        lastFailureDisposition = nil
        lastFailureDiagnostic = nil
        consecutiveRetryableFailures = 0
        retryTask?.cancel()
        retryTask = nil
        networkDebounceTask?.cancel()
        networkDebounceTask = nil
        syncTask?.cancel()
        presentation = queuePresentation(phase: .signedOut)
    }

    func retryNow() async {
        NotificationCenter.default.post(name: .tasteMapManualSyncRetryRequested, object: nil)
        await requestSync(trigger: .manual, forceRetry: true)
    }

    func synchronizeNow() async {
        await requestSync(trigger: .manual)
    }

    func networkAvailabilityChanged(_ isAvailable: Bool) {
        isNetworkAvailable = isAvailable
        networkDebounceTask?.cancel()
        networkDebounceTask = nil
        if !isAvailable {
            retryTask?.cancel()
            retryTask = nil
            refreshPresentation()
            syncDebug("Network became unavailable")
            return
        }

        syncDebug("Network recovered")
        networkDebounceTask = Task { @MainActor [weak self, networkRecoveryDelay] in
            do { try await Task.sleep(for: networkRecoveryDelay) } catch { return }
            await self?.requestSync(trigger: .networkRecovered)
        }
    }

    func refreshPresentation() {
        let mutations = (try? scopedQueue().allMutations()) ?? []
        let conflictCount = mutations.filter { $0.state == .conflicted }.count
        let failedCount = mutations.filter { $0.state == .failed }.count
        let pendingCount = mutations.filter {
            $0.state == .queued || $0.state == .uploading || $0.state == .failed
        }.count
        let photoCounts = photoTransferCounts()

        let phase: SyncPresentationPhase
        if conflictCount > 0 {
            phase = .conflicted
        } else if syncTask != nil {
            phase = .syncing
        } else if !isAuthenticated {
            phase = .signedOut
        } else if (pendingCount > 0 || photoCounts.pending > 0) && !isNetworkAvailable {
            phase = .waitingForNetwork
        } else if failedCount > 0 || photoCounts.failed > 0 || lastFailureDisposition != nil {
            phase = .failed
        } else if pendingCount > 0 || photoCounts.pending > 0 {
            phase = .pending
        } else {
            phase = .synced
        }
        presentation = queuePresentation(
            phase: phase,
            pendingCount: pendingCount,
            pendingPhotoCount: photoCounts.pending,
            failedPhotoCount: photoCounts.failed,
            conflictCount: conflictCount
        )
    }

    private func restoreSessionAndSync() async {
        let previousOwnerUserID = currentOwnerUserID
        currentOwnerUserID = await authenticatedUserIDProvider()
        if currentOwnerUserID != previousOwnerUserID {
            lastFailureDisposition = nil
            lastFailureDiagnostic = nil
            consecutiveRetryableFailures = 0
        }
        isAuthenticated = currentOwnerUserID != nil
        refreshPresentation()
        guard isAuthenticated else { return }
        recoverInterruptedQueue()
        await requestSync(trigger: .launch)
    }

    private func requestSync(trigger: SyncTrigger, forceRetry: Bool = false) async {
        if let runningTask = syncTask {
            if trigger == .localMutation || forceRetry {
                rerunAfterCurrentPass = true
                forceRetryAfterCurrentPass = forceRetryAfterCurrentPass || forceRetry
            }
            await runningTask.value
            return
        }

        if !isAuthenticated {
            currentOwnerUserID = await authenticatedUserIDProvider()
            isAuthenticated = currentOwnerUserID != nil
        }
        guard isAuthenticated else {
            refreshPresentation()
            return
        }
        guard isNetworkAvailable else {
            refreshPresentation()
            return
        }

        if trigger == .foreground,
           let lastAutomaticSyncAt,
           now().timeIntervalSince(lastAutomaticSyncAt) < automaticSyncInterval,
           pendingMutationCount() == 0 {
            return
        }

        if forceRetry {
            do {
                try scopedQueue().prepareManualRetry()
                try context.save()
                lastFailureDisposition = nil
                lastFailureDiagnostic = nil
            } catch {
                lastFailureDisposition = .permanent
                refreshPresentation()
                return
            }
        }

        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runSyncLoop(trigger: trigger)
        }
        syncTask = task
        refreshPresentation()
        await task.value
    }

    private func runSyncLoop(trigger: SyncTrigger) async {
        var currentTrigger = trigger
        repeat {
            rerunAfterCurrentPass = false
            let succeeded = await performSinglePass(trigger: currentTrigger)
            let canRerun = rerunAfterCurrentPass
                && isAuthenticated
                && isNetworkAvailable
                && (succeeded || forceRetryAfterCurrentPass)
            guard canRerun else { break }
            if forceRetryAfterCurrentPass {
                try? scopedQueue().prepareManualRetry()
                try? context.save()
                forceRetryAfterCurrentPass = false
            }
            currentTrigger = .localMutation
        } while true

        forceRetryAfterCurrentPass = false
        syncTask = nil
        refreshPresentation()
    }

    private func performSinglePass(trigger: SyncTrigger) async -> Bool {
        syncDebug("Sync requested: \(trigger.rawValue)")
        let startedAt = Date()
        do {
            try await SyncEngine(
                context: context,
                api: api,
                ownerUserID: currentOwnerUserID ?? LocalAccountOwner.legacyQuarantine,
                retryBaseDelay: retryBaseDelay
            ).synchronize()
            lastFailureDisposition = nil
            lastFailureDiagnostic = nil
            consecutiveRetryableFailures = 0
            lastAutomaticSyncAt = now()
            NotificationCenter.default.post(name: .tasteMapSyncDidComplete, object: nil)
            retryTask?.cancel()
            retryTask = nil
            return true
        } catch {
            let disposition = SyncErrorClassifier.disposition(for: error)
            if disposition == .cancelled { return false }
            lastFailureDisposition = disposition
            if disposition == .authentication { isAuthenticated = false }
            if disposition == .retryable {
                consecutiveRetryableFailures += 1
                scheduleRetry()
            }
            lastFailureDiagnostic = SyncErrorClassifier.diagnostic(
                for: error,
                duration: Date().timeIntervalSince(startedAt),
                retryCount: consecutiveRetryableFailures
            )
            if let diagnostic = lastFailureDiagnostic {
                syncDebug(
                    "Sync failed stage=\(diagnostic.stage.rawValue) request=\(diagnostic.requestCategory) "
                        + "category=\(diagnostic.category.rawValue) status=\(diagnostic.httpStatus ?? 0) "
                        + "duration_ms=\(diagnostic.durationMilliseconds) retry=\(diagnostic.retryCount) "
                        + "final=\(diagnostic.finalDisposition.rawValue)"
                )
            }
            return false
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        guard isAuthenticated, isNetworkAvailable else { return }
        let exponentialSeconds = min(
            pow(2, Double(max(0, consecutiveRetryableFailures - 1))) * retryBaseDelay,
            SyncRetryPolicy.maximumBackoff
        )
        let mutationRetryDate = try? scopedQueue().earliestRetryDate()
        let desiredDate = max(
            mutationRetryDate ?? now().addingTimeInterval(exponentialSeconds),
            now().addingTimeInterval(exponentialSeconds)
        )
        let delay = max(0, desiredDate.timeIntervalSince(now()))
        retryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            await self?.requestSync(trigger: .scheduledRetry)
        }
    }

    private func recoverInterruptedQueue() {
        do {
            guard currentOwnerUserID != nil else { return }
            try scopedQueue().resetInterruptedUploads()
            try context.save()
        } catch {
            lastFailureDisposition = .permanent
        }
        refreshPresentation()
    }

    private func pendingMutationCount() -> Int {
        ((try? scopedQueue().allMutations()) ?? []).filter {
            $0.state == .queued || $0.state == .uploading || $0.state == .failed
        }.count
    }

    private func queuePresentation(
        phase: SyncPresentationPhase,
        pendingCount: Int? = nil,
        pendingPhotoCount: Int? = nil,
        failedPhotoCount: Int? = nil,
        conflictCount: Int? = nil
    ) -> SyncPresentation {
        let mutations = (try? scopedQueue().allMutations()) ?? []
        let photoCounts = photoTransferCounts()
        let checkpoint = try? context.fetch(FetchDescriptor<SyncCheckpoint>()).first(where: {
            $0.ownerUserID == currentOwnerUserID
        })
        return SyncPresentation(
            phase: phase,
            pendingCount: pendingCount ?? mutations.filter {
                $0.state == .queued || $0.state == .uploading || $0.state == .failed
            }.count,
            pendingPhotoCount: pendingPhotoCount ?? photoCounts.pending,
            failedPhotoCount: failedPhotoCount ?? photoCounts.failed,
            conflictCount: conflictCount ?? mutations.filter { $0.state == .conflicted }.count,
            lastSyncedAt: checkpoint?.lastSyncedAt,
            diagnostic: phase == .failed ? lastFailureDiagnostic : nil
        )
    }

    private func photoTransferCounts() -> (pending: Int, failed: Int) {
        let photos = ((try? context.fetch(FetchDescriptor<PhotoAsset>())) ?? []).filter {
            $0.ownerUserID == currentOwnerUserID
        }
        var pending = 0
        var failed = 0
        for photo in photos where photo.draftSessionID == nil {
            if photo.deletedAt != nil {
                guard photo.storageKey != nil, photo.binaryDeletedAt == nil else { continue }
                pending += 1
                if photo.uploadLastError != nil { failed += 1 }
                continue
            }
            guard photo.uploadState == .queued || photo.uploadState == .uploading || photo.uploadState == .failed else {
                continue
            }
            pending += 1
            if photo.uploadState == .failed { failed += 1 }
        }
        return (pending, failed)
    }

    private func scopedQueue() -> SwiftDataSyncQueue {
        SwiftDataSyncQueue(
            context: context,
            ownerUserID: currentOwnerUserID ?? LocalAccountOwner.legacyQuarantine
        )
    }
}

private enum SyncTrigger: String {
    case launch
    case foreground
    case networkRecovered
    case sessionRestored
    case localMutation
    case manual
    case scheduledRetry
}

final class NetworkPathObserver: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.lafayette.tastemap.network-path")
    private var isStarted = false

    func start(_ handler: @escaping @Sendable (Bool) -> Void) {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { path in
            handler(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
        isStarted = false
    }
}

nonisolated private func syncDebug(_ message: String) {
#if DEBUG
    Logger(subsystem: "com.lafayette.tastemap", category: "Sync").debug("\(message, privacy: .public)")
#endif
}
