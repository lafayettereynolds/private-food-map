import SwiftUI

enum PersonalRestaurantFilterFocus: String, Identifiable, Sendable {
    case all
    case sort
    case city
    case rating
    case price
    case visitCount
    case companion
    case cuisine
    case recommendationSource

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "筛选与排序"
        case .sort: "排序"
        case .city: "城市"
        case .rating: "评分"
        case .price: "消费"
        case .visitCount: "到访次数"
        case .companion: "饭搭子"
        case .cuisine: "菜系"
        case .recommendationSource: "推荐来源"
        }
    }
}

struct PersonalRestaurantFilterSheet: View {
    let options: PersonalRestaurantFilterOptions
    let locationDenied: Bool
    let hasCurrentLocation: Bool
    let onApply: (PersonalRestaurantFilterState) -> Void
    let focus: PersonalRestaurantFilterFocus

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PersonalRestaurantFilterState

    init(
        state: PersonalRestaurantFilterState,
        options: PersonalRestaurantFilterOptions,
        locationDenied: Bool,
        hasCurrentLocation: Bool,
        focus: PersonalRestaurantFilterFocus = .all,
        onApply: @escaping (PersonalRestaurantFilterState) -> Void
    ) {
        self.options = options
        self.locationDenied = locationDenied
        self.hasCurrentLocation = hasCurrentLocation
        self.focus = focus
        self.onApply = onApply
        _draft = State(initialValue: state)
    }

    var body: some View {
        NavigationStack {
            Form {
                if focus == .all || focus == .sort { sortSection }
                if focus == .all || focus == .rating { ratingSection }
                if draft.appliesVisitScopedFilters {
                    if focus == .all { diningModeSection }
                    if focus == .all || focus == .visitCount { visitCountSection }
                    if focus == .all || focus == .price { priceSection }
                    if focus == .all { queueSection }
                    if focus == .all { occasionSection }
                    if focus == .all || focus == .recommendationSource { sourceSection }
                    if focus == .all { periodSection }
                    if focus == .all || focus == .companion { companionSection }
                }
                if focus == .all || focus == .cuisine { cuisineSection }
                if focus == .all || focus == .city { citySection }
                if focus == .all { distanceSection }
            }
            .navigationTitle(
                focus == .all && draft.activeFilterCount > 0
                    ? "筛选（\(draft.activeFilterCount)）"
                    : focus.title
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("重置") { resetFocusedValue() }
                        .disabled(!focusedValueIsActive)
                        .accessibilityIdentifier("personal-filter-reset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        onApply(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("personal-filter-apply")
                }
            }
        }
    }

    private var sortSection: some View {
        Section("排序") {
            TasteMapSegmentedControl(
                selection: $draft.sort,
                items: PersonalRestaurantSort.allCases.map {
                    .init($0, title: $0.title)
                },
                accessibilityIdentifier: "personal-filter-sort"
            )
        }
    }

    private var ratingSection: some View {
        Section {
            PersonalFilterChipGrid {
                filterChip("全部", selected: draft.ratingBands.isEmpty, identifier: "personal-filter-rating-all") {
                    draft.ratingBands.removeAll()
                }
                ForEach(PersonalRatingBand.allCases.reversed()) { band in
                    filterChip(
                        band.title,
                        selected: draft.ratingBands.contains(band),
                        identifier: "personal-filter-rating-\(band.rawValue)"
                    ) {
                        if draft.ratingBands.contains(band) { draft.ratingBands.remove(band) }
                        else { draft.ratingBands.insert(band) }
                    }
                }
            }
        } header: {
            Text("评分区间 · 可多选")
        } footer: {
            Text("仅统计真实且非空的到访评分；未评分不会被当作 0 分。")
        }
    }

    private var diningModeSection: some View {
        Section("用餐方式") {
            PersonalFilterChipGrid {
                filterChip("全部", selected: draft.diningMode == nil, identifier: "personal-filter-dining-all") {
                    draft.diningMode = nil
                }
                ForEach(DiningMode.allCases) { mode in
                    filterChip(
                        mode.title,
                        selected: draft.diningMode == mode,
                        identifier: "personal-filter-dining-\(mode.rawValue)"
                    ) { draft.diningMode = draft.diningMode == mode ? nil : mode }
                }
            }
        }
    }

