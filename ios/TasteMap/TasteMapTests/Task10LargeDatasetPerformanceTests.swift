import Foundation
import Testing
import UIKit
@testable import TasteMap

@Suite("Task 10 large library performance")
@MainActor
struct Task10LargeDatasetPerformanceTests {
    private let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("1,000 Restaurants, 10,000 Visits, 5,000 Dishes and 2,000 photos share one bounded projection")
    func completeLargeFixtureProjection() {
        let restaurants = (0..<1_000).map { index in
            Restaurant(
                id: uuid(index),
                ownerUserID: "tm_task10_performance",
                name: "性能餐厅 \(index)",
                address: "性能路 \(index) 号",
                latitude: 30.18 + Double(index % 40) * 0.002,
                longitude: 120.08 + Double(index / 40) * 0.002,
                city: index.isMultiple(of: 2) ? "杭州" : "上海",
                status: index.isMultiple(of: 5) ? .wantToGo : .visited,
                createdAt: referenceDate.addingTimeInterval(-Double(index) * 60),
                updatedAt: referenceDate,
                syncStatus: .synced
            )
        }
        let visits = (0..<10_000).map { index in
            Visit(
                id: uuid(20_000 + index),
                ownerUserID: "tm_task10_performance",
                restaurantId: restaurants[index % restaurants.count].id,
                visitedAt: referenceDate.addingTimeInterval(-Double(index % 730) * 86_400),
                rating: index.isMultiple(of: 4) ? nil : 4.5,
                note: index.isMultiple(of: 17) ? "适合性能检索的长内容 \(index)" : nil,
                myActualSpend: index.isMultiple(of: 3) ? Decimal(240 + index % 500) : nil,
                pricePerPerson: index.isMultiple(of: 2) ? 150 : nil,
                diningMode: index.isMultiple(of: 2) ? .dineIn : .takeout,
                queueDuration: index.isMultiple(of: 7) ? .under30 : nil,
                companionNames: index.isMultiple(of: 11) ? ["饭搭子 \(index % 10)"] : [],
                recommendationSourceText: index.isMultiple(of: 13) ? "来源 \(index % 12)" : nil,
                createdAt: referenceDate,
                updatedAt: referenceDate,
                syncStatus: .synced
            )
        }
        let dishes = (0..<5_000).map { index in
            let visit = visits[index]
            return Dish(
                id: uuid(40_000 + index),
                ownerUserID: "tm_task10_performance",
                restaurantId: visit.restaurantId,
                visitId: visit.id,
                name: "菜品 \(index)",
                taste: "风味 \(index % 20)",
                rating: 4,
                sortOrder: index % 8,
                createdAt: referenceDate,
                updatedAt: referenceDate,
                syncStatus: .synced
            )
        }
        let photos = (0..<2_000).map { index in
            let visit = visits[index]
            return PhotoAsset(
                id: uuid(60_000 + index),
                ownerUserID: "tm_task10_performance",
                restaurantId: visit.restaurantId,
                visitId: visit.id,
                kind: index.isMultiple(of: 10) ? .restaurantMarker : .visit,
                storageProvider: .r2,
                storageKey: "task10/\(index)/display.jpg",
                thumbnailStorageKey: "task10/\(index)/thumbnail.jpg",
                mimeType: "image/jpeg",
                byteSize: 64_000,
                width: 1_200,
                height: 900,
                sortOrder: index % 4,
                uploadState: .uploaded,
                createdAt: referenceDate,
                updatedAt: referenceDate,
                syncStatus: .synced
            )
        }

        let start = ContinuousClock.now
        let snapshot = RestaurantBrowseBuilder.build(
            restaurants: restaurants,
            visits: visits,
            photos: photos,
            dishes: dishes
        )
        var state = PersonalRestaurantFilterState(status: .visited)
        state.city = "杭州"
        state.ratingBands = [.five]
        state.priceRange = .from100To200
        state.visitCount = .ten
        state.sort = .rating
        let filtered = PersonalRestaurantFilterEngine.resolve(
            snapshot: snapshot,
            state: state,
            now: referenceDate
        )
        let searched = RestaurantBrowseSearch.filter(snapshot.visited, query: "性能餐厅 128")
        let elapsed = start.duration(to: .now)

        #expect(snapshot.visited.count == 800)
        #expect(snapshot.wantToGo.count == 200)
        #expect(snapshot.footprints.count == 10_000)
        #expect(!filtered.items.isEmpty)
        #expect(filtered.items.allSatisfy { $0.restaurant.city == "杭州" })
        #expect(searched.contains { $0.restaurant.name == "性能餐厅 128" })
        #expect(elapsed < .seconds(15), "Large projection took \(elapsed)")
    }

