import SwiftUI

struct BackupImportPlanSummarySection: View {
    let plan: BackupImportPlan

    var body: some View {
        Section {
            Label("安全匹配计划", systemImage: "list.bullet.clipboard")
                .font(.headline)
            ForEach(plan.summary.entities, id: \.entityType) { summary in
                if total(summary) > 0 {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(summary.entityType.title).font(.subheadline.weight(.semibold))
                        Text(summaryText(summary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            LabeledContent("预计同步变更", value: "\(plan.summary.estimatedMutationCount)")
                .accessibilityIdentifier("backup-import-plan-mutation-count")
        } header: {
            Text("计划摘要")
        } footer: {
            Text("精确 provider identity 才会自动匹配；跨地图来源的相似餐厅必须由你确认。")
        }
        .accessibilityIdentifier("backup-import-plan-page")

#if DEBUG
        Section("Development Diagnostics") {
            Text("Plan ID：\(plan.planID.uuidString.lowercased())")
                .font(.caption2.monospaced()).textSelection(.enabled)
            Text("Local revision：\(plan.localSnapshotRevision)")
                .font(.caption2.monospaced()).textSelection(.enabled)
            Text("Source SHA：\(plan.sourceFileSHA256)")
                .font(.caption2.monospaced()).textSelection(.enabled)
        }
#endif
    }

    private func total(_ value: BackupImportEntityActionSummary) -> Int {
        value.create + value.exactMerge + value.exactDuplicate + value.review + value.skipped + value.blocked
    }

    private func summaryText(_ value: BackupImportEntityActionSummary) -> String {
        var parts: [String] = []
        if value.create > 0 { parts.append("新增 \(value.create)") }
        if value.exactMerge > 0 { parts.append("匹配/合并 \(value.exactMerge)") }
        if value.exactDuplicate > 0 { parts.append("重复跳过 \(value.exactDuplicate)") }
        if value.review > 0 { parts.append("需确认 \(value.review)") }
        if value.skipped > 0 { parts.append("跳过 \(value.skipped)") }
        if value.blocked > 0 { parts.append("待依赖确认 \(value.blocked)") }
        return parts.joined(separator: " · ")
    }
}

struct BackupImportReviewSection: View {
    let item: ImportPlanReviewItem
    let completed: Int
    let total: Int
    let select: (BackupImportReviewOption) -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(item.entityType.title, systemImage: icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(min(completed + 1, total)) / \(total)")
                        .font(.caption.monospacedDigit())
                        .accessibilityLabel("第 \(min(completed + 1, total)) 项，共 \(total) 项")
                }
                Text(item.title).font(.title3.weight(.semibold))
                comparison(title: "备份中的内容", value: item.sourceSafeLabel, image: "doc")
                if let candidate = item.candidateSafeLabel {
                    comparison(title: "本机候选", value: candidate, image: "iphone")
                }
                Text(item.reason).font(.subheadline).foregroundStyle(.secondary)
                if let detail = item.detail {
                    Text(safeDetail(detail)).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("需要你的确认")
        } footer: {
            Text("没有默认合并。名称相似不等于同一家餐厅；连锁分店请重点核对城市和地址。")
        }

        Section("处理方式") {
            ForEach(item.options) { option in
                Button { select(option) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: optionIcon(option.kind))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.title).foregroundStyle(.primary)
                            Text(optionExplanation(option.kind))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("\(option.title)。\(optionExplanation(option.kind))")
                .accessibilityIdentifier("backup-import-review-option-\(item.entityType.rawValue)-\(option.id)")
            }
        }
    }

    private var icon: String {
        switch item.entityType {
        case .restaurant: "fork.knife.circle"
        case .visit: "calendar"
        case .dish: "takeoutbag.and.cup.and.straw"
        case .profile: "person.crop.circle"
        case .restaurantList: "list.number"
        default: "questionmark.bubble"
        }
    }

    private func comparison(title: String, value: String, image: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: image).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func safeDetail(_ value: String) -> String {
        value.replacingOccurrences(of: "字段：displayName", with: "字段：显示名称")
            .replacingOccurrences(of: "字段：bio", with: "字段：个人简介")
            .replacingOccurrences(of: "字段：city", with: "字段：城市")
            .replacingOccurrences(of: "字段：visibility", with: "字段：主页可见范围")
            .replacingOccurrences(of: "字段：avatarPresetID", with: "字段：头像样式")
    }

    private func optionIcon(_ kind: BackupImportReviewOptionKind) -> String {
        switch kind {
        case .merge: "arrow.triangle.merge"
        case .create: "plus.circle"
        case .skip: "forward.end"
        case .keepCurrent: "iphone"
        case .useBackup: "doc.badge.arrow.up"
        }
    }

    private func optionExplanation(_ kind: BackupImportReviewOptionKind) -> String {
        switch kind {
        case .merge: "将安全关联到这条现有记录"
        case .create: "保留为一条独立的新记录"
        case .skip: "这条内容不会导入"
        case .keepCurrent: "保留当前非空资料值"
        case .useBackup: "只替换这个资料字段"
        }
    }
}

struct BackupImportLimitationsSection: View {
    let run: BackupImportPreflightRun
    private var result: ImportPreflightResult { run.result }

    var body: some View {
        Section("导入限制") {
            Label(photoMessage, systemImage: "photo.badge.exclamationmark")
                .accessibilityIdentifier("backup-import-final-photo-warning")
            if result.deprecatedFieldCount > 0 {
                Label("发现 \(result.deprecatedFieldCount) 项旧版本已停用内容，不会导入。", systemImage: "archivebox")
            }
            if result.securityDiscardCount > 0 {
                Label("已忽略 \(result.securityDiscardCount) 项身份、会员或社交权限信息。", systemImage: "lock.shield")
            }
        }
    }

    private var photoMessage: String {
        switch result.sourceFormat {
        case .backupV1:
            "Backup v1 不包含照片原图；\(result.counts.photos) 条照片记录不会导入。"
        case .legacyWebV4:
            "旧 Web 备份中的照片原图无法仅凭此文件恢复；\(result.counts.photos) 条照片记录不会导入。"
        }
    }
}

struct BackupImportFinalConfirmationView: View {
    let plan: BackupImportPlan
    let run: BackupImportPreflightRun
    let confirm: () -> Void
    let back: () -> Void

    var body: some View {
        Section {
            Label("添加到当前 Taste Map 账户", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline)
            Text("这是 Import，不是账户恢复。不会保留未经服务器证明的远端 owner、version 或权限。")
                .font(.footnote).foregroundStyle(.secondary)
        }

        Section("将新增") {
            ForEach(createdResults, id: \.0) { type, count in
                LabeledContent(type.title, value: "\(count)")
            }
            if createdResults.isEmpty { Text("没有需要新增的记录").foregroundStyle(.secondary) }
        }

        Section("将安全匹配或合并") {
            ForEach(mergedResults, id: \.0) { type, count in
                LabeledContent(type.title, value: "\(count)")
            }
            if mergedResults.isEmpty { Text("没有需要合并的记录").foregroundStyle(.secondary) }
        }

        Section("将跳过") {
            LabeledContent("重复或明确跳过", value: "\(skippedCount)")
            LabeledContent("照片记录", value: "\(run.result.counts.photos)")
            LabeledContent("旧版已停用内容", value: "\(run.result.deprecatedFieldCount)")
        }

        Section("同步") {
            LabeledContent("预计同步变更", value: "\(plan.summary.estimatedMutationCount)")
            Text("导入先在本机完成。网络失败只会让同步稍后重试，不会让本地 Import 失败。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        BackupImportLimitationsSection(run: run)

        Section {
            Button("开始导入", action: confirm)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 48)
                .accessibilityIdentifier("backup-import-confirm-execute")
            Button("返回检查", role: .cancel, action: back)
                .frame(maxWidth: .infinity, minHeight: 44)
        } footer: {
            Text("点击“开始导入”后将执行一个不可中途取消的安全事务。")
        }
    }

    private var createdResults: [(BackupImportEntityKind, Int)] {
        plan.summary.entities.compactMap { $0.create > 0 ? ($0.entityType, $0.create) : nil }
    }
    private var mergedResults: [(BackupImportEntityKind, Int)] {
        plan.summary.entities.compactMap { $0.exactMerge > 0 ? ($0.entityType, $0.exactMerge) : nil }
    }
    private var skippedCount: Int {
        plan.summary.entities.reduce(0) { $0 + $1.skipped + $1.exactDuplicate }
    }
}

struct BackupImportResultView: View {
    let result: BackupImportResult
    let syncPresentation: SyncPresentation
    let syncNow: () -> Void
    let importAnother: () -> Void

    var body: some View {
        Section {
            Label("已导入到本机", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.semibold)).foregroundStyle(.green)
                .accessibilityIdentifier("backup-import-local-success")
            Text("关闭 App 后数据仍会保留。云端同步是后续独立状态。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        Section("结果") {
            resultRow(.restaurant, "餐厅")
            resultRow(.visit, "到访")
            resultRow(.dish, "菜品")
            resultRow(.restaurantList, "榜单")
            if result.photoSkippedCount > 0 {
                LabeledContent("照片记录跳过", value: "\(result.photoSkippedCount)")
            }
            LabeledContent("已加入同步队列", value: "\(result.mutationCount)")
                .accessibilityIdentifier("backup-import-result-mutation-count")
        }
        Section {
            SyncStatusView(presentation: syncPresentation)
            if syncPresentation.phase != .syncing && syncPresentation.phase != .signedOut {
                Button(syncPresentation.allowsRetry ? "重试同步" : "立即同步", action: syncNow)
                    .accessibilityIdentifier("backup-import-sync-now")
            }
        } header: {
            Text("同步状态")
        } footer: {
            Text("“已导入本机”不等于“已同步到云端”。离线时队列会等待联网。")
        }
        Section {
            NavigationLink {
                RestaurantCollectionView(segment: .visited)
            } label: {
                Label("查看餐厅", systemImage: "fork.knife")
            }
            .accessibilityIdentifier("backup-import-result-restaurants")
            Button("继续导入另一个文件", action: importAnother)
                .accessibilityIdentifier("backup-import-another")
        }
#if DEBUG
        Section("Development Diagnostics") {
            Text("Plan ID：\(result.planID.uuidString.lowercased())").font(.caption2.monospaced())
            LabeledContent("事务", value: String(format: "%.3f s", result.transactionSeconds))
            LabeledContent("验证", value: String(format: "%.3f s", result.verificationSeconds))
        }
#endif
    }

    private func resultRow(_ type: BackupImportEntityKind, _ title: String) -> some View {
        let value = result.entity(type)
        return LabeledContent(title, value: "新增 \(value.created) · 合并 \(value.merged) · 跳过 \(value.skipped + value.duplicate)")
    }
}
