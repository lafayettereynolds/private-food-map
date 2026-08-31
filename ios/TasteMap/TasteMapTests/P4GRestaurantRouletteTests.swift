import Foundation
import Testing
@testable import TasteMap

@Suite("P4-G Restaurant Roulette")
struct P4GRestaurantRouletteTests {
    @Test("Empty, single and multiple candidate selection remain inside the pool")
    func basicSelection() {
        var generator = SeededRouletteGenerator(seed: 7)
        #expect(RestaurantRouletteEngine.select(
            from: [], excludingImmediateRepeat: nil, using: &generator
        ) == nil)

        let one = candidate(1)
        #expect(RestaurantRouletteEngine.select(
            from: [one], excludingImmediateRepeat: nil, using: &generator
        ) == one)
        let pool = (1...8).map { candidate($0) }
        for _ in 0..<200 {
            let selected = RestaurantRouletteEngine.select(
                from: pool, excludingImmediateRepeat: nil, using: &generator
            )
            #expect(selected.map(pool.contains) == true)
        }
    }

    @Test("Tombstones and invalid coordinates are excluded while Global identity deduplicates")
    func validityAndGlobalIdentity() {
        let old = record(1, globalKey: "apple_maps:same", updatedAt: date(100))
        let newest = record(2, globalKey: "APPLE_MAPS:same", updatedAt: date(200))
        let tombstone = record(3, globalKey: "apple_maps:deleted", deletedAt: date(300))
        let invalid = record(4, globalKey: "apple_maps:invalid", latitude: .nan)
        let blank = record(5, globalKey: "apple_maps:blank", name: "   ")

        let values = RestaurantRouletteEngine.candidates(
            from: [old, newest, tombstone, invalid, blank]
        )

        #expect(values.count == 1)
        #expect(values[0].restaurantID == newest.restaurantID)
        #expect(values[0].globalKey == newest.globalKey)
    }

    @Test("Status, city and session exclusions are deterministic and do not invent filters")
    func filtersAndStableOrdering() {
        let values = RestaurantRouletteEngine.candidates(from: [
            record(3, name: "云边小馆", city: "杭州", status: .visited),
            record(1, name: "青岚寿司", city: "杭州", status: .wantToGo),
            record(2, name: "雨巷火锅", city: "上海", status: .wantToGo),
        ])
        let firstPass = RestaurantRouletteEngine.filtered(values, by: RouletteFilter(
            source: .wantToGo,
            city: " 杭州 ",
            excludedGlobalKeys: []
        ))
        let secondPass = RestaurantRouletteEngine.filtered(Array(values.reversed()), by: RouletteFilter(
            source: .wantToGo,
            city: "杭州",
            excludedGlobalKeys: []
        ))
        #expect(firstPass.map(\.globalKey) == secondPass.map(\.globalKey))
        #expect(firstPass.map(\.displayName) == ["青岚寿司"])

        let excluded = RestaurantRouletteEngine.filtered(values, by: RouletteFilter(
            source: .all,
            city: "杭州",
            excludedGlobalKeys: Set(firstPass.map(\.globalKey))
        ))
        #expect(excluded.map(\.displayName) == ["云边小馆"])
    }

    @Test("Default geographic scope prefers Profile city then deterministic local majority")
    func geographicScope() {
        let values = RestaurantRouletteEngine.candidates(from: [
            record(1, city: "杭州"), record(2, city: "杭州"),
            record(3, city: "上海"), record(4, city: "北京"),
        ])
        #expect(RestaurantRouletteEngine.defaultCity(for: values, preferredCity: "上海") == "上海")
        #expect(RestaurantRouletteEngine.defaultCity(for: values, preferredCity: "东京") == "杭州")
        #expect(RestaurantRouletteEngine.cities(in: values) == ["北京", "杭州", "上海"])
        #expect(RestaurantRouletteEngine.defaultCity(
            for: [candidate(99, city: "")], preferredCity: nil
        ) == nil)
    }

    @Test("Immediate result is excluded once and becomes eligible again later")
    func immediateRepeatPrevention() {
        let pool = [candidate(1), candidate(2)]
        var generator = SeededRouletteGenerator(seed: 42)
        let first = RestaurantRouletteEngine.select(
            from: pool, excludingImmediateRepeat: nil, using: &generator
        )!
        let second = RestaurantRouletteEngine.select(
            from: pool, excludingImmediateRepeat: first.globalKey, using: &generator
        )!
        let third = RestaurantRouletteEngine.select(
            from: pool, excludingImmediateRepeat: second.globalKey, using: &generator
        )!
        #expect(first.globalKey != second.globalKey)
        #expect(second.globalKey != third.globalKey)
        #expect(first.globalKey == third.globalKey)
    }

    @Test("Deterministic RNG reaches every candidate without pinning first or last")
    func randomCoverage() {
        let pool = (0..<20).map { candidate($0) }
        var generator = SeededRouletteGenerator(seed: 0xCAFE_BABE)
        var seen: Set<String> = []
        for _ in 0..<8_000 {
            if let result = RestaurantRouletteEngine.select(
                from: pool, excludingImmediateRepeat: nil, using: &generator
            ) {
                seen.insert(result.globalKey)
            }
        }
        #expect(seen == Set(pool.map(\.globalKey)))
        #expect(seen.contains(pool[0].globalKey))
        #expect(seen.contains(pool[pool.count - 1].globalKey))
    }

    @Test("Selected index maps exactly to the pointer and every candidate owns one segment")
    func animationGeometry() {
        for candidateCount in [2, 3, 8, 12, 30, 100, 1_000] {
            let visualCount = RestaurantRouletteEngine.visualSegmentCount(candidateCount: candidateCount)
            #expect(visualCount == candidateCount)
            for selectedIndex in 0..<candidateCount {
                let rotation = RestaurantRouletteEngine.targetRotation(
                    currentRotation: 137,
                    selectedIndex: selectedIndex,
                    candidateCount: candidateCount,
                    fullTurns: 5
                )
                #expect(rotation > 5 * 360)
                #expect(RestaurantRouletteEngine.pointerVisualIndex(
                    finalRotation: rotation,
                    visualSegmentCount: visualCount
                ) == RestaurantRouletteEngine.visualIndex(
                    selectedIndex: selectedIndex,
                    candidateCount: candidateCount
                ))
            }
        }
    }

    @Test("Large library keeps all records searchable while active wheel stays exact and bounded")
    func largePool() {
        let records = (0..<1_000).map { index in
            record(
                index,
                city: index.isMultiple(of: 2) ? "杭州" : "上海",
                status: index.isMultiple(of: 3) ? .wantToGo : .visited
            )
        }
        let candidates = RestaurantRouletteEngine.candidates(from: records)
        let hangzhou = RestaurantRouletteEngine.filtered(
            candidates,
            by: RouletteFilter(source: .all, city: "杭州")
        )
        #expect(candidates.count == 1_000)
        #expect(hangzhou.count == 500)
        let selectedKeys = RestaurantRouletteEngine.defaultActiveGlobalKeys(from: hangzhou)
        let active = RestaurantRouletteEngine.activeCandidates(
            from: hangzhou,
            selectedGlobalKeys: selectedKeys
        )
        #expect(active.count == RestaurantRouletteEngine.maximumActiveCandidateCount)
        #expect(Set(active.map(\.globalKey)).count == active.count)
        #expect(RestaurantRouletteEngine.visualSegmentCount(candidateCount: active.count) == active.count)
    }

    @Test("Preferred entry is seeded once and selection never invents or duplicates Restaurants")
    func preferredCandidateSelection() throws {
        let candidates = (0..<30).map { candidate($0) }
        let preferred = try #require(candidates.last)
        let selectedKeys = RestaurantRouletteEngine.defaultActiveGlobalKeys(
            from: candidates,
            preferredGlobalKey: preferred.globalKey
        )
        let active = RestaurantRouletteEngine.activeCandidates(
            from: candidates,
            selectedGlobalKeys: selectedKeys
        )

        #expect(selectedKeys.count == RestaurantRouletteEngine.maximumActiveCandidateCount)
        #expect(active.contains(preferred))
        #expect(active.allSatisfy(candidates.contains))
        #expect(Set(active.map(\.globalKey)).count == active.count)
        #expect(RestaurantRouletteEngine.visualSegmentCount(candidateCount: active.count) == active.count)
    }

    @Test("Result metadata uses active Visits, user Photo and factual state")
    @MainActor
    func resultMetadata() throws {
        let id = uuid(1)
        let restaurant = Restaurant(
            id: id, name: "青岚寿司", address: "西湖区 1 号", latitude: 30.25,
            longitude: 120.16, appleMapItemIdentifier: "apple-result", city: "杭州",
            status: .visited, syncStatus: .synced,
            remoteRecordData: try contractData(id: id, tags: ["日料", "寿司", "日料"])
        )
        let visits = [
            Visit(restaurantId: id, visitedAt: date(100), rating: 4, syncStatus: .synced),
            Visit(restaurantId: id, visitedAt: date(200), rating: 5, syncStatus: .synced),
            Visit(restaurantId: id, visitedAt: date(300), rating: 1, deletedAt: date(301), syncStatus: .synced),
        ]
        let photo = PhotoAsset(
            restaurantId: id, kind: .restaurantMarker, mimeType: "image/jpeg",
            byteSize: 10, sortOrder: 0, uploadState: .localOnly, syncStatus: .synced
        )
        let candidates = RestaurantRouletteEngine.candidates(from: RouletteRestaurantRecord.capture(
            restaurants: [restaurant], visits: visits, photos: [photo]
        ))
        let result = try #require(candidates.first)
        #expect(result.globalKey == "apple_maps:contract-1")
        #expect(result.averageRating == 4.5)
        #expect(result.visitCount == 2)
        #expect(result.latestVisitAt == date(200))
        #expect(result.photoID == photo.id)
        #expect(result.categories == ["日料", "寿司"])
        #expect(result.statusDetail == "你已经去过 2 次")
    }

    @Test("Identity fallback supports Apple Maps-only and stable manual Restaurants")
    @MainActor
    func identityFallback() {
        let apple = Restaurant(
            id: uuid(2), name: "Apple 店", address: "地址", latitude: 30,
            longitude: 120, appleMapItemIdentifier: "apple-only", city: "杭州"
        )
        let manual = Restaurant(
            id: uuid(3), name: "手工店", address: "地址", latitude: 30,
            longitude: 120, city: "杭州", remoteID: "tm-restaurant-manual"
        )
        let candidates = RestaurantRouletteEngine.candidates(from: RouletteRestaurantRecord.capture(
            restaurants: [manual, apple], visits: [], photos: []
        ))
        #expect(Set(candidates.map(\.globalKey)) == [
            "apple_maps:apple-only", "manual:tastemap:tm-restaurant-manual",
        ])
    }

    private func candidate(
        _ index: Int,
        city: String = "杭州",
        status: RestaurantStatus = .visited
    ) -> RouletteCandidate {
        RouletteCandidate(
            restaurantID: uuid(index), globalKey: "apple_maps:candidate-\(index)",
            displayName: "候选餐厅 \(index)", address: "地址 \(index)", city: city,
            status: status, averageRating: status == .visited ? 4 : nil,
            visitCount: status == .visited ? 1 : 0,
            latestVisitAt: status == .visited ? date(index) : nil,
            photoID: nil, categories: [], markerEmoji: "🍽️", updatedAt: date(index)
        )
    }

    private func record(
        _ index: Int,
        globalKey: String? = nil,
        name: String? = nil,
        city: String = "杭州",
        status: RestaurantStatus = .visited,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        latitude: Double = 30.25
    ) -> RouletteRestaurantRecord {
        RouletteRestaurantRecord(
            restaurantID: uuid(index),
            globalKey: globalKey ?? "apple_maps:record-\(index)",
            displayName: name ?? "餐厅 \(index)", address: "地址 \(index)", city: city,
            status: status, updatedAt: updatedAt ?? date(index), deletedAt: deletedAt,
            averageRating: nil, visitCount: 0, latestVisitAt: nil, photoID: nil,
            categories: [], markerEmoji: "🍽️", latitude: latitude, longitude: 120.16
        )
    }

    @MainActor
    private func contractData(id: UUID, tags: [String]) throws -> Data {
        let timestamp = "2026-08-29T00:00:00.000Z"
        let identity = try RestaurantPlaceIdentityContract(
            provider: .appleMaps, externalId: "contract-1", isPrimary: true,
            createdAt: timestamp, updatedAt: timestamp
        )
        let contract = try RestaurantJSONContractV1(
            id: id.uuidString.lowercased(), userId: "tm_test", placeIdentities: [identity],
            name: "青岚寿司", address: "西湖区 1 号", city: "杭州",
            latitude: 30.25, longitude: 120.16, status: .visited,
            preferenceLevel: .like, overallRating: nil, foodRating: nil,
            environmentRating: nil, serviceRating: nil, valueRating: nil,
            tags: tags, longTermNote: "", pricePerPerson: nil, phone: nil,
            openingHours: nil, markerType: .emoji, markerPhotoId: nil,
            merchantImageUrl: nil, markerEmoji: "🍣", createdAt: timestamp,
            updatedAt: timestamp, deletedAt: nil
        )
        return try JSONEncoder().encode(contract)
    }

    private func date(_ value: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(value))
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", abs(value)))!
    }
}

private struct SeededRouletteGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }
}
