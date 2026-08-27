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
    var note: String

    init(
        visitedAt: Date = .now,
        diningMode: DiningMode = .dineIn,
        partySize: Int? = nil,
        rating: Double? = nil,
        valueRating: Double? = nil,
        environmentRating: Double? = nil,
        serviceRating: Double? = nil,
        myActualSpend: Decimal? = nil,
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
            note: visit.note ?? ""
        )
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
        return self
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        let value = formatter.number(from: trimmed)?.decimalValue
            ?? Decimal(string: trimmed.replacingOccurrences(of: ",", with: "."))
        guard let value else { throw VisitDraftValidationError.invalidSpend }
        guard value >= .zero else { throw VisitDraftValidationError.negativeSpend }
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

    var errorDescription: String? {
        switch self {
        case .invalidDate: "到访日期无效，请重新选择。"
        case .invalidRating: "评分必须是 0.5 到 5.0 之间的半星。"
        case .invalidDetailedRating(let dimension): "\(dimension.title)评分必须是 0.5 到 5.0 之间的半星。"
        case .invalidPartySize: "用餐人数必须是大于 0 的整数，或留空。"
        case .invalidSpend: "请输入正确的消费金额，或留空。"
        case .negativeSpend: "消费金额不能为负数。"
        }
    }
}
