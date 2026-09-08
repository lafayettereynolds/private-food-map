// swift-tools-version: 5.9
import PackageDescription

// Formal Hybrid bridge package. It compiles the existing native models,
// ownership boundary and image policy into the isolated Capacitor shell without
// changing the shipping TasteMap.xcodeproj target membership or default root.
let package = Package(
    name: "TasteMapHybridBridge",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "TasteMapHybridBridge", targets: ["TasteMapHybridBridge"]),
    ],
    targets: [
        .target(
            name: "TasteMapHybridBridge",
            path: "ios/TasteMap/TasteMap",
            exclude: ["Assets.xcassets", "PrivacyInfo.xcprivacy"],
            sources: [
                "Components/RestaurantImagePriorityPolicy.swift",
                "Components/FoodCategoryVisual.swift",
                "Models/CompanionSource.swift",
                "Models/DiningMode.swift",
                "Models/Restaurant.swift",
                "Models/RestaurantCandidate.swift",
                "Models/Remote/RestaurantJSONContract.swift",
                "Models/RestaurantStatus.swift",
                "Models/SocialRelationship.swift",
                "Models/SyncStatus.swift",
                "Models/UserProfile.swift",
                "Models/Visit.swift",
                "Models/VisitContext.swift",
                "Hybrid/TasteMapHybridBridgeService.swift",
                "Hybrid/TasteMapHybridBridgeDispatcher.swift",
                "Hybrid/TasteMapHybridContracts.swift",
                "Hybrid/TasteMapDiscoveryRefreshCoordinator.swift",
                "Hybrid/TasteMapDiscoveryPageCoordinator.swift",
                "Hybrid/TasteMapDiscoveryQuery.swift",
                "Hybrid/TasteMapHybridDebugFixture.swift",
                "Persistence/LocalAccountOwnership.swift",
                "Services/RestaurantCityFilterIdentity.swift",
                "Services/RestaurantVisitStatePolicy.swift",
            ],
            swiftSettings: [.define("TASTEMAP_HYBRID_BRIDGE_CORE")]
        ),
        .testTarget(
            name: "TasteMapHybridBridgeTests",
            dependencies: ["TasteMapHybridBridge"],
            path: "hybrid/native-tests"
        ),
    ]
)
