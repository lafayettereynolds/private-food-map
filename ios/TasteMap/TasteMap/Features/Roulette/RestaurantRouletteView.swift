import SwiftData
import SwiftUI
import UIKit

struct RestaurantRouletteScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    @Query private var photos: [PhotoAsset]
    @State private var isShowingSearch = false

    let preferredCity: String?
    let initialRestaurantID: UUID?

    init(preferredCity: String? = nil, initialRestaurantID: UUID? = nil) {
        self.preferredCity = preferredCity
        self.initialRestaurantID = initialRestaurantID
    }

    private var candidates: [RouletteCandidate] {
        RestaurantRouletteEngine.candidates(from: RouletteRestaurantRecord.capture(
            restaurants: restaurants,
            visits: visits,
            photos: photos
        ))
    }

    var body: some View {
        RestaurantRouletteExperienceView(
            candidates: candidates,
            restaurants: restaurants,
            photos: photos,
            preferredCity: preferredCity,
            initialResultGlobalKey: initialResultGlobalKey,
            onSearch: { isShowingSearch = true }
        )
        .sheet(isPresented: $isShowingSearch) {
            RestaurantSearchView { candidate, action in
                switch action {
                case .wantToGo:
                    _ = try LocalTasteMapStore(context: modelContext).addToWantToGo(
                        candidate: candidate,
                        among: restaurants
                    )
                case .recordVisit:
                    _ = try LocalTasteMapStore(context: modelContext).restaurant(
                        for: candidate,
                        among: restaurants,
                        status: .visited
                    )
                    try modelContext.save()
                }
            }
        }
    }

    private var initialResultGlobalKey: String? {
        guard let initialRestaurantID else { return nil }
        return candidates.first(where: { $0.restaurantID == initialRestaurantID })?.globalKey
    }
}

