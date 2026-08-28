import SwiftData
import SwiftUI

#Preview("P2-E · 最小 Visit") {
    P2EVisitContextPreviewFactory.editor(.minimal)
}

#Preview("P2-E · 全部用餐上下文") {
    P2EVisitContextPreviewFactory.editor(.complete)
}

#Preview("P2-E · 有用餐场景") {
    P2EVisitContextPreviewFactory.editor(.withOccasions)
}

#Preview("P2-E · 无用餐场景") {
    P2EVisitContextPreviewFactory.editor(.withoutOccasions)
}

#Preview("P2-E · 未记录等位") {
    P2EVisitContextPreviewFactory.editor(.waitNil)
}

#Preview("P2-E · 明确无需等位") {
    P2EVisitContextPreviewFactory.editor(.waitZero)
}

#Preview("P2-E · 较长等位") {
    P2EVisitContextPreviewFactory.editor(.longWait)
}

#Preview("P2-E · 支付信息为空") {
    P2EVisitContextPreviewFactory.editor(.paymentEmpty)
}

#Preview("P2-E · 公开可见") {
    P2EVisitContextPreviewFactory.editor(.publicVisibility)
}

#Preview("P2-E · 全字段小屏", traits: .fixedLayout(width: 320, height: 568)) {
    P2EVisitContextPreviewFactory.editor(.smallScreen)
}

@MainActor
private enum P2EVisitContextPreviewFactory {
    enum State {
        case minimal
        case complete
        case withOccasions
        case withoutOccasions
        case waitNil
        case waitZero
        case longWait
        case paymentEmpty
        case publicVisibility
        case smallScreen
    }

    static func editor(_ state: State) -> some View {
        let container = try! TasteMapPersistence.makeContainer(inMemory: true)
        let restaurant = Restaurant(
            name: "湖边小馆",
            address: "杭州市上城区湖滨路 18 号",
            latitude: 30.259,
            longitude: 120.168,
            appleMapItemIdentifier: "p2e-preview-apple",
            city: "杭州",
            status: .visited,
            syncStatus: .synced
        )
        container.mainContext.insert(restaurant)
        let visit = previewVisit(state, restaurantID: restaurant.id)
        container.mainContext.insert(visit)
        return VisitEditorView(restaurant: restaurant, visit: visit)
            .environment(PremiumEntitlementService.preview(status: .premium))
            .modelContainer(container)
    }

    private static func previewVisit(_ state: State, restaurantID: UUID) -> Visit {
        let isComplete = state == .complete || state == .smallScreen
        let occasions: [VisitDiningOccasion] = switch state {
        case .withOccasions: [.friends, .celebration]
        case .complete, .smallScreen: [.date, .friends, .other]
        default: []
        }
        let queue: VisitQueueDuration? = switch state {
        case .waitZero: .noWait
        case .longWait: .over120
        case .complete, .smallScreen: .under60
        default: nil
        }
        return Visit(
            restaurantId: restaurantID,
            visitedAt: Date(timeIntervalSince1970: 1_787_592_000),
            rating: isComplete ? 4.5 : nil,
            valueRating: isComplete ? 5 : nil,
            environmentRating: isComplete ? 4 : nil,
            serviceRating: isComplete ? 4.5 : nil,
            note: isComplete ? "窗边位置很舒服，晚餐节奏也刚刚好。" : nil,
            myActualSpend: isComplete ? 188 : nil,
            totalPrice: isComplete ? 756 : nil,
            pricePerPerson: isComplete ? 189 : nil,
            diningMode: .dineIn,
            visibility: state == .publicVisibility ? .public : .private,
            paymentMode: (state == .paymentEmpty || !isComplete) ? nil : .aa,
            queueDuration: queue,
            diningOccasions: occasions,
            diningOccasionText: occasions.contains(.other) ? "旅行聚餐" : nil,
            valueTags: isComplete ? ["划算", "份量合适"] : [],
            environmentTags: isComplete ? ["有氛围", "景观好"] : [],
            serviceTags: isComplete ? ["热情", "高效"] : [],
            noiseLevel: isComplete ? .normal : nil,
            diningDuration: isComplete ? .under30 : nil,
            portionLevel: isComplete ? .generous : nil,
            transportConvenience: isComplete ? .veryConvenient : nil,
            specialNotes: isComplete ? "周末晚餐建议提前到店取号；靠窗桌数量有限。" : nil,
            partySize: isComplete ? 4 : nil,
            serverVersion: 2,
            syncStatus: .synced
        )
    }
}
