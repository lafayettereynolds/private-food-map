// swift-tools-version: 5.9
import PackageDescription

// Isolated POC-only package: it compiles the existing native models, persistence
// and image policy into the generated Capacitor shell without changing the
// shipping TasteMap.xcodeproj target membership.
let package = Package(
    name: "TasteMapNativePOC",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "TasteMapNativePOC", targets: ["TasteMapNativePOC"]),
    ],
    targets: [
        .target(
            name: "TasteMapNativePOC",
            path: "ios/TasteMap/TasteMap",
            sources: [
                "Components/RestaurantImagePriorityPolicy.swift",
                "Models/CompanionSource.swift",
                "Models/DiningMode.swift",
                "Models/Restaurant.swift",
                "Models/RestaurantStatus.swift",
                "Models/SocialRelationship.swift",
                "Models/SyncStatus.swift",
                "Models/UserProfile.swift",
                "Models/Visit.swift",
                "Models/VisitContext.swift",
                "POC/TasteMapHybridPOCService.swift",
                "Persistence/LocalAccountOwnership.swift",
            ],
            swiftSettings: [.define("TASTEMAP_HYBRID_POC_CORE")]
        ),
        .testTarget(
            name: "TasteMapNativePOCTests",
            dependencies: ["TasteMapNativePOC"],
            path: "hybrid-poc/native-tests"
        ),
    ]
)
