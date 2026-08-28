import Foundation

struct VisitDraft: Equatable {
    var visitedAt: Date
    var diningMode: DiningMode
    var partySize: Int?
    var rating: Double?
    var valueRating: Double?
    var environmentRating: Double?
    var serviceRating: Double?
    var myActualSpend: Decimal?
    var totalPrice: Decimal?
    var visibility: VisitVisibility
    var paymentModeRawValue: String?
    var queueDurationRawValue: String?
    var diningOccasionRawValues: [String]
    var diningOccasionText: String
    var valueTags: [String]
    var environmentTags: [String]
    var serviceTags: [String]
    var noiseLevelRawValue: String?
    var diningDurationRawValue: String?
    var portionLevelRawValue: String?
    var transportConvenienceRawValue: String?
    var specialNotes: String
    var companionIDs: [String]
    var companionNames: [String]
    var recommendationSourceID: String?
    var recommendationSourceTypeRawValue: String?
    var recommendationSourceUserID: String?
    var recommendationSourceText: String
    var sharedMealID: String?
    var note: String

    var paymentMode: VisitPaymentMode? {
        get { paymentModeRawValue.flatMap(VisitPaymentMode.init(rawValue:)) }
        set { paymentModeRawValue = newValue?.rawValue }
    }

    var queueDuration: VisitQueueDuration? {
        get { queueDurationRawValue.flatMap(VisitQueueDuration.init(rawValue:)) }
        set { queueDurationRawValue = newValue?.rawValue }
    }

    var diningOccasions: [VisitDiningOccasion] {
        get { diningOccasionRawValues.compactMap(VisitDiningOccasion.init(rawValue:)) }
        set {
            let unknown = diningOccasionRawValues.filter { VisitDiningOccasion(rawValue: $0) == nil }
            diningOccasionRawValues = unknown + newValue.map(\.rawValue)
        }
    }

    var noiseLevel: VisitNoiseLevel? {
        get { noiseLevelRawValue.flatMap(VisitNoiseLevel.init(rawValue:)) }
        set { noiseLevelRawValue = newValue?.rawValue }
    }

    var diningDuration: VisitDiningDuration? {
        get { diningDurationRawValue.flatMap(VisitDiningDuration.init(rawValue:)) }
        set { diningDurationRawValue = newValue?.rawValue }
    }

    var portionLevel: VisitPortionLevel? {
        get { portionLevelRawValue.flatMap(VisitPortionLevel.init(rawValue:)) }
        set { portionLevelRawValue = newValue?.rawValue }
    }

    var transportConvenience: VisitTransportConvenience? {
        get { transportConvenienceRawValue.flatMap(VisitTransportConvenience.init(rawValue:)) }
        set { transportConvenienceRawValue = newValue?.rawValue }
    }

