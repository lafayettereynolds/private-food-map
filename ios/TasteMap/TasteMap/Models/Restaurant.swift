import Foundation
import SwiftData

@Model
final class Restaurant {
    @Attribute(.unique) var id: UUID
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var appleMapItemIdentifier: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        appleMapItemIdentifier: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.appleMapItemIdentifier = appleMapItemIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
