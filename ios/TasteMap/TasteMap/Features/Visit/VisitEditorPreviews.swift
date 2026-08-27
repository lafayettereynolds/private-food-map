import SwiftData
import SwiftUI

#Preview("Visit Editor · 新建默认") {
    VisitEditorPreviewFactory.make(.newDefault)
}

#Preview("Visit Editor · 完整填写") {
    VisitEditorPreviewFactory.make(.complete)
}

#Preview("Visit Editor · 未评分") {
    VisitEditorPreviewFactory.make(.unrated)
}

#Preview("Visit Editor · 未填写消费") {
    VisitEditorPreviewFactory.make(.noSpend)
}

#Preview("Visit Editor · 未填写人数") {
    VisitEditorPreviewFactory.make(.noPartySize)
}

#Preview("Visit Editor · 到店") {
    VisitEditorPreviewFactory.make(.dineIn)
}

#Preview("Visit Editor · 外卖") {
    VisitEditorPreviewFactory.make(.takeout)
}

#Preview("Visit Editor · 编辑已有 Visit") {
    VisitEditorPreviewFactory.make(.editing)
}

#Preview("Visit Editor · 长备注") {
    VisitEditorPreviewFactory.make(.longNote)
}

#Preview("Visit Editor · 小屏", traits: .fixedLayout(width: 320, height: 568)) {
    VisitEditorPreviewFactory.make(.smallScreen)
}

@MainActor
private enum VisitEditorPreviewFactory {
    enum State: Equatable {
        case newDefault
        case complete
        case unrated
        case noSpend
        case noPartySize
        case dineIn
        case takeout
        case editing
        case longNote
        case smallScreen
    }

    static func make(_ state: State) -> some View {
        let container = try! TasteMapPersistence.makeContainer(inMemory: true)
        let restaurant = Restaurant(
            name: "湖边小馆",
            address: "杭州市上城区湖滨路 18 号",
            latitude: 30.259,
            longitude: 120.168,
            appleMapItemIdentifier: "preview-visit-editor",
            city: "杭州",
            status: state == .newDefault ? .wantToGo : .visited,
            syncStatus: .synced
        )
        container.mainContext.insert(restaurant)

        if state == .newDefault {
            return AnyView(VisitEditorView(restaurant: restaurant).modelContainer(container))
        }

        let visit = previewVisit(state, restaurantID: restaurant.id)
        container.mainContext.insert(visit)
        return AnyView(
            VisitEditorView(restaurant: restaurant, visit: visit)
                .modelContainer(container)
        )
    }

    private static func previewVisit(_ state: State, restaurantID: UUID) -> Visit {
        Visit(
            restaurantId: restaurantID,
            visitedAt: Date(timeIntervalSince1970: 1_787_592_000),
            rating: state == .unrated ? nil : 4.5,
            note: state == .longNote
                ? "这是一段较长的到访记录，用来确认多行文字、动态字体和小屏设备中依然能够完整编辑，不会遮挡保存与删除入口。味道、氛围和当时的心情都可以保留下来。"
                : "窗边的位置很舒服，下次还想再来。",
            myActualSpend: state == .noSpend ? nil : 168.5,
            diningMode: state == .takeout ? .takeout : .dineIn,
            partySize: state == .noPartySize ? nil : 2,
            serverVersion: state == .editing ? 3 : 0,
            syncStatus: state == .editing ? .synced : .pending
        )
    }
}
