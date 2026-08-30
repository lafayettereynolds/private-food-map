import SwiftUI

struct CommunityReportTarget: Identifiable, Equatable {
    let type: ModerationContentTypeV1
    let contentID: String
    let authorUserID: String
    let title: String
    var id: String { "\(type.rawValue):\(contentID)" }
}

struct CommunityReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let target: CommunityReportTarget
    let api: any ReleaseSafetyAPI
    @State private var reason: ModerationReasonV1 = .spam
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("举报对象") { Text(target.title) }
                Section("原因") {
                    Picker("原因", selection: $reason) {
                        ForEach(ModerationReasonV1.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("community-report-reason")
                }
                Section("补充说明（可选）") {
                    TextField("最多 500 字", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("community-report-details")
                }
                if let message { Section { Text(message).foregroundStyle(.secondary) } }
            }
            .navigationTitle("举报内容")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("提交") { Task { await submit() } }
                        .disabled(isSubmitting || details.count > 500)
                        .accessibilityIdentifier("community-report-submit")
                }
            }
        }
        .accessibilityIdentifier("community-report-sheet")
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await api.report(
                type: target.type, id: target.contentID, reason: reason,
                details: details, requestID: UUID()
            )
            dismiss()
        } catch { message = "举报没有提交成功，请稍后重试。" }
    }
}