    var hasExperienceContext: Bool {
        !valueTags.isEmpty || !environmentTags.isEmpty || !serviceTags.isEmpty ||
            noiseLevelRawValue != nil || diningDurationRawValue != nil ||
            portionLevelRawValue != nil || transportConvenienceRawValue != nil ||
            !specialNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        visitedAt: Date = .now,
        diningMode: DiningMode = .dineIn,
        partySize: Int? = nil,
        rating: Double? = nil,
        valueRating: Double? = nil,
        environmentRating: Double? = nil,
        serviceRating: Double? = nil,
        myActualSpend: Decimal? = nil,
        totalPrice: Decimal? = nil,
        visibility: VisitVisibility = .private,
        paymentMode: VisitPaymentMode? = nil,
        queueDuration: VisitQueueDuration? = nil,
        diningOccasions: [VisitDiningOccasion] = [],
        diningOccasionText: String = "",
        valueTags: [String] = [],
        environmentTags: [String] = [],
        serviceTags: [String] = [],
        noiseLevel: VisitNoiseLevel? = nil,
        diningDuration: VisitDiningDuration? = nil,
        portionLevel: VisitPortionLevel? = nil,
        transportConvenience: VisitTransportConvenience? = nil,
        specialNotes: String = "",
        companionIDs: [String] = [],
        companionNames: [String] = [],
        recommendationSourceID: String? = nil,
        recommendationSourceType: RecommendationSourceType? = nil,
        recommendationSourceUserID: String? = nil,
        recommendationSourceText: String = "",
        sharedMealID: String? = nil,
        note: String = ""
    ) {
        self.visitedAt = visitedAt
        self.diningMode = diningMode
        self.partySize = partySize
        self.rating = rating
        self.valueRating = valueRating
        self.environmentRating = environmentRating
        self.serviceRating = serviceRating
        self.myActualSpend = myActualSpend
        self.totalPrice = totalPrice
        self.visibility = visibility
        self.paymentModeRawValue = paymentMode?.rawValue
        self.queueDurationRawValue = queueDuration?.rawValue
        self.diningOccasionRawValues = diningOccasions.map(\.rawValue)
        self.diningOccasionText = diningOccasionText
        self.valueTags = valueTags
        self.environmentTags = environmentTags
        self.serviceTags = serviceTags
        self.noiseLevelRawValue = noiseLevel?.rawValue
        self.diningDurationRawValue = diningDuration?.rawValue
        self.portionLevelRawValue = portionLevel?.rawValue
        self.transportConvenienceRawValue = transportConvenience?.rawValue
        self.specialNotes = specialNotes
        self.companionIDs = companionIDs
        self.companionNames = companionNames
        self.recommendationSourceID = recommendationSourceID
        self.recommendationSourceTypeRawValue = recommendationSourceType?.rawValue
        self.recommendationSourceUserID = recommendationSourceUserID
        self.recommendationSourceText = recommendationSourceText
        self.sharedMealID = sharedMealID
        self.note = note
    }

    init(visit: Visit) {
        self.init(
            visitedAt: visit.visitedAt,
            diningMode: visit.diningMode,
            partySize: visit.partySize,
            rating: visit.rating,
            valueRating: visit.valueRating,
            environmentRating: visit.environmentRating,
            serviceRating: visit.serviceRating,
            myActualSpend: visit.myActualSpend,
            totalPrice: visit.totalPrice,
            visibility: visit.visibility,
            paymentMode: visit.paymentMode,
            queueDuration: visit.queueDuration,
            diningOccasions: visit.diningOccasions,
            diningOccasionText: visit.diningOccasionText ?? "",
            valueTags: visit.valueTags,
            environmentTags: visit.environmentTags,
            serviceTags: visit.serviceTags,
            noiseLevel: visit.noiseLevel,
            diningDuration: visit.diningDuration,
            portionLevel: visit.portionLevel,
            transportConvenience: visit.transportConvenience,
            specialNotes: visit.specialNotes ?? "",
            companionIDs: visit.companionIDs,
            companionNames: visit.companionNames,
            recommendationSourceID: visit.recommendationSourceID,
            recommendationSourceType: visit.recommendationSourceType,
            recommendationSourceUserID: visit.recommendationSourceUserID,
            recommendationSourceText: visit.recommendationSourceText ?? "",
            sharedMealID: visit.sharedMealID,
            note: visit.note ?? ""
        )
        paymentModeRawValue = visit.paymentModeRawValue
        queueDurationRawValue = visit.queueDurationRawValue
        diningOccasionRawValues = visit.diningOccasionRawValues
        noiseLevelRawValue = visit.noiseLevelRawValue
        diningDurationRawValue = visit.diningDurationRawValue
        portionLevelRawValue = visit.portionLevelRawValue
        transportConvenienceRawValue = visit.transportConvenienceRawValue
        recommendationSourceTypeRawValue = visit.recommendationSourceTypeRawValue
    }

