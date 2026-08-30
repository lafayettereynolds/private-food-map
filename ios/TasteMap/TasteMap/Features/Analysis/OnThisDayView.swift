import SwiftData
import SwiftUI

struct OnThisDayScreen: View {
    @Query private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    @Query private var dishes: [Dish]
    @Query private var visitDishes: [VisitDish]
    @Query private var photos: [PhotoAsset]
    @Query private var companions: [DiningCompanion]
    @Query private var recommendationSources: [RecommendationSource]

    let currentUserID: String
    let context: OnThisDayContext
    @State private var report: OnThisDayReport?

    init(
        currentUserID: String,
        context: OnThisDayContext = .live()
    ) {
        self.currentUserID = currentUserID
        self.context = context
    }

    private var dataRevision: String {
        let dates = restaurants.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + visits.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + dishes.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + visitDishes.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + photos.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + companions.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
            + recommendationSources.map { max($0.updatedAt, $0.deletedAt ?? .distantPast) }
        return [
            restaurants.count, visits.count, dishes.count, visitDishes.count,
            photos.count, companions.count, recommendationSources.count,
        ].map(String.init).joined(separator: ":")
            + ":\(dates.max()?.timeIntervalSince1970 ?? 0)"
            + ":\(context.referenceDate.timeIntervalSince1970)"
            + ":\(context.calendar.timeZone.identifier):\(currentUserID)"
    }

    private var activePhotosByID: [UUID: PhotoAsset] {
        photos.filter { $0.deletedAt == nil && $0.binaryDeletedAt == nil }.reduce(into: [:]) {
            $0[$1.id] = $1
        }
    }

    private var activeRestaurantsByID: [UUID: Restaurant] {
        let projection = AnalysisRestaurantIdentity.projection(for: restaurants)
        return restaurants.filter {
            $0.deletedAt == nil && projection.representativeIDs.contains($0.id)
        }.reduce(into: [:]) { $0[$1.id] = $1 }
    }

    var body: some View {
        Group {
            if let report {
                OnThisDayAnalysisView(
                    report: report,
                    photosByID: activePhotosByID,
                    restaurantsByID: activeRestaurantsByID
                )
            } else {
                ProgressView("正在翻开往年的今天…")
                    .tint(TasteMapAnalysisTheme.brand)
            }
        }
        .task(id: dataRevision) {
            let input = OnThisDayInput.capture(
                currentUserID: currentUserID,
                restaurants: restaurants,
                visits: visits,
                dishes: dishes,
                visitDishes: visitDishes,
                photos: photos,
                companions: companions,
                recommendationSources: recommendationSources
            )
            let context = context
            report = await Task.detached(priority: .userInitiated) {
                OnThisDayAnalyzer.analyze(input, context: context)
            }.value
        }
    }
}

