import SwiftUI

@MainActor
private struct RoulettePreviewHost: View {
    let fixture: RoulettePreviewFixture

    var body: some View {
        NavigationStack {
            RestaurantRouletteExperienceView(
                candidates: fixture.candidates,
                restaurants: fixture.restaurants,
                photos: fixture.photos,
                preferredCity: "杭州",
                initialSource: fixture.source,
                initialCity: fixture.city,
                initialResultGlobalKey: fixture.resultGlobalKey,
                forceReducedMotion: fixture.reduceMotion
            )
        }
    }
}

@MainActor
private struct RoulettePreviewFixture {
    let candidates: [RouletteCandidate]
    let restaurants: [Restaurant]
    let photos: [PhotoAsset]
    let source: RouletteCandidateSource
    let city: String?
    let resultGlobalKey: String?
    let reduceMotion: Bool

    static func make(
        count: Int,
        statuses: [RestaurantStatus] = [.wantToGo, .visited],
        source: RouletteCandidateSource = .all,
        city: String? = "杭州",
        includePhoto: Bool = false,
        longName: Bool = false,
        showResult: Bool = false,
        reduceMotion: Bool = false
    ) -> RoulettePreviewFixture {
        var restaurants: [Restaurant] = []
        var photos: [PhotoAsset] = []
        var records: [RouletteRestaurantRecord] = []
        let names = ["青岚寿司", "雨巷火锅", "野火烧鸟", "小满食堂", "云边小馆", "山茶面馆", "白露咖啡", "松风料理"]
        for index in 0..<count {
            let id = uuid(60_000 + index)
            let status = statuses[index % max(1, statuses.count)]
            let name = longName && index == 0
                ? "这是一家名字特别长但结果必须完整显示的杭州江南创意融合料理餐厅（湖滨总店）"
                : "\(names[index % names.count])\(index >= names.count ? " · \(index + 1)" : "")"
            let restaurant = Restaurant(
                id: id, name: name, address: "杭州市西湖区好味路 \(index + 1) 号",
                latitude: 30.24 + Double(index) * 0.0001,
                longitude: 120.15 + Double(index) * 0.0001,
                appleMapItemIdentifier: "preview-roulette-\(index)", city: "杭州",
                status: status, syncStatus: .synced
            )
            restaurants.append(restaurant)
            let photoID: UUID?
            if includePhoto && index == 0 {
                let photo = PhotoAsset(
                    id: uuid(70_000 + index), restaurantId: id, kind: .restaurantMarker,
                    mimeType: "image/jpeg", byteSize: 20_000, width: 1_200, height: 900,
                    visibility: .private, uploadState: .localOnly, syncStatus: .synced
                )
                photos.append(photo)
                photoID = photo.id
            } else {
                photoID = nil
            }
            records.append(RouletteRestaurantRecord(
                restaurantID: id,
                globalKey: "apple_maps:preview-roulette-\(index)",
                displayName: name,
                address: restaurant.address,
                city: "杭州",
                status: status,
                updatedAt: Date(timeIntervalSince1970: 1_777_000_000 + Double(index)),
                deletedAt: nil,
                averageRating: status == .visited ? 3.5 + Double(index % 4) * 0.5 : nil,
                visitCount: status == .visited ? index % 4 + 1 : 0,
                latestVisitAt: status == .visited ? .now.addingTimeInterval(Double(-index * 86_400)) : nil,
                photoID: photoID,
                categories: index.isMultiple(of: 2) ? ["日料"] : ["中餐"],
                markerEmoji: ["🍣", "🍲", "🍢", "🍜"][index % 4],
                latitude: restaurant.latitude,
                longitude: restaurant.longitude
            ))
        }
        let candidates = RestaurantRouletteEngine.candidates(from: records)
        return RoulettePreviewFixture(
            candidates: candidates,
            restaurants: restaurants,
            photos: photos,
            source: source,
            city: city,
            resultGlobalKey: showResult ? candidates.first?.globalKey : nil,
            reduceMotion: reduceMotion
        )
    }

    private static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}

#Preview("01 Empty") {
    RoulettePreviewHost(fixture: .make(count: 0, city: nil))
}

#Preview("02 One Restaurant") {
    RoulettePreviewHost(fixture: .make(count: 1))
}

#Preview("03 Two Restaurants") {
    RoulettePreviewHost(fixture: .make(count: 2))
}

#Preview("04 Six Restaurants") {
    RoulettePreviewHost(fixture: .make(count: 6))
}

#Preview("05 Twelve Restaurants") {
    RoulettePreviewHost(fixture: .make(count: 12))
}

#Preview("06 Thirty Restaurants") {
    RoulettePreviewHost(fixture: .make(count: 30))
}

#Preview("07 One Hundred Plus") {
    RoulettePreviewHost(fixture: .make(count: 120))
}

#Preview("08 Want To Go Only") {
    RoulettePreviewHost(fixture: .make(count: 8, statuses: [.wantToGo], source: .wantToGo))
}

#Preview("09 Visited Only") {
    RoulettePreviewHost(fixture: .make(count: 8, statuses: [.visited], source: .visited))
}

#Preview("10 Mixed") {
    RoulettePreviewHost(fixture: .make(count: 8, statuses: [.visited, .wantToGo]))
}

#Preview("11 With Photo") {
    RoulettePreviewHost(fixture: .make(count: 6, includePhoto: true, showResult: true))
}

#Preview("12 No Photo") {
    RoulettePreviewHost(fixture: .make(count: 6, showResult: true))
}

#Preview("13 Result") {
    RoulettePreviewHost(fixture: .make(count: 8, showResult: true))
}

#Preview("14 Long Restaurant Name") {
    RoulettePreviewHost(fixture: .make(count: 6, longName: true, showResult: true))
}

#Preview("15 Filter Empty") {
    RoulettePreviewHost(fixture: .make(count: 6, statuses: [.visited], source: .wantToGo))
}

#Preview("16 Small Screen") {
    RoulettePreviewHost(fixture: .make(count: 8))
        .frame(width: 320, height: 640)
}

#Preview("17 Large Type") {
    RoulettePreviewHost(fixture: .make(count: 6, showResult: true))
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("18 Reduce Motion") {
    RoulettePreviewHost(fixture: .make(count: 8, reduceMotion: true))
}