    private var visitCountSection: some View {
        Section("到访次数") {
            PersonalFilterChipGrid {
                filterChip("全部", selected: draft.visitCount == nil, identifier: "personal-filter-count-all") {
                    draft.visitCount = nil
                }
                ForEach(PersonalVisitCountFilter.allCases) { count in
                    filterChip(
                        count.title,
                        selected: draft.visitCount == count,
                        identifier: "personal-filter-count-\(count.rawValue)"
                    ) { draft.visitCount = draft.visitCount == count ? nil : count }
                }
            }
        }
    }

    private var priceSection: some View {
        Section {
            PersonalFilterChipGrid {
                filterChip("全部", selected: draft.priceRange == nil, identifier: "personal-filter-price-all") {
                    draft.priceRange = nil
                }
                ForEach(PersonalPriceRange.allCases) { range in
                    filterChip(
                        range.title,
                        selected: draft.priceRange == range,
                        identifier: "personal-filter-price-\(range.rawValue)"
                    ) { draft.priceRange = draft.priceRange == range ? nil : range }
                }
            }
        } header: {
            Text("人均价格")
        } footer: {
            Text("沿用 Web 正式语义：匹配单次到访记录的人均价格，不混入“我的实际消费”。")
        }
    }

    private var queueSection: some View {
        Section("等待时长") {
            PersonalFilterChipGrid {
                filterChip("全部", selected: draft.queue == nil, identifier: "personal-filter-queue-all") {
                    draft.queue = nil
                }
                ForEach(VisitQueueDuration.allCases) { value in
                    let filter = PersonalQueueFilter.recorded(value)
                    filterChip(
                        value.title,
                        selected: draft.queue == filter,
                        identifier: "personal-filter-queue-\(value.rawValue)"
                    ) { draft.queue = draft.queue == filter ? nil : filter }
                }
                filterChip(
                    "未记录",
                    selected: draft.queue == .unrecorded,
                    identifier: "personal-filter-queue-unrecorded"
                ) { draft.queue = draft.queue == .unrecorded ? nil : .unrecorded }
            }
        }
    }

    private var occasionSection: some View {
        Section("适合场景 · 可多选") {
            PersonalFilterChipGrid {
                filterChip("全部", selected: draft.diningOccasions.isEmpty, identifier: "personal-filter-occasion-all") {
                    draft.diningOccasions.removeAll()
                }
                ForEach(VisitDiningOccasion.allCases) { occasion in
                    filterChip(
                        occasion.title,
                        selected: draft.diningOccasions.contains(occasion),
                        identifier: "personal-filter-occasion-\(occasion.rawValue)"
                    ) {
                        if draft.diningOccasions.contains(occasion) { draft.diningOccasions.remove(occasion) }
                        else { draft.diningOccasions.insert(occasion) }
                    }
                }
            }
        }
    }

    private var sourceSection: some View {
        Section("推荐来源") {
            optionPicker(
                title: "推荐来源",
                allTitle: "全部来源",
                selection: $draft.sourceID,
                options: options.sources,
                identifier: "personal-filter-source"
            )
        }
    }

    private var periodSection: some View {
        Section("到访时间") {
            PersonalFilterChipGrid {
                filterChip("不限", selected: draft.visitPeriod == nil, identifier: "personal-filter-period-all") {
                    draft.visitPeriod = nil
                }
                ForEach(PersonalVisitPeriod.allCases) { period in
                    filterChip(
                        period.title,
                        selected: draft.visitPeriod == period,
                        identifier: "personal-filter-period-\(period.rawValue)"
                    ) { draft.visitPeriod = draft.visitPeriod == period ? nil : period }
                }
            }
        }
    }

    private var companionSection: some View {
        Section {
            optionPicker(
                title: "饭搭子",
                allTitle: "全部饭搭子",
                selection: $draft.companionID,
                options: options.companions,
                identifier: "personal-filter-companion"
            )
        } header: {
            Text("饭搭子")
        } footer: {
            Text("这里使用你的私人饭搭子记录，不把姓名当作社交用户身份。")
        }
    }

