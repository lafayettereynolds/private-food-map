import SwiftData
import SwiftUI

struct CompanionPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissSearch) private var dismissSearch
    @Environment(\.modelContext) private var modelContext
    @Query private var companions: [DiningCompanion]
    @Query private var visits: [Visit]

    @Binding var selectedIDs: [String]
    @Binding var selectedNames: [String]
    var ownerUserID: String = "local"

    @State private var searchText = ""
    @State private var newName = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if activeCompanions.isEmpty {
                    ContentUnavailableView(
                        "还没有饭搭子",
                        systemImage: "person.2",
                        description: Text("写下一个名字，下次记录时就能直接选择。")
                    )
                } else if filteredCompanions.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    Section(searchText.isEmpty ? "最近 / 常用饭搭子" : "搜索结果") {
                        ForEach(filteredCompanions) { companion in
                            Button { toggle(companion) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(companion.displayName)
                                            .foregroundStyle(.primary)
                                        if let usage = usageByID[companion.remoteID ?? ""], usage.count > 0 {
                                            Text("一起吃过 \(usage.count) 次")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if selectedIDs.contains(companion.remoteID ?? "") {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .accessibilityIdentifier("companion-option-\(companion.id.uuidString)")
                        }
                    }
                }

                Section("新增名字") {
                    TextField("例如：小王、妈妈、同事 Alex", text: $newName)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("companion-new-name")
                    Button("新增并选中", systemImage: "plus.circle.fill", action: add)
                        .disabled(PrivateDirectoryName.normalized(newName).isEmpty)
                        .accessibilityIdentifier("companion-add")
                }

                if !selectedNames.isEmpty {
                    Section("已选择") {
                        Text(selectedNames.joined(separator: "、"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索已有饭搭子")
            .navigationTitle("和谁一起吃")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("无法保存饭搭子", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "请重试。")
            }
        }
    }

    private var activeCompanions: [DiningCompanion] {
        companions.filter { $0.deletedAt == nil && $0.ownerUserId == ownerUserID }
    }

    private var filteredCompanions: [DiningCompanion] {
        let query = PrivateDirectoryName.normalized(searchText)
        return activeCompanions
            .filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) }
            .sorted { left, right in
                let leftUsage = usageByID[left.remoteID ?? ""] ?? (0, .distantPast)
                let rightUsage = usageByID[right.remoteID ?? ""] ?? (0, .distantPast)
                if leftUsage.1 != rightUsage.1 { return leftUsage.1 > rightUsage.1 }
                if leftUsage.0 != rightUsage.0 { return leftUsage.0 > rightUsage.0 }
                return left.updatedAt > right.updatedAt
            }
    }

    private var usageByID: [String: (count: Int, latest: Date)] {
        var result: [String: (Int, Date)] = [:]
        for visit in visits where visit.deletedAt == nil {
            for id in visit.companionIDs {
                let current = result[id] ?? (0, .distantPast)
                result[id] = (current.0 + 1, max(current.1, visit.visitedAt))
            }
        }
        return result
    }

    private func toggle(_ companion: DiningCompanion) {
        let shouldDismissAfterSearch = !searchText.isEmpty
        guard let remoteID = companion.remoteID else { return }
        if let index = selectedIDs.firstIndex(of: remoteID) {
            selectedIDs.remove(at: index)
            if selectedNames.indices.contains(index) { selectedNames.remove(at: index) }
        } else {
            selectedIDs.append(remoteID)
            selectedNames.append(companion.displayName)
        }
        dismissSearch()
        if shouldDismissAfterSearch { dismiss() }
    }

    private func add() {
        do {
            let companion = try LocalCompanionSourceStore(context: modelContext)
                .findOrCreateCompanion(name: newName, ownerUserID: ownerUserID)
            try modelContext.save()
            if let remoteID = companion.remoteID, !selectedIDs.contains(remoteID) {
                selectedIDs.append(remoteID)
                selectedNames.append(companion.displayName)
            }
            newName = ""
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "饭搭子没有保存成功。"
        }
    }

}

