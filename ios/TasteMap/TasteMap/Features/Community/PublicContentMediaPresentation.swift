import Foundation

/// Presentation of already-authorized API photos, without importing another
/// user's images into the viewer's library or inventing export permission.
struct PublicContentMediaPresentation {
    let galleryPhotos: [PublicContentPhotoV1]
    let resolution: RestaurantImageResolution

    init(item: PublicContentItemV1) {
        let visit = item.kind == .visit && item.visit?.ownerUserId == item.user.userId ? item.visit : nil
        self.init(photos: visit.map { Self.validatedPhotos($0.photos, visitID: $0.id, authorID: $0.ownerUserId) } ?? [],
                  fallbackPhotoID: item.restaurant.photo?.photoId, merchantURL: item.restaurant.merchantImageUrl)
    }

    init(card: DiscoveryCardV1) {
        let photos: [PublicContentPhotoV1]
        if card.mode == .similarTaste, let activity = card.activity, let authorID = card.sourceUser?.userId {
            photos = (DiscoveryPhotoProjectionV1.activityAlbum(activity.photos, visitID: activity.visitId, authorID: authorID) ?? []).map {
                .init(photoId: $0.photoId, variant: $0.variant, sourceType: $0.sourceType,
                      restaurantId: $0.restaurantId, visitId: $0.visitId, ownerUserId: $0.ownerUserId,
                      visibility: $0.visibility, createdAt: $0.createdAt, exportAllowed: $0.exportAllowed)
            }
        } else { photos = [] }
        self.init(photos: photos, fallbackPhotoID: card.restaurant.photo?.photoId, merchantURL: card.restaurant.merchantImageUrl)
    }

    static func columnCount(photoCount: Int) -> Int {
        photoCount <= 1 ? 1 : photoCount == 2 || photoCount == 4 ? 2 : 3
    }

    private static func validatedPhotos(_ photos: [PublicContentPhotoV1], visitID: String, authorID: String) -> [PublicContentPhotoV1] {
        let ids = Set((DiscoveryPhotoProjectionV1.activityAlbum(photos.map(\.discoveryProjection), visitID: visitID, authorID: authorID) ?? []).map(\.photoId))
        var seen = Set<String>()
        return photos.filter { ids.contains($0.photoId) && seen.insert($0.photoId.lowercased()).inserted }
    }

    private init(photos: [PublicContentPhotoV1], fallbackPhotoID: String?, merchantURL: String?) {
        galleryPhotos = photos
        // A real album never borrows a Restaurant thumbnail from another Visit.
        let photoIDs = photos.isEmpty ? [fallbackPhotoID].compactMap { $0 } : photos.map(\.photoId)
        var seen = Set<RestaurantImageSourceReference>()
        let photoSources = photoIDs.flatMap {
            RestaurantImagePriorityPolicy.resolution(
                localUserPhotoID: nil, publicOrCachedPhotoID: $0
            ).sources
        }.filter { seen.insert($0).inserted }
        let merchantSources = photos.isEmpty ? RestaurantImagePriorityPolicy.resolution(
            localUserPhotoID: nil,
            providerMerchantImageURL: merchantURL
        ).sources : []
        resolution = RestaurantImageResolution(sources: photoSources + merchantSources)
    }
}