struct OnThisDayAnalysisView: View {
    let report: OnThisDayReport
    let photosByID: [UUID: PhotoAsset]
    let restaurantsByID: [UUID: Restaurant]
    @State private var showingPoster = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                header
                if report.hasMemories {
                    ForEach(report.groups) { group in
                        yearSection(group)
                    }
                    shareCard
                    privacyNote
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .background(TasteMapAnalysisTheme.canvas.ignoresSafeArea())
        .tasteMapBottomNavigationHidden()
        .navigationTitle("那年今日")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if report.hasMemories {
                ToolbarItem(placement: .primaryAction) {
                    Button("分享", systemImage: "square.and.arrow.up") { showingPoster = true }
                        .accessibilityIdentifier("on-this-day-share-toolbar")
                }
            }
        }
        .sheet(isPresented: $showingPoster) {
            OnThisDayPosterSheet(report: report, photosByID: photosByID)
        }
        .accessibilityIdentifier("on-this-day-page")
    }

    private var shareCard: some View {
        Button { showingPoster = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(TasteMapAnalysisTheme.brand)
                    .frame(width: 52, height: 52)
                    .background(TasteMapAnalysisTheme.brandSoft, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text("生成那年今日海报")
                        .font(.headline)
                        .foregroundStyle(TasteMapAnalysisTheme.ink)
                    Text("独立 1080 × 1920 浅色图片，可保存或系统分享")
                        .font(.caption)
                        .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("on-this-day-share-poster")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ON THIS DAY")
                    .font(.caption2.weight(.bold))
                    .tracking(1.8)
                Spacer()
                Label("\(report.month) 月 \(report.day) 日", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(TasteMapAnalysisTheme.brand)
            Text("看看过去这些年的今天，你吃了什么。")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("只取你自己的本地有效到访；今年的记录不会提前变成回忆。")
                .font(.subheadline)
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
        }
        .accessibilityIdentifier("on-this-day-header")
    }

    private func yearSection(_ group: OnThisDayYearGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(group.year))
                    .font(.title.weight(.heavy))
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                    .accessibilityIdentifier("on-this-day-year-\(group.year)")
                Text("\(group.memories.first?.yearsAgo ?? 0) 年前")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TasteMapAnalysisTheme.brand)
                Spacer()
                Text("\(group.memories.count) 次到访")
                    .font(.caption)
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            }
            ForEach(group.memories) { memory in
                memoryDestination(memory)
            }
        }
    }

    @ViewBuilder
    private func memoryDestination(_ memory: OnThisDayMemory) -> some View {
        let card = OnThisDayMemoryCard(memory: memory, photosByID: photosByID)
        if let restaurant = restaurantsByID[memory.restaurantID] {
            NavigationLink { RestaurantDetailView(restaurant: restaurant) } label: { card }
                .buttonStyle(.plain)
                .accessibilityIdentifier("on-this-day-memory-\(memory.id.uuidString)")
        } else {
            card.accessibilityIdentifier("on-this-day-memory-\(memory.id.uuidString)")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            AnalysisFoodGlyph(symbol: "🍽️", tone: .cream, size: 78)
            Text("往年的今天还没有记录。")
                .font(.title2.weight(.heavy))
                .foregroundStyle(TasteMapAnalysisTheme.ink)
            Text("这里只显示同月同日的真实历史到访，不会用附近日期或随机内容填充。")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 58)
        .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityIdentifier("on-this-day-empty")
    }

    private var privacyNote: some View {
        Label("那年今日只在本人页面读取本地记录，不请求发现、社区或其他用户数据。", systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                TasteMapAnalysisTheme.leafGreenSoft.opacity(0.66),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
    }
}

private struct OnThisDayMemoryCard: View {
    let memory: OnThisDayMemory
    let photosByID: [UUID: PhotoAsset]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RestaurantEvidenceImage(
                reference: memory.imageReference,
                photosByID: photosByID,
                height: 176
            )
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(memory.restaurantName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(TasteMapAnalysisTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if !memory.city.isEmpty {
                            Label(memory.city, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                        }
                    }
                    Spacer(minLength: 8)
                    if let rating = memory.rating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(TasteMapAnalysisTheme.ingredientRed)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                TasteMapAnalysisTheme.ingredientRedSoft,
                                in: Capsule()
                            )
                    }
                }
                if let note = memory.note {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(TasteMapAnalysisTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            TasteMapAnalysisTheme.creamSoft,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                if !memory.dishNames.isEmpty {
                    factRow("fork.knife", title: "吃过", value: memory.dishNames.joined(separator: "、"))
                }
                if !memory.companions.isEmpty {
                    factRow("person.2.fill", title: "一起吃", value: memory.companions.joined(separator: "、"))
                }
                if let source = memory.recommendationSource {
                    factRow("sparkles", title: "从哪里发现", value: source)
                }
                if let spend = memory.spend {
                    factRow("wallet.bifold", title: "实际消费", value: Self.currency(spend))
                }
                HStack {
                    Text(memory.visitedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                    Spacer()
                    Label("查看餐厅", systemImage: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TasteMapAnalysisTheme.brand)
                }
            }
            .padding(17)
        }
        .background(TasteMapAnalysisTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(TasteMapAnalysisTheme.brand.opacity(0.10))
        }
        .accessibilityElement(children: .contain)
    }

    private func factRow(_ icon: String, title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(TasteMapAnalysisTheme.brand)
                .frame(width: 18)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            Text(value)
                .font(.caption)
                .foregroundStyle(TasteMapAnalysisTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func currency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CNY"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "¥\(value)"
    }
}
