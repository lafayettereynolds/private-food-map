import CoreGraphics

/// Native peer of mapMarkerShape.ts. The user's lossless PNG is the artwork;
/// this primitive only places its photograph window, never redraws the chest.
enum RestaurantMapMarkerShape: Equatable {
    case circle, treasureChest

    static let assetName = "MapMarkerTreasureChest"
    // Latest Lafayette hold: never enable from launch arguments or user state.
    static let treasureChestCandidateEnabled = false

    static func resolve(status: RestaurantMapMarkerStatus, candidateEnabled: Bool = treasureChestCandidateEnabled) -> Self {
        candidateEnabled && status != .visited ? .treasureChest : .circle
    }

    /// Maintains the established centered outer bounds. The pending rectangle
    /// is geometry evidence only, not a painted substitute for the PNG silhouette.
    func path(in rect: CGRect) -> CGPath {
        self == .circle ? CGPath(ellipseIn: rect, transform: nil) : CGPath(rect: rect, transform: nil)
    }

    static func photoFrame(in rect: CGRect) -> CGRect {
        scaled(CGRect(x: 8, y: 32, width: 46, height: 24), in: rect)
    }

    static func claspFrame(in rect: CGRect) -> CGRect {
        scaled(CGRect(x: 25, y: 29, width: 12, height: 14), in: rect)
    }

    /// Even-odd window exposes the underlying canonical photo while keeping
    /// the actual original clasp pixels above it. The asset itself is untouched.
    static func shellMask(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addRect(rect)
        path.addRect(photoFrame(in: rect))
        path.addRect(claspFrame(in: rect).intersection(photoFrame(in: rect)))
        return path
    }

    private static func scaled(_ pixels: CGRect, in rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + rect.width * pixels.minX / 62,
               y: rect.minY + rect.height * pixels.minY / 62,
               width: rect.width * pixels.width / 62, height: rect.height * pixels.height / 62)
    }
}
