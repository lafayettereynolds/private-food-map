import SwiftData
import SwiftUI
import UIKit

struct RestaurantListsOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allLists: [RestaurantList]
    let currentUserID: String
    let photoAPI: (any PhotoBinaryAPI)?
    @State private var query = ""
    @State private var creating = false
    @State private var deleting: RestaurantList?
    @State private var message: String?

    private var lists: [RestaurantList] {
        allLists.filter {
            $0.ownerUserID == currentUserID && $0.deletedAt == nil &&
                (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query))
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        Group {
            if lists.isEmpty && query.isEmpty {
                ContentUnavailableView {
                    Label("还没有榜单", systemImage: "list.number")
                } description: {
                    Text("创建一份有主题的餐厅榜单，空榜单也可以先保存。")
                } actions: {
                    Button("新建榜单") { creating = true }.buttonStyle(.borderedProminent)
                }
            } else if lists.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(lists) { list in
                            NavigationLink {
                                RestaurantListDetailView(
                                    list: list, currentUserID: currentUserID, photoAPI: photoAPI
                                )
                            } label: {
                                RestaurantListSummaryCard(list: list, photoAPI: photoAPI)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("restaurant-list-card-\(list.id.uuidString.lowercased())")
                            .contextMenu {
                                Button("删除榜单", systemImage: "trash", role: .destructive) {
                                    deleting = list
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .background(TasteMapCoreTheme.page)
            }
        }
        .navigationTitle("我的榜单")
        .searchable(text: $query, prompt: "搜索榜单标题")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("新建", systemImage: "plus") { creating = true }
            }
        }
        .sheet(isPresented: $creating) {
            RestaurantListEditorSheet(currentUserID: currentUserID)
        }
        .confirmationDialog(
            "删除这份榜单？",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除榜单", role: .destructive) {
                if let deleting {
                    do { try LocalRestaurantListStore(context: modelContext).delete(deleting, actorUserID: currentUserID) }
                    catch { message = error.localizedDescription }
                }
                deleting = nil
            }
            Button("取消", role: .cancel) { deleting = nil }
        } message: {
            Text("餐厅、想吃、到访、照片和菜品都不会被删除。")
        }
        .alert("榜单没有删除", isPresented: .init(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好", role: .cancel) { message = nil }
        } message: { Text(message ?? "请稍后重试。") }
        .accessibilityIdentifier("restaurant-lists-overview")
        .tasteMapBottomNavigationHidden()
    }
}

struct RestaurantListSummaryCard: View {
    let list: RestaurantList
    let photoAPI: (any PhotoBinaryAPI)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RestaurantListCoverGrid(
                places: list.previewRestaurants,
                customPhotoID: list.coverMode == .custom ? list.customCoverPhotoID : nil,
                photoAPI: photoAPI
            )
            .frame(height: 142)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(list.title).font(.headline).lineLimit(2)
                    Text("\(list.activeItemCount) 家餐厅\(list.isRanked ? " · 排名榜单" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Label(list.visibility.title, systemImage: list.visibility.systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(list.visibility == .public ? Color.accentColor : .secondary)
            }
        }
        .padding(12)
        .tasteMapCoreCard(radius: 22, showsShadow: true)
    }
}

