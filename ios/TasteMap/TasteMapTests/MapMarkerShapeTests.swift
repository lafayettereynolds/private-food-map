import CoreGraphics
import UIKit
import MapKit
import Testing
@testable import TasteMap

@Suite("Paused treasure chest candidate isolation")
@MainActor
struct MapMarkerShapeTests {
    @Test("Formal defaults keep all Restaurant shells circular while candidate remains testable")
    func statusMapping() {
        #expect(!RestaurantMapMarkerShape.treasureChestCandidateEnabled)
        #expect(RestaurantMapMarkerShape.resolve(status: .visited) == .circle)
        #expect(RestaurantMapMarkerShape.resolve(status: .wantToGo) == .circle)
        #expect(RestaurantMapMarkerShape.resolve(status: .recommended) == .circle)
        #expect(RestaurantMapMarkerShape.resolve(status: .wantToGo, candidateEnabled: true) == .treasureChest)
        #expect(RestaurantMapMarkerShape.resolve(status: .recommended, candidateEnabled: true) == .treasureChest)
        #expect(RestaurantMapMarkerShape.resolve(status: .visited, candidateEnabled: true) == .circle)
    }

    @Test("Formal pending annotations show their historical dashed circle and no chest")
    func formalPendingShell() throws {
        for status: RestaurantMapMarkerStatus in [.wantToGo, .recommended] {
            let marker = RestaurantMapMarkerPresentation(id: UUID(), name: "Formal pending", latitude: 30.27, longitude: 120.15,
                status: status, visual: .category(.other), visitCount: 0, averageRating: nil, distanceKilometers: nil)
            let view = RestaurantMarkerAnnotationView(annotation: nil, reuseIdentifier: "formal-pending")
            _ = view.configure(marker)
            view.layoutIfNeeded()
            let visual = try #require(view.subviews.first)
            let shell = try #require(visual.subviews.compactMap { $0 as? UIImageView }.last)
            #expect(shell.isHidden)
            #expect(visual.layer.cornerRadius == visual.bounds.width / 2)
            let dashed = try #require(visual.layer.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
            #expect(!dashed.isHidden)
            #expect(dashed.lineDashPattern == RestaurantMapMarkerRingPolicy.unvisitedDashPattern.map(NSNumber.init(value:)))
            #expect(view.bounds.size == CGSize(width: 44, height: 44))
            #expect(view.centerOffset == .zero)
        }
    }

    @Test("The silhouette preserves the same centered frame at every existing diameter")
    func unchangedFrame() {
        for diameter: CGFloat in [10, 11, 14, 15, 24, 28, 32, 36, 40] {
            let frame = CGRect(x: (44 - diameter) / 2, y: (44 - diameter) / 2, width: diameter, height: diameter)
            for shape: RestaurantMapMarkerShape in [.circle, .treasureChest] {
                let bounds = shape.path(in: frame).boundingBoxOfPath
                #expect(abs(bounds.minX - frame.minX) < 0.000001)
                #expect(abs(bounds.minY - frame.minY) < 0.000001)
                #expect(abs(bounds.width - frame.width) < 0.000001)
                #expect(abs(bounds.height - frame.height) < 0.000001)
                #expect(abs(bounds.midX - 22) < 0.000001)
                #expect(abs(bounds.midY - 22) < 0.000001)
            }
        }
    }

    @Test("Original PNG keeps its clasp above the bounded real photograph window")
    func boundedDecorations() {
        let frame = CGRect(x: 6, y: 6, width: 32, height: 32)
        let clasp = RestaurantMapMarkerShape.claspFrame(in: frame)
        #expect(frame.contains(clasp))
        #expect(abs(clasp.midX - frame.midX) < 0.000001)
        let photo = RestaurantMapMarkerShape.photoFrame(in: frame)
        #expect(frame.contains(photo))
        #expect(abs(photo.width / frame.width - 46.0 / 62) < 0.000001)
        #expect(abs(photo.height / frame.height - 24.0 / 62) < 0.000001)
        let mask = RestaurantMapMarkerShape.shellMask(in: frame)
        #expect(mask.contains(CGPoint(x: frame.midX, y: frame.minY + 2), using: .evenOdd))
        #expect(!mask.contains(CGPoint(x: photo.minX + 1, y: photo.midY), using: .evenOdd))
        #expect(mask.contains(CGPoint(x: clasp.midX, y: photo.minY + 1), using: .evenOdd))
    }

    @Test("Photo completion preserves chest layers and reuse restores the visited circle")
    @MainActor
    func photoCompletionAndReuse() throws {
        let restaurantID = UUID()
        let photoID = UUID()
        func marker(_ status: RestaurantMapMarkerStatus) -> RestaurantMapMarkerPresentation {
            .init(id: restaurantID, name: "Marker shape test", latitude: 30.27, longitude: 120.15,
                  status: status, visual: .photo(photoID), visitCount: 0, averageRating: nil, distanceKilometers: nil)
        }
        let view = RestaurantMarkerAnnotationView(annotation: nil, reuseIdentifier: "chest-photo-reuse")
        view.setTreasureChestCandidateForTesting(true)
        for status: RestaurantMapMarkerStatus in [.wantToGo, .recommended] {
            let pending = marker(status)
            _ = view.configure(pending)
            view.layoutIfNeeded()
            let visual = try #require(view.subviews.first)
            let imageViews = visual.subviews.compactMap { $0 as? UIImageView }
            let shell = try #require(imageViews.last)
            let photoView = try #require(imageViews.first)
            let shellImage = try #require(shell.image)
            let shellCGImage = try #require(shellImage.cgImage)
            #expect(shellCGImage.width == 62)
            #expect(shellCGImage.height == 62)
            #expect([CGImageAlphaInfo.first, .last, .premultipliedFirst, .premultipliedLast].contains(shellCGImage.alphaInfo))
            #expect(!shell.isHidden)
            #expect(shell.center == CGPoint(x: visual.bounds.midX, y: visual.bounds.midY))
            #expect(shell.bounds.width == visual.bounds.width + 4)
            let originalMask = try #require(shell.layer.mask)
            let originalFrame = view.frame
            let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
                UIColor.brown.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            }
            view.finishImageLoad(image, for: pending, generation: view.imageGeneration)
            view.layoutIfNeeded()
            #expect(shell.image === shellImage)
            #expect(shell.layer.mask === originalMask)
            #expect(view.frame == originalFrame)
            #expect(view.bounds.size == CGSize(width: 44, height: 44))
            #expect(view.centerOffset == .zero)
            #expect(photoView.image === image)
        }
        _ = view.configure(marker(.visited))
        view.layoutIfNeeded()
        let restoredVisual = try #require(view.subviews.first)
        #expect(restoredVisual.layer.mask == nil)
        #expect(restoredVisual.layer.cornerRadius == restoredVisual.bounds.width / 2)
        let restoredShell = try #require(restoredVisual.subviews.compactMap { $0 as? UIImageView }.last)
        #expect(restoredShell.isHidden)
        #expect(view.bounds.size == CGSize(width: 44, height: 44))
        #expect(view.centerOffset == .zero)
    }
}
