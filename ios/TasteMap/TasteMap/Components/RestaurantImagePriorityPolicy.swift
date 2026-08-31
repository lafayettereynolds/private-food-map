import Foundation

/// One cross-surface contract for Restaurant-facing imagery.
///
/// A Food & Dining visual is an honest final fallback. It must never mask a
/// real image that the user owns or that Taste Map may legally display.
nonisolated enum RestaurantImageSourceReference: Equatable, Sendable {
    case localUserPhoto(UUID)
    case publicOrCachedPhoto(String)
    case providerMerchantImage(URL)
    case foodDiningFallback
}

nonisolated enum RestaurantImagePriorityPolicy {
    static func preferred(
        localUserPhotoID: UUID?,
        publicOrCachedPhotoID: String? = nil,
        providerMerchantImageURL: String? = nil
    ) -> RestaurantImageSourceReference {
        if let localUserPhotoID {
            return .localUserPhoto(localUserPhotoID)
        }
        if let publicPhotoID = nonempty(publicOrCachedPhotoID) {
            return .publicOrCachedPhoto(publicPhotoID)
        }
        if let providerURL = safeHTTPSURL(providerMerchantImageURL) {
            return .providerMerchantImage(providerURL)
        }
        return .foodDiningFallback
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
