import SwiftData
import SwiftUI

struct VisitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allRestaurants: [Restaurant]

    private let restaurant: Restaurant?
    private let candidate: RestaurantCandidate?
    private let visit: Visit?
    private let onSaved: ((UUID) -> Void)?

    @State private var draft: VisitDraft
    @State private var partySizeText: String
    @State private var spendText: String
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isConfirmingDeletion = false

    @MainActor
    init(
        restaurant: Restaurant,
        visit: Visit? = nil,
        onSaved: ((UUID) -> Void)? = nil
    ) {
        self.restaurant = restaurant
        candidate = nil
        self.visit = visit
        self.onSaved = onSaved
        let initialDraft = visit.map(VisitDraft.init) ?? VisitDraft()
        _draft = State(initialValue: initialDraft)
        _partySizeText = State(initialValue: Self.integerString(initialDraft.partySize))
        _spendText = State(initialValue: Self.spendString(initialDraft.myActualSpend))
    }

    @MainActor
    init(candidate: RestaurantCandidate, onSaved: ((UUID) -> Void)? = nil) {
        restaurant = nil
        self.candidate = candidate
        visit = nil
        self.onSaved = onSaved
        _draft = State(initialValue: VisitDraft())
        _partySizeText = State(initialValue: "")
        _spendText = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                restaurantSection
                basicsSection
                ratingSection
                spendSection
                noteSection
                if visit != nil { deleteSection }
            }
            .navigationTitle(visit == nil ? "新增到访" : "编辑到访")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(isSaving)
                        .accessibilityIdentifier("visit-editor-save")
                }
            }
            .confirmationDialog(
                "删除这次到访？",
                isPresented: $isConfirmingDeletion,
                titleVisibility: .visible
            ) {
                Button("删除到访记录", role: .destructive, action: deleteVisit)
                Button("取消", role: .cancel) {}
            } message: {
                Text("这只会删除当前 Visit，不会影响这家餐厅的其他记录。")
            }
            .alert("无法完成", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "请稍后重试。")
            }
        }
    }

    private var restaurantSection: some View {
        Section("餐厅") {
            Text(restaurant?.name ?? candidate?.name ?? "")
                .font(.headline)
            let address = restaurant?.address ?? candidate?.address ?? ""
            if !address.isEmpty {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var basicsSection: some View {
        Section {
            DatePicker(
                "到访日期",
                selection: $draft.visitedAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("visit-editor-date")

            Picker("用餐方式", selection: $draft.diningMode) {
                ForEach(DiningMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("visit-editor-dining-mode")

            LabeledContent("用餐人数") {
                TextField("未填写", text: $partySizeText)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .accessibilityLabel("用餐人数，可选")
                    .accessibilityIdentifier("visit-editor-party-size")
            }
        } header: {
            Text("基础")
        } footer: {
            Text("人数可留空；填写时必须是大于 0 的整数。日期与时间会按设备当前时区显示。")
        }
    }

    private var ratingSection: some View {
        Section("评价") {
            HalfStarRatingPicker(rating: $draft.rating)
        }
    }

    private var spendSection: some View {
        Section {
            TextField("例如 128.50", text: $spendText)
                .keyboardType(.decimalPad)
                .accessibilityLabel("我的实际消费，可选")
                .accessibilityIdentifier("visit-editor-spend")
        } header: {
            Text("消费")
        } footer: {
            Text("留空表示未记录，不会按 0 元保存。")
        }
    }

    private var noteSection: some View {
        Section("记录") {
            TextEditor(text: $draft.note)
                .frame(minHeight: 120)
                .accessibilityLabel("到访备注，可选")
                .accessibilityIdentifier("visit-editor-note")
        }
    }

    private var deleteSection: some View {
        Section {
            Button("删除这次到访", systemImage: "trash", role: .destructive) {
                isConfirmingDeletion = true
            }
            .disabled(isSaving)
            .accessibilityIdentifier("visit-editor-delete")
        } footer: {
            Text("不会删除餐厅，也不会影响其他到访记录。")
        }
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }

        do {
            var validatedDraft = draft
            validatedDraft.partySize = try VisitDraft.partySize(from: partySizeText)
            validatedDraft.myActualSpend = try VisitDraft.spend(from: spendText)
            validatedDraft = try validatedDraft.validated()

            let store = LocalTasteMapStore(context: modelContext)
            let restaurantID: UUID
            if let visit, let restaurant {
                try store.update(visit, draft: validatedDraft)
                restaurantID = restaurant.id
            } else {
                let resolvedRestaurant: Restaurant
                if let restaurant {
                    resolvedRestaurant = restaurant
                } else if let candidate {
                    resolvedRestaurant = try store.restaurant(for: candidate, among: allRestaurants)
                } else {
                    throw VisitEditorError.missingRestaurant
                }
                try store.createVisit(restaurantId: resolvedRestaurant.id, draft: validatedDraft)
                restaurantID = resolvedRestaurant.id
            }

            onSaved?(restaurantID)
            dismiss()
        } catch let error as LocalizedError {
            saveError = error.errorDescription ?? "本地记录没有保存成功，请重试。"
        } catch {
            saveError = "本地记录没有保存成功，请重试。"
        }
    }

    private func deleteVisit() {
        guard let visit else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try LocalTasteMapStore(context: modelContext).delete(visit)
            dismiss()
        } catch {
            saveError = "这条到访记录没有删除成功，请重试。"
        }
    }

    private static func integerString(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    private static func spendString(_ spend: Decimal?) -> String {
        spend.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
    }
}

private enum VisitEditorError: Error {
    case missingRestaurant
}
