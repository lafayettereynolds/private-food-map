import CoreLocation
import MapKit
import SwiftData
import SwiftUI

@MainActor
struct RestaurantAcquisitionDependencies {
    let searchService: any RestaurantSearching
    let linkResolver: any ExternalRestaurantLinkResolving
    let locationProvider: any RestaurantLocationProviding

    static func live(linkResolver: any ExternalRestaurantLinkResolving) -> Self {
        Self(
            searchService: MapKitRestaurantSearchService(),
            linkResolver: linkResolver,
            locationProvider: LocationPermissionManager()
        )
    }
}

struct AddRestaurantView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.localAccountScope) private var accountScope
    @Query private var restaurants: [Restaurant]
    @StateObject private var viewModel: RestaurantAcquisitionViewModel
    @AppStorage("taste-map-last-search-city") private var city = ""
    @State private var query = ""
    @State private var manualPresented = false
    @State private var selectedCandidate: RestaurantAcquisitionSelection?
    @State private var pendingManualCandidate: RestaurantCandidate?
    @State private var cityEdited = false
    @State private var actionError: String?
    @State private var initialManualEntryPresented = false

    private let initialSharedText: String?
    private let startsWithManualEntry: Bool
    private let onCandidateSelected: ((RestaurantCandidate) throws -> Void)?
    let onAction: (RestaurantCandidate, RestaurantSearchAction) throws -> Void

    private var scopedRestaurants: [Restaurant] {
        restaurants.filter { accountScope.contains(ownerUserID: $0.ownerUserID) }
    }

    init(
        dependencies: RestaurantAcquisitionDependencies,
        initialSharedText: String? = nil,
        startsWithManualEntry: Bool = false,
        onCandidateSelected: ((RestaurantCandidate) throws -> Void)? = nil,
        onAction: @escaping (RestaurantCandidate, RestaurantSearchAction) throws -> Void
    ) {
        _viewModel = StateObject(wrappedValue: RestaurantAcquisitionViewModel(
            searchService: dependencies.searchService,
            linkResolver: dependencies.linkResolver,
            locationProvider: dependencies.locationProvider
        ))
        self.initialSharedText = initialSharedText
        self.startsWithManualEntry = startsWithManualEntry
        self.onCandidateSelected = onCandidateSelected
        self.onAction = onAction
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if hasSharedImport { sharedImportSection }
                    searchSection
                    if !viewModel.hasSearched { nearbySection }
                    manualEntry
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AcquisitionPalette.page.ignoresSafeArea())
            .navigationTitle("添加餐厅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .task {
                if startsWithManualEntry, !initialManualEntryPresented {
                    initialManualEntryPresented = true
                    manualPresented = true
                }
                guard viewModel.nearbyState == .idle else { return }
                await viewModel.loadNearby()
                if !cityEdited, let detectedCity = viewModel.detectedCity {
                    city = detectedCity
                }
                if !(initialSharedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
                   viewModel.linkResults.isEmpty,
                   viewModel.linkMessage == nil {
                    await viewModel.resolveLink(initialSharedText ?? "", city: city)
                }
            }
            .onChange(of: viewModel.detectedCity) { _, detectedCity in
                if !cityEdited, let detectedCity {
                    city = detectedCity
                }
            }
            .onChange(of: scenePhase) { previous, value in
                guard value == .active, previous != .active, viewModel.nearbyState != .idle else { return }
                Task { await viewModel.refreshAfterForeground() }
            }
            .sheet(isPresented: $manualPresented, onDismiss: presentPendingManualCandidate) {
                ManualRestaurantAddView(
                    viewModel: viewModel,
                    initialCity: city,
                    restaurants: scopedRestaurants,
                    onCityChanged: { value in
                        cityEdited = true
                        city = value
                    },
                    onSelect: { candidate in pendingManualCandidate = candidate }
                )
            }
            .sheet(item: $selectedCandidate) { candidate in
                RestaurantCandidateConfirmationView(acquisition: candidate, onAction: perform)
            }
            .alert("无法添加餐厅", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("好", role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "请稍后重试。")
            }
        }
        .tint(AcquisitionPalette.brand)
    }

    private var hasSharedImport: Bool {
        !(initialSharedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private var nearbySection: some View {
        AcquisitionSection(title: "附近餐厅", subtitle: "当前位置 3 公里内", systemImage: "location.fill") {
            switch viewModel.nearbyState {
            case .idle, .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在寻找附近的真实餐厅…")
                        .font(.subheadline)
                        .foregroundStyle(AcquisitionPalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
            case .locationDenied:
                AcquisitionMessage(
                    icon: "location.slash",
                    title: "没有定位权限也可以添加",
                    message: "输入城市继续搜索，或者使用链接和手动添加。定位不是前置条件。",
                    retryTitle: nil,
                    retry: nil
                )
            case .failed(let message):
                AcquisitionMessage(
                    icon: "location.slash",
                    title: "附近餐厅暂时不可用",
                    message: message,
                    retryTitle: "重试定位",
                    retry: { Task { await viewModel.loadNearby() } }
                )
            case .loaded:
                if viewModel.locationAccuracy == .reduced {
                    AcquisitionMessage(
                        icon: "location.circle",
                        title: "当前为大致位置",
                        message: "系统只提供了有限精度定位，附近结果可能有明显偏差。可在系统设置中为 Taste Map 开启精确位置后重新定位。",
                        retryTitle: "重新定位",
                        retry: { Task { await viewModel.loadNearby() } }
                    )
                }
                if viewModel.nearbyResults.isEmpty {
                    AcquisitionMessage(
                        icon: "mappin.slash",
                        title: "附近暂时没有结果",
                        message: "可以扩大范围按城市搜索，或手动添加地图上搜不到的小店。",
                        retryTitle: "重新定位",
                        retry: { Task { await viewModel.loadNearby() } }
                    )
                } else {
                    ForEach(viewModel.nearbyResults.prefix(8)) { candidate in
                        RestaurantAcquisitionCandidateRow(
                            candidate: candidate,
                            match: RestaurantDeduplicator.classifiedMatch(for: candidate, in: scopedRestaurants),
                            onSelect: select
                        )
                    }
                    Text(viewModel.locationAccuracy == .reduced
                         ? "以上餐厅按当前大致位置计算距离。"
                         : "以上餐厅按当前 GPS 坐标计算，并由近到远排序。")
                        .font(.caption)
                        .foregroundStyle(AcquisitionPalette.muted)
                }
            }
        }
    }

    private var searchSection: some View {
        AcquisitionSection(title: "搜索餐厅", subtitle: "名称、地址与城市范围", systemImage: "magnifyingglass") {
            VStack(alignment: .leading, spacing: 7) {
                Text("餐厅名称或地址")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AcquisitionPalette.muted)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AcquisitionPalette.brand)
                    TextField("例如：寿喜烧、南京西路", text: $query)
                        .submitLabel(.search)
                        .accessibilityIdentifier("restaurant-query-field")
                        .onChange(of: query) { _, value in
                            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                viewModel.clearSearch()
                            }
                        }
                        .onSubmit { Task { await viewModel.search(query: query, city: city) } }
                    if !query.isEmpty {
                        Button {
                            query = ""
                            viewModel.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AcquisitionPalette.muted)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除餐厅搜索")
                    }
                }
                .acquisitionInput()

                if let label = viewModel.currentLocationLabel {
                    Label(label, systemImage: "location.circle")
                        .font(.caption)
                        .foregroundStyle(AcquisitionPalette.muted)
                        .lineLimit(2)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("搜索城市")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AcquisitionPalette.muted)
                HStack(spacing: 10) {
                    Image(systemName: "building.2")
                        .foregroundStyle(AcquisitionPalette.brand)
                    TextField("例如：杭州、上海、东京、纽约", text: Binding(
                        get: { city },
                        set: { value in
                            cityEdited = true
                            city = value
                        }
                    ))
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("restaurant-city-field")
                }
                .acquisitionInput()
            }

            Button {
                Task { await viewModel.search(query: query, city: city) }
            } label: {
                HStack {
                    if viewModel.isSearching { ProgressView().tint(.white) }
                    else { Image(systemName: "magnifyingglass") }
                    Text(viewModel.isSearching ? "正在搜索" : "搜索餐厅")
                }
                .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.borderedProminent)
            .tint(AcquisitionPalette.brand)
            .disabled(viewModel.isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("restaurant-search-submit")

            if let message = viewModel.searchMessage {
                AcquisitionMessage(icon: "magnifyingglass", title: "搜索结果", message: message, retryTitle: nil, retry: nil)
            }
            ForEach(viewModel.searchResults) { candidate in
                RestaurantAcquisitionCandidateRow(
                    candidate: candidate,
                    match: RestaurantDeduplicator.classifiedMatch(for: candidate, in: scopedRestaurants),
                    onSelect: select
                )
            }
        }
    }

    private var sharedImportSection: some View {
        AcquisitionSection(title: "来自外部分享", subtitle: "Taste Map 正在识别餐厅与位置", systemImage: "square.and.arrow.down") {
            if viewModel.isResolvingLink {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在读取分享内容…")
                        .font(.subheadline)
                        .foregroundStyle(AcquisitionPalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            if let message = viewModel.linkMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AcquisitionPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(viewModel.linkResults) { candidate in
                RestaurantAcquisitionCandidateRow(
                    candidate: candidate,
                    match: RestaurantDeduplicator.classifiedMatch(for: candidate, in: scopedRestaurants),
                    onSelect: select
                )
            }
        }
        .accessibilityIdentifier("shared-restaurant-import")
    }

    private var manualEntry: some View {
        AcquisitionMethodButton(
            icon: "storefront",
            title: "手动添加餐厅",
            subtitle: "适合地图上搜不到的小摊、快闪店、私房店和新开门店"
        ) { manualPresented = true }
        .padding(12)
        .acquisitionCard()
        .accessibilityIdentifier("open-manual-restaurant")
    }

    private func select(_ candidate: RestaurantCandidate, match: RestaurantDeduplicator.Match?) {
        if let onCandidateSelected {
            do {
                try onCandidateSelected(candidate)
            } catch {
                actionError = "无法打开餐厅详情，请重试。"
            }
            return
        }
        selectedCandidate = RestaurantAcquisitionSelection(candidate: candidate, match: match)
    }

    private func presentPendingManualCandidate() {
        guard let pendingManualCandidate else { return }
        self.pendingManualCandidate = nil
        select(pendingManualCandidate, match: nil)
    }

    private func perform(_ candidate: RestaurantCandidate, _ action: RestaurantSearchAction) {
        do {
            try onAction(candidate, action)
            dismiss()
        } catch {
            actionError = "餐厅先保存在本地时出现问题，请重试。"
        }
    }
}

private struct RestaurantAcquisitionSelection: Identifiable {
    let candidate: RestaurantCandidate
    let match: RestaurantDeduplicator.Match?
    var id: UUID { candidate.id }
}

private struct RestaurantCandidateConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    let acquisition: RestaurantAcquisitionSelection
    let onAction: (RestaurantCandidate, RestaurantSearchAction) -> Void
    @State private var selection: Selection = .visited
    @State private var confirmedProbableMatch = false

    private var candidate: RestaurantCandidate { acquisition.candidate }
    private var dedupeMatch: RestaurantDeduplicator.Match? { acquisition.match }

    private enum Selection: String, CaseIterable, Identifiable {
        case visited = "我去过"
        case wantToGo = "我想去"
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                RestaurantDetailStandardBody {
                    RestaurantCandidateHero(candidate: candidate)
                } header: {
                    RestaurantDetailHeader(identity: RestaurantDetailIdentityPresentation(
                        name: candidate.name,
                        address: candidate.address,
                        city: candidate.city,
                        status: nil
                    ))
                } actions: {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("保存到 Taste Map")
                            .font(.headline)

                        if let dedupeMatch {
                            RestaurantCandidateDedupeNotice(
                                restaurant: dedupeMatch.restaurant,
                                kind: dedupeMatch.kind,
                                confirmed: $confirmedProbableMatch
                            )
                        }

                        TasteMapSegmentedControl(
                            selection: $selection,
                            items: Selection.allCases.map {
                                .init($0, title: $0.rawValue)
                            },
                            accessibilityIdentifier: "restaurant-status-selection"
                        )

                        AcquisitionMessage(
                            icon: selection == .visited ? "fork.knife" : "bookmark",
                            title: selection == .visited ? "记录这次体验" : "加入想吃清单",
                            message: selection == .visited
                                ? "继续后填写日期、评分、消费、菜品和照片。"
                                : "先保存餐厅，之后到访时再补充完整记录。",
                            retryTitle: nil,
                            retry: nil
                        )

                        Button {
                            onAction(candidate, selection == .visited ? .recordVisit : .wantToGo)
                        } label: {
                            Label(
                                actionTitle,
                                systemImage: selection == .visited ? "fork.knife" : "bookmark.fill"
                            )
                            .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AcquisitionPalette.brand)
                        .disabled(requiresProbableMatchConfirmation && !confirmedProbableMatch)
                        .accessibilityIdentifier("confirm-restaurant-selection")
                    }
                    .padding(18)
                    .tasteMapCoreCard(radius: 22)
                } business: {
                    RestaurantCandidateBusinessSection(candidate: candidate)
                } location: {
                    RestaurantLocationSection(
                        candidate: candidate,
                        onOpenAppleMaps: openAppleMaps
                    )
                } ratings: {
                    RestaurantCandidateUnavailableSection(
                        title: "评分参考",
                        systemImage: "star.circle",
                        message: "地图来源暂未提供可信评分；Taste Map 不会用假评分填充。"
                    )
                } userPhotos: {
                    RestaurantUserPhotosSection(hasPhotos: false) { EmptyView() }
                } personalOverview: {
                    EmptyView()
                } history: {
                    EmptyView()
                } context: {
                    EmptyView()
                } extended: {
                    EmptyView()
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(AcquisitionPalette.page.ignoresSafeArea())
            .navigationTitle("确认餐厅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回") { dismiss() }
                }
            }
        }
        .tint(AcquisitionPalette.brand)
        .accessibilityIdentifier("restaurant-acquisition-preview")
    }

    private var requiresProbableMatchConfirmation: Bool {
        dedupeMatch?.kind == .probableCrossProvider
    }

    private var actionTitle: String {
        let prefix = requiresProbableMatchConfirmation ? "确认合并并" : ""
        return prefix + (selection == .visited ? "继续记录到访" : "保存到我的地图")
    }

    private func openAppleMaps() {
        let coordinate = CLLocationCoordinate2D(
            latitude: candidate.latitude,
            longitude: candidate.longitude
        )
        let mapItem: MKMapItem
        if #available(iOS 26.0, *) {
            mapItem = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        } else {
            mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        }
        mapItem.name = candidate.name
        mapItem.openInMaps()
    }
}

