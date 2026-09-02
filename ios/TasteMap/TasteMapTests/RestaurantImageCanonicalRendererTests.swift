import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("Canonical Restaurant image renderer")
struct RestaurantImageCanonicalRendererTests {
    @Test("The canonical plan preserves user, public, provider, fallback priority")
    func canonicalPriority() throws {
        let localID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000111"))
        let provider = try #require(URL(string: "https://images.example.com/restaurant.jpg"))
        let resolution = RestaurantImagePriorityPolicy.resolution(
            localUserPhotoID: localID,
            publicOrCachedPhotoID: "00000000-0000-4000-8000-000000000222",
            providerMerchantImageURL: provider
        )

        #expect(resolution.sources == [
            .localUserPhoto(localID),
            .publicOrCachedPhoto("00000000-0000-4000-8000-000000000222"),
            .providerMerchantImage(provider),
        ])
        #expect(resolution.preferredSource == .localUserPhoto(localID))
    }

    @Test("A failed source advances through every legal real source before fallback")
    func failureChain() throws {
        let localID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000111"))
        let publicID = "00000000-0000-4000-8000-000000000222"
        let provider = try #require(URL(string: "https://images.example.com/restaurant.jpg"))
        let resolution = RestaurantImagePriorityPolicy.resolution(
            localUserPhotoID: localID,
            publicOrCachedPhotoID: publicID,
            providerMerchantImageURL: provider
        )

        #expect(resolution.sources(afterFailureOf: .localUserPhoto(localID)) == [
            .publicOrCachedPhoto(publicID), .providerMerchantImage(provider),
        ])
        #expect(resolution.sources(afterFailureOf: .publicOrCachedPhoto(publicID)) == [
            .providerMerchantImage(provider),
        ])
        #expect(resolution.sources(afterFailureOf: .providerMerchantImage(provider)).isEmpty)
    }

    @Test("Invalid provider URLs never become a source and no source is an honest fallback")
    func invalidAndEmptySources() {
        let invalid = RestaurantImagePriorityPolicy.resolution(
            localUserPhotoID: nil,
            providerMerchantImageURL: "http://unsafe.example.com/image.jpg"
        )
        let empty = RestaurantImagePriorityPolicy.resolution(
            localUserPhotoID: nil,
            providerMerchantImageURL: nil as String?
        )

        #expect(invalid.isFallbackOnly)
        #expect(invalid.preferredSource == .foodDiningFallback)
        #expect(empty.isFallbackOnly)
    }

    @Test("Map, List, Detail, Roulette and Analytics share the same source identity")
    func crossSurfaceConsistency() throws {
        let localID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000111"))
        let provider = try #require(URL(string: "https://images.example.com/restaurant.jpg"))
        let expected = RestaurantImagePriorityPolicy.resolution(
            localUserPhotoID: localID,
            providerMerchantImageURL: provider
        )
        let map = RestaurantMapMarkerPresentation(
            id: localID, name: "同一家餐厅", latitude: 30.2, longitude: 120.1,
            status: .visited, visual: .photo(localID),
            fallbackMerchantImageURL: provider,
            visitCount: 2, averageRating: 4.5, distanceKilometers: nil
        )
        let analysis = AnalysisImageReference.photo(localID, providerFallback: provider)

        #expect(map.imageResolution == expected)
        #expect(analysis.restaurantResolution == expected)
        #expect(RestaurantImagePriorityPolicy.resolution(
            localUserPhotoID: localID,
            providerMerchantImageURL: provider
        ) == expected)
    }

    @Test("Rich Visual QA contains user, public, provider and honest no-image Restaurants")
    @MainActor
    func richDemoImageMix() throws {
        let container = try TasteMapPersistence.makeContainer(inMemory: true)
        try TasteMapVisualQAFixtures.insert(mode: .rich, into: container)
        let restaurants = try container.mainContext.fetch(FetchDescriptor<Restaurant>())
        let photos = try container.mainContext.fetch(FetchDescriptor<PhotoAsset>())
        let photoRestaurantIDs = Set(photos.compactMap(\.restaurantId))
        var userPhoto = 0
        var publicPhoto = 0
        var provider = 0
        var fallback = 0

        for restaurant in restaurants where restaurant.deletedAt == nil {
            let contract = restaurant.remoteRecordData.flatMap {
                try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
            }
            if photoRestaurantIDs.contains(restaurant.id) { userPhoto += 1 }
            else if contract?.markerPhotoId != nil { publicPhoto += 1 }
            else if contract?.merchantImageUrl != nil { provider += 1 }
            else { fallback += 1 }
        }

        #expect(userPhoto == 60)
        #expect(publicPhoto == 20)
        #expect(provider == 20)
        #expect(fallback == 15)
    }

#if DEBUG
    @Test("Visual QA never labels a generated fixture as a provider merchant image")
    @MainActor
    func visualQAMerchantImageHonesty() throws {
        let localID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000111"))
        let provider = try #require(URL(string: "https://images.example.com/restaurant.jpg"))
        let local = RestaurantImagePriorityPolicy.resolution(
            localUserPhotoID: localID,
            providerMerchantImageURL: provider
        )
        let providerOnly = RestaurantImagePriorityPolicy.resolution(
            localUserPhotoID: nil,
            providerMerchantImageURL: provider
        )

        #expect(RestaurantImageLoader.visualQAFixtureSource(in: local) == .localUserPhoto(localID))
        #expect(RestaurantImageLoader.visualQAFixtureSource(in: providerOnly) == nil)
    }
#endif
}
