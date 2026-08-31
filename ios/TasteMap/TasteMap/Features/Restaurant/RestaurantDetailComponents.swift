import MapKit
import SwiftUI

struct RestaurantDetailIdentityPresentation: Equatable {
    let name: String
    let address: String
    let city: String
    let status: RestaurantStatus?

    @MainActor
    init(restaurant: Restaurant) {
        name = restaurant.name
        address = restaurant.address
        city = restaurant.city
        status = restaurant.status
    }

    init(
        projection: DiscoveryRestaurantProjectionV1,
        viewerState: DiscoveryViewerRestaurantStateV1
    ) {
        name = projection.name
        address = projection.address
        city = projection.city
        switch viewerState {
        case .none: status = nil
        case .wantToGo: status = .wantToGo
        case .visited: status = .visited
        }
    }

    init(name: String, address: String, city: String, status: RestaurantStatus? = nil) {
        self.name = name
        self.address = address
        self.city = city
        self.status = status
    }
}

struct RestaurantDetailHeader: View {
    let identity: RestaurantDetailIdentityPresentation

    @MainActor
    init(restaurant: Restaurant) {
        identity = RestaurantDetailIdentityPresentation(restaurant: restaurant)
    }

    init(identity: RestaurantDetailIdentityPresentation) {
        self.identity = identity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    if !identity.city.isEmpty {
                        Label(identity.city, systemImage: "building.2")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TasteMapCoreTheme.textSecondary)
                    }
                    Text(identity.name)
                        .font(.title.bold())
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if let status = identity.status {
                    RestaurantStatusBadge(status: status)
                }
            }

            if !identity.address.isEmpty {
                Label(identity.address, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
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
    var showsThumbnails = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if photos.isEmpty {
                RestaurantPhotoFallback(
                    merchantImageURL: merchantImageURL,
                    markerEmoji: markerEmoji
                )
            } else {
                if let primaryPhoto = photos.first {
                    Button { onSelect(primaryPhoto) } label: {
                        PhotoAssetImageView(photo: primaryPhoto)
                            .frame(maxWidth: .infinity)
                            .frame(height: 216)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(alignment: .bottomLeading) {
                                PhotoUploadStatusBadge(photo: primaryPhoto)
                                    .padding(8)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("restaurant-photo-\(primaryPhoto.id.uuidString)")
                    .overlay(alignment: .bottomTrailing) {
                        if primaryPhoto.uploadState == .failed {
                            Button("重试") { onRetry(primaryPhoto) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .padding(8)
                        }
                    }
                }

                if showsThumbnails, photos.count > 1 {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 8) {
                            ForEach(Array(photos.dropFirst())) { photo in
                            Button { onSelect(photo) } label: {
                                PhotoAssetImageView(photo: photo)
                                    .frame(width: 92, height: 68)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(alignment: .bottomLeading) {
                                        PhotoUploadStatusBadge(photo: photo)
                                            .padding(4)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("restaurant-photo-\(photo.id.uuidString)")
                            .overlay(alignment: .bottomTrailing) {
                                if photo.uploadState == .failed {
                                    Button("重试") { onRetry(photo) }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.mini)
                                        .padding(4)
                                    }
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            Text(photos.isEmpty ? (merchantImageURL == nil ? "餐厅图标" : "商家图片") : "\(photos.count) 张")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("restaurant-photo-gallery")
    }
}

struct RestaurantUserPhotosSection<Content: View>: View {
    let hasPhotos: Bool
    @ViewBuilder let content: Content

    init(hasPhotos: Bool, @ViewBuilder content: () -> Content) {
        self.hasPhotos = hasPhotos
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("用户实拍")
                .font(.title3.bold())
            if hasPhotos {
                content
            } else {
                ContentUnavailableView(
                    "还没有用户实拍",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("公开或本人记录的到访照片会显示在这里。")
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .tasteMapCoreCard(radius: 22)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("restaurant-user-photos")
    }
}

struct RestaurantLocalUserPhotosContent: View {
    let photos: [PhotoAsset]
    let onSelect: (PhotoAsset) -> Void
    let onRetry: (PhotoAsset) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(photos) { photo in
                    Button { onSelect(photo) } label: {
                        PhotoAssetImageView(photo: photo)
                            .frame(width: 132, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(alignment: .bottomLeading) {
                                PhotoUploadStatusBadge(photo: photo).padding(6)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("restaurant-user-photo-\(photo.id.uuidString)")
                    .overlay(alignment: .bottomTrailing) {
                        if photo.uploadState == .failed {
                            Button("重试") { onRetry(photo) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.mini)
                                .padding(6)
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// The single ordered Restaurant Detail subject used by local and remote routes.
/// Source-specific wrappers provide data and actions, never their own section order.
struct RestaurantDetailStandardBody<
    Hero: View,
    Header: View,
    Actions: View,
    Business: View,
    Location: View,
    Ratings: View,
    UserPhotos: View,
    PersonalOverview: View,
    History: View,
    Context: View,
    Extended: View
>: View {
    let hero: Hero
    let header: Header
    let actions: Actions
    let business: Business
    let location: Location
    let ratings: Ratings
    let userPhotos: UserPhotos
    let personalOverview: PersonalOverview
    let history: History
    let context: Context
    let extended: Extended

    init(
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder header: () -> Header,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder business: () -> Business,
        @ViewBuilder location: () -> Location,
        @ViewBuilder ratings: () -> Ratings,
        @ViewBuilder userPhotos: () -> UserPhotos,
        @ViewBuilder personalOverview: () -> PersonalOverview,
        @ViewBuilder history: () -> History,
        @ViewBuilder context: () -> Context,
        @ViewBuilder extended: () -> Extended
    ) {
        self.hero = hero()
        self.header = header()
        self.actions = actions()
        self.business = business()
        self.location = location()
        self.ratings = ratings()
        self.userPhotos = userPhotos()
        self.personalOverview = personalOverview()
        self.history = history()
        self.context = context()
        self.extended = extended()
    }

    var body: some View {
        LazyVStack(spacing: 14) {
            hero
            header
            actions
            business
            location
            ratings
            userPhotos
            personalOverview
            history
            context
            extended
        }
    }
}

enum RestaurantDetailSectionOrderContract {
    static let identifiers = [
        "restaurant-photo-gallery",
        "restaurant-detail-header",
        "restaurant-detail-quick-actions",
        "restaurant-business-information",
        "restaurant-detail-location",
        "restaurant-rating-references",
        "restaurant-user-photos",
        "restaurant-detail-statistics",
        "restaurant-visit-history",
    ]
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
        .frame(height: 216)
        .background(Color.accentColor.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipped()
        .accessibilityIdentifier(merchantImageURL == nil ? "restaurant-brand-fallback" : "restaurant-merchant-image")
    }

    private var brandFallback: some View {
        VStack(spacing: 10) {
            FoodDiningVisualIcon(
                kind: FoodDiningVisualLibrary.kind(legacySymbol: markerEmoji),
                usage: .decorative,
                size: 62,
                foregroundColor: TasteMapCoreTheme.brandDeep,
                backgroundColor: TasteMapCoreTheme.brandSoft
            )
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
                .font(.headline)
                .padding(.bottom, 8)
                .accessibilityIdentifier("restaurant-business-information")

            if let referencePrice = metadata.referencePrice {
                informationRow(
                    title: "参考人均",
                    value: RestaurantDetailFormatting.referencePrice(referencePrice),
                    systemImage: "yensign.circle.fill"
                )
                .accessibilityIdentifier("restaurant-reference-price")
                dividerAfterReferencePrice
            }

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

            if let longTermNote = metadata.longTermNote {
                informationRow(title: "我的长期备注", value: longTermNote, systemImage: "note.text")
                    .accessibilityIdentifier("restaurant-long-term-note")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .tasteMapCoreCard(radius: 16)
    }

    @ViewBuilder private var dividerAfterPhone: some View {
        if metadata.openingHours != nil || metadata.longTermNote != nil {
            Divider().padding(.leading, 36)
        }
    }

    @ViewBuilder private var dividerAfterOpeningHours: some View {
        if metadata.longTermNote != nil {
            Divider().padding(.leading, 36)
        }
    }

    @ViewBuilder private var dividerAfterReferencePrice: some View {
        if metadata.callablePhone != nil || metadata.openingHours != nil || metadata.longTermNote != nil {
            Divider().padding(.leading, 36)
        }
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
        .padding(.vertical, 7)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("评分参考")
                .font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    ForEach(references) { reference in
                        VStack(spacing: 7) {
                            ZStack {
                                Circle()
                                    .fill(TasteMapCoreTheme.surfaceSubtle)
                                    .overlay {
                                        Circle().stroke(TasteMapCoreTheme.brand.opacity(0.36), lineWidth: 2)
                                    }
                                Text(String(format: "%.1f", reference.value))
                                    .font(.title3.bold())
                                    .foregroundStyle(TasteMapCoreTheme.brandDeep)
                            }
                            .frame(width: 70, height: 70)
                            .overlay(alignment: .bottomTrailing) {
                                Text("\(reference.sampleCount)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(TasteMapCoreTheme.brand, in: Circle())
                                    .overlay { Circle().stroke(TasteMapCoreTheme.surface, lineWidth: 2) }
                                    .accessibilityLabel("\(reference.sampleCount) 个样本")
                            }
                            Text(reference.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "\(reference.title)，评分 \(String(format: "%.1f", reference.value))，\(reference.sampleCount) 个样本"
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .tasteMapCoreCard(radius: 16)
        .accessibilityIdentifier("restaurant-rating-references")
    }
}

struct RestaurantDiscoveryContextSection: View {
    let context: DiscoveryCachedCardContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("发现线索")
                .font(.title3.bold())
            ForEach(context.reasons) { reason in
                Label(reason.text, systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(TasteMapCoreTheme.brandDeep)
            }
            if let similarity = context.similarity {
                Label(
                    "同味度 \(similarity.percent)% · \(similarity.sharedRestaurantCount) 家共同评分餐厅",
                    systemImage: "person.2.wave.2"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .tasteMapCoreCard(radius: 22)
        .accessibilityIdentifier("restaurant-discovery-context")
    }
}

struct RestaurantLocationSection: View {
    let name: String
    let latitude: Double
    let longitude: Double
    let onOpenAppleMaps: () -> Void

    @MainActor
    init(restaurant: Restaurant, onOpenAppleMaps: @escaping () -> Void) {
        name = restaurant.name
        latitude = restaurant.latitude
        longitude = restaurant.longitude
        self.onOpenAppleMaps = onOpenAppleMaps
    }

    init(
        projection: DiscoveryRestaurantProjectionV1,
        onOpenAppleMaps: @escaping () -> Void
    ) {
        name = projection.name
        latitude = projection.latitude
        longitude = projection.longitude
        self.onOpenAppleMaps = onOpenAppleMaps
    }

    init(
        candidate: RestaurantCandidate,
        onOpenAppleMaps: @escaping () -> Void
    ) {
        name = candidate.name
        latitude = candidate.latitude
        longitude = candidate.longitude
        self.onOpenAppleMaps = onOpenAppleMaps
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
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
            Text("到这里去")
                .font(.title3.bold())

            Map(initialPosition: .region(region), interactionModes: []) {
                Marker(name, coordinate: coordinate)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(true)

            Button(action: onOpenAppleMaps) {
                Label("用 Apple Maps 导航", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("open-in-apple-maps")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .tasteMapCoreCard(radius: 22)
        .accessibilityIdentifier("restaurant-detail-location")
    }
}

struct RestaurantDetailStatsSection: View {
    let presentation: RestaurantDetailPresentation?
    let remoteMessage: String?

    init(presentation: RestaurantDetailPresentation) {
        self.presentation = presentation
        remoteMessage = nil
    }

    init(remoteMessage: String) {
        presentation = nil
        self.remoteMessage = remoteMessage
    }

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("我的记录")
                .font(.title3.bold())

            if let presentation {
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
            } else {
                ContentUnavailableView(
                    "还没有我的记录",
                    systemImage: "fork.knife.circle",
                    description: Text(remoteMessage ?? "记录到访后会在这里显示你的统计。")
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .tasteMapCoreCard(radius: 22)
        .accessibilityElement(children: .contain)
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
        .accessibilityElement(children: .contain)
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
