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

    @State private var visitedAt: Date
    @State private var rating: Double?
    @State private var note: String
    @State private var spendText: String
    @State private var isSaving = false
    @State private var saveError: String?

    init(
        restaurant: Restaurant,
        visit: Visit? = nil,
        onSaved: ((UUID) -> Void)? = nil
    ) {
        self.restaurant = restaurant
        candidate = nil
        self.visit = visit
        self.onSaved = onSaved
        _visitedAt = State(initialValue: visit?.visitedAt ?? .now)
        _rating = State(initialValue: visit?.rating)
        _note = State(initialValue: visit?.note ?? "")
        _spendText = State(initialValue: Self.spendString(visit?.myActualSpend))
    }

    init(candidate: RestaurantCandidate, onSaved: ((UUID) -> Void)? = nil) {
        restaurant = nil
        self.candidate = candidate
        visit = nil
        self.onSaved = onSaved
        _visitedAt = State(initialValue: .now)
        _rating = State(initialValue: nil)
        _note = State(initialValue: "")
        _spendText = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
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

                Section("到访日期") {
                    DatePicker("日期", selection: $visitedAt)
                }

                Section("评分（可选）") {
                    HalfStarRatingPicker(rating: $rating)
                }

                Section("备注（可选）") {
                    TextEditor(text: $note)
                        .frame(minHeight: 100)
                }

                Section {
                    TextField("例如 128.50", text: $spendText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("我的实际消费（可选）")
                } footer: {
                    Text("想记多少就记多少，可以直接保存。")
                }
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
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "请稍后重试。")
            }
        }
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }

        do {
            let store = LocalTasteMapStore(context: modelContext)
            let spend = Self.decimal(from: spendText)
            let restaurantID: UUID

            if let visit, let restaurant {
                try store.update(
                    visit,
                    visitedAt: visitedAt,
                    rating: rating,
                    note: note,
                    myActualSpend: spend
                )
                restaurantID = restaurant.id
            } else {
                let resolvedRestaurant: Restaurant
                if let restaurant {
                    resolvedRestaurant = restaurant
                } else if let candidate {
                    resolvedRestaurant = store.restaurant(for: candidate, among: allRestaurants)
                } else {
                    throw VisitEditorError.missingRestaurant
                }

                try store.createVisit(
                    restaurantId: resolvedRestaurant.id,
                    visitedAt: visitedAt,
                    rating: rating,
                    note: note,
                    myActualSpend: spend
                )
                restaurantID = resolvedRestaurant.id
            }

            onSaved?(restaurantID)
            dismiss()
        } catch {
            saveError = "本地记录没有保存成功，请重试。"
        }
    }

    private static func decimal(from text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        return formatter.number(from: trimmed)?.decimalValue
            ?? Decimal(string: trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private static func spendString(_ spend: Decimal?) -> String {
        spend.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
    }
}

private enum VisitEditorError: Error {
    case missingRestaurant
}
