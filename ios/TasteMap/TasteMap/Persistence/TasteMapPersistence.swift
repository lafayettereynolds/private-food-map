import Foundation
import SwiftData

enum TasteMapPersistence {
    static let schema = Schema([
        Restaurant.self,
        Visit.self,
        Dish.self,
        VisitDish.self,
        PhotoAsset.self,
        DiningCompanion.self,
        RecommendationSource.self,
        UserProfile.self,
        CachedSocialProfile.self,
        CachedFriendship.self,
        CachedFollow.self,
        SocialMutation.self,
        SyncMutation.self,
        SyncCheckpoint.self,
    ])

    static func makeContainer(
        inMemory: Bool = false,
        configurationName: String = "TasteMap",
        storageURL: URL? = nil
    ) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let storageURL {
            configuration = ModelConfiguration(
                configurationName,
                schema: schema,
                url: storageURL,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                configurationName,
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