struct RestaurantRouletteExperienceView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let candidates: [RouletteCandidate]
    let restaurants: [Restaurant]
    let photos: [PhotoAsset]
    let preferredCity: String?
    let onSearch: () -> Void
    let forceReducedMotion: Bool

    @State private var source: RouletteCandidateSource
    @State private var selectedCity: String?
    @State private var excludedGlobalKeys: Set<String>
    @State private var result: RouletteCandidate?
    @State private var lastResultGlobalKey: String?
    @State private var rotation: Double = 0
    @State private var isSpinning = false
    @State private var isShowingFilters = false
    @State private var isShowingCandidateManager = false
    @State private var cityWasInitialized: Bool
    @State private var spinToken = UUID()

    init(
        candidates: [RouletteCandidate],
        restaurants: [Restaurant],
        photos: [PhotoAsset],
        preferredCity: String? = nil,
        initialSource: RouletteCandidateSource = .all,
        initialCity: String? = nil,
        excludedGlobalKeys: Set<String> = [],
        initialResultGlobalKey: String? = nil,
        forceReducedMotion: Bool = false,
        onSearch: @escaping () -> Void = {}
    ) {
        self.candidates = candidates
        self.restaurants = restaurants
        self.photos = photos
        self.preferredCity = preferredCity
        self.onSearch = onSearch
        self.forceReducedMotion = forceReducedMotion
        _source = State(initialValue: initialSource)
        _selectedCity = State(initialValue: initialCity)
        _excludedGlobalKeys = State(initialValue: excludedGlobalKeys)
        _result = State(initialValue: candidates.first { $0.globalKey == initialResultGlobalKey })
        _lastResultGlobalKey = State(initialValue: initialResultGlobalKey)
        _cityWasInitialized = State(initialValue: initialCity != nil)
    }

    private var filter: RouletteFilter {
        RouletteFilter(
            source: source,
            city: selectedCity,
            excludedGlobalKeys: excludedGlobalKeys
        )
    }

    private var filteredCandidates: [RouletteCandidate] {
        RestaurantRouletteEngine.filtered(candidates, by: filter)
    }

    private var baseCandidates: [RouletteCandidate] {
        RestaurantRouletteEngine.filtered(
            candidates,
            by: RouletteFilter(source: source, city: selectedCity)
        )
    }

    private var cities: [String] {
        RestaurantRouletteEngine.cities(in: candidates)
    }

    private var displayedResult: RouletteCandidate? {
        filteredCandidates.count == 1 ? filteredCandidates[0] : result
    }

    private var usesReducedMotion: Bool {
        accessibilityReduceMotion || forceReducedMotion
    }

    private var stateKey: String {
        "\(source.rawValue)|\(selectedCity ?? "")|\(filteredCandidates.map(\.globalKey).joined(separator: "|"))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                conditionBar
                if filteredCandidates.isEmpty {
                    emptyState
                } else if filteredCandidates.count == 1 {
                    singleCandidateState
                } else {
                    rouletteStage
                    if let displayedResult {
                        resultCard(displayedResult)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                localOnlyNote
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 34)
        }
        .background(RouletteTheme.canvas.ignoresSafeArea())
        .navigationTitle("今天吃什么")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("筛选", systemImage: "slider.horizontal.3") {
                    isShowingFilters = true
                }
                .accessibilityIdentifier("roulette-filter-open")
            }
        }
        .sheet(isPresented: $isShowingFilters) {
            RouletteFilterSheet(
                source: $source,
                selectedCity: $selectedCity,
                cities: cities,
                onReset: resetConditions
            )
        }
        .sheet(isPresented: $isShowingCandidateManager) {
            RouletteCandidateManager(
                candidates: baseCandidates,
                excludedGlobalKeys: $excludedGlobalKeys
            )
        }
        .task { initializeCityIfNeeded() }
        .onChange(of: candidates.map(\.globalKey)) { _, _ in
            reconcileCityAndResult()
        }
        .onChange(of: stateKey) { _, _ in
            guard let result,
                  !filteredCandidates.contains(where: { $0.globalKey == result.globalKey }) else { return }
            self.result = nil
        }
        .tasteMapBottomNavigationHidden()
        .accessibilityIdentifier("restaurant-roulette-screen")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("帮你做个轻松决定")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(RouletteTheme.brand)
                Text("今天，就交给转盘")
                    .font(.largeTitle.bold())
                    .foregroundStyle(RouletteTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("只从你的真实餐厅记录中均匀抽取，不会偷偷按评分加权。")
                    .font(.subheadline)
                    .foregroundStyle(RouletteTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(RouletteTheme.brandSoft)
                Text("🥢").font(.title)
            }
            .frame(width: 64, height: 64)
            .rotationEffect(.degrees(4))
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: RouletteTheme.brandDeep.opacity(0.07), radius: 18, y: 9)
    }

    private var conditionBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                conditionChip(symbol: source == .all ? "fork.knife" : source == .wantToGo ? "bookmark.fill" : "checkmark.circle.fill", text: source.title)
                if let selectedCity {
                    conditionChip(symbol: "mappin.and.ellipse", text: selectedCity)
                }
                Spacer(minLength: 4)
                Button {
                    isShowingFilters = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(RouletteTheme.brandSoft, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("调整候选条件")
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(filteredCandidates.count) 家餐厅可选")
                        .font(.headline)
                        .foregroundStyle(RouletteTheme.ink)
                        .accessibilityIdentifier("roulette-candidate-count")
                    Text(candidateCountDetail)
                        .font(.caption)
                        .foregroundStyle(RouletteTheme.muted)
                }
                Spacer()
                if !baseCandidates.isEmpty {
                    Button("管理候选") { isShowingCandidateManager = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(RouletteTheme.brandDeep)
                        .accessibilityIdentifier("roulette-manage-candidates")
                }
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var rouletteStage: some View {
        VStack(spacing: 18) {
            RouletteWheelView(
                candidates: filteredCandidates,
                rotation: rotation,
                isSpinning: isSpinning,
                onSpin: spin
            )
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 330 : 380)
            Text(isSpinning ? "正在慢慢停下来…" : result == nil ? "点一下转盘中央，让今天轻松一点" : "不合心意？可以再来一次")
                .font(.subheadline)
                .foregroundStyle(RouletteTheme.muted)
                .animation(.default, value: isSpinning)
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("roulette-stage")
    }

    private var singleCandidateState: some View {
        VStack(spacing: 14) {
            Text("今天就它了")
                .font(.title2.bold())
                .foregroundStyle(RouletteTheme.brandDeep)
            Text("当前条件下只有这一家，不需要假装随机。")
                .font(.subheadline)
                .foregroundStyle(RouletteTheme.muted)
            if let candidate = filteredCandidates.first {
                resultCard(candidate)
            }
        }
        .accessibilityIdentifier("roulette-single-state")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                candidates.isEmpty ? "还没有候选餐厅" : "没有符合条件的餐厅",
                systemImage: candidates.isEmpty ? "fork.knife.circle" : "line.3.horizontal.decrease.circle"
            )
        } description: {
            Text(candidates.isEmpty
                 ? "先收藏几家想吃或记录去过的餐厅，再来转一转。"
                 : "可以清除部分条件，或重新加入暂时排除的餐厅。")
        } actions: {
            if candidates.isEmpty {
                Button("搜索餐厅", systemImage: "magnifyingglass", action: onSearch)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("roulette-empty-search")
            } else {
                Button("清除条件", action: resetConditions)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("roulette-clear-filters")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityIdentifier("roulette-empty-state")
    }

    private var localOnlyNote: some View {
        Label("本地抽取 · 断网也能用", systemImage: "iphone.and.arrow.forward")
            .font(.caption)
            .foregroundStyle(RouletteTheme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .accessibilityIdentifier("roulette-offline-note")
    }

    @ViewBuilder
    private func resultCard(_ candidate: RouletteCandidate) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            ZStack(alignment: .bottomLeading) {
                resultImage(candidate)
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 150 : 190)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                Text("今天吃")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.46), in: Capsule())
                    .padding(12)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(candidate.displayName)
                    .font(.title2.bold())
                    .foregroundStyle(RouletteTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("roulette-result-name")
                if !candidate.city.isEmpty || !candidate.address.isEmpty {
                    Label(
                        [candidate.city, candidate.address].filter { !$0.isEmpty }.joined(separator: " · "),
                        systemImage: "mappin.and.ellipse"
                    )
                    .font(.subheadline)
                    .foregroundStyle(RouletteTheme.muted)
                    .lineLimit(2)
                }
                HStack(spacing: 8) {
                    statusPill(candidate)
                    if let rating = candidate.averageRating {
                        Label(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(RouletteTheme.caramel)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(RouletteTheme.cream, in: Capsule())
                    }
                }
                Text(candidate.statusDetail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(RouletteTheme.brandDeep)
            }
            HStack(spacing: 12) {
                Button {
                    spin()
                } label: {
                    Label("再来一次", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSpinning || filteredCandidates.count < 2)
                .accessibilityIdentifier("roulette-reroll")

                if let restaurant = restaurants.first(where: { $0.id == candidate.restaurantID }) {
                    NavigationLink {
                        RestaurantDetailView(restaurant: restaurant)
                    } label: {
                        Label("查看餐厅", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("roulette-open-restaurant")
                }
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: RouletteTheme.brandDeep.opacity(0.08), radius: 18, y: 9)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("今天吃：\(candidate.displayName)。\(candidate.statusDetail)")
        .accessibilityIdentifier("roulette-result-card")
    }

    @ViewBuilder
    private func resultImage(_ candidate: RouletteCandidate) -> some View {
        if let photoID = candidate.photoID,
           let photo = photos.first(where: { $0.id == photoID && $0.deletedAt == nil }) {
            PhotoAssetImageView(photo: photo, variant: .display)
        } else {
            ZStack {
                LinearGradient(
                    colors: [RouletteTheme.brandSoft, RouletteTheme.cream, RouletteTheme.leafSoft],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(candidate.markerEmoji)
                    .font(.system(size: 70))
                    .shadow(color: .white.opacity(0.8), radius: 12)
            }
            .accessibilityLabel("餐厅暂无照片")
        }
    }

    private func statusPill(_ candidate: RouletteCandidate) -> some View {
        Label(candidate.status.title, systemImage: candidate.status.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(candidate.status == .wantToGo ? RouletteTheme.brand : RouletteTheme.leaf)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                candidate.status == .wantToGo ? RouletteTheme.brandSoft : RouletteTheme.leafSoft,
                in: Capsule()
            )
    }

    private func conditionChip(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(RouletteTheme.brandDeep)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RouletteTheme.brandSoft, in: Capsule())
    }

    private var candidateCountDetail: String {
        let excluded = baseCandidates.count - filteredCandidates.count
        if excluded > 0 { return "本次暂不考虑 \(excluded) 家" }
        if filteredCandidates.count > 30 { return "完整候选池参与随机，轮盘仅做简化展示" }
        return "每家机会相同"
    }

    private func initializeCityIfNeeded() {
        guard !cityWasInitialized else { return }
        selectedCity = RestaurantRouletteEngine.defaultCity(
            for: candidates,
            preferredCity: preferredCity
        )
        cityWasInitialized = true
    }

    private func reconcileCityAndResult() {
        let availableCities = RestaurantRouletteEngine.cities(in: candidates)
        if let selectedCity,
           !availableCities.contains(where: {
               $0.localizedCaseInsensitiveCompare(selectedCity) == .orderedSame
           }) {
            self.selectedCity = RestaurantRouletteEngine.defaultCity(
                for: candidates,
                preferredCity: preferredCity
            )
        } else {
            initializeCityIfNeeded()
        }
        excludedGlobalKeys.formIntersection(Set(candidates.map(\.globalKey)))
        if let result,
           !candidates.contains(where: { $0.globalKey == result.globalKey }) {
            self.result = nil
        }
    }

    private func resetConditions() {
        source = .all
        excludedGlobalKeys = []
        selectedCity = RestaurantRouletteEngine.defaultCity(
            for: candidates,
            preferredCity: preferredCity
        )
        result = nil
    }

    private func spin() {
        guard !isSpinning, filteredCandidates.count > 1,
              let selected = RestaurantRouletteEngine.select(
                  from: filteredCandidates,
                  excludingImmediateRepeat: lastResultGlobalKey
              ),
              let selectedIndex = filteredCandidates.firstIndex(of: selected) else { return }

        let token = UUID()
        spinToken = token
        isSpinning = true
        result = nil
        RouletteHaptics.started()

        let nextRotation = RestaurantRouletteEngine.targetRotation(
            currentRotation: rotation,
            selectedIndex: selectedIndex,
            candidateCount: filteredCandidates.count,
            fullTurns: usesReducedMotion ? 1 : 5
        )
        let duration = usesReducedMotion ? 0.28 : 3.0
        withAnimation(
            usesReducedMotion
                ? .easeOut(duration: duration)
                : .timingCurve(0.12, 0.67, 0.06, 1, duration: duration)
        ) {
            rotation = nextRotation
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard spinToken == token else { return }
            result = selected
            lastResultGlobalKey = selected.globalKey
            isSpinning = false
            RouletteHaptics.finished()
            UIAccessibility.post(
                notification: .announcement,
                argument: "今天吃：\(selected.displayName)"
            )
        }
    }
}

private struct RouletteWheelView: View {
    let candidates: [RouletteCandidate]
    let rotation: Double
    let isSpinning: Bool
    let onSpin: () -> Void

    private var visualCount: Int {
        RestaurantRouletteEngine.visualSegmentCount(candidateCount: candidates.count)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: size / 2, y: size / 2)
            let labelRadius = size * (candidates.count <= 12 ? 0.34 : 0.37)
            ZStack {
                ZStack {
                    ForEach(0..<visualCount, id: \.self) { index in
                        RouletteSliceShape(index: index, count: visualCount)
                            .fill(RouletteTheme.sliceColors[index % RouletteTheme.sliceColors.count])
                            .overlay {
                                RouletteSliceShape(index: index, count: visualCount)
                                    .stroke(.white.opacity(0.92), lineWidth: candidates.count <= 30 ? 1.4 : 0.8)
                            }
                    }
                    if candidates.count <= 30 {
                        ForEach(0..<visualCount, id: \.self) { index in
                            let angle = (Double(index) + 0.5) * 360 / Double(visualCount)
                            let radians = angle * .pi / 180
                            Text(label(for: index))
                                .font(candidates.count <= 12 ? .caption2.weight(.bold) : .system(size: 8, weight: .bold))
                                .foregroundStyle(RouletteTheme.ink.opacity(0.82))
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                                .frame(width: candidates.count <= 12 ? size * 0.24 : 24)
                                .position(
                                    x: center.x + sin(radians) * labelRadius,
                                    y: center.y - cos(radians) * labelRadius
                                )
                                .rotationEffect(.degrees(-rotation))
                                .accessibilityHidden(true)
                        }
                    } else {
                        ForEach(0..<visualCount, id: \.self) { index in
                            let angle = (Double(index) + 0.5) * 360 / Double(visualCount)
                            let radians = angle * .pi / 180
                            Circle()
                                .fill(.white.opacity(index.isMultiple(of: 2) ? 0.78 : 0.52))
                                .frame(width: 8, height: 8)
                                .position(
                                    x: center.x + sin(radians) * labelRadius,
                                    y: center.y - cos(radians) * labelRadius
                                )
                        }
                    }
                }
                .frame(width: size - 34, height: size - 34)
                .clipShape(Circle())
                .overlay { Circle().stroke(.white, lineWidth: 7) }
                .overlay { Circle().stroke(RouletteTheme.brand.opacity(0.78), lineWidth: 2) }
                .shadow(color: RouletteTheme.brandDeep.opacity(0.18), radius: 18, y: 10)
                .rotationEffect(.degrees(rotation))

                Circle()
                    .fill(RouletteTheme.brandDeep)
                    .frame(width: size * 0.29, height: size * 0.29)
                    .overlay { Circle().stroke(.white, lineWidth: 6) }
                    .shadow(color: RouletteTheme.brandDeep.opacity(0.2), radius: 10, y: 5)
                Button(action: onSpin) {
                    VStack(spacing: 2) {
                        Text(isSpinning ? "转动中" : "转一下")
                            .font(.headline.bold())
                        Text(isSpinning ? "马上揭晓" : "随机选一家")
                            .font(.caption2)
                            .opacity(0.84)
                    }
                    .foregroundStyle(.white)
                    .frame(width: size * 0.29, height: size * 0.29)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isSpinning)
                .accessibilityLabel(isSpinning ? "正在抽取餐厅" : "开始随机抽取")
                .accessibilityHint("候选餐厅共 \(candidates.count) 家")
                .accessibilityIdentifier("roulette-spin")
            }
            .frame(width: size, height: size)
            .overlay(alignment: .top) {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(RouletteTheme.brandDeep)
                    .rotationEffect(.degrees(180))
                    .offset(y: -8)
                    .shadow(color: .white, radius: 2)
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("餐厅转盘，共 \(candidates.count) 家候选餐厅")
        .accessibilityIdentifier("roulette-wheel")
    }

    private func label(for index: Int) -> String {
        if candidates.count <= 12 {
            return RestaurantRouletteEngine.abbreviatedName(
                candidates[index].displayName,
                candidateCount: candidates.count
            )
        }
        return "\(index + 1)"
    }
}

private struct RouletteSliceShape: Shape {
    let index: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        guard count > 0 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let segment = 360 / Double(count)
        let start = Angle.degrees(-90 + Double(index) * segment)
        let end = Angle.degrees(-90 + Double(index + 1) * segment)
        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        path.closeSubpath()
        return path
    }
}

private struct RouletteFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var source: RouletteCandidateSource
    @Binding var selectedCity: String?
    let cities: [String]
    let onReset: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("候选来源") {
                    Picker("餐厅状态", selection: $source) {
                        ForEach(RouletteCandidateSource.allCases) { value in
                            Text(value.title)
                                .tag(value)
                                .accessibilityIdentifier("roulette-source-\(value.rawValue)")
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("roulette-source-picker")
                }
                if !cities.isEmpty {
                    Section("所在城市") {
                        Picker("城市", selection: $selectedCity) {
                            ForEach(cities, id: \.self) { city in
                                Text(city).tag(Optional(city))
                            }
                        }
                        Text("使用用户资料城市；没有匹配时选择本地记录最多的城市，不请求精确定位。")
                            .font(.caption)
                            .foregroundStyle(RouletteTheme.muted)
                    }
                }
                Section {
                    Button("恢复默认条件") { onReset() }
                        .accessibilityIdentifier("roulette-reset-filters")
                }
            }
            .navigationTitle("候选条件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct RouletteCandidateManager: View {
    @Environment(\.dismiss) private var dismiss
    let candidates: [RouletteCandidate]
    @Binding var excludedGlobalKeys: Set<String>
    @State private var query = ""

    private var visible: [RouletteCandidate] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return candidates }
        return candidates.filter {
            [$0.displayName, $0.city, $0.address]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            List(visible) { candidate in
                Toggle(isOn: includedBinding(candidate)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(candidate.displayName).font(.headline)
                        Text([candidate.status.title, candidate.city].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(RouletteTheme.muted)
                    }
                }
                .accessibilityIdentifier("roulette-candidate-toggle-\(candidate.globalKey)")
            }
            .searchable(text: $query, prompt: "搜索我的餐厅")
            .navigationTitle("管理候选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("全部加入") { excludedGlobalKeys.subtract(candidates.map(\.globalKey)) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func includedBinding(_ candidate: RouletteCandidate) -> Binding<Bool> {
        Binding(
            get: { !excludedGlobalKeys.contains(candidate.globalKey) },
            set: { included in
                if included { excludedGlobalKeys.remove(candidate.globalKey) }
                else { excludedGlobalKeys.insert(candidate.globalKey) }
            }
        )
    }
}

private enum RouletteHaptics {
    @MainActor static func started() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
    }

    @MainActor static func finished() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

enum RouletteTheme {
    static let brand = Color(red: 0.31, green: 0.42, blue: 0.55)
    static let brandDeep = Color(red: 0.20, green: 0.31, blue: 0.41)
    static let brandSoft = Color(red: 0.93, green: 0.96, blue: 0.98)
    static let canvas = Color(red: 0.975, green: 0.975, blue: 0.965)
    static let ink = Color(red: 0.09, green: 0.16, blue: 0.21)
    static let muted = Color(red: 0.36, green: 0.41, blue: 0.45)
    static let leaf = Color(red: 0.27, green: 0.55, blue: 0.38)
    static let leafSoft = Color(red: 0.91, green: 0.96, blue: 0.92)
    static let cream = Color(red: 0.98, green: 0.94, blue: 0.84)
    static let caramel = Color(red: 0.68, green: 0.43, blue: 0.24)
    static let sliceColors: [Color] = [
        Color(red: 0.86, green: 0.91, blue: 0.95),
        Color(red: 0.91, green: 0.95, blue: 0.91),
        Color(red: 0.98, green: 0.93, blue: 0.82),
        Color(red: 0.97, green: 0.89, blue: 0.87),
        Color(red: 0.91, green: 0.89, blue: 0.94),
        Color(red: 0.94, green: 0.92, blue: 0.86),
    ]
}
