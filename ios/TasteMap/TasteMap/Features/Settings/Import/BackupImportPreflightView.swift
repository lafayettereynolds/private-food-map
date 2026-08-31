import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupImportPreflightView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NativeAuthServices.self) private var authServices
    @Environment(SyncCoordinator.self) private var syncCoordinator

    #if DEBUG
    let fixtureInput: BackupImportFixtureInput?
    #endif
    @State private var coordinator: BackupImportFlowCoordinator
    @State private var isShowingFileImporter = false

    init(
        modelContainer: ModelContainer,
        currentTasteMapUserID: String?
    ) {
        #if DEBUG
        fixtureInput = nil
        #endif
        _coordinator = State(initialValue: BackupImportFlowCoordinator(
            container: modelContainer,
            currentTasteMapUserID: currentTasteMapUserID
        ))
    }

    #if DEBUG
    init(
        modelContainer: ModelContainer,
        currentTasteMapUserID: String?,
        fixtureInput: BackupImportFixtureInput? = nil,
        injectedFailurePoint: BackupImportFailurePoint? = nil
    ) {
        self.fixtureInput = fixtureInput
        _coordinator = State(initialValue: BackupImportFlowCoordinator(
            container: modelContainer,
            currentTasteMapUserID: currentTasteMapUserID,
            injectedFailurePoint: injectedFailurePoint
        ))
    }
    #endif

    var body: some View {
        List { content }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("backup-import-preflight-page")
            .toolbar { toolbar }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false,
                onCompletion: handleFileSelection
            )
            .onDisappear { coordinator.viewDidDisappear() }
            .onChange(of: coordinator.state) { _, state in
                if state == .completed { syncCoordinator.refreshPresentation() }
            }
    }

    @ViewBuilder private var content: some View {
        switch coordinator.state {
        case .idle, .selectingFile:
            introduction
        case .reading:
            processing("读取文件", "正在执行 25 MiB 限制、严格 UTF-8 与安全文件访问检查。", true)
        case .preflighting:
            processing("安全预检", "正在识别 Backup v1 / Legacy Web v4，并检查关系、照片与权限字段。", true)
        case .preflightReady:
            if let run = coordinator.preflightRun {
                BackupImportPreflightSummaryView(
                    run: run,
                    isAuthenticated: coordinator.currentTasteMapUserID != nil,
                    generatePlan: coordinator.generatePlan
                )
            }
        case .planning:
            processing("生成匹配计划", "正在用当前账户、本地快照与文件指纹建立可验证计划。", true)
        case let .reviewRequired(completed, total):
            if let plan = coordinator.plan, let item = coordinator.currentReviewItem {
                BackupImportPlanSummarySection(plan: plan)
                BackupImportReviewSection(
                    item: item,
                    completed: completed,
                    total: total,
                    select: { coordinator.select($0, for: item) }
                )
                if coordinator.unresolvedReviewCount > 1,
                   plan.reviewItems.allSatisfy({ item in
                       item.options.contains(where: { $0.kind == .create })
                   }) {
                    Section {
                        Button("其余可新建项全部作为新记录") {
                            coordinator.makeAllRemainingNewWhereAvailable()
                        }
                        .accessibilityIdentifier("backup-import-review-all-create")
                    } footer: {
                        Text("此操作只选择“新建”，绝不会批量合并相似项。")
                    }
                }
            }
        case .readyToImport:
            if let plan = coordinator.plan, let run = coordinator.preflightRun {
                BackupImportPlanSummarySection(plan: plan)
                BackupImportLimitationsSection(run: run)
                Section {
                    Button("查看最终确认") { coordinator.prepareFinalConfirmation() }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("backup-import-review-complete")
                } footer: {
                    Text("所有需要确认的项目已处理。此时仍未写入任何数据。")
                }
            }
        case .confirming:
            if let plan = coordinator.plan, let run = coordinator.preflightRun {
                BackupImportFinalConfirmationView(
                    plan: plan,
                    run: run,
                    confirm: beginImport,
                    back: coordinator.returnToPlan
                )
            }
        case let .importing(stage):
            processing(stage.title, "事务已经开始，正在完成原子写入与同步队列建立。为避免半状态，此阶段不能取消。", false)
        case .verifying:
            processing("验证本地数据", "正在检查目标 ID、餐厅身份、到访关联、榜单顺序与同步队列。", false)
        case .completed:
            if let result = coordinator.result {
                BackupImportResultView(
                    result: result,
                    syncPresentation: syncCoordinator.presentation,
                    syncNow: { Task { await syncCoordinator.synchronizeNow() } },
                    importAnother: coordinator.startAnotherImport
                )
            }
        case let .failed(failure):
            failureView(failure)
        case .cancelled:
            cancelledView
        case .planStale:
            stalePlanView
        }
    }

    private var introduction: some View {
        Group {
            Section {
                Label("安全合并到当前账户", systemImage: "checkmark.shield").font(.headline)
                Text("支持 Taste Map Backup v1 与 Legacy Web v4 JSON。系统会先预检和匹配，只有你最终确认后才写入。")
                Text("Import 只添加或安全合并业务副本，不会恢复账户、Premium、好友权限或旧版远端 owner。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button(action: chooseFile) {
                    Label(chooseFileTitle, systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(coordinator.currentTasteMapUserID == nil)
                .accessibilityIdentifier("backup-import-choose-file")
            } footer: {
                Text(coordinator.currentTasteMapUserID == nil
                    ? "请先登录 Taste Map，再导入到当前账户。"
                    : "文件只在本机处理；完全离线也可以完成本地导入，联网后由现有同步队列上传。")
            }
        }
    }

    private func processing(_ title: String, _ detail: String, _ canCancel: Bool) -> some View {
        Section {
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text(title).font(.headline)
                Text(detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if canCancel {
                    Button("取消", role: .cancel) { coordinator.cancelBeforeTransaction() }
                        .frame(minWidth: 88, minHeight: 44)
                        .accessibilityIdentifier("backup-import-cancel")
                } else {
                    Label("正在完成安全导入…", systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("backup-import-processing")
        }
    }

    private func failureView(_ failure: BackupImportFailurePresentation) -> some View {
        Group {
            Section {
                Label("无法完成导入", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(.red)
                Text(failure.message).accessibilityIdentifier("backup-import-error-message")
                if failure.existingDataUnchanged {
                    Text("你的现有数据保持不变。").font(.footnote).foregroundStyle(.secondary)
                }
#if DEBUG
                Text("错误代码：\(failure.code)").font(.caption.monospaced()).foregroundStyle(.secondary)
#endif
            }
            Section {
                Button("重新选择文件", action: chooseFile).accessibilityIdentifier("backup-import-reselect")
                Button("关闭", role: .cancel) { dismiss() }
            }
        }
    }

    private var cancelledView: some View {
        Group {
            Section {
                Label("已取消", systemImage: "xmark.circle")
                    .font(.headline)
                    .accessibilityIdentifier("backup-import-cancelled-state")
                Text("尚未开始事务，没有修改任何数据。").foregroundStyle(.secondary)
            }
            Section {
                Button("重新选择文件", action: chooseFile)
                Button("关闭", role: .cancel) { dismiss() }
            }
        }
    }

    private var stalePlanView: some View {
        Group {
            Section {
                Label("数据已发生变化", systemImage: "arrow.clockwise.circle.fill")
                    .font(.headline).foregroundStyle(.orange)
                Text("原匹配计划已拒绝执行。需要基于当前本地数据重新检查；不会在后台悄悄替换计划后继续写入。")
            }
            Section {
                Button("重新生成匹配计划") { coordinator.regenerateAfterStalePlan() }
                    .accessibilityIdentifier("backup-import-regenerate-stale-plan")
                Button("取消", role: .cancel) { coordinator.cancelBeforeTransaction() }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if coordinator.state != .idle, coordinator.state != .completed,
           !coordinator.state.transactionHasStarted {
            ToolbarItem(placement: .topBarTrailing) {
                Button("关闭") { dismiss() }.accessibilityIdentifier("backup-import-close")
            }
        }
    }

    private var navigationTitle: String {
        switch coordinator.state {
        case .reviewRequired: "逐项确认"
        case .readyToImport: "匹配计划"
        case .confirming: "最终确认"
        case .completed: "导入结果"
        default: "导入数据"
        }
    }

    private func chooseFile() {
        coordinator.beginFileSelection()
        #if DEBUG
        if let fixtureInput {
            coordinator.readAndPreflight(data: fixtureInput.data, fileName: fixtureInput.fileName, fixtureDelay: fixtureInput.delay)
        } else {
            isShowingFileImporter = true
        }
        #else
        isShowingFileImporter = true
        #endif
    }

    private var chooseFileTitle: String {
        #if DEBUG
        fixtureInput == nil ? "选择 JSON 文件" : "选择测试文件"
        #else
        "选择 JSON 文件"
        #endif
    }

    private func handleFileSelection(_ selection: Result<[URL], Error>) {
        switch selection {
        case let .success(urls):
            guard let url = urls.first else { coordinator.fileSelectionCancelled(); return }
            coordinator.readAndPreflight(url: url)
        case let .failure(error):
            if (error as NSError).code == NSUserCancelledError { coordinator.fileSelectionCancelled() }
            else { coordinator.fileSelectionFailed() }
        }
    }

    private func beginImport() {
        Task { @MainActor in
            let currentUserID = await authServices.sessionManager.restoredUser()?.id
#if DEBUG
            let fixtureUserID = BackupImportDevelopmentFixture.current == nil ? nil : coordinator.currentTasteMapUserID
#else
            let fixtureUserID: String? = nil
#endif
            coordinator.execute(currentUserIDAtConfirmation: currentUserID ?? fixtureUserID)
        }
    }
}

struct BackupImportPreflightSummaryView: View {
    let run: BackupImportPreflightRun
    let isAuthenticated: Bool
    let generatePlan: () -> Void
    private var result: ImportPreflightResult { run.result }

    var body: some View {
        statusSection
        Section("文件") {
            LabeledContent("类型", value: result.sourceFormat.title).accessibilityIdentifier("backup-import-source-format")
            LabeledContent("版本", value: "\(result.sourceVersion)")
            if let exportedAt = result.sourceMetadata.exportedAt { LabeledContent("导出时间", value: exportedAt) }
            LabeledContent("文件大小", value: ByteCountFormatter.string(fromByteCount: Int64(result.fileSize), countStyle: .file))
#if DEBUG
            VStack(alignment: .leading, spacing: 6) {
                Text("文件 SHA-256").font(.caption).foregroundStyle(.secondary)
                Text(result.sourceFileSHA256).font(.caption2.monospaced()).textSelection(.enabled)
            }
#endif
        }
        Section("内容") {
            count("餐厅", result.counts.restaurants); count("到访", result.counts.visits)
            count("菜品", result.counts.dishes); count("菜品关联", result.counts.visitDishes)
            count("照片记录", result.counts.photos); count("饭搭子", result.counts.companions)
            count("推荐来源", result.counts.recommendationSources); count("榜单", result.counts.restaurantLists)
            count("榜单条目", result.counts.restaurantListItems)
        }
        Section("安全检查") {
            LabeledContent("无法继续", value: "\(result.blockingCount)")
            LabeledContent("需要确认", value: "\(result.reviewCount)")
            LabeledContent("警告", value: "\(result.warningCount)")
            LabeledContent("已忽略身份/权限信息", value: "\(result.securityDiscardCount)")
            LabeledContent("旧版已停用内容", value: "\(result.deprecatedFieldCount)")
        }
        Section("照片") {
            Label(result.photoBinaryStatus.message, systemImage: "photo.badge.exclamationmark")
                .accessibilityIdentifier("backup-import-photo-message")
        }
        if !result.issues.isEmpty {
            Section {
                NavigationLink { BackupImportIssuesView(result: result) } label: {
                    Label("查看问题详情", systemImage: "list.bullet.rectangle")
                }.accessibilityIdentifier("backup-import-issues-entry")
            }
        }
        Section {
            if result.blockingCount == 0, isAuthenticated {
                Button("生成匹配计划", action: generatePlan)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("backup-import-generate-plan")
            }
        } footer: {
            Text(result.blockingCount == 0 ? "下一步只生成匹配计划，仍不会写入。" : "请查看阻塞原因，或重新选择文件。")
        }
#if DEBUG
        Section("Development Timing") {
            LabeledContent("读取", value: Self.duration(run.timing.fileReadSeconds))
            LabeledContent("格式检查", value: Self.duration(run.timing.inspectionSeconds))
            LabeledContent("解码与规范化", value: Self.duration(run.timing.decodeAndNormalizeSeconds))
            LabeledContent("验证", value: Self.duration(run.timing.validationSeconds))
            LabeledContent("总计", value: Self.duration(run.timing.totalSeconds))
        }
#endif
    }

    private var statusSection: some View {
        Section {
            if result.blockingCount > 0 {
                Label("此文件暂时无法继续导入。", systemImage: "xmark.octagon.fill")
                    .font(.headline).foregroundStyle(.red).accessibilityIdentifier("backup-import-blocking-state")
            } else if result.reviewCount > 0 {
                Label("文件可以继续，但有内容需要确认。", systemImage: "exclamationmark.bubble.fill")
                    .font(.headline).foregroundStyle(.orange).accessibilityIdentifier("backup-import-review-state")
            } else {
                Label("预检通过。", systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(.green).accessibilityIdentifier("backup-import-clean-state")
            }
        }
    }
    private func count(_ title: String, _ value: Int) -> some View { LabeledContent(title, value: "\(value)") }
    private static func duration(_ seconds: Double) -> String { String(format: "%.3f s", seconds) }
}

struct BackupImportIssuesView: View {
    let result: ImportPreflightResult
    var body: some View {
        List {
            ForEach(BackupImportIssueSeverity.allCases, id: \.self) { severity in
                let issues = result.issues(with: severity)
                if !issues.isEmpty {
                    Section(severity.title) {
                        ForEach(issues) { issue in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(issue.title).font(.headline)
                                Text(issue.explanation).font(.subheadline).foregroundStyle(.secondary)
                                if issue.count > 1 { Text("共 \(issue.count) 项").font(.caption) }
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("问题详情")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("backup-import-issues-page")
    }
}
