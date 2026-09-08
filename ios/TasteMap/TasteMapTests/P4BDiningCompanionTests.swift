import Foundation
import Testing
import UIKit
@testable import TasteMap

@Suite("P4-B dining companion analytics and share poster", .serialized)
@MainActor
struct P4BDiningCompanionTests {
    @Test("No companion and no shared visit stay honest")
    func emptyState() {
        let empty = DiningCompanionPreviewFixtures.empty
        #expect(empty.companionCount == 0)
        #expect(empty.companionsWithVisitsCount == 0)
        #expect(empty.summaries.isEmpty)
        #expect(empty.lead == nil)

        let one = DiningCompanionPreviewFixtures.singleVisit.analyses[0]
        #expect(one.sharedVisitCount == 1)
        #expect(one.sufficiency == .insufficient)
        #expect(one.topFoods.isEmpty)
        #expect(one.keywords.isEmpty)
        #expect(one.behavioralPortrait.contains("只有一次"))
    }

    @Test("Companion evidence requires three visits/two restaurants then eight/four")
    func sufficiencyThresholds() {
        let two = analyze(input(sharedVisitCount: 2)).analyses[0]
        let three = analyze(input(sharedVisitCount: 3)).analyses[0]
        let five = analyze(input(sharedVisitCount: 5)).analyses[0]
        let six = analyze(input(sharedVisitCount: 6)).analyses[0]
        let eight = analyze(input(sharedVisitCount: 8)).analyses[0]
        #expect(two.sufficiency == .insufficient)
        #expect(three.sufficiency == .emerging)
        #expect(five.sufficiency == .emerging)
        #expect(six.sufficiency == .emerging)
        #expect(eight.sufficiency == .established)
        #expect(DiningCompanionPreviewFixtures.repeatedRestaurant.analyses[0].sufficiency == .insufficient)
    }

