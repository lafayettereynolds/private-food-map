import Foundation
import SwiftUI
import UIKit

/// The same unmodified, supplied artwork catalog used by React. This is content
/// illustration material, never a Restaurant avatar or a claimed user photo.
struct FoodLibraryArtworkCatalog: Decodable, Sendable {
    struct Entry: Decodable, Equatable, Sendable {
        let id: String
        let sheet: String
        let row: Int
        let column: Int
        let label: String
        let keywords: [String]
    }
    let columns: Int
    let rows: Int
    let sheetWidth: Int
    let sheetHeight: Int
    let rowEdges: [Int]
    let crops: [String: [Int]]?
    let entries: [Entry]
    let categoryDefaults: [String: String]

    func resolve(name: String, tags: [String], category: FoodCategoryVisualID) -> Entry? {
        func match(_ text: String) -> Entry? {
            let normalized = text.precomposedStringWithCompatibilityMapping.lowercased()
            return entries.first { entry in entry.keywords.contains { normalized.contains($0) } }
        }
        return match(name) ?? match(tags.joined(separator: "|"))
            ?? entries.first { $0.id == categoryDefaults[category.rawValue] }
    }

    static let bundled: FoodLibraryArtworkCatalog? = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "public/food-library"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }()
}

struct FoodLibraryArtworkDescriptor: Equatable, Sendable {
    let name: String
    var tags: [String] = []
    var categoryVisualID: FoodCategoryVisualID = .other
}

@MainActor
struct FoodLibraryArtwork: View {
    let descriptor: FoodLibraryArtworkDescriptor

    private var entry: FoodLibraryArtworkCatalog.Entry? {
        FoodLibraryArtworkCatalog.bundled?.resolve(name: descriptor.name, tags: descriptor.tags,
                                                   category: descriptor.categoryVisualID)
    }

    var body: some View {
        Group {
            if let entry, let image = Self.image(for: entry) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                // A corrupt/missing bundle is an explicit unavailable state;
                // do not silently regress to the Restaurant-avatar emoji.
                Text("素材暂不可用")
                    .font(TasteMapDesignTokens.Typography.control)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("\(descriptor.name) · \(entry?.label ?? "食物")素材插画（非餐厅实拍）")
        .accessibilityIdentifier("food-library-artwork-\(entry?.id ?? "unavailable")")
    }

    private static let images = NSCache<NSString, UIImage>()

    private static func image(for entry: FoodLibraryArtworkCatalog.Entry) -> UIImage? {
        if let cached = images.object(forKey: entry.id as NSString) { return cached }
        guard let catalog = FoodLibraryArtworkCatalog.bundled,
              catalog.columns > 0, catalog.rows > 0,
              (0..<catalog.columns).contains(entry.column), (0..<catalog.rows).contains(entry.row),
              let url = Bundle.main.url(forResource: entry.sheet, withExtension: "png", subdirectory: "public/food-library"),
              let source = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
        // Crop only the viewport in memory; source PNGs remain byte-identical.
        let width = CGFloat(source.width) / CGFloat(catalog.columns)
        guard catalog.rowEdges.count == catalog.rows + 1, catalog.sheetHeight > 0 else { return nil }
        let scale = CGFloat(source.height) / CGFloat(catalog.sheetHeight)
        let top = CGFloat(catalog.rowEdges[entry.row]) * scale
        let height = CGFloat(catalog.rowEdges[entry.row + 1] - catalog.rowEdges[entry.row]) * scale
        let rect: CGRect
        if let crop = catalog.crops?[entry.id], crop.count == 4, catalog.sheetWidth > 0 {
            let xScale = CGFloat(source.width) / CGFloat(catalog.sheetWidth)
            rect = CGRect(x: CGFloat(crop[0]) * xScale, y: CGFloat(crop[1]) * scale,
                          width: CGFloat(crop[2]) * xScale, height: CGFloat(crop[3]) * scale)
        } else {
            rect = CGRect(x: CGFloat(entry.column) * width, y: top, width: width, height: height)
        }
        guard let cropped = source.cropping(to: rect) else { return nil }
        let image = UIImage(cgImage: cropped)
        images.setObject(image, forKey: entry.id as NSString)
        return image
    }
}
