import SwiftData
import SwiftUI
import UIKit

struct RestaurantRouletteScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NativeAuthServices.self) private var authServices
    @Environment(\.localAccountScope) private var accountScope
    @Query private var restaurants: [Restaurant]
    @Query private var visits: [Visit]
    @Query private var photos: [PhotoAsset]
    @State private var isShowingSearch = false
    @State private var isShowingManualAdd = false

    let preferredCity: String?
    let initialRestaurantID: UUID?

    init(preferredCity: String? = nil, initialRestaurantID: UUID? = nil) {
        self.preferredCity = preferredCity
        self.initialRestaurantID = initialRestaurantID
    }

    private var owned: ProfileOwnedContentScope.Snapshot {
        ProfileOwnedContentScope.capture(
            currentUserID: accountScope.ownerUserID,
            restaurants: restaurants,
            visits: visits,
            photos: photos
        )
    }

    private var candidates: [RouletteCandidate] {
        RestaurantRouletteEngine.candidates(from: RouletteRestaurantRecord.capture(
            restaurants: owned.restaurants,
            visits: owned.visits,
            photos: owned.photos
        ))
    }

    var body: some View {
        RestaurantRouletteExperienceView(
            candidates: candidates,
            restaurants: owned.restaurants,
            photos: owned.photos,
            preferredCity: preferredCity,
            initialResultGlobalKey: initialResultGlobalKey,
            onSearch: { isShowingSearch = true },
            onAddCustom: { isShowingManualAdd = true }
        )
        .sheet(isPresented: $isShowingSearch) {
            RestaurantSearchView { candidate, action in
                try save(candidate: candidate, action: action)
            }
        }
        .sheet(isPresented: $isShowingManualAdd) {
            AddRestaurantView(
                dependencies: acquisitionDependencies,
                startsWithManualEntry: true
            ) { candidate, action in
                try save(candidate: candidate, action: action)
            }
        }
    }

    private func save(candidate: RestaurantCandidate, action: RestaurantSearchAction) throws {
        switch action {
        case .wantToGo:
            _ = try LocalTasteMapStore(context: modelContext).addToWantToGo(
                candidate: candidate,
                among: owned.restaurants,
                actorUserID: accountScope.ownerUserID
            )
        case .recordVisit:
            _ = try LocalTasteMapStore(context: modelContext).restaurant(
                for: candidate,
                among: owned.restaurants,
                status: .visited,
                actorUserID: accountScope.ownerUserID
            )
            try modelContext.save()
        }
    }

    private var acquisitionDependencies: RestaurantAcquisitionDependencies {
#if DEBUG
        if TasteMapUITestFixtures.usesRestaurantAcquisitionFixture {
            return TasteMapUITestFixtures.restaurantAcquisitionDependencies
        }
#endif
        return .live(linkResolver: authServices.externalRestaurantLinkAPI)
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
    let onAddCustom: () -> Void
    let forceReducedMotion: Bool

    @State private var source: RouletteCandidateSource
    @State private var selectedCity: String?
    @State private var selectedGlobalKeys: Set<String>
    @State private var selectionWasInitialized: Bool
    @State private var result: RouletteCandidate?
    @State private var lastResultGlobalKey: String?
    @State private var rotation: Double = 0
    @State private var isSpinning = false
    @State private var isShowingFilters = false
    @State private var isShowingCandidateManager = false
    @State private var temporaryCandidates: [RouletteCandidate] = []
    @State private var cityWasInitialized: Bool
    @State private var spinToken = UUID()
    @State private var presentsManualAddAfterManager = false

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
        onSearch: @escaping () -> Void = {},
        onAddCustom: @escaping () -> Void = {}
    ) {
        self.candidates = candidates
        self.restaurants = restaurants
        self.photos = photos
        self.preferredCity = preferredCity
        self.onSearch = onSearch
        self.onAddCustom = onAddCustom
        self.forceReducedMotion = forceReducedMotion
        let initialResult = candidates.first { $0.globalKey == initialResultGlobalKey }
        let resolvedInitialCity = initialCity
            ?? initialResult.flatMap { $0.city.isEmpty ? nil : $0.city }
            ?? RestaurantRouletteEngine.defaultCity(for: candidates, preferredCity: preferredCity)
        let initialCandidates = RestaurantRouletteEngine.filtered(
            candidates,
            by: RouletteFilter(source: initialSource, city: resolvedInitialCity)
        ).filter { !excludedGlobalKeys.contains($0.globalKey) }
        let initialSelection = RestaurantRouletteEngine.defaultActiveGlobalKeys(
            from: initialCandidates,
            preferredGlobalKey: initialResultGlobalKey
        )
        _source = State(initialValue: initialSource)
        _selectedCity = State(initialValue: resolvedInitialCity)
        _selectedGlobalKeys = State(initialValue: initialSelection)
        _selectionWasInitialized = State(initialValue: !candidates.isEmpty)
        _result = State(initialValue: initialResult)
        _lastResultGlobalKey = State(initialValue: initialResultGlobalKey)
        _cityWasInitialized = State(initialValue: !candidates.isEmpty || initialCity != nil)
    }

    private var filter: RouletteFilter {
        RouletteFilter(
            source: source,
            city: selectedCity
        )
    }

    private var filteredCandidates: [RouletteCandidate] {
        RestaurantRouletteEngine.activeCandidates(
            from: baseCandidates,
            selectedGlobalKeys: selectedGlobalKeys
        )
    }

    private var baseCandidates: [RouletteCandidate] {
        RestaurantRouletteEngine.filtered(
            candidates,
            by: RouletteFilter(source: source, city: selectedCity)
        ) + temporaryCandidates
    }

    private var cities: [String] {
        RestaurantRouletteEngine.cities(in: candidates)
    }

    private var candidatesForManager: [RouletteCandidate] {
        RestaurantRouletteEngine.filtered(
            candidates,
            by: RouletteFilter(source: .all, city: selectedCity)
        )
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
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("从你的餐厅里选 2～10 家，让轮盘替你决定。")
                        .font(.subheadline)
                        .foregroundStyle(RouletteTheme.muted)
                    Text("候选与结果一一对应，每家机会相同。")
                        .font(.caption)
                        .foregroundStyle(RouletteTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                candidatePool
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
        .sheet(isPresented: $isShowingFilters) {
            RouletteFilterSheet(
                source: $source,
                selectedCity: $selectedCity,
                cities: cities,
                onReset: resetConditions
            )
        }
        .sheet(isPresented: $isShowingCandidateManager, onDismiss: {
            guard presentsManualAddAfterManager else { return }
            presentsManualAddAfterManager = false
            onAddCustom()
        }) {
            RouletteCandidateManager(
                candidates: candidatesForManager,
                temporaryCandidates: temporaryCandidates,
                photos: photos,
                initialSource: source,
                initialSelectedGlobalKeys: selectedGlobalKeys,
                onApply: { keys, selectedSource, temporaryItems in
                    selectedGlobalKeys = keys
                    source = selectedSource
                    temporaryCandidates = temporaryItems
                    result = nil
                },
                onAddCustom: {
                    presentsManualAddAfterManager = true
                }
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

    private var candidatePool: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { candidatePoolHeader }
            } else {
                HStack(alignment: .firstTextBaseline) { candidatePoolHeader }
            }

            if filteredCandidates.isEmpty {
                Text(baseCandidates.isEmpty ? "当前条件下没有可选餐厅" : "从“管理候选”选择 2～10 家餐厅")
                    .font(.subheadline)
                    .foregroundStyle(RouletteTheme.muted)
                    .padding(.vertical, 4)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(filteredCandidates) { candidate in
                            candidateChip(candidate)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("roulette-candidate-chips")
            }

            Divider()
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { conditionItems(includesSpacer: false) }
                }
            } else {
                HStack(spacing: 8) { conditionItems(includesSpacer: true) }
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { candidateSummary }
            } else {
                HStack { candidateSummary }
            }
        }
        .padding(16)
        .background(RouletteTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TasteMapCoreTheme.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var candidatePoolHeader: some View {
                Text("已选候选")
                    .font(.headline)
                    .foregroundStyle(RouletteTheme.ink)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Text("\(filteredCandidates.count) / \(RestaurantRouletteEngine.maximumActiveCandidateCount)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(RouletteTheme.brandDeep)
                Button("清空") { clearCandidatePool() }
                    .font(.subheadline.weight(.semibold))
                    .disabled(filteredCandidates.isEmpty || isSpinning)
                    .accessibilityIdentifier("roulette-clear-candidates")
    }

    @ViewBuilder
    private func conditionItems(includesSpacer: Bool) -> some View {
        conditionChip(
            symbol: source == .all
                ? "fork.knife"
                : source == .wantToGo
                    ? "bookmark.fill"
                    : RestaurantStatus.visited.systemImage,
            text: source.title
        )
        if let selectedCity {
            conditionChip(symbol: "building.2.fill", text: selectedCity)
        }
        if includesSpacer { Spacer(minLength: 4) }
        Button {
            isShowingFilters = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
                .frame(
                    width: dynamicTypeSize.isAccessibilitySize ? 44 : 34,
                    height: dynamicTypeSize.isAccessibilitySize ? 44 : 34
                )
                .background(RouletteTheme.brandSoft, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("调整候选条件")
        .accessibilityIdentifier("roulette-filter-open")
    }

    @ViewBuilder
    private var candidateSummary: some View {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(filteredCandidates.count) 家候选餐厅")
                        .font(.headline)
                        .foregroundStyle(RouletteTheme.ink)
                        .accessibilityIdentifier("roulette-candidate-count")
                    Text(candidateCountDetail)
                        .font(.caption)
                        .foregroundStyle(RouletteTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                if !candidatesForManager.isEmpty {
                    Button("管理候选餐厅") { isShowingCandidateManager = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(RouletteTheme.brandDeep)
                        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 4 : 0)
                        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 44 : nil)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("roulette-manage-candidates")
                }
    }

    private var rouletteStage: some View {
        VStack(spacing: 18) {
            RouletteWheelView(
                candidates: filteredCandidates,
                photos: photos,
                rotation: rotation,
                isSpinning: isSpinning,
                hasResult: result != nil,
                onSpin: spin
            )
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 330 : 380)
            Text(isSpinning ? "正在慢慢停下来…" : result == nil ? "点一下转盘中央，让今天轻松一点" : "不合心意？可以再来一次")
                .font(.subheadline)
                .foregroundStyle(RouletteTheme.muted)
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
        TasteMapEmptyState(
            title: candidates.isEmpty
                ? "还没有候选餐厅"
                : baseCandidates.isEmpty ? "没有符合条件的餐厅" : "候选池为空",
            message: candidates.isEmpty
                ? "先收藏几家想吃或记录去过的餐厅，再来转一转。"
                : baseCandidates.isEmpty
                    ? "可以清除筛选条件，再选择餐厅。"
                    : "选择 2～10 家真实餐厅，轮盘会立即生成。",
            systemImage: candidates.isEmpty
                ? "fork.knife.circle"
                : baseCandidates.isEmpty ? "line.3.horizontal.decrease.circle" : "plus.circle",
            foodDiningVisualKind: candidates.isEmpty ? .genericDining : nil,
            actionTitle: candidates.isEmpty
                ? "搜索餐厅"
                : !baseCandidates.isEmpty ? "管理候选" : "清除条件",
            action: performEmptyStateAction,
            actionAccessibilityIdentifier: candidates.isEmpty
                ? "roulette-empty-search"
                : !baseCandidates.isEmpty ? "roulette-empty-manage" : "roulette-clear-filters",
            presentation: .embedded,
            accessibilityIdentifier: "roulette-empty-state"
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(RouletteTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func performEmptyStateAction() {
        if candidates.isEmpty {
            onSearch()
        } else if !baseCandidates.isEmpty {
            isShowingCandidateManager = true
        } else {
            resetConditions()
        }
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
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 12) { resultActions(candidate) }
                } else {
                    HStack(spacing: 12) { resultActions(candidate) }
                }
            }
        }
        .padding(16)
        .background(RouletteTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: RouletteTheme.brandDeep.opacity(0.08), radius: 18, y: 9)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("今天吃：\(candidate.displayName)。\(candidate.statusDetail)")
        .accessibilityIdentifier("roulette-result-card")
    }

    @ViewBuilder
    private func resultActions(_ candidate: RouletteCandidate) -> some View {
                Button {
                    spin()
                } label: {
                    Label("再来一次", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSpinning || filteredCandidates.count < 2)
                .accessibilityIdentifier("roulette-reroll")

                if let restaurantID = candidate.restaurantID,
                   let restaurant = restaurants.first(where: { $0.id == restaurantID }) {
                    NavigationLink {
                        RestaurantDetailView(restaurant: restaurant, entrySource: .roulette)
                    } label: {
                        Label("查看餐厅", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("roulette-open-restaurant")
                }
    }

    @ViewBuilder
    private func resultImage(_ candidate: RouletteCandidate) -> some View {
        RouletteRestaurantImage(
            candidate: candidate,
            photos: photos,
            variant: .display,
            fallbackIconSize: 38
        )
    }

    private func statusPill(_ candidate: RouletteCandidate) -> some View {
        Label(
            candidate.isTemporary ? "临时候选" : candidate.status.title,
            systemImage: candidate.isTemporary ? "fork.knife" : candidate.status.systemImage
        )
            .font(.caption.weight(.semibold))
            .foregroundStyle(candidate.isTemporary || candidate.status == .wantToGo ? RouletteTheme.brand : RouletteTheme.leaf)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                candidate.isTemporary || candidate.status == .wantToGo ? RouletteTheme.brandSoft : RouletteTheme.leafSoft,
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

    private func candidateChip(_ candidate: RouletteCandidate) -> some View {
        HStack(spacing: 7) {
            RouletteCandidateAvatar(candidate: candidate, photos: photos, diameter: 25)
            Text(candidate.displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Button {
                selectedGlobalKeys.remove(candidate.globalKey)
                if result?.globalKey == candidate.globalKey { result = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .disabled(isSpinning)
            .accessibilityLabel("移除 \(candidate.displayName)")
        }
        .foregroundStyle(RouletteTheme.ink)
        .padding(.leading, 5)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .background(RouletteTheme.canvas, in: Capsule())
        .overlay { Capsule().stroke(TasteMapCoreTheme.border, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("roulette-candidate-chip-\(candidate.globalKey)")
    }

    private var candidateCountDetail: String {
        if baseCandidates.count > RestaurantRouletteEngine.maximumActiveCandidateCount {
            return "候选库 \(baseCandidates.count) 家 · 最多选择 10 家"
        }
        return "每家机会相同 · 扇区与候选一一对应"
    }

    private func initializeCityIfNeeded() {
        guard !cityWasInitialized else { return }
        if let initial = result, !initial.city.isEmpty {
            selectedCity = initial.city
        } else {
            selectedCity = RestaurantRouletteEngine.defaultCity(
                for: candidates,
                preferredCity: preferredCity
            )
        }
        cityWasInitialized = true
        initializeSelectionIfNeeded()
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
        let availableCandidates = candidates + temporaryCandidates
        selectedGlobalKeys.formIntersection(Set(availableCandidates.map(\.globalKey)))
        initializeSelectionIfNeeded()
        if let result,
           !availableCandidates.contains(where: { $0.globalKey == result.globalKey }) {
            self.result = nil
        }
    }

    private func resetConditions() {
        source = .all
        selectedCity = RestaurantRouletteEngine.defaultCity(
            for: candidates,
            preferredCity: preferredCity
        )
        result = nil
    }

    private func initializeSelectionIfNeeded() {
        guard !selectionWasInitialized, !baseCandidates.isEmpty else { return }
        selectedGlobalKeys = RestaurantRouletteEngine.defaultActiveGlobalKeys(
            from: baseCandidates,
            preferredGlobalKey: result?.globalKey
        )
        selectionWasInitialized = true
    }

    private func clearCandidatePool() {
        selectedGlobalKeys.removeAll()
        temporaryCandidates.removeAll()
        result = nil
        lastResultGlobalKey = nil
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let candidates: [RouletteCandidate]
    let photos: [PhotoAsset]
    let rotation: Double
    let isSpinning: Bool
    let hasResult: Bool
    let onSpin: () -> Void

    private var visualCount: Int {
        RestaurantRouletteEngine.visualSegmentCount(candidateCount: candidates.count)
    }

    private var visualSlots: [RouletteCandidate?] {
        RestaurantRouletteEngine.visualSlots(from: candidates)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: size / 2, y: size / 2)
            let wheelSize = size - 24
            let labelRadius = size * (candidates.count <= 4 ? 0.31 : candidates.count <= 6 ? 0.33 : 0.36)
            ZStack {
                ZStack {
                    ForEach(0..<visualCount, id: \.self) { index in
                        RouletteSliceShape(index: index, count: visualCount)
                            .fill(RouletteTheme.sliceColors[index % RouletteTheme.sliceColors.count])
                            .overlay {
                                RouletteSliceShape(index: index, count: visualCount)
                                    .stroke(.white.opacity(0.94), lineWidth: 2)
                            }
                    }
                    ForEach(0..<visualCount, id: \.self) { index in
                        let angle = (Double(index) + 0.5) * 360 / Double(visualCount)
                        let radians = angle * .pi / 180
                        Group {
                            if let candidate = visualSlots[index] {
                                segmentLabel(candidate, size: size)
                            } else {
                                addMoreSegmentLabel(size: size)
                            }
                        }
                            .position(
                                x: center.x + sin(radians) * labelRadius,
                                y: center.y - cos(radians) * labelRadius
                            )
                            .rotationEffect(.degrees(-rotation))
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: wheelSize, height: wheelSize)
                .clipShape(Circle())
                .overlay { Circle().stroke(.white, lineWidth: 9) }
                .overlay { Circle().stroke(RouletteTheme.brand.opacity(0.78), lineWidth: 3) }
                .overlay { Circle().inset(by: 7).stroke(RouletteTheme.brandDeep.opacity(0.22), lineWidth: 1) }
                .shadow(color: RouletteTheme.brandDeep.opacity(0.18), radius: 16, y: 8)
                .rotationEffect(.degrees(rotation))

                Circle()
                    .fill(RouletteTheme.brandDeep)
                    .frame(width: centerDiameter(size), height: centerDiameter(size))
                    .overlay { Circle().stroke(.white, lineWidth: 5) }
                    .shadow(color: RouletteTheme.brandDeep.opacity(0.2), radius: 10, y: 5)
                Button(action: onSpin) {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            Text(isSpinning ? "抽取中" : hasResult ? "再抽" : "开始")
                                .font(.headline.bold())
                        } else {
                            VStack(spacing: 2) {
                                Text(isSpinning ? "抽取中" : hasResult ? "再抽一次" : "开始")
                                    .font((hasResult ? Font.subheadline : .headline).bold())
                                Text(isSpinning ? "马上揭晓" : "随机选一家")
                                    .font(.caption2)
                                    .opacity(0.84)
                            }
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: centerDiameter(size), height: centerDiameter(size))
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
                ZStack {
                    Circle()
                        .fill(.white)
                        .overlay {
                            Circle().stroke(RouletteTheme.brandDeep, lineWidth: 3)
                        }
                    Image(systemName: "mappin")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(RouletteTheme.brandDeep)
                }
                    .frame(width: 43, height: 43)
                    .offset(y: -13)
                    .shadow(color: RouletteTheme.brandDeep.opacity(0.2), radius: 4, y: 2)
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("餐厅转盘，共 \(candidates.count) 家候选餐厅")
        .accessibilityIdentifier("roulette-wheel")
    }

    private func centerDiameter(_ size: CGFloat) -> CGFloat {
        size * (dynamicTypeSize.isAccessibilitySize ? 0.50 : 0.30)
    }

    private func addMoreSegmentLabel(size: CGFloat) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
            Text("添加更多\n餐厅")
                .font(.system(size: 6.5, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .foregroundStyle(RouletteTheme.wheelMuted)
        .frame(width: size * 0.16)
    }

    private func segmentLabel(_ candidate: RouletteCandidate, size: CGFloat) -> some View {
        let compact = candidates.count > 6
        return VStack(spacing: compact ? 1 : 2) {
            RouletteCandidateAvatar(
                candidate: candidate,
                photos: photos,
                diameter: compact ? 20 : 27
            )
            Text(RestaurantRouletteEngine.abbreviatedName(
                candidate.displayName,
                candidateCount: candidates.count
            ))
            .font(.system(size: compact ? 7 : 9, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            if !candidate.city.isEmpty {
                Text(candidate.city)
                    .font(.system(size: compact ? 5.5 : 6.5, weight: .medium))
                    .foregroundStyle(RouletteTheme.wheelMuted)
                    .lineLimit(1)
            }
            if let rating = candidate.averageRating {
                Text("★ \(rating.formatted(.number.precision(.fractionLength(1))))")
                    .font(.system(size: compact ? 6 : 7, weight: .bold))
                    .foregroundStyle(RouletteTheme.caramel)
            }
        }
        .foregroundStyle(RouletteTheme.wheelInk)
        .frame(width: compact ? size * 0.15 : size * 0.22)
    }
}

private struct RouletteCandidateAvatar: View {
    let candidate: RouletteCandidate
    let photos: [PhotoAsset]
    let diameter: CGFloat

    var body: some View {
        RouletteRestaurantImage(
            candidate: candidate,
            photos: photos,
            variant: .thumbnail,
            fallbackIconSize: diameter * 0.38
        )
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay { Circle().stroke(.white.opacity(0.96), lineWidth: 1.5) }
        .accessibilityHidden(true)
    }
}

private struct RouletteRestaurantImage: View {
    let candidate: RouletteCandidate
    let photos: [PhotoAsset]
    let variant: PhotoBinaryVariant
    let fallbackIconSize: CGFloat

    var body: some View {
        TasteMapRestaurantImage(
            resolution: RestaurantImagePriorityPolicy.resolution(
                localUserPhotoID: candidate.photoID,
                publicOrCachedPhotoID: candidate.publicPhotoID,
                providerMerchantImageURL: candidate.merchantImageURL
            ),
            photosByID: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) }),
            semanticID: candidate.globalKey,
            variant: variant,
            fallbackForegroundColor: RouletteTheme.brandDeep,
            fallbackBackgroundColor: .white.opacity(0.76),
            fallbackIconSize: max(24, fallbackIconSize * 2.1),
            accessibilityLabel: "\(candidate.displayName)餐厅图片"
        )
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
                    TasteMapSegmentedControl(
                        selection: $source,
                        items: RouletteCandidateSource.allCases.map {
                            .init($0, title: $0.title)
                        },
                        accessibilityIdentifier: "roulette-source-picker"
                    )
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
    let photos: [PhotoAsset]
    let onApply: (Set<String>, RouletteCandidateSource, [RouletteCandidate]) -> Void
    let onAddCustom: () -> Void
    @State private var query = ""
    @State private var temporaryName = ""
    @State private var temporaryMessage = ""
    @State private var temporaryCandidates: [RouletteCandidate]
    @State private var source: RouletteCandidateSource
    @State private var selectedGlobalKeys: Set<String>

    init(
        candidates: [RouletteCandidate],
        temporaryCandidates: [RouletteCandidate],
        photos: [PhotoAsset],
        initialSource: RouletteCandidateSource,
        initialSelectedGlobalKeys: Set<String>,
        onApply: @escaping (Set<String>, RouletteCandidateSource, [RouletteCandidate]) -> Void,
        onAddCustom: @escaping () -> Void
    ) {
        self.candidates = candidates
        self.photos = photos
        self.onApply = onApply
        self.onAddCustom = onAddCustom
        _temporaryCandidates = State(initialValue: temporaryCandidates)
        _source = State(initialValue: initialSource)
        _selectedGlobalKeys = State(initialValue: initialSelectedGlobalKeys)
    }

    private var allCandidates: [RouletteCandidate] {
        candidates + temporaryCandidates
    }

    private var visible: [RouletteCandidate] {
        let sourceFiltered = candidates.filter {
            switch source {
            case .all: true
            case .wantToGo: $0.status == .wantToGo
            case .visited: $0.status == .visited
            }
        } + temporaryCandidates
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return sourceFiltered
        }
        return sourceFiltered.filter {
            [$0.displayName, $0.city, $0.address]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TasteMapSegmentedControl(
                        selection: $source,
                        items: RouletteCandidateSource.allCases.map {
                            .init($0, title: $0.title)
                        },
                        accessibilityIdentifier: "roulette-manager-source"
                    )
                }
                Section("添加自定义餐厅") {
                    HStack(spacing: 10) {
                        TextField("输入自定义餐厅名称", text: $temporaryName)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                            .onSubmit(addTemporaryCandidate)
                            .accessibilityIdentifier("roulette-custom-candidate-name")
                        Button("添加", action: addTemporaryCandidate)
                            .font(.subheadline.weight(.semibold))
                            .disabled(
                                temporaryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || selectedCount >= RestaurantRouletteEngine.maximumActiveCandidateCount
                            )
                            .accessibilityLabel("添加自定义餐厅到候选")
                            .accessibilityIdentifier("roulette-add-temporary-candidate")
                    }
                    if !temporaryMessage.isEmpty {
                        Text(temporaryMessage)
                            .font(.caption)
                            .foregroundStyle(RouletteTheme.muted)
                            .accessibilityIdentifier("roulette-custom-candidate-message")
                    }
                }
                Section {
                    ForEach(visible) { candidate in
                        Toggle(isOn: includedBinding(candidate)) {
                            HStack(spacing: 10) {
                                RouletteCandidateAvatar(
                                    candidate: candidate,
                                    photos: photos,
                                    diameter: 38
                                )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(candidate.displayName).font(.headline)
                                    Text(candidate.isTemporary
                                        ? "临时候选 · 不会创建餐厅记录"
                                        : [candidate.status.title, candidate.city].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(RouletteTheme.muted)
                                }
                            }
                        }
                        .disabled(
                            !selectedGlobalKeys.contains(candidate.globalKey)
                                && selectedCount >= RestaurantRouletteEngine.maximumActiveCandidateCount
                        )
                        .accessibilityHint(
                            !selectedGlobalKeys.contains(candidate.globalKey)
                                && selectedCount >= RestaurantRouletteEngine.maximumActiveCandidateCount
                                ? "最多选择 10 家餐厅"
                                : ""
                        )
                        .accessibilityIdentifier("roulette-candidate-toggle-\(candidate.globalKey)")
                    }
                } header: {
                    Text("已选 \(selectedCount) / \(RestaurantRouletteEngine.maximumActiveCandidateCount) · 每家对应一个轮盘扇区")
                }
                Section {
                    Button("创建正式餐厅记录", systemImage: "plus") {
                        dismiss()
                        onAddCustom()
                    }
                    .accessibilityIdentifier("roulette-create-restaurant")
                } footer: {
                    Text("只有需要地址、地图身份和餐厅详情时，才进入正式手动添加流程。")
                }
            }
            .searchable(text: $query, prompt: "搜索我的餐厅")
            .navigationTitle("管理候选餐厅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用当前结果") {
                        onApply(selectedGlobalKeys, source, temporaryCandidates)
                        dismiss()
                    }
                    .accessibilityIdentifier("roulette-apply-candidates")
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(selectedCount == 0 ? "选择前 10 家" : "清空选择") {
                        if selectedCount == 0 {
                            let sourceCandidates = candidates.filter {
                                source == .all
                                    || (source == .wantToGo && $0.status == .wantToGo)
                                    || (source == .visited && $0.status == .visited)
                            }
                            selectedGlobalKeys = RestaurantRouletteEngine.defaultActiveGlobalKeys(
                                from: sourceCandidates
                            )
                        } else {
                            selectedGlobalKeys.removeAll()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("最多 10 家")
                        .font(.caption)
                        .foregroundStyle(RouletteTheme.muted)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
    }

    private func includedBinding(_ candidate: RouletteCandidate) -> Binding<Bool> {
        Binding(
            get: { selectedGlobalKeys.contains(candidate.globalKey) },
            set: { included in
                if included,
                   selectedCount < RestaurantRouletteEngine.maximumActiveCandidateCount {
                    selectedGlobalKeys.insert(candidate.globalKey)
                } else if !included {
                    selectedGlobalKeys.remove(candidate.globalKey)
                }
            }
        )
    }

    private var selectedCount: Int {
        allCandidates.reduce(into: 0) { count, candidate in
            if selectedGlobalKeys.contains(candidate.globalKey) { count += 1 }
        }
    }

    private func addTemporaryCandidate() {
        let name = temporaryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard selectedCount < RestaurantRouletteEngine.maximumActiveCandidateCount else {
            temporaryMessage = "最多选择 10 家餐厅。"
            return
        }
        guard !allCandidates.contains(where: {
            $0.displayName.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else {
            temporaryMessage = "这家餐厅已经在候选池里了。"
            return
        }
        guard let candidate = RestaurantRouletteEngine.temporaryCandidate(name: name) else { return }
        temporaryCandidates.append(candidate)
        selectedGlobalKeys.insert(candidate.globalKey)
        query = ""
        temporaryName = ""
        temporaryMessage = "已将“\(name)”加入候选餐厅。"
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
    static let brand = TasteMapCoreTheme.brand
    static let brandDeep = TasteMapCoreTheme.brandDeep
    static let brandSoft = TasteMapCoreTheme.brandSoft
    static let canvas = TasteMapCoreTheme.page
    static let surface = TasteMapCoreTheme.surface
    static let ink = TasteMapCoreTheme.textPrimary
    static let muted = TasteMapCoreTheme.textSecondary
    // Wheel slices deliberately remain light in both appearances. Their text
    // therefore uses fixed dark ink instead of an adaptive label color.
    static let wheelInk = Color(red: 0.11, green: 0.17, blue: 0.22)
    static let wheelMuted = Color(red: 0.31, green: 0.39, blue: 0.45)
    static let leaf = Color(red: 0.27, green: 0.55, blue: 0.38)
    static let leafSoft = Color(red: 0.91, green: 0.96, blue: 0.92)
    static let cream = Color(red: 0.98, green: 0.94, blue: 0.84)
    static let caramel = Color(red: 0.68, green: 0.43, blue: 0.24)
    static let sliceColors: [Color] = [
        Color(red: 220 / 255, green: 229 / 255, blue: 237 / 255),
        Color(red: 215 / 255, green: 227 / 255, blue: 223 / 255),
        Color(red: 240 / 255, green: 215 / 255, blue: 181 / 255),
        Color(red: 227 / 255, green: 221 / 255, blue: 232 / 255),
        Color(red: 222 / 255, green: 231 / 255, blue: 220 / 255),
        Color(red: 234 / 255, green: 219 / 255, blue: 210 / 255),
        Color(red: 220 / 255, green: 228 / 255, blue: 232 / 255),
        Color(red: 232 / 255, green: 224 / 255, blue: 207 / 255),
        Color(red: 215 / 255, green: 226 / 255, blue: 232 / 255),
        Color(red: 228 / 255, green: 218 / 255, blue: 223 / 255),
    ]
}