struct RestaurantListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [RestaurantListItem]
    @Query private var restaurants: [Restaurant]
    let list: RestaurantList
    let currentUserID: String
    let photoAPI: (any PhotoBinaryAPI)?
    @State private var editing = false
    @State private var adding = false
    @State private var editingNote: RestaurantListItem?
    @State private var selectedPlace: RestaurantListPlaceContractV1?
    @State private var message: String?

    private var items: [RestaurantListItem] {
        allItems.filter { $0.listID == list.id && $0.deletedAt == nil }
            .sorted {
                if $0.position != $1.position { return $0.position < $1.position }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    var body: some View {
        List {
            Section {
                RestaurantListCoverGrid(
                    places: items.prefix(4).compactMap(\.restaurantSnapshot),
                    customPhotoID: list.coverMode == .custom ? list.customCoverPhotoID : nil,
                    photoAPI: photoAPI
                )
                .frame(height: 210)
                .listRowInsets(.init())
                .listRowBackground(Color.clear)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(list.visibility.title, systemImage: list.visibility.systemImage)
                        if list.isRanked { Label("排名榜单", systemImage: "number") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if !list.listDescription.isEmpty {
                        Text(list.listDescription).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            Section("餐厅 · \(items.count)") {
                if items.isEmpty {
                    ContentUnavailableView(
                        "还没有加入餐厅", systemImage: "fork.knife.circle",
                        description: Text("可以从去过、想吃或 Apple 地图搜索加入；不会自动改变想吃状态。")
                    )
                    Button("添加餐厅", systemImage: "plus") { adding = true }
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button { if let place = item.restaurantSnapshot { selectedPlace = place } } label: {
                            RestaurantListItemRow(
                                item: item, rank: list.isRanked ? index + 1 : nil,
                                photoAPI: photoAPI
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("restaurant-list-item-\(item.restaurantGlobalKey)")
                        .swipeActions(edge: .trailing) {
                            Button("移除", role: .destructive) { remove(item) }
                            Button("备注") { editingNote = item }.tint(.blue)
                        }
                    }
                    .onMove(perform: move)
                    .onDelete { offsets in offsets.compactMap { items.indices.contains($0) ? items[$0] : nil }.forEach(remove) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(list.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if list.visibility == .public {
                    PublicShareButton(
                        entityType: .list,
                        entityID: list.remoteID ?? ""
                    ) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("分享榜单")
                }
                EditButton()
                    .accessibilityIdentifier("restaurant-list-edit-mode")
                Button("设置", systemImage: "slider.horizontal.3") { editing = true }
                    .accessibilityIdentifier("restaurant-list-settings")
            }
            ToolbarItem(placement: .bottomBar) {
                Button("添加餐厅", systemImage: "plus.circle.fill") { adding = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("restaurant-list-add-restaurants")
            }
        }
        .sheet(isPresented: $editing) {
            RestaurantListEditorSheet(currentUserID: currentUserID, list: list)
        }
        .sheet(isPresented: $adding) {
            RestaurantListAddRestaurantSheet(
                list: list, currentUserID: currentUserID, photoAPI: photoAPI
            )
        }
        .sheet(item: $editingNote) { item in
            RestaurantListNoteEditor(item: item, currentUserID: currentUserID)
        }
        .sheet(item: $selectedPlace) { place in
            DiscoveryRestaurantDestination(
                card: place.listDiscoveryCard,
                restaurants: restaurants,
                onWantToGo: { addToWantToGo(place) },
                photoAPI: photoAPI,
                entrySource: .restaurantList
            )
        }
        .alert("榜单没有更新", isPresented: .init(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好", role: .cancel) { message = nil }
        } message: { Text(message ?? "请稍后重试。") }
        .accessibilityIdentifier("restaurant-list-detail")
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        do {
            try LocalRestaurantListStore(context: modelContext).reorder(
                list: list, orderedItemIDs: reordered.map(\.id), actorUserID: currentUserID
            )
        } catch { message = error.localizedDescription }
    }

    private func remove(_ item: RestaurantListItem) {
        do { try LocalRestaurantListStore(context: modelContext).remove(item, actorUserID: currentUserID) }
        catch { message = error.localizedDescription }
    }

    private func addToWantToGo(_ place: RestaurantListPlaceContractV1) {
        do {
            _ = try LocalDiscoveryStore(context: modelContext).addToWantToGo(
                projection: place.discoveryProjection,
                among: restaurants,
                currentUserID: currentUserID
            )
        } catch { message = "暂时无法加入想吃，请稍后重试。" }
    }
}

private struct RestaurantListItemRow: View {
    let item: RestaurantListItem
    let rank: Int?
    let photoAPI: (any PhotoBinaryAPI)?

    var body: some View {
        HStack(spacing: 13) {
            if let rank {
                Text("#\(rank)")
                    .font(rank <= 3 ? .title3.bold() : .subheadline.bold())
                    .foregroundStyle(rank <= 3 ? Color.accentColor : .secondary)
                    .frame(width: 36, alignment: .leading)
            }
            if let place = item.restaurantSnapshot {
                RestaurantListPlaceImage(place: place, photoAPI: photoAPI)
                    .frame(width: rank != nil && rank! <= 3 ? 74 : 58, height: rank != nil && rank! <= 3 ? 74 : 58)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text(place.name).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    Text([place.city, place.address].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if !item.note.isEmpty { Text(item.note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct RestaurantListEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var photos: [PhotoAsset]
    @Query private var restaurants: [Restaurant]
    let currentUserID: String
    let list: RestaurantList?
    @State private var title: String
    @State private var description: String
    @State private var visibility: RestaurantListVisibility
    @State private var isRanked: Bool
    @State private var coverMode: RestaurantListCoverMode
    @State private var customCoverPhotoID: String?
    @State private var message: String?

    init(currentUserID: String, list: RestaurantList? = nil) {
        self.currentUserID = currentUserID
        self.list = list
        _title = State(initialValue: list?.title ?? "")
        _description = State(initialValue: list?.listDescription ?? "")
        _visibility = State(initialValue: list?.visibility ?? .private)
        _isRanked = State(initialValue: list?.isRanked ?? false)
        _coverMode = State(initialValue: list?.coverMode ?? .automatic)
        _customCoverPhotoID = State(initialValue: list?.customCoverPhotoID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("榜单") {
                    TextField("榜单标题", text: $title).textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("restaurant-list-title")
                    Text("\(title.count)/60").font(.caption2).foregroundStyle(title.count > 60 ? .red : .secondary)
                    TextField("描述（可选）", text: $description, axis: .vertical).lineLimit(3 ... 6)
                        .accessibilityIdentifier("restaurant-list-description")
                    Text("\(description.count)/240").font(.caption2).foregroundStyle(description.count > 240 ? .red : .secondary)
                    Toggle("显示排名", isOn: $isRanked)
                }
                Section("谁可以看") {
                    Picker("可见范围", selection: $visibility) {
                        ForEach(RestaurantListVisibility.allCases) { value in
                            Label(value.title, systemImage: value.systemImage).tag(value)
                        }
                    }
                    .accessibilityIdentifier("restaurant-list-visibility")
                }
                if list != nil {
                    Section {
                        Picker("封面模式", selection: $coverMode) {
                            Text("自动使用榜单餐厅").tag(RestaurantListCoverMode.automatic)
                            if !availableCoverPhotos.isEmpty { Text("使用已有公开照片").tag(RestaurantListCoverMode.custom) }
                        }
                        if coverMode == .custom {
                            Picker("照片", selection: $customCoverPhotoID) {
                                Text("请选择").tag(String?.none)
                                ForEach(availableCoverPhotos, id: \.id) { photo in
                                    Text(photo.fileName ?? "餐厅照片").tag(Optional(photo.remoteID ?? photo.id.uuidString.lowercased()))
                                }
                            }
                        }
                    } header: {
                        Text("封面")
                    } footer: {
                        Text("自定义封面复用 P2 已上传且公开的照片，不会重新上传。")
                    }
                }
                if let message { Text(message).foregroundStyle(.red) }
            }
            .navigationTitle(list == nil ? "新建榜单" : "编辑榜单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("restaurant-list-save")
                }
            }
        }
    }

    private var availableCoverPhotos: [PhotoAsset] {
        let ownedRestaurantIDs = ProfileOwnedContentScope.capture(
            currentUserID: currentUserID,
            restaurants: restaurants
        ).restaurantIDs
        return photos.filter {
            ProfileOwnedContentScope.isSafeListCover($0, ownedBy: currentUserID) &&
                $0.restaurantId.map(ownedRestaurantIDs.contains) == true
        }
    }

    private func save() {
        do {
            let store = LocalRestaurantListStore(context: modelContext)
            if let list {
                try store.update(
                    list, actorUserID: currentUserID, title: title, description: description,
                    visibility: visibility, isRanked: isRanked, coverMode: coverMode,
                    customCoverPhotoID: customCoverPhotoID
                )
            } else {
                _ = try store.create(
                    ownerUserID: currentUserID, title: title, description: description,
                    visibility: visibility, isRanked: isRanked
                )
            }
            dismiss()
        } catch { message = error.localizedDescription }
    }
}

struct RestaurantListAddRestaurantSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var restaurants: [Restaurant]
    let list: RestaurantList
    let currentUserID: String
    let photoAPI: (any PhotoBinaryAPI)?
    @State private var query = ""
    @State private var search = false
    @State private var message: String?

    private var available: [Restaurant] {
        restaurants.filter {
            $0.deletedAt == nil &&
                ProfileOwnedContentScope.isRestaurant($0, ownedBy: currentUserID) &&
                (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) ||
                $0.address.localizedCaseInsensitiveContains(query))
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("搜索新的餐厅", systemImage: "magnifyingglass") { search = true }
                } footer: { Text("仅加入榜单，不会自动变成想吃。") }
                Section("我的去过与想吃") {
                    if available.isEmpty { Text("没有匹配的餐厅").foregroundStyle(.secondary) }
                    ForEach(available) { restaurant in
                        Button { add(restaurant) } label: {
                            HStack {
                                Text(restaurant.status == .visited ? "✓" : "♡")
                                VStack(alignment: .leading) {
                                    Text(restaurant.name).foregroundStyle(.primary)
                                    Text(restaurant.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(); Image(systemName: "plus.circle")
                            }
                        }
                        .accessibilityIdentifier("restaurant-list-add-\(restaurant.id.uuidString.lowercased())")
                    }
                }
            }
            .navigationTitle("添加餐厅")
            .searchable(text: $query, prompt: "搜索我的餐厅")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $search) {
                RestaurantSearchView(selectionTitle: "加入这份榜单") { candidate in
                    _ = try LocalRestaurantListStore(context: modelContext).add(
                        candidate: candidate, to: list, actorUserID: currentUserID
                    )
                }
            }
            .alert("没有加入榜单", isPresented: .init(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好", role: .cancel) { message = nil }
            } message: { Text(message ?? "请稍后重试。") }
        }
    }

    private func add(_ restaurant: Restaurant) {
        do {
            _ = try LocalRestaurantListStore(context: modelContext).add(
                restaurant: restaurant, to: list, actorUserID: currentUserID
            )
        } catch { message = error.localizedDescription }
    }
}

private struct RestaurantListNoteEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let item: RestaurantListItem
    let currentUserID: String
    @State private var note: String
    @State private var message: String?

    init(item: RestaurantListItem, currentUserID: String) {
        self.item = item; self.currentUserID = currentUserID
        _note = State(initialValue: item.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("写一句入选理由", text: $note, axis: .vertical).lineLimit(3 ... 8)
                Text("\(note.count)/160").font(.caption).foregroundStyle(note.count > 160 ? .red : .secondary)
                if let message { Text(message).foregroundStyle(.red) }
            }
            .navigationTitle("榜单备注")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try LocalRestaurantListStore(context: modelContext).updateNote(
                                item, note: note, actorUserID: currentUserID
                            )
                            dismiss()
                        } catch { message = error.localizedDescription }
                    }
                }
            }
        }
    }
}

struct AddRestaurantToListsSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var lists: [RestaurantList]
    @Query private var items: [RestaurantListItem]
    let restaurant: Restaurant
    let currentUserID: String
    @State private var creating = false
    @State private var message: String?

    private var ownLists: [RestaurantList] {
        lists.filter { $0.ownerUserID == currentUserID && $0.deletedAt == nil }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                if ownLists.isEmpty {
                    ContentUnavailableView("还没有榜单", systemImage: "list.number", description: Text("先创建一份榜单。"))
                }
                ForEach(ownLists) { list in
                    Button { toggle(list) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(list.title).foregroundStyle(.primary)
                                Text("\(list.activeItemCount) 家 · \(list.visibility.title)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: contains(list) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(contains(list) ? Color.accentColor : .secondary)
                        }
                    }
                }
                Button("新建榜单", systemImage: "plus") { creating = true }
            }
            .navigationTitle("加入榜单")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $creating) { RestaurantListEditorSheet(currentUserID: currentUserID) }
            .alert("榜单没有更新", isPresented: .init(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好", role: .cancel) { message = nil }
            } message: { Text(message ?? "请稍后重试。") }
        }
    }

    private func contains(_ list: RestaurantList) -> Bool {
        items.contains {
            $0.listID == list.id && $0.deletedAt == nil && $0.restaurantGlobalKey == globalKey
        }
    }

    private func toggle(_ list: RestaurantList) {
        do {
            let store = LocalRestaurantListStore(context: modelContext)
            if let current = items.first(where: {
                $0.listID == list.id && $0.deletedAt == nil && $0.restaurantGlobalKey == globalKey
            }) {
                try store.remove(current, actorUserID: currentUserID)
            } else {
                _ = try store.add(restaurant: restaurant, to: list, actorUserID: currentUserID)
            }
        } catch { message = error.localizedDescription }
    }

    private var globalKey: String {
        guard let record = try? SyncRecordMapper.restaurantRecord(restaurant),
              let primary = record.placeIdentities.first(where: \.isPrimary) ?? record.placeIdentities.first else {
            return "local:\(restaurant.id.uuidString.lowercased())"
        }
        return "\(primary.provider.rawValue):\(primary.externalId)"
    }
}

/// Adds a provider-neutral place projection from Discovery, Community or a
/// public list. It creates only the ListItem relationship; it never copies the
/// source user's visits, notes, photos or want-to-go state.
struct AddPlaceToListsSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var lists: [RestaurantList]
    @Query private var items: [RestaurantListItem]
    @Query private var restaurants: [Restaurant]
    let place: DiscoveryRestaurantProjectionV1
    let currentUserID: String
    @State private var creating = false
    @State private var message: String?

    private var ownLists: [RestaurantList] {
        lists.filter { $0.ownerUserID == currentUserID && $0.deletedAt == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                if ownLists.isEmpty {
                    ContentUnavailableView(
                        "还没有榜单", systemImage: "list.number",
                        description: Text("先创建一份榜单，再把这家餐厅加入。")
                    )
                }
                ForEach(ownLists) { list in
                    Button { toggle(list) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(list.title).foregroundStyle(.primary)
                                Text("\(list.activeItemCount) 家 · \(list.visibility.title)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: contains(list) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(contains(list) ? Color.accentColor : .secondary)
                        }
                    }
                }
                Button("新建榜单", systemImage: "plus") { creating = true }
            }
            .navigationTitle("加入榜单")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $creating) { RestaurantListEditorSheet(currentUserID: currentUserID) }
            .alert("榜单没有更新", isPresented: .init(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好", role: .cancel) { message = nil }
            } message: { Text(message ?? "请稍后重试。") }
        }
    }

    private func contains(_ list: RestaurantList) -> Bool {
        items.contains {
            $0.listID == list.id && $0.deletedAt == nil && $0.restaurantGlobalKey == place.globalKey
        }
    }

    private func toggle(_ list: RestaurantList) {
        do {
            let store = LocalRestaurantListStore(context: modelContext)
            if let current = items.first(where: {
                $0.listID == list.id && $0.deletedAt == nil && $0.restaurantGlobalKey == place.globalKey
            }) {
                try store.remove(current, actorUserID: currentUserID)
            } else {
                _ = try store.add(
                    projection: place, to: list, actorUserID: currentUserID,
                    localRestaurants: restaurants
                )
            }
        } catch { message = error.localizedDescription }
    }
}

struct PublicRestaurantListsSection: View {
    @Environment(\.modelContext) private var modelContext
    let ownerUserID: String
    let currentUserID: String
    let api: any RestaurantListAPI
    let photoAPI: (any PhotoBinaryAPI)?
    @State private var lists: [PublicListSummaryDTO] = []
    @State private var loading = false
    @State private var message: String?
    @State private var selected: PublicListSummaryDTO?
    @State private var nextCursor: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("餐厅榜单").font(.headline); Spacer(); if loading { ProgressView() } }
            if lists.isEmpty {
                Text(message ?? "TA 还没有你可以查看的榜单。")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 10)
            } else {
                ForEach(lists) { list in
                    Button { selected = list } label: {
                        HStack(spacing: 12) {
                            PublicListPreviewGrid(values: list.previewRestaurants, photoAPI: photoAPI)
                                .frame(width: 82, height: 66).clipShape(RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(list.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                Text("\(list.restaurantCount) 家餐厅 · \(list.visibility.title)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("public-restaurant-list-\(list.id)")
                }
                if nextCursor != nil {
                    Button("加载更多榜单") { Task { await loadMore() } }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .tasteMapCoreCard(radius: 20)
        .task { await load() }
        .sheet(item: $selected) { summary in
            PublicRestaurantListDetailView(
                summary: summary, currentUserID: currentUserID, api: api, photoAPI: photoAPI
            )
        }
    }

    @MainActor private func load() async {
        let store = LocalRestaurantListStore(context: modelContext)
        lists = (try? store.cachedSummaries(viewerUserID: currentUserID, ownerUserID: ownerUserID)) ?? []
        loading = true; defer { loading = false }
        do {
            #if DEBUG
            let page = TasteMapUITestFixtures.usesRestaurantListsFixture
                ? try TasteMapUITestFixtures.restaurantListPublicPage(ownerUserID: ownerUserID)
                : try await api.profileLists(userID: ownerUserID, cursor: nil, limit: 20)
            #else
            let page = try await api.profileLists(userID: ownerUserID, cursor: nil, limit: 20)
            #endif
            lists = page.items
            nextCursor = page.nextCursor
            try store.cache(summaries: page.items, viewerUserID: currentUserID, ownerUserID: ownerUserID, replace: page.nextCursor == nil)
            message = nil
        } catch SyncAPIError.server(let status, _) where status == 403 || status == 404 {
            for list in lists { store.invalidate(listID: list.id, viewerUserID: currentUserID) }
            lists = []; message = "这些榜单已经不可查看。"
        } catch { message = lists.isEmpty ? "榜单暂时无法加载。" : "当前显示最近缓存的榜单。" }
    }

    @MainActor private func loadMore() async {
        guard let cursor = nextCursor, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await api.profileLists(userID: ownerUserID, cursor: cursor, limit: 20)
            var seen = Set(lists.map(\.id))
            lists.append(contentsOf: page.items.filter { seen.insert($0.id).inserted })
            nextCursor = page.nextCursor
            try LocalRestaurantListStore(context: modelContext).cache(
                summaries: page.nextCursor == nil ? lists : page.items,
                viewerUserID: currentUserID,
                ownerUserID: ownerUserID,
                replace: page.nextCursor == nil
            )
            message = nil
        } catch {
            message = "更多榜单暂时无法加载。"
        }
    }
}

struct PublicRestaurantListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var restaurants: [Restaurant]
    let summary: PublicListSummaryDTO
    let currentUserID: String
    let api: any RestaurantListAPI
    let photoAPI: (any PhotoBinaryAPI)?
    @State private var detail: PublicListDetailDTO?
    @State private var loading = false
    @State private var message: String?
    @State private var selected: RestaurantListPlaceContractV1?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let detail {
                        PublicListPreviewGrid(values: detail.list.previewRestaurants, photoAPI: photoAPI)
                            .frame(height: 190).listRowInsets(.init())
                        Text("由 \(detail.list.owner.displayName) 创建").font(.subheadline).foregroundStyle(.secondary)
                        if !detail.list.description.isEmpty { Text(detail.list.description) }
                    }
                }
                Section("餐厅") {
                    if let detail, detail.items.isEmpty { Text("这份榜单还没有餐厅。\n").foregroundStyle(.secondary) }
                    ForEach(Array((detail?.items ?? []).enumerated()), id: \.element.id) { index, item in
                        Button { selected = item.restaurant } label: {
                            HStack(spacing: 12) {
                                if detail?.list.isRanked == true { Text("#\(index + 1)").font(.headline).foregroundStyle(Color.accentColor).frame(width: 34) }
                                RestaurantListPlaceImage(place: item.restaurant, photoAPI: photoAPI)
                                    .frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.restaurant.name).font(.headline).foregroundStyle(.primary)
                                    Text(item.restaurant.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    if !item.note.isEmpty { Text(item.note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("public-list-restaurant-\(item.restaurant.globalKey)")
                    }
                    if detail?.nextCursor != nil { Button("加载更多") { Task { await loadMore() } }.frame(maxWidth: .infinity) }
                }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle(detail?.list.title ?? summary.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                if summary.visibility == .public {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: "Taste Map · \(summary.title) · \(summary.restaurantCount) 家餐厅") {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .overlay { if loading && detail == nil { ProgressView("正在加载榜单…") } }
            .task { await load() }
            .refreshable { await load() }
            .sheet(item: $selected) { place in
                DiscoveryRestaurantDestination(
                    card: place.listDiscoveryCard, restaurants: restaurants,
                    onWantToGo: { addToWantToGo(place) }, photoAPI: photoAPI,
                    entrySource: .restaurantList
                )
            }
        }
    }

    @MainActor private func load() async {
        let store = LocalRestaurantListStore(context: modelContext)
        detail = (try? store.cachedDetail(listID: summary.id, viewerUserID: currentUserID))
        loading = true; defer { loading = false }
        do {
            #if DEBUG
            let value = TasteMapUITestFixtures.usesRestaurantListsFixture
                ? try TasteMapUITestFixtures.restaurantListPublicDetail()
                : try await api.detail(listID: summary.id, cursor: nil, limit: 50)
            #else
            let value = try await api.detail(listID: summary.id, cursor: nil, limit: 50)
            #endif
            detail = value; message = nil
            try store.cache(detail: value, viewerUserID: currentUserID, replace: value.nextCursor == nil)
        } catch SyncAPIError.server(let status, _) where status == 403 || status == 404 {
            store.invalidate(listID: summary.id, viewerUserID: currentUserID)
            detail = nil; message = "这份榜单已经不可查看。"
        } catch { message = detail == nil ? "榜单暂时无法加载。" : "当前显示最近缓存；联网刷新后会重新验证权限。" }
    }

    @MainActor private func loadMore() async {
        guard let cursor = detail?.nextCursor else { return }
        do {
            let page = try await api.detail(listID: summary.id, cursor: cursor, limit: 50)
            guard let current = detail else { detail = page; return }
            var seen = Set(current.items.map(\.id))
            let combined = current.items + page.items.filter { seen.insert($0.id).inserted }
            let combinedDetail = PublicListDetailDTO(
                apiVersion: 1,
                list: page.list,
                items: combined,
                nextCursor: page.nextCursor,
                generatedAt: page.generatedAt
            )
            detail = combinedDetail
            try LocalRestaurantListStore(context: modelContext).cache(
                detail: page.nextCursor == nil ? combinedDetail : page,
                viewerUserID: currentUserID,
                replace: page.nextCursor == nil
            )
        } catch { message = "加载更多失败，请稍后重试。" }
    }

    private func addToWantToGo(_ place: RestaurantListPlaceContractV1) {
        do {
            _ = try LocalDiscoveryStore(context: modelContext).addToWantToGo(
                projection: place.discoveryProjection,
                among: restaurants,
                currentUserID: currentUserID
            )
        }
        catch { message = "暂时无法加入想吃，请稍后重试。" }
    }
}

struct RestaurantListCoverGrid: View {
    let places: [RestaurantListPlaceContractV1]
    let customPhotoID: String?
    let photoAPI: (any PhotoBinaryAPI)?

    var body: some View {
        if let customPhotoID {
            RestaurantListPhotoIDImage(photoID: customPhotoID, fallbackEmoji: "🍽️", photoAPI: photoAPI)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        } else if places.isEmpty {
            LinearGradient(colors: [Color.accentColor.opacity(0.16), .orange.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay {
                    FoodDiningVisualIcon(
                        kind: .menu,
                        usage: .decorative,
                        size: 58,
                        foregroundColor: TasteMapCoreTheme.brandDeep,
                        backgroundColor: TasteMapCoreTheme.surface.opacity(0.82)
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
        } else {
            PublicListPreviewGrid(
                values: places.map { .init(globalKey: $0.globalKey, name: $0.name, photoId: $0.markerPhotoId, merchantImageUrl: $0.merchantImageUrl, markerEmoji: $0.markerEmoji) },
                photoAPI: photoAPI
            )
        }
    }
}

struct PublicListPreviewGrid: View {
    let values: [PublicListPreviewRestaurantDTO]
    let photoAPI: (any PhotoBinaryAPI)?
    var body: some View {
        GeometryReader { proxy in
            let columns = values.count <= 1 ? 1 : 2
            let rows = values.count <= 2 ? 1 : 2
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: columns), spacing: 2) {
                ForEach(Array(values.prefix(4))) { value in
                    RestaurantListPhotoIDImage(photoID: value.photoId, merchantImageURL: value.merchantImageUrl, fallbackEmoji: value.markerEmoji, photoAPI: photoAPI)
                        .frame(height: (proxy.size.height - CGFloat(rows - 1) * 2) / CGFloat(rows))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}

struct RestaurantListPlaceImage: View {
    let place: RestaurantListPlaceContractV1
    let photoAPI: (any PhotoBinaryAPI)?
    var body: some View {
        RestaurantListPhotoIDImage(photoID: place.markerPhotoId, merchantImageURL: place.merchantImageUrl, fallbackEmoji: place.markerEmoji, photoAPI: photoAPI)
    }
}

private struct RestaurantListPhotoIDImage: View {
    let photoID: String?
    var merchantImageURL: String? = nil
    let fallbackEmoji: String
    let photoAPI: (any PhotoBinaryAPI)?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else if let merchantImageURL, let url = URL(string: merchantImageURL) {
                AsyncImage(url: url) { phase in
                    if let value = phase.image { value.resizable().scaledToFill() } else { placeholder }
                }
            } else { placeholder }
        }
        .clipped()
        .task(id: photoID) {
            guard let photoID, let id = UUID(uuidString: photoID), let photoAPI else { return }
            if let data = try? await photoAPI.download(photoID: id, variant: .thumbnail) { image = UIImage(data: data) }
        }
    }

    private var placeholder: some View {
        LinearGradient(colors: [Color.accentColor.opacity(0.18), .orange.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                FoodDiningVisualIcon(
                    kind: FoodDiningVisualLibrary.kind(
                        legacySymbol: fallbackEmoji.isEmpty ? nil : fallbackEmoji
                    ),
                    usage: .decorative,
                    size: 42,
                    foregroundColor: TasteMapCoreTheme.brandDeep,
                    backgroundColor: TasteMapCoreTheme.surface.opacity(0.8)
                )
            }
    }
}

extension RestaurantListPlaceContractV1 {
    var listDiscoveryCard: DiscoveryCardV1 {
        .init(
            id: "list:\(globalKey)", mode: .forYou, restaurant: discoveryProjection,
            viewerState: .none,
            ratings: .init(
                mine: .init(value: nil, sampleCount: 0), community: .init(value: nil, sampleCount: 0),
                friends: .init(value: nil, sampleCount: 0), similarTaste: .init(value: nil, sampleCount: 0)
            ),
            reasons: [.init(code: "public_list", text: "来自公开餐厅榜单")],
            sourceUser: nil, similarity: nil, trend: nil, cacheScope: .public, rank: 1, score: 0
        )
    }
}
