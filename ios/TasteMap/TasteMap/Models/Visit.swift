import Foundation
import SwiftData

@Model
final class Visit {
    @Attribute(.unique) var id: UUID
    var restaurantId: UUID
    var visitedAt: Date
    var rating: Double?
    var valueRating: Double?
    var environmentRating: Double?
    var serviceRating: Double?
    var note: String?
    var myActualSpend: Decimal?
    var totalPrice: Decimal?
    var pricePerPerson: Decimal?
    private var diningModeValue: String = DiningMode.dineIn.rawValue
    private var visibilityValue: String = VisitVisibility.private.rawValue
    private var paymentModeValue: String?
    private var queueDurationValue: String?
    private var diningOccasionsJSON: String = "[]"
    var diningOccasionText: String?
    private var valueTagsJSON: String = "[]"
    private var environmentTagsJSON: String = "[]"
    private var serviceTagsJSON: String = "[]"
    private var noiseLevelValue: String?
    private var diningDurationValue: String?
    private var portionLevelValue: String?
    private var transportConvenienceValue: String?
    var specialNotes: String?
    var partySize: Int?
    var createdAt: Date
    var updatedAt: Date
    @Attribute(.unique) var remoteID: String?
    var deletedAt: Date?
    var serverVersion: Int64 = 0
    var lastSyncedAt: Date?
    private var syncStatusValue: String = SyncStatus.pending.rawValue

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusValue) ?? .pending }
        set { syncStatusValue = newValue.rawValue }
    }

    var diningMode: DiningMode {
        get { DiningMode(rawValue: diningModeValue) ?? .dineIn }
        set { diningModeValue = newValue.rawValue }
    }

    var visibility: VisitVisibility {
        get { VisitVisibility(rawValue: visibilityValue) ?? .private }
        set { visibilityValue = newValue.rawValue }
    }

    var paymentMode: VisitPaymentMode? {
        get { paymentModeValue.flatMap(VisitPaymentMode.init(rawValue:)) }
        set { paymentModeValue = newValue?.rawValue }
    }

    var paymentModeRawValue: String? {
        get { paymentModeValue }
        set { paymentModeValue = Self.normalizedRawValue(newValue) }
    }

    var queueDuration: VisitQueueDuration? {
        get { queueDurationValue.flatMap(VisitQueueDuration.init(rawValue:)) }
        set { queueDurationValue = newValue?.rawValue }
    }

    var queueDurationRawValue: String? {
        get { queueDurationValue }
        set { queueDurationValue = Self.normalizedRawValue(newValue) }
    }

    var diningOccasionRawValues: [String] {
        get { VisitStringArrayStorage.decode(diningOccasionsJSON) }
        set { diningOccasionsJSON = VisitStringArrayStorage.encode(newValue) }
    }

    var diningOccasions: [VisitDiningOccasion] {
        get { diningOccasionRawValues.compactMap(VisitDiningOccasion.init(rawValue:)) }
        set {
            let unknown = diningOccasionRawValues.filter { VisitDiningOccasion(rawValue: $0) == nil }
            diningOccasionRawValues = unknown + newValue.map(\.rawValue)
        }
    }

    var valueTags: [String] {
        get { VisitStringArrayStorage.decode(valueTagsJSON) }
        set { valueTagsJSON = VisitStringArrayStorage.encode(newValue) }
    }

    var environmentTags: [String] {
        get { VisitStringArrayStorage.decode(environmentTagsJSON) }
        set { environmentTagsJSON = VisitStringArrayStorage.encode(newValue) }
    }

    var serviceTags: [String] {
        get { VisitStringArrayStorage.decode(serviceTagsJSON) }
        set { serviceTagsJSON = VisitStringArrayStorage.encode(newValue) }
    }

    var noiseLevel: VisitNoiseLevel? {
        get { noiseLevelValue.flatMap(VisitNoiseLevel.init(rawValue:)) }
        set { noiseLevelValue = newValue?.rawValue }
    }

    var noiseLevelRawValue: String? {
        get { noiseLevelValue }
        set { noiseLevelValue = Self.normalizedRawValue(newValue) }
    }

    var diningDuration: VisitDiningDuration? {
        get { diningDurationValue.flatMap(VisitDiningDuration.init(rawValue:)) }
        set { diningDurationValue = newValue?.rawValue }
    }

    var diningDurationRawValue: String? {
        get { diningDurationValue }
        set { diningDurationValue = Self.normalizedRawValue(newValue) }
    }

    var portionLevel: VisitPortionLevel? {
        get { portionLevelValue.flatMap(VisitPortionLevel.init(rawValue:)) }
        set { portionLevelValue = newValue?.rawValue }
    }

    var portionLevelRawValue: String? {
        get { portionLevelValue }
        set { portionLevelValue = Self.normalizedRawValue(newValue) }
    }

    var transportConvenience: VisitTransportConvenience? {
        get { transportConvenienceValue.flatMap(VisitTransportConvenience.init(rawValue:)) }
        set { transportConvenienceValue = newValue?.rawValue }
    }

    var transportConvenienceRawValue: String? {
        get { transportConvenienceValue }
        set { transportConvenienceValue = Self.normalizedRawValue(newValue) }
    }

    init(
        id: UUID = UUID(),
        restaurantId: UUID,
        visitedAt: Date = .now,
        rating: Double? = nil,
        valueRating: Double? = nil,
        environmentRating: Double? = nil,
        serviceRating: Double? = nil,
        note: String? = nil,
        myActualSpend: Decimal? = nil,
        totalPrice: Decimal? = nil,
        pricePerPerson: Decimal? = nil,
        diningMode: DiningMode = .dineIn,
        visibility: VisitVisibility = .private,
        paymentMode: VisitPaymentMode? = nil,
        queueDuration: VisitQueueDuration? = nil,
        diningOccasions: [VisitDiningOccasion] = [],
        diningOccasionText: String? = nil,
        valueTags: [String] = [],
        environmentTags: [String] = [],
        serviceTags: [String] = [],
        noiseLevel: VisitNoiseLevel? = nil,
        diningDuration: VisitDiningDuration? = nil,
        portionLevel: VisitPortionLevel? = nil,
        transportConvenience: VisitTransportConvenience? = nil,
        specialNotes: String? = nil,
        partySize: Int? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        remoteID: String? = nil,
        deletedAt: Date? = nil,
        serverVersion: Int64 = 0,
        lastSyncedAt: Date? = nil,
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id
        self.restaurantId = restaurantId
        self.visitedAt = visitedAt
        self.rating = Self.validatedRating(rating)
        self.valueRating = Self.validatedRating(valueRating)
        self.environmentRating = Self.validatedRating(environmentRating)
        self.serviceRating = Self.validatedRating(serviceRating)
        self.note = note?.nilIfBlank
        self.myActualSpend = myActualSpend
        self.totalPrice = totalPrice
        self.pricePerPerson = pricePerPerson
        self.diningModeValue = diningMode.rawValue
        self.visibilityValue = visibility.rawValue
        self.paymentModeValue = paymentMode?.rawValue
        self.queueDurationValue = queueDuration?.rawValue
        self.diningOccasionsJSON = VisitStringArrayStorage.encode(diningOccasions.map(\.rawValue))
        self.diningOccasionText = diningOccasionText?.nilIfBlank
        self.valueTagsJSON = VisitStringArrayStorage.encode(valueTags)
        self.environmentTagsJSON = VisitStringArrayStorage.encode(environmentTags)
        self.serviceTagsJSON = VisitStringArrayStorage.encode(serviceTags)
        self.noiseLevelValue = noiseLevel?.rawValue
        self.diningDurationValue = diningDuration?.rawValue
        self.portionLevelValue = portionLevel?.rawValue
        self.transportConvenienceValue = transportConvenience?.rawValue
        self.specialNotes = specialNotes?.nilIfBlank
        self.partySize = partySize.flatMap { $0 >= 1 ? $0 : nil }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.remoteID = remoteID ?? id.uuidString
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
        self.lastSyncedAt = lastSyncedAt
        self.syncStatusValue = syncStatus.rawValue
    }

    static func validatedRating(_ value: Double?) -> Double? {
        guard let value, (0.5...5).contains(value) else { return nil }
        let halfStep = (value * 2).rounded() / 2
        return abs(halfStep - value) < 0.000_001 ? halfStep : nil
    }

    private static func normalizedRawValue(_ value: String?) -> String? {
        value?.nilIfBlank
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