struct RecommendationSourcePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissSearch) private var dismissSearch
    @Environment(\.modelContext) private var modelContext
    @Query private var sources: [RecommendationSource]
    @Query private var visits: [Visit]

    @Binding var selectedID: String?
    @Binding var selectedTypeRawValue: String?
    @Binding var selectedUserID: String?
    @Binding var selectedText: String
    var ownerUserID: String = "local"

    @State private var searchText = ""
    @State private var newName = ""
    @State private var newType: RecommendationSourceType = .other
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if activeSources.isEmpty {
                    ContentUnavailableView(
                        "还没有推荐来源",
                        systemImage: "sparkles",
                        description: Text("写下真实来源名称，下次可以直接复用。")
                    )
                } else if filteredSources.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    Section(searchText.isEmpty ? "最近使用" : "搜索结果") {
                        ForEach(filteredSources) { source in
                            Button { select(source) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(source.displayName)
                                            .foregroundStyle(.primary)
                                        Text(source.sourceType.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedID == source.remoteID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .accessibilityIdentifier("source-option-\(source.id.uuidString)")
                        }
                    }
                }

                Section("新增来源") {
                    TextField("例如：朋友小王、某美食博主", text: $newName)
                        .accessibilityIdentifier("source-new-name")
                    Picker("来源类型", selection: $newType) {
                        ForEach(RecommendationSourceType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    Button("新增并选中", systemImage: "plus.circle.fill", action: add)
                        .disabled(PrivateDirectoryName.normalized(newName).isEmpty)
                        .accessibilityIdentifier("source-add")
                }

                if selectedID != nil || !selectedText.isEmpty {
                    Section {
                        Button("清除推荐来源", role: .destructive) {
                            selectedID = nil
                            selectedTypeRawValue = nil
                            selectedUserID = nil
                            selectedText = ""
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索已有来源")
            .navigationTitle("推荐来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("无法保存推荐来源", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "请重试。")
            }
        }
    }

    private var activeSources: [RecommendationSource] {
        sources.filter { $0.deletedAt == nil && $0.ownerUserId == ownerUserID }
    }

    private var filteredSources: [RecommendationSource] {
        let query = PrivateDirectoryName.normalized(searchText)
        return activeSources
            .filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) }
            .sorted { left, right in
                let leftUsage = usageByID[left.remoteID ?? ""] ?? (0, .distantPast)
                let rightUsage = usageByID[right.remoteID ?? ""] ?? (0, .distantPast)
                if leftUsage.1 != rightUsage.1 { return leftUsage.1 > rightUsage.1 }
                if leftUsage.0 != rightUsage.0 { return leftUsage.0 > rightUsage.0 }
                return left.updatedAt > right.updatedAt
            }
    }

    private var usageByID: [String: (count: Int, latest: Date)] {
        var result: [String: (Int, Date)] = [:]
        for visit in visits where visit.deletedAt == nil {
            guard let id = visit.recommendationSourceID else { continue }
            let current = result[id] ?? (0, .distantPast)
            result[id] = (current.0 + 1, max(current.1, visit.visitedAt))
        }
        return result
    }

    private func select(_ source: RecommendationSource) {
        let shouldDismissAfterSearch = !searchText.isEmpty
        selectedID = source.remoteID
        selectedTypeRawValue = source.sourceType.rawValue
        selectedUserID = source.linkedTasteMapUserId
        selectedText = source.displayName
        dismissSearch()
        if shouldDismissAfterSearch { dismiss() }
    }

    private func add() {
        do {
            let source = try LocalCompanionSourceStore(context: modelContext)
                .findOrCreateRecommendationSource(
                    name: newName,
                    type: newType,
                    ownerUserID: ownerUserID
                )
            try modelContext.save()
            select(source)
            newName = ""
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "推荐来源没有保存成功。"
        }
    }

}
