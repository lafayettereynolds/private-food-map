#if DEBUG
import SwiftUI

struct BackupImportPlanContext: Identifiable, Hashable {
    let id: UUID
    let source: BackupImportSourceGraph
    let snapshot: BackupImportLocalSnapshot
    let initialPlan: BackupImportPlan

    init(source: BackupImportSourceGraph, snapshot: BackupImportLocalSnapshot, initialPlan: BackupImportPlan) {
        id = initialPlan.planID
        self.source = source
        self.snapshot = snapshot
        self.initialPlan = initialPlan
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct BackupImportPlanView: View {
    let context: BackupImportPlanContext
    @State private var plan: BackupImportPlan
    @State private var decisions: [String: BackupImportReviewDecision] = [:]
    @State private var errorMessage: String?

    init(context: BackupImportPlanContext) {
        self.context = context
        _plan = State(initialValue: context.initialPlan)
    }

    var body: some View {
        List {
            Section {
                Label("匹配计划已生成", systemImage: "list.bullet.clipboard")
                    .font(.headline)
                Text("这是 Development 只读预览。选择仅更新内存计划，不会写入 SwiftData，也不会联网。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("计划摘要") {
                LabeledContent("新增", value: "\(count(.create))")
                LabeledContent("自动匹配/合并", value: "\(count(.exactMerge))")
                LabeledContent("完全重复", value: "\(count(.exactDuplicate))")
                LabeledContent("需要确认", value: "\(plan.summary.reviewCount)")
                LabeledContent("跳过", value: "\(count(.skip))")
                LabeledContent("预计同步变更", value: "\(plan.summary.estimatedMutationCount)")
                    .accessibilityIdentifier("backup-import-plan-mutation-count")
            }

            if !context.initialPlan.reviewItems.isEmpty {
                Section("需要确认") {
                    ForEach(context.initialPlan.reviewItems) { item in
                        review(item)
                    }
                }
            }

            if !plan.warnings.isEmpty {
                Section("限制与提醒") {
                    ForEach(plan.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                    }
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section {
                Label("本阶段不提供正式导入", systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("backup-import-no-execute")
            } footer: {
                Text("真正写入必须等 F1-C4 的最终确认流程。")
            }
        }
        .navigationTitle("匹配计划")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("backup-import-plan-page")
    }

    @ViewBuilder
    private func review(_ item: ImportPlanReviewItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title).font(.headline)
            Text(item.sourceSafeLabel).font(.subheadline)
            if let candidate = item.candidateSafeLabel {
                Text("当前候选：\(candidate)").font(.subheadline).foregroundStyle(.secondary)
            }
            Text(item.reason).font(.footnote).foregroundStyle(.secondary)
            if let detail = item.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            Text("处理方式").font(.caption).foregroundStyle(.secondary)
            ForEach(item.options) { option in
                Button {
                    choose(option, for: item)
                } label: {
                    HStack {
                        Text(option.title)
                        Spacer()
                        if decisions[item.id]?.selectedOptionID == option.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .frame(minHeight: 36)
                }
                .accessibilityIdentifier("backup-import-review-option-\(item.entityType.rawValue)-\(option.id)")
            }
            if let selected = decisions[item.id]?.selectedOptionID {
                Text("已选择：\(item.options.first(where: { $0.id == selected })?.title ?? selected)")
                    .font(.caption).foregroundStyle(.green)
            }
        }
        .padding(.vertical, 6)
    }

    private func choose(_ option: BackupImportReviewOption, for item: ImportPlanReviewItem) {
        decisions[item.id] = BackupImportReviewDecision(
            reviewItemID: item.id, selectedOptionID: option.id,
            sourceFileSHA256: context.source.sourceFileSHA256,
            sourceID: item.sourceID, targetID: option.targetID,
            localSnapshotRevision: context.snapshot.revision
        )
        recalculate()
    }

    private func recalculate() {
        do {
            plan = try BackupImportPlanEngine().makePlan(
                source: context.source, local: context.snapshot,
                decisions: Array(decisions.values), generatedAt: plan.generatedAt
            )
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func count(_ action: BackupImportPlanActionKind) -> Int {
        plan.actions.filter { $0.action == action }.count
    }
}

#Preview("Matching plan") {
    Text("Use the import preflight Development fixture to generate a plan.")
}
#endif
