#if DEBUG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupImportPreflightView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let currentTasteMapUserID: String?
    let developmentFixture: BackupImportDevelopmentFixture?
    var fileReader = BackupImportFileReader()
    var preflightService = BackupImportPreflightService()

    @State private var isShowingFileImporter = false
    @State private var stage: BackupImportProgressStage?
    @State private var run: BackupImportPreflightRun?
    @State private var errorMessage: String?
    @State private var planningErrorMessage: String?
    @State private var planContext: BackupImportPlanContext?
    @State private var preflightTask: Task<Void, Never>?

    var body: some View {
        List {
            if let stage {
                processingSection(stage)
            } else if let run {
                BackupImportPreflightSummaryView(
                    run: run,
                    currentTasteMapUserID: currentTasteMapUserID,
                    planningErrorMessage: planningErrorMessage,
                    generatePlan: { generatePlan(from: run) }
                )
            } else if let errorMessage {
                errorSection(errorMessage)
            } else {
                introductionSection
            }
        }
        .navigationTitle("导入数据")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("backup-import-preflight-page")
        .toolbar {
            if run != nil || errorMessage != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .accessibilityIdentifier("backup-import-close")
                }
            }
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { selection in
            switch selection {
            case let .success(urls):
                guard let url = urls.first else { return }
                startPreflight(url: url)
            case let .failure(error):
                if (error as NSError).code != NSUserCancelledError {
                    errorMessage = "文件选择未完成：\(error.localizedDescription)"
                }
            }
        }
        .onDisappear { preflightTask?.cancel() }
        .navigationDestination(item: $planContext) { value in
            BackupImportPlanView(context: value)
        }
    }

    private var introductionSection: some View {
        Group {
            Section {
                Label("只读安全预检", systemImage: "checkmark.shield")
                    .font(.headline)
                Text("系统会先检查文件并显示预览，确认前不会修改任何数据。")
                Text("支持 Taste Map Backup v1 与 Legacy Web v4 JSON。当前版本不会执行导入、合并或同步。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(action: chooseFile) {
                    Label(
                        developmentFixture == nil ? "选择 JSON 文件" : "选择测试文件",
                        systemImage: "doc.badge.magnifyingglass"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("backup-import-choose-file")
            } footer: {
                Text("文件仅在本机离线检查；不会上传，也不会永久保存文件访问权限。")
            }
        }
    }

    private func processingSection(_ stage: BackupImportProgressStage) -> some View {
        Section {
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text(stage.title).font(.headline)
                Text("大型 Legacy 文件可能需要一些时间。不会显示虚假的百分比。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("取消", role: .cancel) { preflightTask?.cancel() }
                    .frame(minWidth: 88, minHeight: 44)
                    .accessibilityIdentifier("backup-import-cancel")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .accessibilityIdentifier("backup-import-processing")
        }
    }

    private func errorSection(_ message: String) -> some View {
        Group {
            Section {
                Label("无法完成预检", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(message)
                    .accessibilityIdentifier("backup-import-error-message")
            }
            Section {
                Button("重新选择文件", action: chooseFile)
                    .accessibilityIdentifier("backup-import-reselect")
                Button("关闭", role: .cancel) { dismiss() }
            }
        }
    }

    private func chooseFile() {
        run = nil
        errorMessage = nil
        if let developmentFixture {
            startPreflight(fixture: developmentFixture)
        } else {
            isShowingFileImporter = true
        }
    }

    private func startPreflight(url: URL) {
        execute {
            try await fileReader.read(from: url)
        }
    }

    private func startPreflight(fixture: BackupImportDevelopmentFixture) {
        execute {
            // Keep the real processing state observable in UI automation;
            // normal user-selected files do not incur this fixture-only delay.
            try await Task.sleep(for: .milliseconds(1_500))
            return try await fileReader.read(data: fixture.data, fileName: fixture.fileName)
        }
    }

    private func execute(
        read: @escaping @Sendable () async throws -> BackupImportSourceFile
    ) {
        preflightTask?.cancel()
        run = nil
        errorMessage = nil
        stage = .reading
        preflightTask = Task { @MainActor in
            let clock = ContinuousClock()
            let readStart = clock.now
            do {
                let source = try await read()
                let readSeconds = Self.seconds(readStart.duration(to: clock.now))
                try Task.checkCancellation()
                stage = .inspecting
                await Task.yield()
                stage = .decoding
                let completed = try await preflightService.preflight(
                    source,
                    fileReadSeconds: readSeconds
                )
                try Task.checkCancellation()
                stage = .summarizing
                await Task.yield()
                run = completed
                stage = nil
            } catch is CancellationError {
                stage = nil
                errorMessage = BackupImportPreflightError.cancelled.localizedDescription
            } catch let error as BackupImportPreflightError {
                stage = nil
                errorMessage = error.localizedDescription
            } catch {
                stage = nil
                errorMessage = "无法安全检查这个文件。"
            }
            preflightTask = nil
        }
    }

    @MainActor
    private func generatePlan(from run: BackupImportPreflightRun) {
        planningErrorMessage = nil
        do {
            guard run.result.blockingCount == 0 else { throw BackupImportPlanningError.preflightBlocked }
            guard let currentTasteMapUserID else { throw BackupImportPlanningError.invalidCurrentUser }
            let source = try BackupImportPlanningSourceMapper.graph(from: run)
            let snapshot: BackupImportLocalSnapshot
            if developmentFixture != nil {
                snapshot = BackupImportDevelopmentFixture.planSnapshot(
                    currentTasteMapUserID: currentTasteMapUserID,
                    source: source
                )
            } else {
                snapshot = try BackupImportLocalSnapshotBuilder(context: modelContext)
                    .make(currentTasteMapUserID: currentTasteMapUserID)
            }
            let plan = try BackupImportPlanEngine().makePlan(source: source, local: snapshot)
            planContext = BackupImportPlanContext(source: source, snapshot: snapshot, initialPlan: plan)
        } catch {
            planningErrorMessage = error.localizedDescription
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

private struct BackupImportPreflightSummaryView: View {
    let run: BackupImportPreflightRun
    let currentTasteMapUserID: String?
    let planningErrorMessage: String?
    let generatePlan: () -> Void

    private var result: ImportPreflightResult { run.result }

    var body: some View {
        statusSection

        Section("文件") {
            LabeledContent("类型", value: result.sourceFormat.title)
                .accessibilityIdentifier("backup-import-source-format")
            LabeledContent("版本", value: "\(result.sourceVersion)")
            if let exportedAt = result.sourceMetadata.exportedAt {
                LabeledContent("导出时间", value: exportedAt)
            }
            LabeledContent(
                "文件大小",
                value: ByteCountFormatter.string(
                    fromByteCount: Int64(result.fileSize),
                    countStyle: .file
                )
            )
            VStack(alignment: .leading, spacing: 6) {
                Text("文件 SHA-256").font(.caption).foregroundStyle(.secondary)
                Text(result.sourceFileSHA256)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }
        }

        Section("内容") {
            count("餐厅", result.counts.restaurants)
            count("到访", result.counts.visits)
            count("菜品", result.counts.dishes)
            count("菜品关联", result.counts.visitDishes)
            count("照片记录", result.counts.photos)
            count("饭搭子", result.counts.companions)
            count("推荐来源", result.counts.recommendationSources)
            count("榜单", result.counts.restaurantLists)
            count("榜单条目", result.counts.restaurantListItems)
            count("Tombstone", result.counts.tombstones)
        }

        Section("检查摘要") {
            LabeledContent("无法继续", value: "\(result.blockingCount)")
            LabeledContent("需要确认", value: "\(result.reviewCount)")
            LabeledContent("警告", value: "\(result.warningCount)")
            LabeledContent("已忽略身份/权限字段", value: "\(result.securityDiscardCount)")
            LabeledContent("旧版已停用字段", value: "\(result.deprecatedFieldCount)")
            LabeledContent("不支持的内容", value: "\(result.unsupportedCount)")
        }

        Section("照片") {
            Label(result.photoBinaryStatus.message, systemImage: "photo.badge.exclamationmark")
                .accessibilityIdentifier("backup-import-photo-message")
        }

        if !result.issues.isEmpty {
            Section {
                NavigationLink {
                    BackupImportIssuesView(result: result)
                } label: {
                    Label("查看问题详情", systemImage: "list.bullet.rectangle")
                }
                .accessibilityIdentifier("backup-import-issues-entry")
            }
        }

        Section {
            if result.blockingCount == 0, currentTasteMapUserID != nil {
                Button("生成匹配计划", action: generatePlan)
                    .accessibilityIdentifier("backup-import-generate-plan")
            }
            if let planningErrorMessage {
                Text(planningErrorMessage).font(.footnote).foregroundStyle(.red)
                    .accessibilityIdentifier("backup-import-plan-error")
            }
            Text("匹配计划只在内存中计算。本阶段没有正式导入按钮，也不会写入任何数据。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section("Development Timing") {
            LabeledContent("读取", value: Self.duration(run.timing.fileReadSeconds))
            LabeledContent("格式检查", value: Self.duration(run.timing.inspectionSeconds))
            LabeledContent("解码与规范化", value: Self.duration(run.timing.decodeAndNormalizeSeconds))
            LabeledContent("验证", value: Self.duration(run.timing.validationSeconds))
            LabeledContent("总计", value: Self.duration(run.timing.totalSeconds))
        }
    }

    private var statusSection: some View {
        Section {
            if result.blockingCount > 0 {
                Label("此文件暂时无法继续导入。", systemImage: "xmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("backup-import-blocking-state")
                Text("请查看阻塞原因，或重新选择文件。")
            } else if result.reviewCount > 0 {
                Label("文件可以继续分析，但存在需要确认的问题。", systemImage: "exclamationmark.bubble.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("backup-import-review-state")
                Text("本轮不会要求你做合并决定，也不会修改数据。")
            } else {
                Label("预检通过。", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("backup-import-clean-state")
                Text("文件结构有效，可以进入下一步的数据匹配阶段。")
            }
        }
    }

    private func count(_ title: String, _ value: Int) -> some View {
        LabeledContent(title, value: "\(value)")
    }

    private static func duration(_ seconds: Double) -> String {
        String(format: "%.3f s", seconds)
    }
}

private struct BackupImportIssuesView: View {
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
                                Text(issue.explanation)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let entityType = issue.entityType {
                                    Text("类型：\(entityType)").font(.caption)
                                }
                                if let reference = issue.sourceReference {
                                    Text("安全引用：\(reference)")
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                }
                                if issue.count > 1 {
                                    Text("共 \(issue.count) 项").font(.caption)
                                }
                            }
                            .padding(.vertical, 4)
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

#Preview("Legacy clean") {
    NavigationStack {
        BackupImportPreflightView(currentTasteMapUserID: "tm_preview", developmentFixture: .legacyValid)
    }
}

#Preview("Legacy blocking") {
    NavigationStack {
        BackupImportPreflightView(currentTasteMapUserID: "tm_preview", developmentFixture: .legacyBlocking)
    }
}
#endif
