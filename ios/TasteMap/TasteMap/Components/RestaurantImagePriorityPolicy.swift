import Foundation
import SwiftUI
import UIKit

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

/// One deterministic local-photo selector. A referenced marker photo is
/// preferred, followed by a Restaurant marker photo and then the newest valid
/// user photo. Page-specific renderers must not invent another ordering.
nonisolated enum RestaurantImagePhotoSelectionPolicy {
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
        return active.sorted(by: photoSort).first
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
           !resolution.isFallbackOnly,
           let fixtureImage = TasteMapVisualQAFixtures.restaurantImage(stableKey: semanticID) {
            return (
                fixtureImage,
                resolution.preferredSource
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
                FoodDiningVisualIcon(
                    kind: fallbackKind,
                    usage: .decorative,
                    size: fallbackIconSize,
                    foregroundColor: fallbackForegroundColor,
                    backgroundColor: fallbackBackgroundColor.opacity(0.84)
                )
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
        case .foodDiningFallback, .none: finished || resolution.isFallbackOnly ? "暂无真实图片" : "正在加载"
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
