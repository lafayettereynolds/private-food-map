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
    @Query private var restaurants: [Restaurant]
    @StateObject private var viewModel: RestaurantAcquisitionViewModel
    @AppStorage("taste-map-last-search-city") private var city = ""
    @State private var query = ""
    @State private var linkPresented = false
    @State private var manualPresented = false
    @State private var actionError: String?

    let onAction: (RestaurantCandidate, RestaurantSearchAction) throws -> Void

    init(
        dependencies: RestaurantAcquisitionDependencies,
        onAction: @escaping (RestaurantCandidate, RestaurantSearchAction) throws -> Void
    ) {
        _viewModel = StateObject(wrappedValue: RestaurantAcquisitionViewModel(
            searchService: dependencies.searchService,
            linkResolver: dependencies.linkResolver,
            locationProvider: dependencies.locationProvider
        ))
        self.onAction = onAction
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    introduction
                    nearbySection
                    searchSection
                    otherMethods
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
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
                guard viewModel.nearbyState == .idle else { return }
                await viewModel.loadNearby()
                if city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let detectedCity = viewModel.detectedCity {
                    city = detectedCity
                }
            }
            .onChange(of: viewModel.detectedCity) { _, detectedCity in
                if city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let detectedCity {
                    city = detectedCity
                }
            }
            .sheet(isPresented: $linkPresented) {
                RestaurantLinkImportView(
                    viewModel: viewModel,
                    city: city,
                    restaurants: restaurants,
                    onAction: perform
                )
            }
            .sheet(isPresented: $manualPresented) {
                ManualRestaurantAddView(
                    viewModel: viewModel,
                    initialCity: city,
                    restaurants: restaurants,
                    onCityChanged: { city = $0 },
                    onAction: perform
                )
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

    private var introduction: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "fork.knife")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(AcquisitionPalette.brand, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text("把真实餐厅加入 Taste Map")
                    .font(.headline)
                    .foregroundStyle(AcquisitionPalette.ink)
                Text("从附近选择、按城市搜索，或添加地图上搜不到的小店。浏览候选不会自动写入你的地图。")
                    .font(.subheadline)
                    .foregroundStyle(AcquisitionPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .acquisitionCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("add-restaurant-introduction")
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
                if viewModel.nearbyResults.isEmpty {
                    AcquisitionMessage(
                        icon: "mappin.slash",
                        title: "附近暂时没有结果",
                        message: "可以扩大范围按城市搜索，或手动添加地图上搜不到的小店。",
                        retryTitle: "重新定位",
                        retry: { Task { await viewModel.loadNearby() } }
                    )
                } else {
                    if let label = viewModel.currentLocationLabel {
                        Label(label, systemImage: "location.circle")
                            .font(.caption)
                            .foregroundStyle(AcquisitionPalette.muted)
                            .lineLimit(2)
                    }
                    ForEach(viewModel.nearbyResults.prefix(5)) { candidate in
                        RestaurantAcquisitionCandidateRow(
                            candidate: candidate,
                            existing: RestaurantDeduplicator.match(for: candidate, in: restaurants),
                            onAction: perform
                        )
                    }
                    if viewModel.nearbyResults.count > 5 {
                        Text("附近还有 \(viewModel.nearbyResults.count - 5) 个结果，可用名称进一步搜索。")
                            .font(.caption)
                            .foregroundStyle(AcquisitionPalette.muted)
                    }
                }
            }
        }
    }

    private var searchSection: some View {
        AcquisitionSection(title: "搜索餐厅", subtitle: "名称、地址与城市范围", systemImage: "magnifyingglass") {
            VStack(alignment: .leading, spacing: 7) {
                Text("搜索城市")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AcquisitionPalette.muted)
                HStack(spacing: 10) {
                    Image(systemName: "building.2")
                        .foregroundStyle(AcquisitionPalette.brand)
                    TextField("例如：杭州、上海、东京、纽约", text: $city)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("restaurant-city-field")
                }
                .acquisitionInput()
            }

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
                        .onSubmit { Task { await viewModel.search(query: query, city: city) } }
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AcquisitionPalette.muted)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除餐厅搜索")
                    }
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
                .frame(maxWidth: .infinity, minHeight: 48)
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
                    existing: RestaurantDeduplicator.match(for: candidate, in: restaurants),
                    onAction: perform
                )
            }
        }
    }

    private var otherMethods: some View {
        AcquisitionSection(title: "其他添加方式", subtitle: "地图上搜不到也没关系", systemImage: "ellipsis.circle") {
            AcquisitionMethodButton(
                icon: "link",
                title: "粘贴餐厅链接",
                subtitle: "支持 Apple 地图、高德和普通餐厅网页"
            ) { linkPresented = true }
            .accessibilityIdentifier("open-restaurant-link-import")

            AcquisitionMethodButton(
                icon: "storefront",
                title: "手动添加地图上搜不到的小店",
                subtitle: "适合小摊、快闪店、私房店和新开门店"
            ) { manualPresented = true }
            .accessibilityIdentifier("open-manual-restaurant")
        }
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

private struct RestaurantLinkImportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: RestaurantAcquisitionViewModel
    let city: String
    let restaurants: [Restaurant]
    let onAction: (RestaurantCandidate, RestaurantSearchAction) -> Void
    @State private var value = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AcquisitionMessage(
                        icon: "link",
                        title: "粘贴餐厅链接或分享文字",
                        message: "Taste Map 会先提取餐厅线索，再让你确认。识别结果不会自动写入数据库。",
                        retryTitle: nil,
                        retry: nil
                    )
                    TextEditor(text: $value)
                        .frame(minHeight: 110)
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        .overlay { RoundedRectangle(cornerRadius: 14).stroke(AcquisitionPalette.border) }
                        .accessibilityLabel("餐厅链接或分享文字")
                        .accessibilityIdentifier("restaurant-link-field")

                    Button {
                        Task { await viewModel.resolveLink(value, city: city) }
                    } label: {
                        HStack {
                            if viewModel.isResolvingLink { ProgressView().tint(.white) }
                            else { Image(systemName: "wand.and.stars") }
                            Text(viewModel.isResolvingLink ? "正在识别" : "识别餐厅")
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AcquisitionPalette.brand)
                    .disabled(viewModel.isResolvingLink || value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("resolve-restaurant-link")

                    if let message = viewModel.linkMessage {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(AcquisitionPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(viewModel.linkResults) { candidate in
                        RestaurantAcquisitionCandidateRow(
                            candidate: candidate,
                            existing: RestaurantDeduplicator.match(for: candidate, in: restaurants),
                            onAction: onAction
                        )
                    }
                }
                .padding(16)
            }
            .background(AcquisitionPalette.page.ignoresSafeArea())
            .navigationTitle("粘贴餐厅链接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
        .tint(AcquisitionPalette.brand)
    }
}

private struct ManualRestaurantAddView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: RestaurantAcquisitionViewModel
    let initialCity: String
    let restaurants: [Restaurant]
    let onCityChanged: (String) -> Void
    let onAction: (RestaurantCandidate, RestaurantSearchAction) -> Void

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
        onAction: @escaping (RestaurantCandidate, RestaurantSearchAction) -> Void
    ) {
        self.viewModel = viewModel
        self.initialCity = initialCity
        self.restaurants = restaurants
        self.onCityChanged = onCityChanged
        self.onAction = onAction
        _city = State(initialValue: initialCity)
        let center = viewModel.currentCoordinate ?? RestaurantCoordinate(latitude: 30.2741, longitude: 120.1551)
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
            latitudinalMeters: 12_000,
            longitudinalMeters: 12_000
        )))
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
                        HStack(spacing: 10) {
                            Button {
                                onCityChanged(city)
                                onAction(candidate, .wantToGo)
                            } label: {
                                Label("加入想吃", systemImage: "bookmark")
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("manual-add-want-to-go")
                            Button {
                                onCityChanged(city)
                                onAction(candidate, .recordVisit)
                            } label: {
                                Label(existing == nil ? "记录去过" : "再次记录", systemImage: "fork.knife")
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AcquisitionPalette.brand)
                            .accessibilityIdentifier("manual-record-visit")
                        }
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
    let existing: Restaurant?
    let onAction: (RestaurantCandidate, RestaurantSearchAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let photoURL = candidate.photoURL {
                        AsyncImage(url: photoURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            candidatePlaceholder
                        }
                    } else {
                        candidatePlaceholder
                    }
                }
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(candidate.name)
                            .font(.headline)
                            .foregroundStyle(AcquisitionPalette.ink)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        if existing != nil {
                            Text("已在地图")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AcquisitionPalette.brandDeep)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AcquisitionPalette.brandSoft, in: Capsule())
                        }
                    }
                    if !candidate.address.isEmpty {
                        Text(candidate.address)
                            .font(.caption)
                            .foregroundStyle(AcquisitionPalette.muted)
                            .lineLimit(2)
                    }
                    let location = [candidate.city, candidate.district].filter { !$0.isEmpty }.joined(separator: " · ")
                    HStack(spacing: 8) {
                        if !location.isEmpty { Text(location) }
                        if let distance = candidate.distanceMeters { Text(Self.distanceText(distance)) }
                    }
                    .font(.caption2)
                    .foregroundStyle(AcquisitionPalette.muted)
                }
            }

            HStack(spacing: 10) {
                Button {
                    onAction(candidate, .wantToGo)
                } label: {
                    Label("加入想吃", systemImage: "bookmark")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("candidate-want-\(candidate.id.uuidString)")
                Button {
                    onAction(candidate, .recordVisit)
                } label: {
                    Label(existing == nil ? "记录去过" : "再次记录", systemImage: "fork.knife")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(AcquisitionPalette.brand)
                .accessibilityIdentifier("candidate-visit-\(candidate.id.uuidString)")
            }
        }
        .padding(14)
        .background(AcquisitionPalette.surfaceSubtle, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(AcquisitionPalette.border) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("restaurant-candidate-\(candidate.id.uuidString)")
    }

    private var candidatePlaceholder: some View {
        ZStack {
            AcquisitionPalette.brandSoft
            Image(systemName: "fork.knife")
                .foregroundStyle(AcquisitionPalette.brand)
        }
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(AcquisitionPalette.brand)
                    .frame(width: 30, height: 30)
                    .background(AcquisitionPalette.brandSoft, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(AcquisitionPalette.ink)
                    Text(subtitle).font(.caption).foregroundStyle(AcquisitionPalette.muted)
                }
            }
            content
        }
        .padding(16)
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
                .frame(width: 32, height: 32)
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
        .padding(12)
        .background(AcquisitionPalette.surfaceSubtle, in: RoundedRectangle(cornerRadius: 14))
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
                    .frame(width: 42, height: 42)
                    .background(AcquisitionPalette.brandSoft, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AcquisitionPalette.ink)
                    Text(subtitle).font(.caption).foregroundStyle(AcquisitionPalette.muted).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(AcquisitionPalette.muted)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private enum AcquisitionPalette {
    static let brand = Color(red: 80 / 255, green: 108 / 255, blue: 140 / 255)
    static let brandDeep = Color(red: 52 / 255, green: 79 / 255, blue: 105 / 255)
    static let brandSoft = Color(red: 237 / 255, green: 242 / 255, blue: 246 / 255)
    static let page = Color(red: 247 / 255, green: 249 / 255, blue: 251 / 255)
    static let surfaceSubtle = Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255)
    static let ink = Color(red: 23 / 255, green: 42 / 255, blue: 58 / 255)
    static let muted = Color(red: 101 / 255, green: 116 / 255, blue: 128 / 255)
    static let border = Color(red: 220 / 255, green: 229 / 255, blue: 236 / 255)
}

private extension View {
    func acquisitionCard() -> some View {
        background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(AcquisitionPalette.border) }
    }

    func acquisitionInput() -> some View {
        padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(AcquisitionPalette.border) }
    }
}