    @ViewBuilder
    private var cuisineSection: some View {
        if !options.cuisines.isEmpty {
            Section("菜系") {
                Picker("菜系", selection: optionalString($draft.cuisine)) {
                    Text("全部菜系").tag("")
                    ForEach(options.cuisines, id: \.self) { Text($0).tag($0) }
                }
                .accessibilityIdentifier("personal-filter-cuisine")
            }
        }
    }

    @ViewBuilder
    private var citySection: some View {
        if !options.cities.isEmpty {
            Section("城市") {
                Picker("城市", selection: optionalString($draft.city)) {
                    Text("全部城市").tag("")
                    ForEach(options.cities, id: \.self) { Text($0).tag($0) }
                }
                .accessibilityIdentifier("personal-filter-city")
            }
        }
    }

    private var distanceSection: some View {
        Section {
            PersonalFilterChipGrid {
                filterChip("不限", selected: draft.distance == nil, identifier: "personal-filter-distance-all") {
                    draft.distance = nil
                }
                ForEach(PersonalDistanceFilter.allCases) { distance in
                    filterChip(
                        distance.title,
                        selected: draft.distance == distance,
                        identifier: "personal-filter-distance-\(distance.rawValue)",
                        disabled: locationDenied
                    ) { draft.distance = draft.distance == distance ? nil : distance }
                }
            }
        } header: {
            Text("距离")
        } footer: {
            if locationDenied {
                Text("定位权限未开启，距离筛选不可用；其他筛选仍可正常使用。")
            } else if !hasCurrentLocation {
                Text("应用距离筛选时会获取一次当前位置。")
            } else {
                Text("距离以当前设备位置为基准，仅计算具有合法坐标的餐厅。")
            }
        }
    }

    private func optionPicker(
        title: String,
        allTitle: String,
        selection: Binding<String?>,
        options: [PersonalFilterOption],
        identifier: String
    ) -> some View {
        Picker(title, selection: optionalString(selection)) {
            Text(allTitle).tag("")
            ForEach(options) { Text($0.title).tag($0.id) }
        }
        .accessibilityIdentifier(identifier)
    }

    private func optionalString(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }

    private var focusedValueIsActive: Bool {
        switch focus {
        case .all: draft.activeFilterCount > 0 || draft.sort != .comprehensive
        case .sort: draft.sort != .comprehensive
        case .city: draft.city != nil
        case .rating: !draft.ratingBands.isEmpty
        case .price: draft.priceRange != nil
        case .visitCount: draft.visitCount != nil
        case .companion: draft.companionID != nil
        case .cuisine: draft.cuisine != nil
        case .recommendationSource: draft.sourceID != nil
        }
    }

    private func resetFocusedValue() {
        switch focus {
        case .all: draft.resetKeepingStatus()
        case .sort: draft.sort = .comprehensive
        case .city: draft.city = nil
        case .rating: draft.ratingBands.removeAll()
        case .price: draft.priceRange = nil
        case .visitCount: draft.visitCount = nil
        case .companion: draft.companionID = nil
        case .cuisine: draft.cuisine = nil
        case .recommendationSource: draft.sourceID = nil
        }
    }

    private func filterChip(
        _ title: String,
        selected: Bool,
        identifier: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 34)
                .padding(.horizontal, 8)
                .background(selected ? Color.accentColor : Color(uiColor: .secondarySystemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

private struct PersonalFilterChipGrid<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            content
        }
        .padding(.vertical, 3)
    }
}

#Preview("个人筛选") {
    PersonalRestaurantFilterSheet(
        state: PersonalRestaurantFilterState(status: .visited),
        options: PersonalRestaurantFilterOptions(
            cities: ["杭州", "上海"],
            cuisines: ["日料", "江浙菜"],
            companions: [.init(id: "companion:小林", title: "小林")],
            sources: [.init(id: "source:朋友推荐", title: "朋友推荐")]
        ),
        locationDenied: false,
        hasCurrentLocation: true,
        onApply: { _ in }
    )
}