private struct RestaurantCandidateHero: View {
    let candidate: RestaurantCandidate

    var body: some View {
        TasteMapRestaurantImage(
            resolution: RestaurantImagePriorityPolicy.resolution(
                localUserPhotoID: nil,
                providerMerchantImageURL: candidate.photoURL
            ),
            semanticID: candidate.id.uuidString,
            variant: .display,
            fallbackForegroundColor: AcquisitionPalette.brandDeep,
            fallbackBackgroundColor: AcquisitionPalette.brandSoft,
            fallbackIconSize: 62,
            accessibilityLabel: "\(candidate.name)餐厅图片"
        )
        .frame(maxWidth: .infinity)
        .frame(height: 216)
        .background(AcquisitionPalette.brandSoft)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipped()
        .accessibilityIdentifier("restaurant-photo-gallery")
    }

}

private struct RestaurantCandidateBusinessSection: View {
    let candidate: RestaurantCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("餐厅信息")
                .font(.headline)
                .padding(.bottom, 8)
                .accessibilityIdentifier("restaurant-business-information")
            candidateRow(title: "参考人均", value: "地图来源暂未提供", icon: "yensign.circle")
            Divider().padding(.leading, 34)
            candidateRow(title: "电话", value: candidate.phone ?? "地图来源暂未提供", icon: "phone")
            Divider().padding(.leading, 34)
            candidateRow(title: "营业时间", value: candidate.openingHours ?? "地图来源暂未提供", icon: "clock")
        }
        .padding(14)
        .tasteMapCoreCard(radius: 16)
    }

    private func candidateRow(title: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AcquisitionPalette.brand)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(AcquisitionPalette.muted)
                Text(value).font(.subheadline).foregroundStyle(AcquisitionPalette.ink)
            }
        }
        .padding(.vertical, 7)
    }
}

