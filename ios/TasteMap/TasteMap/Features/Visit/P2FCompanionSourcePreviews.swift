import SwiftData
import SwiftUI

#Preview("P2-F · 未记录饭搭子与来源") {
    P2FCompanionSourcePreviewFactory.editor(.empty)
}

#Preview("P2-F · 一位饭搭子") {
    P2FCompanionSourcePreviewFactory.editor(.oneCompanion)
}

#Preview("P2-F · 多位饭搭子与完整 Visit") {
    P2FCompanionSourcePreviewFactory.editor(.complete)
}

#Preview("P2-F · 长名字与较多分析项") {
    P2FCompanionSourcePreviewFactory.editor(.longNames)
}

#Preview("P2-F · 饭搭子新增与搜索") {
    P2FCompanionSourcePreviewFactory.companionPicker(hasRecords: true)
}

#Preview("P2-F · 还没有饭搭子") {
    P2FCompanionSourcePreviewFactory.companionPicker(hasRecords: false)
}

#Preview("P2-F · 多种推荐来源") {
    P2FCompanionSourcePreviewFactory.sourcePicker(hasRecords: true)
}

#Preview("P2-F · 还没有推荐来源") {
    P2FCompanionSourcePreviewFactory.sourcePicker(hasRecords: false)
}

#Preview("P2-F · 多人完整 Visit 小屏", traits: .fixedLayout(width: 320, height: 568)) {
    P2FCompanionSourcePreviewFactory.editor(.smallScreen)
}

@MainActor
private enum P2FCompanionSourcePreviewFactory {
    enum State {
        case empty
        case oneCompanion
        case complete
        case longNames
        case smallScreen
    }

    static func editor(_ state: State) -> some View {
        let container = try! TasteMapPersistence.makeContainer(inMemory: true)
        let restaurant = Restaurant(
            name: "湖畔小馆",
            address: "杭州市上城区湖滨路 18 号",
            latitude: 30.259,
            longitude: 120.168,
            appleMapItemIdentifier: "p2f-preview-apple",
            city: "杭州",
            status: .visited,
            syncStatus: .synced
        )
        container.mainContext.insert(restaurant)

        let companionNames: [String]
        switch state {
        case .empty:
            companionNames = []
        case .oneCompanion:
            companionNames = ["小王"]
        case .complete, .smallScreen:
            companionNames = ["小王", "妈妈", "大学室友 Alex"]
        case .longNames:
            companionNames = [
                "每次都会认真研究菜单的大学室友",
                "从上海专程来杭州一起吃饭的老朋友",
                "同事 Alex",
            ]
        }

        let companions = companionNames.map { name in
            DiningCompanion(displayName: name, syncStatus: .synced)
        }
        companions.forEach(container.mainContext.insert)

        let source: RecommendationSource? = switch state {
        case .empty, .oneCompanion:
            nil
        case .complete, .smallScreen:
            RecommendationSource(
                displayName: "朋友小李的杭州私藏清单",
                sourceType: .friend,
                syncStatus: .synced
            )
        case .longNames:
            RecommendationSource(
                displayName: "小红书上那篇收藏了很久的杭州秋日餐厅合集",
                sourceType: .xiaohongshu,
                syncStatus: .synced
            )
        }
        if let source { container.mainContext.insert(source) }

        let isComplete = state == .complete || state == .smallScreen || state == .longNames
        let visit = Visit(
            restaurantId: restaurant.id,
            visitedAt: Date(timeIntervalSince1970: 1_787_592_000),
            rating: isComplete ? 4.5 : nil,
            valueRating: isComplete ? 4 : nil,
            environmentRating: isComplete ? 5 : nil,
            serviceRating: isComplete ? 4.5 : nil,
            note: isComplete ? "一起坐在窗边慢慢吃完，菜单里还有几道菜值得下次再来。" : nil,
            myActualSpend: isComplete ? 188 : nil,
            diningMode: .dineIn,
            visibility: .private,
            diningOccasions: isComplete ? [.friends, .celebration] : [],
            companionIDs: companions.compactMap(\.remoteID),
            companionNames: companionNames,
            recommendationSourceID: source?.remoteID,
            recommendationSourceType: source?.sourceType,
            recommendationSourceText: source?.displayName,
            partySize: companionNames.isEmpty ? nil : companionNames.count + 1,
            syncStatus: .synced
        )
        container.mainContext.insert(visit)
        return VisitEditorView(restaurant: restaurant, visit: visit)
            .modelContainer(container)
    }

    static func companionPicker(hasRecords: Bool) -> some View {
        let container = try! TasteMapPersistence.makeContainer(inMemory: true)
        if hasRecords {
            let restaurantID = UUID()
            for (index, name) in ["妈妈", "小王", "大学室友 Alex", "同事小陈"].enumerated() {
                let companion = DiningCompanion(
                    displayName: name,
                    updatedAt: Date.now.addingTimeInterval(Double(-index * 3_600)),
                    syncStatus: .synced
                )
                container.mainContext.insert(companion)
                if let remoteID = companion.remoteID, index < 3 {
                    container.mainContext.insert(Visit(
                        restaurantId: restaurantID,
                        visitedAt: Date.now.addingTimeInterval(Double(-index * 86_400)),
                        companionIDs: [remoteID],
                        companionNames: [name],
                        syncStatus: .synced
                    ))
                }
            }
        }
        return P2FCompanionPickerPreviewHost()
            .modelContainer(container)
    }

    static func sourcePicker(hasRecords: Bool) -> some View {
        let container = try! TasteMapPersistence.makeContainer(inMemory: true)
        if hasRecords {
            let restaurantID = UUID()
            let records: [(String, RecommendationSourceType)] = [
                ("朋友小李", .friend),
                ("小红书 @杭州吃货日记", .xiaohongshu),
                ("收藏很久的城市散步与餐厅合集", .blogger),
                ("自己路过发现", .self),
            ]
            for (index, record) in records.enumerated() {
                let source = RecommendationSource(
                    displayName: record.0,
                    sourceType: record.1,
                    updatedAt: Date.now.addingTimeInterval(Double(-index * 3_600)),
                    syncStatus: .synced
                )
                container.mainContext.insert(source)
                if let remoteID = source.remoteID, index < 3 {
                    container.mainContext.insert(Visit(
                        restaurantId: restaurantID,
                        visitedAt: Date.now.addingTimeInterval(Double(-index * 86_400)),
                        recommendationSourceID: remoteID,
                        recommendationSourceType: record.1,
                        recommendationSourceText: record.0,
                        syncStatus: .synced
                    ))
                }
            }
        }
        return P2FSourcePickerPreviewHost()
            .modelContainer(container)
    }
}

private struct P2FCompanionPickerPreviewHost: View {
    @State private var selectedIDs: [String] = []
    @State private var selectedNames: [String] = []

    var body: some View {
        CompanionPickerSheet(selectedIDs: $selectedIDs, selectedNames: $selectedNames)
    }
}

private struct P2FSourcePickerPreviewHost: View {
    @State private var selectedID: String?
    @State private var selectedTypeRawValue: String?
    @State private var selectedUserID: String?
    @State private var selectedText = ""

    var body: some View {
        RecommendationSourcePickerSheet(
            selectedID: $selectedID,
            selectedTypeRawValue: $selectedTypeRawValue,
            selectedUserID: $selectedUserID,
            selectedText: $selectedText
        )
    }
}
