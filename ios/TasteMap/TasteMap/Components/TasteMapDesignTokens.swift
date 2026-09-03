import SwiftUI

/// Stable, reusable measurements and typography for the Core UI System.
///
/// Canonical page templates compose these values; feature screens should not
/// create a second visual scale for the same kind of control. A genuinely
/// page-specific composition may still own a local measurement when its reason
/// is documented by that template.
enum TasteMapDesignTokens {
    enum Spacing {
        static let hairline: CGFloat = 1
        static let xxxSmall: CGFloat = 2
        static let xxSmall: CGFloat = 3
        static let xSmall: CGFloat = 4
        static let compact: CGFloat = 5
        static let small: CGFloat = 8
        static let medium: CGFloat = 10
        static let regular: CGFloat = 12
        static let stateContent: CGFloat = 13
        static let content: CGFloat = 14
        static let section: CGFloat = 16
        static let large: CGFloat = 18
        static let xLarge: CGFloat = 20
        static let xxLarge: CGFloat = 24
        static let hero: CGFloat = 32
    }

    enum Radius {
        static let small: CGFloat = 10
        static let compact: CGFloat = 12
        static let control: CGFloat = 13
        static let medium: CGFloat = 16
        static let emptyArtwork: CGFloat = 17
        static let card: CGFloat = 20
        static let activityCard: CGFloat = 22
    }

    enum Border {
        static let standard: CGFloat = 1
    }

    enum Control {
        /// iOS accessibility-safe minimum interactive target.
        static let minimumHitTarget: CGFloat = 44
        static let chipVisibleHeight: CGFloat = 34
        static let segmentedVisibleHeight: CGFloat = 38
        static let primaryTabMinimumHeight: CGFloat = 44
        static let primaryTabIndicatorHeight: CGFloat = 2
        static let filterChipHorizontalPadding: CGFloat = 11
        static let filterBadgeMinimumHeight: CGFloat = 18
        static let primaryTabCompactMinimumWidth: CGFloat = 76
    }

    enum Icon {
        static let compact: CGFloat = 14
        static let standard: CGFloat = 18
        static let prominent: CGFloat = 24
        static let sectionContainer: CGFloat = 32
        static let emptyContainer: CGFloat = 54
        static let foodEmptyArtwork: CGFloat = 58
    }

    enum Avatar {
        static let compact: CGFloat = 28
        static let standard: CGFloat = 40
        static let profile: CGFloat = 72
    }

    enum ImageRatio {
        static let square: CGFloat = 1
        static let restaurantLandscape: CGFloat = 16 / 9
        static let restaurantCard: CGFloat = 4 / 3
        static let socialPoster: CGFloat = 9 / 16
    }

    enum Typography {
        static let filterLabel = Font.caption.weight(.semibold)
        static let filterBadge = Font.caption2.monospacedDigit().weight(.bold)
        static let primaryTabSelected = Font.subheadline.weight(.semibold)
        static let primaryTab = Font.subheadline.weight(.medium)
        static let selectedControl = Font.subheadline.weight(.semibold)
        static let control = Font.subheadline.weight(.medium)
        static let activityRating = Font.caption.weight(.semibold)
        static let sectionTitle = Font.title3.weight(.semibold)
        static let sectionSubtitle = Font.caption
        static let emptyTitle = Font.headline
        static let emptyMessage = Font.subheadline
    }

    enum Shadow {
        static let cardRadius: CGFloat = 12
        static let cardYOffset: CGFloat = 5
        static let selectedControlRadius: CGFloat = 5
        static let selectedControlYOffset: CGFloat = 2
    }

    enum Layout {
        static let pageInset: CGFloat = 16
        static let standardSectionSpacing: CGFloat = 16
        /// Compact, left-aligned media used by the open Activity feed composition.
        static let socialFeedMediaWidth: CGFloat = 168
    }
}