private struct RestaurantCandidateUnavailableSection: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(AcquisitionPalette.brand)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(AcquisitionPalette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .tasteMapCoreCard(radius: 22)
        .accessibilityIdentifier("restaurant-rating-references")
    }
}

private struct RestaurantCandidateDedupeNotice: View {
    let restaurant: Restaurant
    let kind: RestaurantDeduplicator.MatchKind
    @Binding var confirmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(
                kind == .exactProviderIdentity ? "已匹配现有餐厅" : "可能是同一家餐厅",
                systemImage: kind == .exactProviderIdentity ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
            )
            .font(.subheadline.weight(.semibold))
            Text("Taste Map 中已有：\(restaurant.name)")
                .font(.caption)
                .foregroundStyle(AcquisitionPalette.muted)
            if kind == .probableCrossProvider {
                Toggle("我确认这是同一家餐厅", isOn: $confirmed)
                    .font(.subheadline)
                    .accessibilityIdentifier("confirm-probable-restaurant-match")
            }
        }
        .padding(12)
        .background(AcquisitionPalette.brandSoft, in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct ManualRestaurantAddView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: RestaurantAcquisitionViewModel
    let initialCity: String
    let restaurants: [Restaurant]
    let onCityChanged: (String) -> Void
    let onSelect: (RestaurantCandidate) -> Void

    @State private var name = ""
    @State private var city: String
    @State private var address = ""
    @State private var selectedCoordinate: RestaurantCoordinate?
    @State private var cameraPosition: MapCameraPosition
    @State private var isResolvingAddress = false
    @State private var message: String?
    private let candidateID = UUID()

    init(
        viewModel: RestaurantAcquisitionViewModel,
        initialCity: String,
        restaurants: [Restaurant],
        onCityChanged: @escaping (String) -> Void,
        onSelect: @escaping (RestaurantCandidate) -> Void
    ) {
        self.viewModel = viewModel
        self.initialCity = initialCity
        self.restaurants = restaurants
        self.onCityChanged = onCityChanged
        self.onSelect = onSelect
        _city = State(initialValue: initialCity)
        if let center = viewModel.currentCoordinate {
            _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                latitudinalMeters: 12_000,
                longitudinalMeters: 12_000
            )))
        } else {
            _cameraPosition = State(initialValue: .automatic)
        }
    }

    private var candidate: RestaurantCandidate? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let selectedCoordinate else { return nil }
        return .manual(
            id: candidateID,
            name: name,
            city: city,
            address: address,
            coordinate: selectedCoordinate
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AcquisitionMessage(
                        icon: "storefront",
                        title: "手动添加小店",
                        message: "名称、城市和地图位置是必要信息；地址可以留空。手动餐厅不需要 Apple Maps ID。",
                        retryTitle: nil,
                        retry: nil
                    )
                    labeledField("小店 / 摊位名称", placeholder: "例如：阿婆葱包桧小摊", text: $name, identifier: "manual-restaurant-name")
                    labeledField("城市", placeholder: "例如：杭州", text: $city, identifier: "manual-restaurant-city")
                    labeledField("地址或附近地标（可选）", placeholder: "例如：武林路 32 号门口", text: $address, identifier: "manual-restaurant-address")

                    HStack(spacing: 10) {
                        Button {
                            Task { await useCurrentLocation() }
                        } label: {
                            Label("使用当前位置", systemImage: "location.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("manual-use-current-location")

                        Button {
                            Task { await locateAddress() }
                        } label: {
                            if isResolvingAddress { ProgressView().frame(maxWidth: .infinity, minHeight: 44) }
                            else { Label("按地址定位", systemImage: "mappin.and.ellipse").frame(maxWidth: .infinity, minHeight: 44) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isResolvingAddress || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("manual-locate-address")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("地图位置")
                            .font(.headline)
                            .foregroundStyle(AcquisitionPalette.ink)
                        Text(selectedCoordinate == nil ? "点击地图选择小店位置" : "已选择位置，可以继续添加")
                            .font(.caption)
                            .foregroundStyle(AcquisitionPalette.muted)
                        MapReader { proxy in
                            Map(position: $cameraPosition) {
                                if let selectedCoordinate {
                                    Marker(
                                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "手动餐厅" : name,
                                        coordinate: CLLocationCoordinate2D(
                                            latitude: selectedCoordinate.latitude,
                                            longitude: selectedCoordinate.longitude
                                        )
                                    )
                                }
                            }
                            .onTapGesture { point in
                                guard let value = proxy.convert(point, from: .local) else { return }
                                selectedCoordinate = RestaurantCoordinate(
                                    latitude: value.latitude,
                                    longitude: value.longitude
                                )
                                message = nil
                            }
                        }
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay { RoundedRectangle(cornerRadius: 18).stroke(AcquisitionPalette.border) }
                        .accessibilityIdentifier("manual-restaurant-map")
                    }

                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(AcquisitionPalette.muted)
                    }

                    if let candidate {
                        let existing = RestaurantDeduplicator.match(for: candidate, in: restaurants)
                        if let existing {
                            Label("将复用已有餐厅：\(existing.name)", systemImage: "checkmark.circle.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AcquisitionPalette.brandDeep)
                        }
                        Button {
                            onCityChanged(city)
                            onSelect(candidate)
                            dismiss()
                        } label: {
                            Label(existing == nil ? "确认位置并继续" : "再次记录到访", systemImage: "checkmark")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AcquisitionPalette.brand)
                        .accessibilityIdentifier("manual-confirm-restaurant")
                    }
                }
                .padding(16)
            }
            .background(AcquisitionPalette.page.ignoresSafeArea())
            .navigationTitle("手动添加餐厅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
        .tint(AcquisitionPalette.brand)
    }

    private func labeledField(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(AcquisitionPalette.muted)
            TextField(placeholder, text: text)
                .acquisitionInput()
                .accessibilityIdentifier(identifier)
        }
    }

    private func useCurrentLocation() async {
        do {
            let (coordinate, context) = try await viewModel.requestCurrentCoordinate()
            selectedCoordinate = coordinate
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                latitudinalMeters: 1_500,
                longitudinalMeters: 1_500
            ))
            if city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let value = context?.city { city = value }
            if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let value = context?.address { address = value }
            message = "已定位到当前位置。保存前请确认地图标记。"
        } catch RestaurantLocationError.permissionDenied {
            message = "定位权限未开启。你仍可以点击地图选择位置。"
        } catch {
            message = "当前位置暂时不可用。你仍可以点击地图选择位置。"
        }
    }

    private func locateAddress() async {
        isResolvingAddress = true
        defer { isResolvingAddress = false }
        do {
            let coordinate = try await viewModel.resolveManualCoordinate(address: address, city: city)
            selectedCoordinate = coordinate
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                latitudinalMeters: 1_500,
                longitudinalMeters: 1_500
            ))
            message = "已找到地址位置，请在地图上确认。"
        } catch {
            message = "暂时无法定位这个地址。你可以直接点击地图选择位置。"
        }
    }
}