    @Test("Overview sorts by shared visit count, then recency, then stable identity")
    func overviewSorting() {
        let overview = DiningCompanionPreviewFixtures.rich
        #expect(overview.summaries.map(\.sharedVisitCount) == [14, 5, 3])
        #expect(overview.summaries.first?.displayName == "小林")
        #expect(overview.lead?.companionID == overview.summaries.first?.id)
        #expect(DiningCompanionAnalyzer.analyze(
            DiningCompanionPreviewFixtures.input(),
            now: DiningCompanionPreviewFixtures.now
        ) == overview)
    }

    @Test("A multi-companion Visit counts once per selected identity")
    func multiCompanionVisit() {
        let source = input(companionCount: 2, sharedVisitCount: 1)
        let first = source.companions[0]
        let second = source.companions[1]
        let visit = copy(source.visits[0], companionIDs: [first.identifiers[0], second.identifiers[0]], companionNames: [])
        let overview = analyze(copy(source, visits: [visit]))
        #expect(overview.analysis(for: first.id)?.sharedVisitCount == 1)
        #expect(overview.analysis(for: second.id)?.sharedVisitCount == 1)
        #expect(overview.analyses.reduce(0) { $0 + $1.sharedVisitCount } == 2)
    }

    @Test("Duplicate names do not merge without an explicit companion identity")
    func duplicateNames() {
        let source = input(companionCount: 1, sharedVisitCount: 2)
        let original = source.companions[0]
        let duplicate = DiningCompanionInput.CompanionRecord(
            id: uuid(8_001), identifiers: [uuid(8_001).uuidString.lowercased()],
            displayName: original.displayName, linkedTasteMapUserID: nil,
            permittedLinkedAvatarPreset: nil, updatedAt: DiningCompanionPreviewFixtures.now, deletedAt: nil
        )
        let nameOnly = source.visits.map { copy($0, companionIDs: [], companionNames: [original.displayName]) }
        let ambiguous = analyze(copy(source, companions: [original, duplicate], visits: nameOnly))
        #expect(ambiguous.analyses.allSatisfy { $0.sharedVisitCount == 0 })

        let explicit = nameOnly.map { copy($0, companionIDs: [original.identifiers[0]], companionNames: [original.displayName]) }
        let resolved = analyze(copy(source, companions: [original, duplicate], visits: explicit))
        #expect(resolved.analysis(for: original.id)?.sharedVisitCount == 2)
        #expect(resolved.analysis(for: duplicate.id)?.sharedVisitCount == 0)
    }

    @Test("Restaurant count is distinct identity count and repeat rate is restaurant based")
    func restaurantIdentityCounts() {
        let repeated = DiningCompanionPreviewFixtures.repeatedRestaurant.analyses[0]
        #expect(repeated.sharedVisitCount == 10)
        #expect(repeated.restaurantCount == 1)
        #expect(repeated.repeatRestaurantRate == 1)
        #expect(repeated.topRestaurants.count == 1)
        #expect(repeated.topRestaurants[0].sharedVisitCount == 10)
    }

    @Test("Dish evidence wins; cuisine is an explicit fallback")
    func foodRankingAndFallback() {
        let dishes = DiningCompanionPreviewFixtures.withDishes.analyses[0]
        #expect(dishes.topFoods.first?.source == .dish)
        #expect(dishes.topFoods.first?.label == "炭烤鸡腿葱串")
        #expect(dishes.topFoods.first!.sharedVisitCount >= 2)

        let cuisines = DiningCompanionPreviewFixtures.noDishes.analyses[0]
        #expect(cuisines.topFoods.first?.source == .cuisine)
        #expect(cuisines.topFoods.first?.label == "日料")
        #expect(cuisines.topFoods.allSatisfy { !$0.label.contains("聚餐") })
    }

    @Test("Cross-restaurant VisitDish links are ignored")
    func crossRestaurantDishLink() {
        let source = input(companionCount: 1, sharedVisitCount: 6)
        let wrong = DiningCompanionInput.VisitDishRecord(
            visitID: source.visits.first(where: { $0.restaurantID != source.dishes[0].restaurantID })!.id,
            dishID: source.dishes[0].id,
            deletedAt: nil
        )
        let report = analyze(copy(source, visitDishes: [wrong])).analyses[0]
        #expect(report.topFoods.first?.source == .cuisine)
    }

    @Test("Nil rating and spend remain nil rather than zero")
    func nilSemantics() {
        let source = input(companionCount: 1, sharedVisitCount: 8)
        let visits = source.visits.map {
            copy($0, rating: .some(nil), myActualSpend: .some(nil))
        }
        let report = analyze(copy(source, visits: visits)).analyses[0]
        #expect(report.rating.sampleCount == 0)
        #expect(report.rating.sharedAverage == nil)
        #expect(report.spend.sampleCount == 0)
        #expect(report.spend.median == nil)
        #expect(report.rating.summary.contains("不会当作 0"))
        #expect(report.rating.summary.contains("没有评分"))
    }

    @Test("Spend uses only the user's actual spend and reports median")
    func spend() {
        let report = DiningCompanionPreviewFixtures.rich.analyses[0]
        #expect(report.spend.sampleCount == 12)
        #expect(report.spend.median != nil)
        #expect(report.spend.totalRecorded! > report.spend.median!)
        #expect(report.spend.summary.contains("本人消费中位数"))
    }

    @Test("Rating comparison needs enough samples and never infers TA rating")
    func ratings() {
        let report = DiningCompanionPreviewFixtures.rich.analyses[0]
        #expect(report.rating.sampleCount == 12)
        #expect(report.rating.sharedAverage != nil)
        #expect(report.rating.overallAverage != nil)
        #expect(report.rating.valueAverage != nil)
        #expect(!report.rating.summary.contains("TA 的评分"))
    }

    @Test("Tombstones remove companion, restaurant and Visit evidence")
    func tombstones() {
        let source = input(companionCount: 2, sharedVisitCount: 8)
        let deletedVisit = copy(source.visits[0], deletedAt: DiningCompanionPreviewFixtures.now)
        let visits = [deletedVisit] + Array(source.visits.dropFirst())
        let restaurants = source.restaurants.map {
            $0.id == source.restaurants[1].id ? copy($0, deletedAt: DiningCompanionPreviewFixtures.now) : $0
        }
        let companions = source.companions.map {
            $0.id == source.companions[1].id ? copy($0, deletedAt: DiningCompanionPreviewFixtures.now) : $0
        }
        let overview = analyze(copy(source, companions: companions, restaurants: restaurants, visits: visits))
        #expect(overview.companionCount == 1)
        #expect(overview.analyses.count == 1)
        #expect(overview.analyses[0].sharedVisitCount < 8)
        #expect(overview.analyses[0].topRestaurants.allSatisfy { $0.id != source.restaurants[1].id })
    }

    @Test("Relation keywords are bounded, explainable and absent below three Visits")
    func keywords() {
        let rich = DiningCompanionPreviewFixtures.rich.analyses[0]
        #expect(!rich.keywords.isEmpty)
        #expect(rich.keywords.count <= 4)
        #expect(rich.keywords.allSatisfy { !$0.contains("亲密") && !$0.contains("人格") })
        #expect(analyze(input(sharedVisitCount: 2)).analyses[0].keywords.isEmpty)
    }

    @Test("Latest Visit, dining context and a renamed companion keep factual stable identity")
    func factualFieldsAndRenameIdentity() {
        let source = input(companionCount: 1, sharedVisitCount: 8)
        let original = analyze(source).analyses[0]
        #expect(original.latestVisit == source.visits.map(\.visitedAt).max())
        #expect(original.diningContexts.contains { $0.label == "朋友聚餐" })
        #expect(original.diningContexts.contains { $0.label == "日常吃饭" })

        let companion = source.companions[0]
        let renamed = DiningCompanionInput.CompanionRecord(
            id: companion.id,
            identifiers: companion.identifiers,
            displayName: "用户后来改写的名字",
            linkedTasteMapUserID: companion.linkedTasteMapUserID,
            permittedLinkedAvatarPreset: companion.permittedLinkedAvatarPreset,
            updatedAt: companion.updatedAt.addingTimeInterval(1),
            deletedAt: nil
        )
        let afterRename = analyze(copy(source, companions: [renamed])).analyses[0]
        #expect(afterRename.companionID == original.companionID)
        #expect(afterRename.companionDisplayName == "用户后来改写的名字")
        #expect(afterRename.sharedVisitCount == original.sharedVisitCount)
        #expect(afterRename.restaurantCount == original.restaurantCount)
    }

    @Test("Exploration, cuisine, weekend and high-rating keywords come only from evidence")
    func keywordEvidencePatterns() {
        let familiar = DiningCompanionPreviewFixtures.repeatedRestaurant.analyses[0]
        #expect(familiar.keywords.isEmpty)

        let source = input(companionCount: 1, sharedVisitCount: 4, includeDishes: false)
        let calendar = Calendar(identifier: .gregorian)
        let visits = source.visits.enumerated().map { index, visit in
            let saturday = calendar.date(from: DateComponents(
                timeZone: TimeZone(secondsFromGMT: 0),
                year: 2026,
                month: 8,
                day: 29 - (index * 7),
                hour: 12
            ))!
            return copy(
                visit,
                restaurantID: source.restaurants[index].id,
                visitedAt: saturday,
                rating: .some(4.8)
            )
        }
        let exploration = DiningCompanionAnalyzer.analyze(copy(source, visits: visits),
            now: calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!, calendar: calendar).analyses[0]
        #expect(exploration.keywords.contains("探店型"))
        #expect(exploration.keywords.contains("周末饭友"))
        #expect(exploration.keywords.contains("高分组合"))
        #expect(exploration.keywords.count <= 4)
    }

    @Test("Representative restaurants have distinct roles and never copy a private note")
    func representativeRestaurantsAndPrivacy() {
        let report = DiningCompanionPreviewFixtures.rich.analyses[0]
        #expect((1...3).contains(report.representativeRestaurants.count))
        #expect(Set(report.representativeRestaurants.map(\.id)).count == report.representativeRestaurants.count)
        let exportedText = ([report.summary, report.behavioralPortrait, report.dataNote]
            + report.representativeRestaurants.map(\.detail)).joined(separator: " ")
        #expect(!exportedText.contains("P4-B 私人备注原文"))
        #expect(report.dataNote.contains("不会读取 TA 的私人"))
        #expect(report.dataNote.contains("私人备注"))
    }

    @Test("A shared Visit photo cannot leak onto a different restaurant card")
    func photoScoping() {
        let source = input(companionCount: 1, sharedVisitCount: 2, includeDishes: false, includePhotos: false)
        let firstVisit = source.visits[0]
        let wrongRestaurant = source.restaurants.first { $0.id != firstVisit.restaurantID }!
        let photo = DiningCompanionInput.PhotoRecord(
            id: uuid(8_010), restaurantID: wrongRestaurant.id, visitID: firstVisit.id,
            dishID: nil, kind: .visit, visibility: .private, sortOrder: 0,
            updatedAt: DiningCompanionPreviewFixtures.now, deletedAt: nil
        )
        let report = analyze(copy(source, photos: [photo])).analyses[0]
        #expect(
            report.topRestaurants.first(where: { $0.id == firstVisit.restaurantID })?.imageReference
                == AnalysisImageReference.none
        )
    }

    @Test("Linked social avatar is used only after the caller grants friend-level permission")
    func linkedAvatarPrivacy() {
        let permitted = DiningCompanionPreviewFixtures.linkedAvatar.analyses[0]
        #expect(permitted.avatar == .preset(.otter))
        let local = DiningCompanionPreviewFixtures.unlinkedAvatar.analyses[0]
        if case .initial = local.avatar {} else { Issue.record("Unlinked companion must use a local initial") }
        #expect(!permitted.id.contains("tm_linked_friend"))
        #expect(!permitted.summary.contains("tm_linked_friend"))
    }

    @Test("Next-meal candidates are local, same-city, non-avoid and deterministic")
    func recommendations() {
        let first = DiningCompanionPreviewFixtures.rich.analyses[0]
        let second = DiningCompanionPreviewFixtures.rich.analyses[0]
        #expect(!first.recommendations.isEmpty)
        #expect(first.recommendations == second.recommendations)
        #expect(first.recommendations.allSatisfy { $0.city == "上海" })
        #expect(first.recommendations.contains { $0.name == "云朵寿喜烧" })
        #expect(Set(first.recommendations.map(\.id)).count == first.recommendations.count)
    }

    @Test("No reliable city scope means no cross-city recommendation")
    func missingGeographicScope() {
        let source = input(companionCount: 1, sharedVisitCount: 0)
        let restaurants = source.restaurants.map {
            DiningCompanionInput.RestaurantRecord(
                id: $0.id, name: $0.name, address: $0.address, city: "",
                status: $0.status, preference: $0.preference, tags: $0.tags,
                updatedAt: $0.updatedAt, deletedAt: $0.deletedAt, isAccessible: $0.isAccessible
            )
        }
        let report = analyze(DiningCompanionInput(
            userDisplayName: source.userDisplayName, userCity: "", companions: source.companions,
            restaurants: restaurants, visits: [], dishes: [], visitDishes: [], photos: []
        )).analyses[0]
        #expect(report.geographicScope == nil)
        #expect(report.recommendations.isEmpty)
    }

    @Test("Avoided, inaccessible and low-rated candidates are filtered")
    func unsafeRecommendationFiltering() {
        let source = input(companionCount: 1, sharedVisitCount: 6)
        let candidateIDs = Set(source.restaurants.suffix(2).map(\.id))
        let restaurants = source.restaurants.map { item in
            guard candidateIDs.contains(item.id) else { return item }
            return DiningCompanionInput.RestaurantRecord(
                id: item.id, name: item.name, address: item.address, city: item.city,
                status: item.status, preference: item.id == source.restaurants[4].id ? .avoid : item.preference,
                tags: item.tags, updatedAt: item.updatedAt, deletedAt: nil,
                isAccessible: item.id != source.restaurants[5].id
            )
        }
        let report = analyze(copy(source, restaurants: restaurants)).analyses[0]
        #expect(report.recommendations.allSatisfy { !candidateIDs.contains($0.localRestaurantID!) })
    }

    @Test("Low-rated, cross-city and non-familiar shared Restaurants do not leak into recommendations")
    func recommendationBoundaries() {
        let source = input(companionCount: 1, sharedVisitCount: 4, includeDishes: false)
        let lowRatedID = source.restaurants[4].id
        let crossCityID = source.restaurants[5].id
        let lowRatedEvidence = copy(
            source.visits[0],
            restaurantID: lowRatedID,
            rating: .some(2.5),
            companionIDs: [],
            companionNames: []
        )
        let restaurants = source.restaurants.map { restaurant in
            guard restaurant.id == crossCityID else { return restaurant }
            return DiningCompanionInput.RestaurantRecord(
                id: restaurant.id,
                name: restaurant.name,
                address: restaurant.address,
                city: "北京",
                status: restaurant.status,
                preference: restaurant.preference,
                tags: restaurant.tags,
                updatedAt: restaurant.updatedAt,
                deletedAt: nil,
                isAccessible: true
            )
        }
        let report = analyze(copy(
            source,
            restaurants: restaurants,
            visits: source.visits + [lowRatedEvidence]
        )).analyses[0]
        #expect(!report.recommendations.contains { $0.localRestaurantID == lowRatedID })
        #expect(!report.recommendations.contains { $0.localRestaurantID == crossCityID })
        let sharedIDs = Set(source.visits.map(\.restaurantID))
        #expect(report.recommendations.allSatisfy { !sharedIDs.contains($0.localRestaurantID!) })
    }

    @Test("An established familiar-restaurant pattern can recommend a trusted shared Restaurant")
    func familiarRestaurantRecommendation() {
        let source = DiningCompanionPreviewFixtures.input(
            companionCount: 1,
            sharedVisitCount: 10,
            includeDishes: false,
            includePhotos: false,
            onlyFirstRestaurant: true
        )
        let visits = source.visits.enumerated().map { index, visit in
            copy(
                visit,
                visitedAt: DiningCompanionPreviewFixtures.now.addingTimeInterval(Double(-30 - index) * 86_400),
                rating: .some(4.8)
            )
        }
        let report = analyze(copy(source, visits: visits)).analyses[0]
        #expect(report.repeatRestaurantRate == 1)
        #expect(report.recommendations.contains { $0.localRestaurantID == source.restaurants[0].id })
        #expect(report.recommendations.first?.localRestaurantID == source.restaurants[4].id)
    }

    @Test("Analyzer does not make network calls and is deterministic offline")
    func offlineDeterminism() {
        let source = input(companionCount: 3, sharedVisitCount: 14)
        let reports = (0..<4).map { _ in analyze(source) }
        #expect(reports.dropFirst().allSatisfy { $0 == reports[0] })
        #expect(reports[0].analyses.allSatisfy { $0.kind == .companion })
    }

    @Test("Analyzer remains interactive for 200 companions and 3000 Visits")
    func performance() {
        let seed = input(companionCount: 3, sharedVisitCount: 14)
        let companions = (0..<200).map { index in
            DiningCompanionInput.CompanionRecord(
                id: uuid(10_000 + index), identifiers: ["perf-\(index)"], displayName: "饭搭子 \(index)",
                linkedTasteMapUserID: nil, permittedLinkedAvatarPreset: nil,
                updatedAt: DiningCompanionPreviewFixtures.now, deletedAt: nil
            )
        }
        let visits = (0..<3_000).map { index in
            let companion = companions[index % companions.count]
            return DiningCompanionInput.VisitRecord(
                id: uuid(20_000 + index), restaurantID: seed.restaurants[index % 4].id,
                visitedAt: Date(timeIntervalSince1970: 1_780_000_000 - Double(index * 1_000)),
                rating: index.isMultiple(of: 4) ? nil : 4.5,
                valueRating: nil, environmentRating: nil, serviceRating: nil,
                myActualSpend: index.isMultiple(of: 5) ? nil : 128,
                diningMode: .dineIn, diningOccasionLabels: [], environmentTags: [], noiseLevelLabel: nil,
                companionIDs: [companion.identifiers[0]], companionNames: [], hasPrivateNote: false,
                updatedAt: DiningCompanionPreviewFixtures.now, deletedAt: nil
            )
        }
        let large = copy(seed, companions: companions, visits: visits, dishes: [], visitDishes: [], photos: [])
        let start = ContinuousClock.now
        let report = analyze(large)
        let elapsed = start.duration(to: .now)
        #expect(report.analyses.count == 200)
        #expect(report.analyses.reduce(0) { $0 + $1.sharedVisitCount } == 3_000)
        #expect(elapsed < .seconds(2))
    }

    @Test("Poster exports exact 9:16 pixels for rich, sparse, no-photo and long-name data")
    func posterRendering() throws {
        for report in [
            DiningCompanionPreviewFixtures.withPhotos.analyses[0],
            DiningCompanionPreviewFixtures.singleVisit.analyses[0],
            DiningCompanionPreviewFixtures.noPhotos.analyses[0],
            DiningCompanionPreviewFixtures.longName.analyses[0],
        ] {
            let image = try AnalysisPosterRenderer.render(
                content: DiningCompanionPosterView(report: report),
                canvasSize: DiningCompanionPosterView.canvasSize
            )
            #expect(image.size == DiningCompanionPosterView.canvasSize)
            #expect(image.cgImage?.width == 1_080)
            #expect(image.cgImage?.height == 1_920)
            #expect(image.pngData()?.isEmpty == false)
        }
    }

    @Test("Poster payload contains shareable facts and excludes private/internal fields")
    func posterPayload() {
        let rich = DiningCompanionPreviewFixtures.rich.analyses[0]
        #expect(rich.companionDisplayName == "小林")
        #expect(rich.sharedVisitCount == 14)
        #expect(rich.restaurantCount == 4)
        #expect(rich.topRestaurants.first != nil)
        #expect(rich.topFoods.first != nil)
        #expect(!rich.keywords.isEmpty)
        #expect(rich.representativeRestaurants.contains { item in
            if case .photo = item.imageReference { return true }
            return false
        })

        let sparse = DiningCompanionPreviewFixtures.singleVisit.analyses[0]
        let noPhoto = DiningCompanionPreviewFixtures.noPhotos.analyses[0]
        #expect(sparse.sufficiency == .insufficient)
        #expect(noPhoto.representativeRestaurants.allSatisfy { $0.imageReference == .none })
        let exportText = ([rich.summary, rich.behavioralPortrait, rich.dataNote]
            + rich.keywords
            + rich.representativeRestaurants.flatMap { [$0.name, $0.role, $0.detail] })
            .joined(separator: " ")
        #expect(!exportText.contains("tm_linked_friend"))
        #expect(!exportText.contains("P4-B 私人备注原文"))
    }

    @Test("P4-B poster shares through the reused temporary PNG lifecycle")
    func temporaryShareFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = try AnalysisPosterRenderer.render(
            content: DiningCompanionPosterView(report: DiningCompanionPreviewFixtures.rich.analyses[0]),
            canvasSize: DiningCompanionPosterView.canvasSize
        )
        let store = AnalysisPosterTemporaryFileStore(rootURL: root)
        let url = try store.write(image, id: "p4b:companion/unsafe")
        #expect(url.pathExtension == "png")
        #expect(FileManager.default.fileExists(atPath: url.path))
        store.remove(url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    private func input(
        companionCount: Int = 1,
        sharedVisitCount: Int = 8,
        includeDishes: Bool = true,
        includePhotos: Bool = true
    ) -> DiningCompanionInput {
        DiningCompanionPreviewFixtures.input(
            companionCount: companionCount,
            sharedVisitCount: sharedVisitCount,
            includeDishes: includeDishes,
            includePhotos: includePhotos
        )
    }

    private func analyze(_ input: DiningCompanionInput) -> DiningCompanionOverview {
        DiningCompanionAnalyzer.analyze(input, now: DiningCompanionPreviewFixtures.now)
    }

    private func copy(
        _ source: DiningCompanionInput,
        userDisplayName: String? = nil,
        userCity: String? = nil,
        companions: [DiningCompanionInput.CompanionRecord]? = nil,
        restaurants: [DiningCompanionInput.RestaurantRecord]? = nil,
        visits: [DiningCompanionInput.VisitRecord]? = nil,
        dishes: [DiningCompanionInput.DishRecord]? = nil,
        visitDishes: [DiningCompanionInput.VisitDishRecord]? = nil,
        photos: [DiningCompanionInput.PhotoRecord]? = nil
    ) -> DiningCompanionInput {
        DiningCompanionInput(
            userDisplayName: userDisplayName ?? source.userDisplayName,
            userCity: userCity ?? source.userCity,
            companions: companions ?? source.companions,
            restaurants: restaurants ?? source.restaurants,
            visits: visits ?? source.visits,
            dishes: dishes ?? source.dishes,
            visitDishes: visitDishes ?? source.visitDishes,
            photos: photos ?? source.photos
        )
    }

    private func copy(
        _ source: DiningCompanionInput.VisitRecord,
        restaurantID: UUID? = nil,
        visitedAt: Date? = nil,
        rating: Double?? = nil,
        myActualSpend: Decimal?? = nil,
        companionIDs: [String]? = nil,
        companionNames: [String]? = nil,
        deletedAt: Date?? = nil
    ) -> DiningCompanionInput.VisitRecord {
        .init(
            id: source.id,
            restaurantID: restaurantID ?? source.restaurantID,
            visitedAt: visitedAt ?? source.visitedAt,
            rating: rating ?? source.rating, valueRating: source.valueRating,
            environmentRating: source.environmentRating, serviceRating: source.serviceRating,
            myActualSpend: myActualSpend ?? source.myActualSpend, diningMode: source.diningMode,
            diningOccasionLabels: source.diningOccasionLabels, environmentTags: source.environmentTags,
            noiseLevelLabel: source.noiseLevelLabel, companionIDs: companionIDs ?? source.companionIDs,
            companionNames: companionNames ?? source.companionNames, hasPrivateNote: source.hasPrivateNote,
            updatedAt: source.updatedAt, deletedAt: deletedAt ?? source.deletedAt
        )
    }

    private func copy(
        _ source: DiningCompanionInput.RestaurantRecord,
        deletedAt: Date?
    ) -> DiningCompanionInput.RestaurantRecord {
        .init(
            id: source.id, name: source.name, address: source.address, city: source.city,
            status: source.status, preference: source.preference, tags: source.tags,
            updatedAt: source.updatedAt, deletedAt: deletedAt, isAccessible: source.isAccessible
        )
    }

    private func copy(
        _ source: DiningCompanionInput.CompanionRecord,
        deletedAt: Date?
    ) -> DiningCompanionInput.CompanionRecord {
        .init(
            id: source.id, identifiers: source.identifiers, displayName: source.displayName,
            linkedTasteMapUserID: source.linkedTasteMapUserID,
            permittedLinkedAvatarPreset: source.permittedLinkedAvatarPreset,
            updatedAt: source.updatedAt, deletedAt: deletedAt
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "20000000-0000-0000-0000-%012d", value))!
    }
}
