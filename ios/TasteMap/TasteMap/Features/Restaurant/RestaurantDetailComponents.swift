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
        .tasteMapCoreCard(radius: 22)
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

struct RestaurantPhotoGallerySection: View {
    let photos: [PhotoAsset]
    let merchantImageURL: URL?
    let markerEmoji: String
    let onSelect: (PhotoAsset) -> Void
    let onRetry: (PhotoAsset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("照片")
                    .font(.title3.bold())
                Spacer()
                Text(photos.isEmpty ? (merchantImageURL == nil ? "餐厅图标" : "商家图片") : "\(photos.count) 张")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if photos.isEmpty {
                RestaurantPhotoFallback(
                    merchantImageURL: merchantImageURL,
                    markerEmoji: markerEmoji
                )
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(photos) { photo in
                            Button { onSelect(photo) } label: {
                                PhotoAssetImageView(photo: photo)
                                    .frame(width: 132, height: 104)
                                    .clipShape(RoundedRectangle(cornerRadius: 15))
                                    .overlay(alignment: .bottomLeading) {
                                        PhotoUploadStatusBadge(photo: photo)
                                            .padding(6)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("restaurant-photo-\(photo.id.uuidString)")
                            .overlay(alignment: .bottomTrailing) {
                                if photo.uploadState == .failed {
                                    Button("重试") { onRetry(photo) }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.mini)
                                        .padding(5)
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .tasteMapCoreCard(radius: 22)
        .accessibilityIdentifier("restaurant-photo-gallery")
    }
}

private struct RestaurantPhotoFallback: View {
    let merchantImageURL: URL?
    let markerEmoji: String

    var body: some View {
        Group {
            if let merchantImageURL {
                AsyncImage(url: merchantImageURL) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        brandFallback
                    @unknown default:
                        brandFallback
                    }
                }
                .accessibilityLabel("餐厅商家图片")
            } else {
                brandFallback
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 176)
        .background(Color.accentColor.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .clipped()
        .accessibilityIdentifier(merchantImageURL == nil ? "restaurant-brand-fallback" : "restaurant-merchant-image")
    }

    private var brandFallback: some View {
        VStack(spacing: 10) {
            Text(markerEmoji)
                .font(.system(size: 52))
                .accessibilityHidden(true)
            Text("Taste Map")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("记录到访照片后，会优先显示你的照片")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RestaurantBusinessInformationSection: View {
    let metadata: RestaurantDetailMetadata
    let onCall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("餐厅信息")
                .font(.title3.bold())
                .padding(.bottom, 14)
                .accessibilityIdentifier("restaurant-business-information")

            if let phone = metadata.callablePhone {
                Button(action: onCall) {
                    informationRow(
                        title: "电话",
                        value: phone,
                        systemImage: "phone.fill",
                        accessoryImage: "phone.arrow.up.right.fill"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("拨打餐厅电话 \(phone)")
                .accessibilityIdentifier("restaurant-call-phone")
                dividerAfterPhone
            }

            if let openingHours = metadata.openingHours {
                informationRow(title: "营业时间", value: openingHours, systemImage: "clock.fill")
                    .accessibilityIdentifier("restaurant-opening-hours")
                dividerAfterOpeningHours
            }

            if let referencePrice = metadata.referencePrice {
                informationRow(
                    title: "参考人均",
                    value: RestaurantDetailFormatting.referencePrice(referencePrice),
                    systemImage: "yensign.circle.fill"
                )
                .accessibilityIdentifier("restaurant-reference-price")
                dividerAfterReferencePrice
            }

            if let longTermNote = metadata.longTermNote {
                informationRow(title: "我的长期备注", value: longTermNote, systemImage: "note.text")
                    .accessibilityIdentifier("restaurant-long-term-note")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .tasteMapCoreCard(radius: 22)
    }

    @ViewBuilder private var dividerAfterPhone: some View {
        if metadata.openingHours != nil || metadata.referencePrice != nil || metadata.longTermNote != nil {
            Divider().padding(.leading, 36)
        }
    }

    @ViewBuilder private var dividerAfterOpeningHours: some View {
        if metadata.referencePrice != nil || metadata.longTermNote != nil {
            Divider().padding(.leading, 36)
        }
    }

    @ViewBuilder private var dividerAfterReferencePrice: some View {
        if metadata.longTermNote != nil { Divider().padding(.leading, 36) }
    }

    private func informationRow(
        title: String,
        value: String,
        systemImage: String,
        accessoryImage: String? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let accessoryImage {
                Image(systemName: accessoryImage).foregroundStyle(.tint).accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

struct RestaurantExperienceSummarySection: View {
    let presentation: RestaurantDetailPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("用餐印象")
                .font(.title3.bold())

            if let queue = presentation.queueSummary {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("平均排队").font(.caption).foregroundStyle(.secondary)
                        Text("约 \(queue.averageMinutes) 分钟 · \(queue.sampleCount) 次记录")
                            .font(.subheadline.weight(.semibold))
                    }
                } icon: {
                    Image(systemName: "hourglass")
                        .foregroundStyle(.tint)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("restaurant-average-queue")
            }

            ForEach(presentation.tagGroups) { group in
                VStack(alignment: .leading, spacing: 9) {
                    Label(group.title, systemImage: group.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(group.tags) { tag in
                                Text("\(tag.label) · \(tag.count)")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Color.accentColor.opacity(0.09), in: Capsule())
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .tasteMapCoreCard(radius: 22)
        .accessibilityIdentifier("restaurant-experience-summary")
    }
}

struct RestaurantRatingReferencesSection: View {
    let references: [RestaurantRatingReference]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("评分参考")
                .font(.title3.bold())
            ForEach(references) { reference in
                HStack(spacing: 12) {
                    Image(systemName: reference.systemImage)
                        .foregroundStyle(.tint)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                    Text(reference.title).font(.subheadline.weight(.medium))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f / 5", reference.value))
                            .font(.subheadline.bold())
                        Text("\(reference.sampleCount) 个样本")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .tasteMapCoreCard(radius: 22)
        .accessibilityIdentifier("restaurant-rating-references")
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
        .tasteMapCoreCard(radius: 22)
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
        .tasteMapCoreCard(radius: 22)
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
    let companionNamesByID: [String: String]
    let sourceNamesByID: [String: String]
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
                        companionNamesByID: companionNamesByID,
                        sourceNamesByID: sourceNamesByID,
                        onEdit: { onEdit(visit) },
                        onDelete: { onDelete(visit) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .tasteMapCoreCard(radius: 22)
        .accessibilityIdentifier("restaurant-visit-history")
    }
}

private struct RestaurantVisitHistoryRow: View {
    let visit: Visit
    let ordinal: Int
    let companionNamesByID: [String: String]
    let sourceNamesByID: [String: String]
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

                    if !visit.compactContextSummary.isEmpty {
                        Label(
                            visit.compactContextSummary.joined(separator: " · "),
                            systemImage: "clock.badge.checkmark"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("visit-history-context")
                    }

                    let companionNames = resolvedCompanionNames
                    if !companionNames.isEmpty {
                        Label(companionNames.joined(separator: "、"), systemImage: "person.2.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .accessibilityIdentifier("visit-history-companions")
                    }

                    if let sourceName = resolvedSourceName {
                        Label(sourceName, systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityIdentifier("visit-history-recommendation-source")
                    }

                    if let note = visit.note, !note.isEmpty {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .accessibilityIdentifier("visit-history-note")
                    }

                    if let spend = visit.myActualSpend {
                        Label(
                            "我的实际消费 \(RestaurantDetailFormatting.currency(spend))",
                            systemImage: "wallet.bifold"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if let paymentMode = visit.paymentMode {
                        Label(paymentMode.title, systemImage: "creditcard.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("visit-history-edit-\(visit.id.uuidString)")

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

    private var resolvedCompanionNames: [String] {
        guard visit.companionIDs.count == visit.companionNames.count else {
            return visit.companionNames
        }
        return zip(visit.companionIDs, visit.companionNames).map { id, snapshot in
            companionNamesByID[id] ?? snapshot
        }
    }

    private var resolvedSourceName: String? {
        if let id = visit.recommendationSourceID, let current = sourceNamesByID[id] { return current }
        return visit.recommendationSourceText
    }
}