private struct RestaurantAcquisitionCandidateRow: View {
    let candidate: RestaurantCandidate
    let match: RestaurantDeduplicator.Match?
    let onSelect: (RestaurantCandidate, RestaurantDeduplicator.Match?) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            TasteMapRestaurantImage(
                resolution: RestaurantImagePriorityPolicy.resolution(
                    localUserPhotoID: nil,
                    providerMerchantImageURL: candidate.photoURL
                ),
                semanticID: candidate.id.uuidString,
                fallbackForegroundColor: AcquisitionPalette.brand,
                fallbackBackgroundColor: AcquisitionPalette.brandSoft,
                fallbackIconSize: 28,
                accessibilityLabel: "\(candidate.name)餐厅图片"
            )
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(candidate.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AcquisitionPalette.ink)
                        .lineLimit(2)
                    if let match {
                        Text(match.kind == .exactProviderIdentity ? "已在地图" : "可能重复")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(AcquisitionPalette.brandDeep)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(AcquisitionPalette.brandSoft, in: Capsule())
                    }
                }
                if !candidate.address.isEmpty {
                    Text(candidate.address)
                        .font(.caption)
                        .foregroundStyle(AcquisitionPalette.muted)
                        .lineLimit(1)
                }
                let location = [candidate.city, candidate.district].filter { !$0.isEmpty }.joined(separator: " · ")
                HStack(spacing: 6) {
                    if !location.isEmpty { Text(location) }
                    if let distance = candidate.distanceMeters {
                        Text(Self.distanceText(distance))
                            .foregroundStyle(AcquisitionPalette.brandDeep)
                    }
                }
                .font(.caption2)
                .foregroundStyle(AcquisitionPalette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onSelect(candidate, match)
            } label: {
                Text("查看")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 34)
                    .background(AcquisitionPalette.brand, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看并确认 \(candidate.name)")
            .accessibilityIdentifier("candidate-select-\(candidate.id.uuidString)")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 9)
        .background(AcquisitionPalette.surfaceSubtle, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(AcquisitionPalette.border) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("restaurant-candidate-\(candidate.id.uuidString)")
    }

    private static func distanceText(_ meters: Double) -> String {
        meters < 1_000 ? "\(Int(meters.rounded())) 米" : String(format: "%.1f 公里", meters / 1_000)
    }
}

