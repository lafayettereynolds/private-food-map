import Foundation
#if !TASTEMAP_HYBRID_BRIDGE_CORE
import SwiftUI
import UIKit
#endif

/// Explicit owner artwork is not a cuisine suggestion. Preserve one complete
/// Unicode emoji (including flags/ZWJ/skin tone) instead of food-allowlisting it.
nonisolated enum RestaurantOwnerAvatarEmojiPolicy {
    static func normalized(_ input: String?) -> String? {
        guard let value = input?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.count == 1, value.unicodeScalars.count <= 16 else { return nil }
        return value.unicodeScalars.contains {
            $0.properties.isEmojiPresentation || $0.value == 0xFE0F || $0.value == 0x20E3 ||
                (0x1F1E6...0x1F1FF).contains($0.value)
        } ? value : nil
    }
}

/// One cross-surface contract for Restaurant-facing imagery.
///
/// A Food & Dining visual is an honest final fallback. It must never mask a
/// real image that the user owns or that Taste Map may legally display.
nonisolated enum RestaurantImageSourceReference: Hashable, Sendable {
    case localUserPhoto(UUID)
    case publicOrCachedPhoto(String)
    case providerMerchantImage(URL)
    case foodDiningFallback
}

/// The canonical, ordered Restaurant image loading plan shared by every
/// Restaurant-facing surface. The fallback is deliberately not a candidate:
/// it is rendered only after every legal real-image source is unavailable or
/// has failed to decode.
nonisolated struct RestaurantImageResolution: Hashable, Sendable {
    let sources: [RestaurantImageSourceReference]

    var preferredSource: RestaurantImageSourceReference {
        sources.first ?? .foodDiningFallback
    }

    var isFallbackOnly: Bool { sources.isEmpty }

    func sources(afterFailureOf failedSource: RestaurantImageSourceReference) -> [RestaurantImageSourceReference] {
        guard let index = sources.firstIndex(of: failedSource) else { return sources }
        return Array(sources.dropFirst(index + 1))
    }
}