    func validated() throws -> VisitDraft {
        guard visitedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw VisitDraftValidationError.invalidDate
        }
        if let rating, Visit.validatedRating(rating) != rating {
            throw VisitDraftValidationError.invalidRating
        }
        for dimension in RatingDimension.allCases {
            let value = dimension.value(in: self)
            if let value, Visit.validatedRating(value) != value {
                throw VisitDraftValidationError.invalidDetailedRating(dimension)
            }
        }
        if let partySize, partySize < 1 {
            throw VisitDraftValidationError.invalidPartySize
        }
        if let myActualSpend, myActualSpend < .zero {
            throw VisitDraftValidationError.negativeSpend
        }
        if let totalPrice, totalPrice < .zero {
            throw VisitDraftValidationError.negativeTotalPrice
        }
        var result = self
        result.diningOccasionRawValues = VisitStringArrayStorage.normalized(diningOccasionRawValues)
        result.valueTags = VisitStringArrayStorage.normalized(valueTags)
        result.environmentTags = VisitStringArrayStorage.normalized(environmentTags)
        result.serviceTags = VisitStringArrayStorage.normalized(serviceTags)
        let normalizedNames = companionNames.map(PrivateDirectoryName.normalized).filter { !$0.isEmpty }
        var seenCompanionNames = Set<String>()
        result.companionNames = normalizedNames.filter { seenCompanionNames.insert($0).inserted }
        result.companionIDs = VisitStringArrayStorage.normalized(companionIDs)
        if !result.companionIDs.isEmpty, result.companionIDs.count != result.companionNames.count {
            throw VisitDraftValidationError.invalidCompanions
        }
        if !result.companionNames.isEmpty {
            result.partySize = max(result.partySize ?? 1, result.companionNames.count + 1)
        }
        result.recommendationSourceText = PrivateDirectoryName.normalized(recommendationSourceText)
        if result.recommendationSourceID == nil {
            result.recommendationSourceTypeRawValue = result.recommendationSourceText.isEmpty
                ? nil
                : (result.recommendationSourceTypeRawValue ?? RecommendationSourceType.other.rawValue)
        }
        if !result.diningOccasions.contains(.other) {
            result.diningOccasionText = ""
        }
        return result
    }

    static func partySize(from text: String) throws -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed), value >= 1 else {
            throw VisitDraftValidationError.invalidPartySize
        }
        return value
    }

    static func spend(from text: String, locale: Locale = .current) throws -> Decimal? {
        try decimal(from: text, locale: locale, invalidError: .invalidSpend, negativeError: .negativeSpend)
    }

    static func totalPrice(from text: String, locale: Locale = .current) throws -> Decimal? {
        try decimal(from: text, locale: locale, invalidError: .invalidTotalPrice, negativeError: .negativeTotalPrice)
    }

    var calculatedPricePerPerson: Decimal? {
        guard let totalPrice, let partySize, partySize >= 1 else { return nil }
        var source = totalPrice / Decimal(partySize)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        return rounded
    }

    private static func decimal(
        from text: String,
        locale: Locale,
        invalidError: VisitDraftValidationError,
        negativeError: VisitDraftValidationError
    ) throws -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        let value = formatter.number(from: trimmed)?.decimalValue
            ?? Decimal(string: trimmed.replacingOccurrences(of: ",", with: "."))
        guard let value else { throw invalidError }
        guard value >= .zero else { throw negativeError }
        return value
    }
}

enum VisitDraftValidationError: LocalizedError, Equatable {
    case invalidDate
    case invalidRating
    case invalidDetailedRating(RatingDimension)
    case invalidPartySize
    case invalidSpend
    case negativeSpend
    case invalidTotalPrice
    case negativeTotalPrice
    case invalidCompanions

    var errorDescription: String? {
        switch self {
        case .invalidDate: "到访日期无效，请重新选择。"
        case .invalidRating: "评分必须是 0.5 到 5.0 之间的半星。"
        case .invalidDetailedRating(let dimension): "\(dimension.title)评分必须是 0.5 到 5.0 之间的半星。"
        case .invalidPartySize: "用餐人数必须是大于 0 的整数，或留空。"
        case .invalidSpend: "请输入正确的消费金额，或留空。"
        case .negativeSpend: "消费金额不能为负数。"
        case .invalidTotalPrice: "请输入正确的整桌账单金额，或留空。"
        case .negativeTotalPrice: "整桌账单不能为负数。"
        case .invalidCompanions: "饭搭子资料没有完整对应，请重新选择。"
        }
    }
}