private struct AcquisitionSection<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(AcquisitionPalette.brand)
                    .font(.caption.weight(.semibold))
                    .frame(width: 24, height: 24)
                    .background(AcquisitionPalette.brandSoft, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AcquisitionPalette.ink)
                    Text(subtitle).font(.caption2).foregroundStyle(AcquisitionPalette.muted)
                }
            }
            content
        }
        .padding(12)
        .acquisitionCard()
    }
}

private struct AcquisitionMessage: View {
    let icon: String
    let title: String
    let message: String
    let retryTitle: String?
    let retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(AcquisitionPalette.brand)
                .font(.caption.weight(.semibold))
                .frame(width: 26, height: 26)
                .background(AcquisitionPalette.brandSoft, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AcquisitionPalette.ink)
                Text(message).font(.caption).foregroundStyle(AcquisitionPalette.muted).fixedSize(horizontal: false, vertical: true)
                if let retryTitle, let retry {
                    Button(retryTitle, action: retry).font(.caption.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(AcquisitionPalette.surfaceSubtle, in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct AcquisitionMethodButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AcquisitionPalette.brand)
                    .frame(width: 34, height: 34)
                    .background(AcquisitionPalette.brandSoft, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AcquisitionPalette.ink)
                    Text(subtitle).font(.caption).foregroundStyle(AcquisitionPalette.muted).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(AcquisitionPalette.muted)
            }
            .frame(minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private enum AcquisitionPalette {
    static let brand = TasteMapCoreTheme.brand
    static let brandDeep = TasteMapCoreTheme.brandDeep
    static let brandSoft = TasteMapCoreTheme.brandSoft
    static let page = TasteMapCoreTheme.page
    static let surfaceSubtle = TasteMapCoreTheme.surfaceSubtle
    static let ink = TasteMapCoreTheme.textPrimary
    static let muted = TasteMapCoreTheme.textSecondary
    static let border = TasteMapCoreTheme.border
    static let surface = TasteMapCoreTheme.surface
}

private extension View {
    func acquisitionCard() -> some View {
        background(AcquisitionPalette.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(AcquisitionPalette.border) }
    }

    func acquisitionInput() -> some View {
        padding(.horizontal, 12)
            .frame(minHeight: 42)
            .background(AcquisitionPalette.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).stroke(AcquisitionPalette.border) }
    }
}
