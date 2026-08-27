import Foundation

struct RestaurantCandidate: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let appleMapItemIdentifier: String?

    init(
        id: UUID = UUID(),
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        appleMapItemIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.appleMapItemIdentifier = appleMapItemIdentifier
    }
}