    @Test("Viewport culling preserves independent IDs, selected marker and antimeridian semantics")
    func viewportCullingDoesNotCluster() {
        let markers = (0..<1_000).map { index in
            RestaurantMapMarkerPresentation(
                id: uuid(100_000 + index),
                name: "Marker \(index)",
                latitude: 30 + Double(index % 50) * 0.01,
                longitude: 120 + Double(index / 50) * 0.01,
                status: .visited,
                visual: .category(.other),
                visitCount: index % 12,
                averageRating: 4,
                distanceKilometers: nil
            )
        }
        let selected = markers.last!
        let start = ContinuousClock.now
        let visible = RestaurantMapViewportPolicy.visibleMarkers(
            markers,
            in: RestaurantMapViewport(
                centerLatitude: 30.15,
                centerLongitude: 120.08,
                latitudeDelta: 0.12,
                longitudeDelta: 0.10
            ),
            selectedRestaurantID: selected.id
        )
        let elapsed = start.duration(to: .now)

        #expect(visible.count < markers.count)
        #expect(visible.contains { $0.id == selected.id })
        #expect(Set(visible.map(\.id)).count == visible.count)
        #expect(visible.allSatisfy { marker in markers.contains { $0.id == marker.id } })
        #expect(elapsed < .seconds(1))

        let dateLineMarkers = [
            RestaurantMapMarkerPresentation(
                id: uuid(200_001), name: "东侧", latitude: 10, longitude: 179.8,
                status: .visited, visual: .category(.other), visitCount: 1,
                averageRating: nil, distanceKilometers: nil
            ),
            RestaurantMapMarkerPresentation(
                id: uuid(200_002), name: "西侧", latitude: 10, longitude: -179.8,
                status: .visited, visual: .category(.other), visitCount: 1,
                averageRating: nil, distanceKilometers: nil
            ),
        ]
        #expect(RestaurantMapViewportPolicy.visibleMarkers(
            dateLineMarkers,
            in: RestaurantMapViewport(
                centerLatitude: 10,
                centerLongitude: 179.9,
                latitudeDelta: 1,
                longitudeDelta: 1
            )
        ).count == 2)
    }

    @MainActor
    @Test("Five poster families render repeatedly inside bounded autorelease scopes")
    func repeatedPosterRendering() throws {
        let started = ContinuousClock.now
        var renderedCount = 0
        for _ in 0..<2 {
            renderedCount += try autoreleasepool {
                let taste = try AnalysisPosterRenderer.render(report: TasteProfilePreviewFixtures.rich)
                let companion = try AnalysisPosterRenderer.render(
                    content: DiningCompanionPosterView(
                        report: DiningCompanionPreviewFixtures.rich.analyses[0]
                    ),
                    canvasSize: DiningCompanionPosterView.canvasSize
                )
                let source = try AnalysisPosterRenderer.render(
                    content: RecommendationSourcePosterView(
                        overview: RecommendationSourcePreviewFixtures.rich
                    ),
                    canvasSize: RecommendationSourcePosterView.canvasSize
                )
                let monthly = try AnalysisPosterRenderer.render(
                    content: MonthlyRecapPosterView(
                        report: MonthlyRecapPreviewFixtures.withAssetImages,
                        resolvedImages: [:]
                    ),
                    canvasSize: MonthlyRecapPosterView.canvasSize
                )
                let annual = try AnalysisPosterRenderer.render(
                    content: AnnualRecapPosterView(
                        report: AnnualRecapPreviewFixtures.withAssetImages,
                        resolvedImages: [:]
                    ),
                    canvasSize: AnnualRecapPosterView.canvasSize
                )
                let images = [taste, companion, source, monthly, annual]
                #expect(images.allSatisfy { $0.cgImage?.width == 1_080 })
                #expect(images.allSatisfy { $0.cgImage?.height == 1_920 })
                return images.count
            }
        }
        #expect(renderedCount == 10)
        #expect(started.duration(to: .now) < .seconds(20))
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!
    }
}
