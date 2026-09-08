import Foundation
import Testing
@testable import TasteMap

@Suite("Supplied food-library content artwork")
struct FoodLibraryArtworkTests {
    @Test("Restaurant name leads broad tags, with deterministic cuisine/default selection")
    func semanticSelection() throws {
        let catalog = try #require(FoodLibraryArtworkCatalog.bundled)
        #expect(catalog.resolve(name: "桂雨咖啡 7", tags: ["早午餐"], category: .cafeBakery)?.id == "coffee")
        #expect(catalog.resolve(name: "河岸牛排馆 4", tags: ["中餐"], category: .chinese)?.id == "steak")
        #expect(catalog.resolve(name: "兰州拉面", tags: [], category: .noodles)?.id == "beef-noodles")
        #expect(catalog.resolve(name: "春日", tags: ["泰餐"], category: .other)?.id == "thai")
        #expect(catalog.resolve(name: "ＦＯＯＤ ＣＡＦＥ", tags: [], category: .other)?.id == "coffee")
        #expect(catalog.resolve(name: "", tags: [], category: .other)?.id == "dining")
        for category in FoodCategoryVisualID.allCases {
            #expect(catalog.resolve(name: "", tags: [], category: category) != nil)
        }
    }

    @Test("Every viewport stays inside its unchanged bundled artwork sheet")
    func boundedSuppliedCells() throws {
        let catalog = try #require(FoodLibraryArtworkCatalog.bundled)
        #expect(catalog.rowEdges.count == catalog.rows + 1)
        #expect(catalog.rowEdges.first == 0)
        #expect(catalog.rowEdges.last == catalog.sheetHeight)
        #expect(zip(catalog.rowEdges, catalog.rowEdges.dropFirst()).allSatisfy { $0 < $1 })
        for entry in catalog.entries {
            #expect((0..<catalog.rows).contains(entry.row))
            #expect((0..<catalog.columns).contains(entry.column))
            #expect(Bundle.main.url(forResource: entry.sheet, withExtension: "png", subdirectory: "public/food-library") != nil)
            if let crop = catalog.crops?[entry.id] {
                #expect(crop.count == 4)
                #expect(crop[0] >= 0 && crop[1] >= 0 && crop[2] > 0 && crop[3] > 0)
                #expect(crop[0] + crop[2] <= catalog.sheetWidth)
                #expect(crop[1] + crop[3] <= catalog.sheetHeight)
            }
        }
    }
}
