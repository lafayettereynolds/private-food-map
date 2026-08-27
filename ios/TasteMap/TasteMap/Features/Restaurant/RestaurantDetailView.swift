import SwiftData
import SwiftUI

struct RestaurantDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Visit.visitedAt, order: .reverse) private var allVisits: [Visit]

    let restaurant: Restaurant

    @State private var isAddingVisit = false
    @State private var editingVisit: Visit?
    @State private var deleteError: String?

    private var visits: [Visit] {
        allVisits.filter { $0.restaurantId == restaurant.id }
    }

    private var ratedVisits: [Visit] {
        visits.filter { $0.rating != nil }
    }

    private var averageRating: Double? {
        guard !ratedVisits.isEmpty else { return nil }
        let total = ratedVisits.compactMap(\.rating).reduce(0, +)
        return total / Double(ratedVisits.count)
    }

    private var totalSpend: Decimal? {
        let values = visits.compactMap(\.myActualSpend)
        guard !values.isEmpty else { return nil }
        return values.reduce(Decimal.zero, +)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("餐厅信息") {
                    Text(restaurant.name)
                        .font(.title3.weight(.semibold))
                    if !restaurant.address.isEmpty {
                        Text(restaurant.address)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("我的记录") {
                    LabeledContent("到访次数", value: "\(visits.count)")
                    LabeledContent("我的平均评分", value: averageRating.map {
                        String(format: "%.1f", $0)
                    } ?? "未评分")
                    if let latestVisit = visits.first {
                        LabeledContent("最近一次到访") {
                            Text(latestVisit.visitedAt, format: .dateTime.year().month().day())
                        }
                    }
                    if let totalSpend {
                        LabeledContent("累计实际消费", value: Self.currencyString(totalSpend))
                    }
                }

                Section("到访历史") {
                    if visits.isEmpty {
                        Text("还没有到访记录")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visits) { visit in
                            Button {
                                editingVisit = visit
                            } label: {
                                VisitRow(visit: visit)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button("删除", role: .destructive) {
                                    delete(visit)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        isAddingVisit = true
                    } label: {
                        Label("记录再次到访", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("餐厅详情")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isAddingVisit) {
                VisitEditorView(restaurant: restaurant)
            }
            .sheet(item: $editingVisit) { visit in
                VisitEditorView(restaurant: restaurant, visit: visit)
            }
            .alert("无法删除", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("好", role: .cancel) { deleteError = nil }
            } message: {
                Text(deleteError ?? "请稍后重试。")
            }
        }
    }

    private func delete(_ visit: Visit) {
        do {
            try LocalTasteMapStore(context: modelContext).delete(visit)
        } catch {
            deleteError = "这条到访记录没有删除成功。"
        }
    }

    private static func currencyString(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }
}

private struct VisitRow: View {
    let visit: Visit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(visit.visitedAt, format: .dateTime.year().month().day())
                    .font(.headline)
                Spacer()
                Text(visit.rating.map { String(format: "%.1f ★", $0) } ?? "未评分")
                    .foregroundStyle(visit.rating == nil ? Color.secondary : Color.orange)
            }

            if let note = visit.note, !note.isEmpty {
                Text(note)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }

            if let spend = visit.myActualSpend {
                Text("实际消费：\(NSDecimalNumber(decimal: spend).stringValue)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
