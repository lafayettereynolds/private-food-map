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

    /// Content-sized Discovery evidence and unframed social actions (React peers use --tm-*).
    enum Activity {
        static let restaurantActionDiameter: CGFloat = 40
        static let reasonRadius = Spacing.compact
        static let reasonGap: CGFloat = 6
        static let reasonHorizontalInset: CGFloat = 6
        static let reasonVerticalInset = Spacing.xxSmall
        static let reasonFont = Font.caption2
        static let socialCountFont = Font.caption.monospacedDigit()
        static let socialCountGap = Spacing.compact
        static let recommendationSignalDiameter: CGFloat = 58
        static let recommendationMedalWidth: CGFloat = 62
        static let recommendationMedalHeight: CGFloat = 70
        static let recommendationSignalValueFont = Font.subheadline.weight(.semibold).monospacedDigit()
        static let recommendationSignalLabelFont = Font.system(size: 8)
        static let recommendationMatchStroke: CGFloat = 1.5
        static let recommendationProbabilityStroke: CGFloat = 3
        static let recommendationMatchDash: [CGFloat] = [3, 3]
    }

    /// Compact relationship action beside a user row; the hit area stays 44pt.
    enum FollowAction {
        static let minimumWidth: CGFloat = 64
        static let visibleHeight: CGFloat = 30
        static let horizontalPadding = Spacing.regular
    }

    /// The owner Dashboard's edit → statistics → first feature-pair rhythm.
    /// Tighten surrounding whitespace without shrinking the statistic targets.
    enum ProfileSummary {
        static let identityGap = Spacing.small
        static let statisticInset = Spacing.xSmall
        static let statisticMinimumHeight = Control.minimumHitTarget
        static let nextGap = Spacing.medium
    }

    /// Personal Restaurant circles stay legible above system POIs at every
    /// city zoom. Beyond the approved regional overview, only the centered
    /// visual shrinks further; the 44-point annotation target never changes.
    enum MapRestaurantMarker {
        static let minimumDiameter = 24.0
        static let maximumDiameter = 28.0
        static let unvisitedDiameterIncrease = 4.0
        static let minimumSelectionIncrease = 2.0
        static let maximumSelectionIncrease = 4.0
        static let farScaleStartLatitudeDelta = 2.4
        static let farScaleFullLatitudeDelta = 80.0
        static let farMinimumDiameter = 10.0
        static let farUnvisitedDiameterIncrease = 1.0
        static let farSelectionIncrease = 1.0
        // Content-only layers; never assign these offsets to map coordinates.
        // The front circle remains centered on the geographic anchor.
        static let stackBackOffsets = [
            CGSize(width: -10, height: -8), CGSize(width: 8, height: -10),
        ]
    }

    /// One canonical geometry for the live-location avatar bubble used by
    /// both the Native SwiftUI map and the persistent Hybrid MapKit surface.
    enum MapLocationMarker {
        static let width: CGFloat = 58
        static let height: CGFloat = 60
        static let haloDiameter: CGFloat = 54
        static let bubbleDiameter: CGFloat = 48
        static let avatarBorderDiameter: CGFloat = 44
        static let avatarDiameter: CGFloat = 40
        static let pointerOuterSide: CGFloat = 16
        static let pointerInnerSide: CGFloat = 12
        static let bubbleTop: CGFloat = 3
        static let pointerCenterY: CGFloat = 48
        static let centerOffsetY: CGFloat = -30
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
