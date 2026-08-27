import SwiftUI

struct RestaurantDishSummary: Identifiable {
    let dish: Dish
    let dishIDs: Set<UUID>
    let visits: [Visit]
    let photo: PhotoAsset?

    var id: UUID { dish.id }
    var visitCount: Int { visits.count }
    var latestVisit: Visit? { visits.max { $0.visitedAt < $1.visitedAt } }
}

@MainActor
enum RestaurantDishPresentation {
    static func summaries(
        restaurantID: UUID,
        dishes: [Dish],
        associations: [VisitDish],
        visits: [Visit],
        photos: [PhotoAsset]
    ) -> [RestaurantDishSummary] {
        let activeVisits = visits.filter { $0.restaurantId == restaurantID && $0.deletedAt == nil }
        let visitByID = Dictionary(uniqueKeysWithValues: activeVisits.map { ($0.id, $0) })
        let activeDishes = dishes.filter { $0.restaurantId == restaurantID && $0.deletedAt == nil }
        let groups = Dictionary(grouping: activeDishes) { DishIdentity.normalizedName($0.name) }

        return groups.values.compactMap { group in
            guard let canonical = group.sorted(by: {
                $0.createdAt == $1.createdAt ? ($0.remoteID ?? "") < ($1.remoteID ?? "") : $0.createdAt < $1.createdAt
            }).first else { return nil }
            let dishIDs = Set(group.map(\.id))
            let relatedVisits = associations
                .filter { $0.deletedAt == nil && dishIDs.contains($0.dishId) }
                .compactMap { visitByID[$0.visitId] }
                .reduce(into: [UUID: Visit]()) { $0[$1.id] = $1 }
                .values
                .sorted { $0.visitedAt > $1.visitedAt }
            guard !relatedVisits.isEmpty else { return nil }
            let photo = photos
                .filter { $0.deletedAt == nil && $0.dishId.map(dishIDs.contains) == true }
                .sorted { $0.createdAt > $1.createdAt }
                .first
            return RestaurantDishSummary(
                dish: canonical,
                dishIDs: dishIDs,
                visits: relatedVisits,
                photo: photo
            )
        }
        .sorted {
            if $0.visitCount != $1.visitCount { return $0.visitCount > $1.visitCount }
            if $0.latestVisit?.visitedAt != $1.latestVisit?.visitedAt {
                return ($0.latestVisit?.visitedAt ?? .distantPast) > ($1.latestVisit?.visitedAt ?? .distantPast)
            }
            return $0.dish.name.localizedStandardCompare($1.dish.name) == .orderedAscending
        }
    }
}

struct RestaurantDishSection: View {
    let summaries: [RestaurantDishSummary]
    @State private var selected: RestaurantDishSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("吃过的菜")
                    .font(.title3.bold())
                Spacer()
                Text(summaries.isEmpty ? "尚未记录" : "\(summaries.count) 道")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if summaries.isEmpty {
                Label("还没有记录过菜品", systemImage: "fork.knife.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                    if index > 0 { Divider() }
                    Button { selected = summary } label: {
                        RestaurantDishRow(summary: summary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("restaurant-dish-\(summary.id.uuidString)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityIdentifier("restaurant-dish-section")
        .sheet(item: $selected) { DishDetailSheet(summary: $0) }
    }
}

private struct RestaurantDishRow: View {
    let summary: RestaurantDishSummary

    var body: some View {
        HStack(spacing: 13) {
            if let photo = summary.photo {
                PhotoAssetImageView(photo: photo)
                    .frame(width: 68, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
            } else {
                Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                    .foregroundStyle(.orange)
                    .frame(width: 68, height: 60)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(summary.dish.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text(summary.dish.rating.map { String(format: "%.1f ★", $0) } ?? "未评分")
                    if let price = summary.dish.price {
                        Text("¥\(NSDecimalNumber(decimal: price).stringValue)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let latest = summary.latestVisit {
                    Text("吃过 \(summary.visitCount) 次 · 最近 \(latest.visitedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct DishDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let summary: RestaurantDishSummary

    var body: some View {
        NavigationStack {
            List {
                if let photo = summary.photo {
                    PhotoAssetImageView(photo: photo)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .listRowBackground(Color.clear)
                }
                Section("菜品记录") {
                    LabeledContent("评分", value: summary.dish.rating.map { String(format: "%.1f ★", $0) } ?? "未评分")
                    LabeledContent("价格", value: summary.dish.price.map { "¥\(NSDecimalNumber(decimal: $0).stringValue)" } ?? "未记录")
                    if !summary.dish.taste.isEmpty {
                        LabeledContent("口味与备注") {
                            Text(summary.dish.taste)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                Section("吃过 \(summary.visitCount) 次") {
                    ForEach(summary.visits) { visit in
                        HStack {
                            Text(visit.visitedAt, format: .dateTime.year().month().day().hour().minute())
                            Spacer()
                            Text(visit.rating.map { String(format: "到访 %.1f ★", $0) } ?? "到访未评分")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(summary.dish.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
