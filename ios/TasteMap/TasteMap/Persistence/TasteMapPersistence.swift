import SwiftData

enum TasteMapPersistence {
    static let schema = Schema([
        Restaurant.self,
        Visit.self,
    ])

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "TasteMap",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
