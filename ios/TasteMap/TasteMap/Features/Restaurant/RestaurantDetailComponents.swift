import MapKit
import SwiftUI

struct RestaurantDetailHeader: View {
    let restaurant: Restaurant

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    if !restaurant.city.isEmpty {
                        Text(restaurant.city)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(restaurant.name)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                RestaurantStatusBadge(status: restaurant.status)
            }

            if !restaurant.address.isEmpty {
                Label(restaurant.address, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("restaurant-detail-header")
    }
}

struct RestaurantStatusBadge: View {
    let status: RestaurantStatus

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(status == .wantToGo ? Color.blue : Color.accentColor)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                (status == .wantToGo ? Color.blue : Color.accentColor).opacity(0.1),
                in: Capsule()
            )
            .accessibilityIdentifier("restaurant-status-\(status.rawValue)")
    }
}

struct RestaurantLocationSection: View {
    let restaurant: Restaurant
    let onOpenAppleMaps: () -> Void

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: restaurant.latitude,
            longitude: restaurant.longitude
        )
    }

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 1_100,
            longitudinalMeters: 1_100
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("位置")
                .font(.title3.bold())

            Map(initialPosition: .region(region), interactionModes: []) {
                Marker(restaurant.name, coordinate: coordinate)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(true)

            Button(action: onOpenAppleMaps) {
                Label("在 Apple Maps 中打开", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("open-in-apple-maps")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct RestaurantDetailStatsSection: View {
    let presentation: RestaurantDetailPresentation

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("我的记录")
                .font(.title3.bold())

            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                RestaurantDetailMetric(
                    title: "到访次数",
                    value: "\(presentation.visitCount) 次",
                    systemImage: "repeat"
                )
                RestaurantDetailMetric(
                    title: "平均评分",
                    value: presentation.averageRating.map { String(format: "%.1f", $0) } ?? "暂无评分",
                    systemImage: "star.fill"
                )
                RestaurantDetailMetric(
                    title: "最近到访",
                    value: presentation.latestVisit.map {
                        RestaurantDetailFormatting.shortDate($0.visitedAt)
                    } ?? "暂无记录",
                    systemImage: "calendar"
                )
                RestaurantDetailMetric(
                    title: "累计消费",
                    value: presentation.totalSpend.map(RestaurantDetailFormatting.currency) ?? "暂无记录",
                    systemImage: "wallet.bifold.fill"
                )
                RestaurantDetailMetric(
                    title: "平均每次消费",
                    value: presentation.averageSpend.map(RestaurantDetailFormatting.currency) ?? "暂无记录",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityIdentifier("restaurant-detail-statistics")
    }
}

private struct RestaurantDetailMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 25, height: 25)
                .background(Color.accentColor.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RestaurantVisitHistorySection: View {
    let visits: [Visit]
    let onEdit: (Visit) -> Void
    let onDelete: (Visit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("到访历史")
                    .font(.title3.bold())
                Spacer()
                Text("\(visits.count) 条")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            if visits.isEmpty {
                ContentUnavailableView(
                    "还没有到访记录",
                    systemImage: "fork.knife.circle",
                    description: Text("真正去过后，每次到访都会独立保存在这里。")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                ForEach(Array(visits.enumerated()), id: \.element.id) { index, visit in
                    if index > 0 { Divider() }
                    RestaurantVisitHistoryRow(
                        visit: visit,
                        ordinal: visits.count - index,
                        onEdit: { onEdit(visit) },
                        onDelete: { onDelete(visit) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityIdentifier("restaurant-visit-history")
    }
}

private struct RestaurantVisitHistoryRow: View {
    let visit: Visit
    let ordinal: Int
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("第 \(ordinal) 次")
                            .font(.headline)
                        Text(visit.visitedAt, format: .dateTime.year().month().day())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(visit.rating.map { String(format: "%.1f ★", $0) } ?? "未评分")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(visit.rating == nil ? Color.secondary : Color.orange)
                    }

                    HStack(spacing: 14) {
                        Label(visit.diningMode.title, systemImage: visit.diningMode.systemImage)
                        if let partySize = visit.partySize {
                            Label("\(partySize) 人", systemImage: "person.2.fill")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let note = visit.note, !note.isEmpty {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }

                    if let spend = visit.myActualSpend {
                        Label(
                            "我的实际消费 \(RestaurantDetailFormatting.currency(spend))",
                            systemImage: "wallet.bifold"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("编辑", systemImage: "square.and.pencil", action: onEdit)
                Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("第 \(ordinal) 次到访操作")
        }
        .padding(.vertical, 12)
        .accessibilityIdentifier("visit-history-row-\(visit.id.uuidString)")
    }
}