nonisolated enum RestaurantImagePriorityPolicy {
    static func resolution(
        localUserPhotoID: UUID?,
        publicOrCachedPhotoID: String? = nil,
        providerMerchantImageURL: String? = nil
    ) -> RestaurantImageResolution {
        var sources: [RestaurantImageSourceReference] = []
        if let localUserPhotoID {
            sources.append(.localUserPhoto(localUserPhotoID))
        }
        if let publicPhotoID = nonempty(publicOrCachedPhotoID),
           publicPhotoID.lowercased() != localUserPhotoID?.uuidString.lowercased() {
            sources.append(.publicOrCachedPhoto(publicPhotoID))
        }
        if let providerURL = safeHTTPSURL(providerMerchantImageURL) {
            sources.append(.providerMerchantImage(providerURL))
        }
        return RestaurantImageResolution(sources: sources)
    }

    static func resolution(
        localUserPhotoID: UUID?,
        publicOrCachedPhotoID: String? = nil,
        providerMerchantImageURL: URL?
    ) -> RestaurantImageResolution {
        resolution(
            localUserPhotoID: localUserPhotoID,
            publicOrCachedPhotoID: publicOrCachedPhotoID,
            providerMerchantImageURL: providerMerchantImageURL?.absoluteString
        )
    }

    static func preferred(
        localUserPhotoID: UUID?,
        publicOrCachedPhotoID: String? = nil,
        providerMerchantImageURL: String? = nil
    ) -> RestaurantImageSourceReference {
        resolution(
            localUserPhotoID: localUserPhotoID,
            publicOrCachedPhotoID: publicOrCachedPhotoID,
            providerMerchantImageURL: providerMerchantImageURL
        ).preferredSource
    }

    static func preferred(
        localUserPhotoID: UUID?,
        publicOrCachedPhotoID: String? = nil,
        providerMerchantImageURL: URL?
    ) -> RestaurantImageSourceReference {
        preferred(
            localUserPhotoID: localUserPhotoID,
            publicOrCachedPhotoID: publicOrCachedPhotoID,
            providerMerchantImageURL: providerMerchantImageURL?.absoluteString
        )
    }

    static func safeHTTPSURL(_ value: String?) -> URL? {
        guard let rawValue = nonempty(value),
              let url = URL(string: rawValue),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#if !TASTEMAP_HYBRID_BRIDGE_CORE
extension RestaurantImagePriorityPolicy {
    /// Builds the canonical loading plan for a Restaurant acquisition candidate.
    ///
    /// Identity matching and owner filtering happen before image projection. A
    /// candidate may contribute a second provider image, but it can never move
    /// ahead of an owned photo, an owner-visible public/cached photo, or the
    /// matched Restaurant's persisted merchant image.
    static func acquisitionResolution(
        matchedRestaurant: Restaurant?,
        authenticatedOwnerUserID: String,
        ownerPhotos: [PhotoAsset],
        candidateProviderMerchantImageURL: URL?
    ) -> RestaurantImageResolution {
        let ownedRestaurant = matchedRestaurant.flatMap { restaurant in
            restaurant.ownerUserID == authenticatedOwnerUserID && restaurant.deletedAt == nil
                ? restaurant
                : nil
        }
        let contract = ownedRestaurant?.remoteRecordData.flatMap {
            try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: $0)
        }.flatMap { value in
            value.userId == authenticatedOwnerUserID ? value : nil
        }
        let ownedPhotos = ownerPhotos.filter {
            $0.ownerUserID == authenticatedOwnerUserID
                && $0.deletedAt == nil
                && $0.binaryDeletedAt == nil
        }
        let localPhoto = ownedRestaurant.flatMap { restaurant in
            RestaurantImagePhotoSelectionPolicy.preferredPhoto(
                restaurantID: restaurant.id,
                photos: ownedPhotos,
                referencedPhotoID: contract?.markerPhotoId
            )
        }
        let persisted = resolution(
            localUserPhotoID: localPhoto?.id,
            publicOrCachedPhotoID: contract?.markerPhotoId,
            providerMerchantImageURL: contract?.merchantImageUrl
        )
        guard let candidateSource = safeHTTPSURL(candidateProviderMerchantImageURL?.absoluteString)
            .map(RestaurantImageSourceReference.providerMerchantImage),
              !persisted.sources.contains(candidateSource) else {
            return persisted
        }
        return RestaurantImageResolution(sources: persisted.sources + [candidateSource])
    }
}

/// One deterministic local-photo selector. A referenced marker photo is
/// preferred, followed by a Restaurant marker photo and then the newest valid
/// user photo. Page-specific renderers must not invent another ordering.
nonisolated enum RestaurantImagePhotoSelectionPolicy {
    /// Content imagery is not a customizable Restaurant avatar. Only actual
    /// Visit/dish photographs may enter heroes, albums or automatic selection.
    static func actualPhotos(restaurantID: UUID, photos: [PhotoAsset]) -> [PhotoAsset] {
        photos.filter {
            $0.restaurantId == restaurantID && [.visit, .dish].contains($0.kind)
                && $0.deletedAt == nil && $0.binaryDeletedAt == nil && $0.uploadState != .deleted
        }.sorted(by: photoSort)
    }

    static func preferredContentPhoto(restaurantID: UUID, photos: [PhotoAsset]) -> PhotoAsset? {
        actualPhotos(restaurantID: restaurantID, photos: photos).first
    }

    static func preferredPhoto(
        restaurantID: UUID,
        photos: [PhotoAsset],
        referencedPhotoID: String? = nil
    ) -> PhotoAsset? {
        let active = photos.filter {
            $0.restaurantId == restaurantID
                && $0.deletedAt == nil
                && $0.binaryDeletedAt == nil
                && $0.uploadState != .deleted
        }
        if let reference = referencedPhotoID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reference.isEmpty,
           let matched = active.first(where: {
               $0.id.uuidString.caseInsensitiveCompare(reference) == .orderedSame
                   || $0.remoteID?.caseInsensitiveCompare(reference) == .orderedSame
           }) {
            return matched
        }
        // An unreferenced custom avatar is never an automatic candidate for a
        // different avatar selection. Explicit references above still win.
        return actualPhotos(restaurantID: restaurantID, photos: active).first
    }

    private static func photoSort(_ lhs: PhotoAsset, _ rhs: PhotoAsset) -> Bool {
        if (lhs.kind == .restaurantMarker) != (rhs.kind == .restaurantMarker) {
            return lhs.kind == .restaurantMarker
        }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

actor RestaurantImageRemoteDataLoader {
    static let shared = RestaurantImageRemoteDataLoader()

    private struct CacheEntry {
        let data: Data
        var access: UInt64
    }

    private var cache: [String: CacheEntry] = [:]
    private var requests: [String: Task<Data?, Never>] = [:]
    private var cacheBytes = 0
    private var accessCounter: UInt64 = 0
    private let maximumObjectBytes = 20 * 1_024 * 1_024
    private let maximumCacheBytes = 32 * 1_024 * 1_024
    private let maximumCount = 96

    func data(
        for source: RestaurantImageSourceReference,
        photoAPI: (any PhotoBinaryAPI)?,
        variant: PhotoBinaryVariant
    ) async -> Data? {
        let key: String
        switch source {
        case .publicOrCachedPhoto(let value): key = "public:\(value):\(variant.rawValue)"
        case .providerMerchantImage(let url): key = "provider:\(url.absoluteString)"
        case .localUserPhoto, .foodDiningFallback: return nil
        }
        if var cached = cache[key] {
            accessCounter &+= 1
            cached.access = accessCounter
            cache[key] = cached
            return cached.data
        }
        if let request = requests[key] { return await request.value }

        let maximumObjectBytes = self.maximumObjectBytes
        let request = Task<Data?, Never> {
            let data: Data?
            switch source {
            case .publicOrCachedPhoto(let value):
                guard let id = UUID(uuidString: value), let photoAPI else { return nil }
                data = try? await photoAPI.download(photoID: id, variant: variant)
            case .providerMerchantImage(let url):
                guard let (candidate, response) = try? await URLSession.shared.data(from: url),
                      let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode),
                      response.mimeType?.lowercased().hasPrefix("image/") == true else { return nil }
                data = candidate
            case .localUserPhoto, .foodDiningFallback:
                data = nil
            }
            guard let data, !data.isEmpty, data.count <= maximumObjectBytes,
                  UIImage(data: data) != nil else { return nil }
            return data
        }
        requests[key] = request
        let result = await request.value
        requests[key] = nil
        if let result { insert(result, for: key) }
        return result
    }

    private func insert(_ data: Data, for key: String) {
        guard data.count <= maximumCacheBytes else { return }
        if let previous = cache[key] { cacheBytes -= previous.data.count }
        accessCounter &+= 1
        cache[key] = CacheEntry(data: data, access: accessCounter)
        cacheBytes += data.count
        while cacheBytes > maximumCacheBytes || cache.count > maximumCount {
            guard let oldest = cache.min(by: { $0.value.access < $1.value.access }) else { break }
            cacheBytes -= oldest.value.data.count
            cache[oldest.key] = nil
        }
    }
}

@MainActor
enum RestaurantImageLoader {
    static func image(
        resolution: RestaurantImageResolution,
        photosByID: [UUID: PhotoAsset],
        coordinator: PhotoTransferCoordinator?,
        photoAPI: (any PhotoBinaryAPI)?,
        variant: PhotoBinaryVariant,
        semanticID: String
    ) async -> (image: UIImage, source: RestaurantImageSourceReference)? {
#if DEBUG
        if TasteMapUITestFixtures.usesVisualQA,
           let fixtureSource = visualQAFixtureSource(in: resolution),
           let fixtureImage = TasteMapVisualQAFixtures.restaurantImage(stableKey: semanticID) {
            return (
                fixtureImage,
                fixtureSource
            )
        }
#endif
        for source in resolution.sources {
            guard !Task.isCancelled else { return nil }
            let data: Data?
            switch source {
            case .localUserPhoto(let id):
                guard let photo = photosByID[id], let coordinator else { continue }
                data = try? await coordinator.imageData(for: photo, variant: variant)
            case .publicOrCachedPhoto(let value):
                if let id = UUID(uuidString: value), let photo = photosByID[id], let coordinator {
                    data = try? await coordinator.imageData(for: photo, variant: variant)
                } else {
                    data = await RestaurantImageRemoteDataLoader.shared.data(
                        for: source,
                        photoAPI: photoAPI,
                        variant: variant
                    )
                }
            case .providerMerchantImage:
                data = await RestaurantImageRemoteDataLoader.shared.data(
                    for: source,
                    photoAPI: photoAPI,
                    variant: variant
                )
            case .foodDiningFallback:
                data = nil
            }
            if let data, let image = UIImage(data: data) { return (image, source) }
        }
        return nil
    }

#if DEBUG
    /// Rich Visual QA may stand in for user-owned/cached fixture binaries, but
    /// must never paint a generated Food Hero and report it as a provider's
    /// merchant photo. Provider-only fixtures therefore exercise the real
    /// network/failure chain and end at the honest dining fallback.
    static func visualQAFixtureSource(
        in resolution: RestaurantImageResolution
    ) -> RestaurantImageSourceReference? {
        resolution.sources.first { source in
            switch source {
            case .localUserPhoto, .publicOrCachedPhoto:
                true
            case .providerMerchantImage, .foodDiningFallback:
                false
            }
        }
    }
#endif
}

/// Canonical SwiftUI Restaurant image renderer.
///
/// Surfaces own their crop, frame and mask. This view exclusively owns source
/// priority, loading, failure chaining and the honest Food & Dining fallback.
struct TasteMapRestaurantImage: View {
    let resolution: RestaurantImageResolution
    var photosByID: [UUID: PhotoAsset] = [:]
    var photoAPI: (any PhotoBinaryAPI)?
    var semanticID: String
    var variant: PhotoBinaryVariant = .thumbnail
    var contentMode: ContentMode = .fill
    var fallbackKind: FoodDiningVisualKind = .genericDining
    var fallbackForegroundColor: Color = TasteMapCoreTheme.brandDeep
    var fallbackBackgroundColor: Color = TasteMapCoreTheme.surfaceSubtle
    var fallbackIconSize: CGFloat = 44
    var categoryVisualID: FoodCategoryVisualID = .other
    var foodLibraryArtwork: FoodLibraryArtworkDescriptor?
    var missingImageLabel: String?
    var accessibilityLabel: String = "餐厅图片"

    @Environment(\.photoTransferCoordinator) private var coordinator
    @State private var renderedImage: UIImage?
    @State private var renderedSource: RestaurantImageSourceReference?
    @State private var finished = false

    var body: some View {
        ZStack {
            fallbackBackgroundColor
            if let renderedImage {
                Image(uiImage: renderedImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if finished || resolution.isFallbackOnly {
                if let foodLibraryArtwork {
                    FoodLibraryArtwork(descriptor: foodLibraryArtwork)
                } else if let missingImageLabel {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: min(fallbackIconSize, 34), weight: .regular))
                        Text(missingImageLabel)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(fallbackForegroundColor.opacity(0.72))
                } else {
                    FoodCategoryVisual(id: categoryVisualID, accessibilityLabel: accessibilityLabel)
                        .frame(width: fallbackIconSize, height: fallbackIconSize)
                }
            } else {
                ProgressView()
                    .tint(fallbackForegroundColor)
            }
        }
        .clipped()
        .task(id: taskIdentity) { await resolve() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("restaurant-image-\(sourceKind)-\(safeSemanticID)")
    }

    private var taskIdentity: String {
        "\(resolution.hashValue):\(variant.rawValue):\(semanticID)"
    }

    private var sourceKind: String {
        switch renderedSource ?? resolution.preferredSource {
        case .localUserPhoto: "user"
        case .publicOrCachedPhoto: "public"
        case .providerMerchantImage: "provider"
        case .foodDiningFallback: "fallback"
        }
    }

    private var accessibilityValue: String {
        switch renderedSource {
        case .localUserPhoto: "用户真实照片"
        case .publicOrCachedPhoto: "公开餐厅照片"
        case .providerMerchantImage: "商户餐厅照片"
        case .foodDiningFallback, .none:
            finished || resolution.isFallbackOnly
                ? (foodLibraryArtwork == nil ? "暂无真实图片" : "食物素材插画，非餐厅实拍") : "正在加载"
        }
    }

    private var safeSemanticID: String {
        semanticID.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "-", options: .regularExpression)
    }

    @MainActor
    private func resolve() async {
        renderedImage = nil
        renderedSource = nil
        finished = resolution.isFallbackOnly
        guard !resolution.isFallbackOnly else { return }

        if let result = await RestaurantImageLoader.image(
            resolution: resolution,
            photosByID: photosByID,
            coordinator: coordinator,
            photoAPI: photoAPI,
            variant: variant,
            semanticID: semanticID
        ) {
            renderedImage = result.image
            renderedSource = result.source
            finished = true
            return
        }
        renderedSource = .foodDiningFallback
        finished = true
    }
}
#endif
