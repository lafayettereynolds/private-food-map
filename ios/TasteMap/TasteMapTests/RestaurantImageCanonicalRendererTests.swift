import Foundation
import SwiftData
import Testing
@testable import TasteMap

@Suite("Canonical Restaurant image renderer")
struct RestaurantImageCanonicalRendererTests {
    private let ownerID = "tm_acquisition_owner"

    @Test("Custom avatar stays explicit and never joins real-photo automatic/content candidates")
    @MainActor
    func customAvatarIsNotContent() throws {
        let restaurant = try acquisitionRestaurant()
        let avatar = PhotoAsset(ownerUserID: ownerID, restaurantId: restaurant.id, kind: .restaurantMarker,
                                mimeType: "image/jpeg", byteSize: 12)
        let actual = PhotoAsset(ownerUserID: ownerID, restaurantId: restaurant.id, kind: .visit,
                                mimeType: "image/jpeg", byteSize: 12)
        let deleted = PhotoAsset(ownerUserID: ownerID, restaurantId: restaurant.id, kind: .dish,
                                 mimeType: "image/jpeg", byteSize: 12)
        deleted.deletedAt = .now
        let photos = [avatar, actual, deleted]
        #expect(RestaurantImagePhotoSelectionPolicy.preferredPhoto(restaurantID: restaurant.id, photos: photos,
                    referencedPhotoID: avatar.id.uuidString)?.id == avatar.id)
        #expect(RestaurantImagePhotoSelectionPolicy.preferredPhoto(restaurantID: restaurant.id, photos: photos)?.id == actual.id)
        #expect(RestaurantImagePhotoSelectionPolicy.actualPhotos(restaurantID: restaurant.id, photos: photos).map(\.id) == [actual.id])
        #expect(RestaurantImagePhotoSelectionPolicy.preferredContentPhoto(restaurantID: restaurant.id, photos: [avatar]) == nil)
    }

    @Test("Remote content provenance rejects marker avatars and supports Visit-less actual dish photos")
    func remotePhotoProvenance() {
        let marker = DiscoveryPhotoProjectionV1(photoId: "marker", variant: .thumbnail, visitId: "visit", photoKind: "restaurant-marker")
        let unknown = DiscoveryPhotoProjectionV1(photoId: "legacy-marker", variant: .thumbnail)
        let actual = DiscoveryPhotoProjectionV1(photoId: "dish", variant: .thumbnail, photoKind: "dish")
        #expect(!marker.isActualDiningPhoto)
        #expect(!unknown.isActualDiningPhoto)
        #expect(actual.isActualDiningPhoto)
        #expect(DiscoveryPhotoProjectionV1.activityAlbum([marker], visitID: "visit", authorID: "owner")?.isEmpty == true)
    }

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

    @Test("Add Restaurant reuses the matched owner's complete canonical image plan")
    @MainActor
    func acquisitionExistingRestaurantSources() throws {
        let localID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000311"))
        let publicID = "00000000-0000-4000-8000-000000000322"
        let restaurant = try acquisitionRestaurant(
            markerPhotoID: publicID,
            merchantImageURL: "https://images.example.com/persisted.jpg"
        )
        let local = PhotoAsset(
            id: localID,
            ownerUserID: ownerID,
            restaurantId: restaurant.id,
            kind: .visit,
            mimeType: "image/jpeg",
            byteSize: 128,
            localFileRelativePath: "owned/display.jpg"
        )
        let candidateURL = try #require(URL(string: "https://images.example.com/candidate.jpg"))

        let resolution = RestaurantImagePriorityPolicy.acquisitionResolution(
            matchedRestaurant: restaurant,
            authenticatedOwnerUserID: ownerID,
            ownerPhotos: [local],
            candidateProviderMerchantImageURL: candidateURL
        )

        #expect(resolution.sources == [
            .localUserPhoto(localID),
            .publicOrCachedPhoto(publicID),
            .providerMerchantImage(try #require(URL(string: "https://images.example.com/persisted.jpg"))),
            .providerMerchantImage(candidateURL),
        ])
    }

    @Test("Add Restaurant resolves public, provider and honest fallback without inventing photos")
    @MainActor
    func acquisitionRemainingSourceCases() throws {
        let publicID = "00000000-0000-4000-8000-000000000422"
        let publicRestaurant = try acquisitionRestaurant(markerPhotoID: publicID)
        let providerRestaurant = try acquisitionRestaurant(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000403")!,
            merchantImageURL: "https://images.example.com/provider-only.jpg"
        )
        let emptyRestaurant = try acquisitionRestaurant(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000404")!
        )

        #expect(RestaurantImagePriorityPolicy.acquisitionResolution(
            matchedRestaurant: publicRestaurant,
            authenticatedOwnerUserID: ownerID,
            ownerPhotos: [],
            candidateProviderMerchantImageURL: nil
        ).preferredSource == .publicOrCachedPhoto(publicID))
        #expect(RestaurantImagePriorityPolicy.acquisitionResolution(
            matchedRestaurant: providerRestaurant,
            authenticatedOwnerUserID: ownerID,
            ownerPhotos: [],
            candidateProviderMerchantImageURL: nil
        ).preferredSource == .providerMerchantImage(
            try #require(URL(string: "https://images.example.com/provider-only.jpg"))
        ))
        #expect(RestaurantImagePriorityPolicy.acquisitionResolution(
            matchedRestaurant: emptyRestaurant,
            authenticatedOwnerUserID: ownerID,
            ownerPhotos: [],
            candidateProviderMerchantImageURL: nil
        ).isFallbackOnly)
        #expect(RestaurantImagePriorityPolicy.acquisitionResolution(
            matchedRestaurant: nil,
            authenticatedOwnerUserID: ownerID,
            ownerPhotos: [],
            candidateProviderMerchantImageURL: nil
        ).isFallbackOnly)
    }

    @Test("Add Restaurant cannot read another owner's private photo and is surface-stable")
    @MainActor
    func acquisitionOwnerIsolationAndSurfaceIdentity() throws {
        let restaurant = try acquisitionRestaurant(
            merchantImageURL: "https://images.example.com/safe-provider.jpg"
        )
        let foreign = PhotoAsset(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000511")!,
            ownerUserID: "tm_foreign_owner",
            restaurantId: restaurant.id,
            kind: .visit,
            mimeType: "image/jpeg",
            byteSize: 128,
            visibility: .private,
            localFileRelativePath: "foreign/private.jpg"
        )
        let search = RestaurantImagePriorityPolicy.acquisitionResolution(
            matchedRestaurant: restaurant,
            authenticatedOwnerUserID: ownerID,
            ownerPhotos: [foreign],
            candidateProviderMerchantImageURL: nil
        )
        let nearby = RestaurantImagePriorityPolicy.acquisitionResolution(
            matchedRestaurant: restaurant,
            authenticatedOwnerUserID: ownerID,
            ownerPhotos: [foreign],
            candidateProviderMerchantImageURL: nil
        )

        #expect(search == nearby)
        #expect(search.sources.count == 1)
        #expect(search.sources.first == .providerMerchantImage(
            try #require(URL(string: "https://images.example.com/safe-provider.jpg"))
        ))
        #expect(!search.sources.contains(.localUserPhoto(foreign.id)))
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

    @Test("Personal Map prefers the owner's photo and retains the real merchant fallback")
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
            allowsRemoteImages: true,
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

    @Test("Public Profile map may render only its permission-authorized remote image sources")
    func publicProfileMapRemoteImageBoundary() throws {
        let provider = try #require(URL(string: "https://images.example.com/public-restaurant.jpg"))
        let marker = RestaurantMapMarkerPresentation(
            id: UUID(), name: "公开餐厅", latitude: 30.2, longitude: 120.1,
            status: .visited, visual: .emoji("🍜"),
            publicPhotoID: "00000000-0000-4000-8000-000000000222",
            fallbackMerchantImageURL: provider,
            allowsRemoteImages: true,
            visitCount: 1, averageRating: 4.5, distanceKilometers: nil
        )

        #expect(marker.imageResolution == RestaurantImagePriorityPolicy.resolution(
            localUserPhotoID: nil,
            publicOrCachedPhotoID: "00000000-0000-4000-8000-000000000222",
            providerMerchantImageURL: provider
        ))
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

    @MainActor
    private func acquisitionRestaurant(
        id: UUID = UUID(uuidString: "00000000-0000-4000-8000-000000000401")!,
        markerPhotoID: String? = nil,
        merchantImageURL: String? = nil
    ) throws -> Restaurant {
        let timestamp = "2026-09-03T00:00:00.000Z"
        let identity = try RestaurantPlaceIdentityContract(
            provider: .appleMaps,
            externalId: "apple-acquisition-\(id.uuidString.lowercased())",
            isPrimary: true,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let contract = try RestaurantJSONContractV1(
            id: id.uuidString.lowercased(),
            userId: ownerID,
            placeIdentities: [identity],
            name: "Canonical Fixture",
            address: "杭州测试路 1 号",
            city: "杭州",
            latitude: 30.25,
            longitude: 120.16,
            status: .visited,
            preferenceLevel: .like,
            overallRating: nil,
            foodRating: nil,
            environmentRating: nil,
            serviceRating: nil,
            valueRating: nil,
            tags: [],
            longTermNote: "",
            pricePerPerson: nil,
            phone: nil,
            openingHours: nil,
            markerType: markerPhotoID == nil ? .emoji : .image,
            markerPhotoId: markerPhotoID,
            merchantImageUrl: merchantImageURL,
            markerEmoji: "🍽️",
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil,
            isTestData: true
        )
        return Restaurant(
            id: id,
            ownerUserID: ownerID,
            name: contract.name,
            address: contract.address,
            latitude: contract.latitude,
            longitude: contract.longitude,
            appleMapItemIdentifier: identity.externalId,
            city: contract.city,
            remoteRecordData: try JSONEncoder().encode(contract)
        )
    }
}
