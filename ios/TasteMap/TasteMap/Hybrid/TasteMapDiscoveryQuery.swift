import Foundation

/// Query-only values. Never persisted as the owner's long-term taste profile.
public struct TasteMapDiscoveryReference: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let source: String
}

public struct TasteMapDiscoveryFilterCapabilities: Codable, Equatable, Sendable {
    public struct Price: Codable, Equatable, Sendable {
        public let bases: [String]
        public let currencies: [String]
    }
    public var cuisines: Bool? = nil
    public var types: Bool? = nil
    public var publicScore: Bool? = nil
    public var publicRatingUsers: Bool? = nil
    public var viewerStates: Bool? = nil
    public var actualPhoto: Bool? = nil
    public var distanceReferenceSources: [String]? = nil
    public var price: Price? = nil
}
public struct TasteMapDiscoveryFilterTaxonomy: Codable, Equatable, Sendable {
    public let cuisines: [String]
    public let types: [String]
}

public struct TasteMapDiscoveryFilters: Codable, Equatable, Sendable {
    public struct Price: Codable, Equatable, Sendable {
        public let minimum: Double
        public let maximumExclusive: Double?
        public let basis: String
        public let currency: String?
    }
    public struct Distance: Codable, Equatable, Sendable {
        public let maximumMeters: Double
        public let reference: TasteMapDiscoveryReference
    }
    public var cuisines: [String] = []
    public var types: [String] = []
    public var priceRange: Price? = nil
    public var minimumPublicScoreOutOfTen: Double? = nil
    public var minimumPredictedLikingOutOfTen: Double? = nil
    public var minimumTasteMatchPercent: Double? = nil
    public var minimumPublicRatingUsers: Int? = nil
    public var viewerStates: [String] = []
    public var viewerStatesWereSpecified = false
    public var requireActualPhoto: Bool = false
    public var distance: Distance? = nil

    public init() {}
    private enum CodingKeys: String, CodingKey {
        case cuisines, types, priceRange, minimumPublicScoreOutOfTen, minimumPublicRatingUsers, viewerStates, requireActualPhoto, distance, minimumPredictedLikingOutOfTen, minimumTasteMatchPercent
    }
    public func encode(to encoder: Encoder) throws {
        var data = encoder.container(keyedBy: CodingKeys.self)
        try data.encode(cuisines, forKey: .cuisines)
        try data.encode(types, forKey: .types)
        try data.encode(priceRange, forKey: .priceRange)
        try data.encode(minimumPublicScoreOutOfTen, forKey: .minimumPublicScoreOutOfTen)
        try data.encodeIfPresent(minimumPredictedLikingOutOfTen, forKey: .minimumPredictedLikingOutOfTen)
        try data.encodeIfPresent(minimumTasteMatchPercent, forKey: .minimumTasteMatchPercent)
        try data.encode(minimumPublicRatingUsers, forKey: .minimumPublicRatingUsers)
        if viewerStatesWereSpecified || !viewerStates.isEmpty { try data.encode(viewerStates, forKey: .viewerStates) }
        try data.encode(requireActualPhoto, forKey: .requireActualPhoto)
        try data.encode(distance, forKey: .distance)
    }
    public init(from decoder: Decoder) throws {
        let raw = try TasteMapHybridJSONValue(from: decoder)
        let fields = try DiscoveryQueryValidation.object(raw, keys: ["cuisines", "types", "priceRange", "minimumPublicScoreOutOfTen", "minimumPublicRatingUsers", "viewerStates", "requireActualPhoto", "distance", "minimumPredictedLikingOutOfTen", "minimumTasteMatchPercent"])
        minimumPredictedLikingOutOfTen = try DiscoveryQueryValidation.optionalNumber(fields["minimumPredictedLikingOutOfTen"], range: 0...10)
        minimumTasteMatchPercent = try DiscoveryQueryValidation.optionalNumber(fields["minimumTasteMatchPercent"], range: 0...100)
        cuisines = try DiscoveryQueryValidation.selection(fields["cuisines"], allowed: Self.cuisineTaxonomy)
        types = try DiscoveryQueryValidation.selection(fields["types"], allowed: Self.typeTaxonomy)
        viewerStates = try DiscoveryQueryValidation.selection(fields["viewerStates"], allowed: ["none", "want_to_go", "visited"])
        viewerStatesWereSpecified = fields["viewerStates"] != nil
        minimumPublicScoreOutOfTen = try DiscoveryQueryValidation.optionalNumber(fields["minimumPublicScoreOutOfTen"], range: 0...10)
        if let count = try DiscoveryQueryValidation.optionalNumber(fields["minimumPublicRatingUsers"], range: 0...9_007_199_254_740_991) {
            guard count.rounded(.down) == count else { throw DiscoveryQueryValidation.invalid() }
            minimumPublicRatingUsers = Int(count)
        }
        if let photo = fields["requireActualPhoto"] {
            guard case let .bool(value) = photo else { throw DiscoveryQueryValidation.invalid() }
            requireActualPhoto = value
        }
        if let value = fields["priceRange"], !DiscoveryQueryValidation.isNull(value) {
            let data = try DiscoveryQueryValidation.object(value, keys: ["minimum", "maximumExclusive", "basis", "currency"])
            let min = try DiscoveryQueryValidation.requiredNumber(data["minimum"], range: 0...Double.greatestFiniteMagnitude)
            let max = try DiscoveryQueryValidation.optionalNumber(data["maximumExclusive"], range: 0...Double.greatestFiniteMagnitude)
            guard max == nil || max! > min else { throw DiscoveryQueryValidation.invalid() }
            let basis = try DiscoveryQueryValidation.string(data["basis"], allowed: ["reference_per_person", "recorded_per_person"])
            let currency = try DiscoveryQueryValidation.currency(data["currency"], required: false)
            priceRange = .init(minimum: min, maximumExclusive: max, basis: basis, currency: currency)
        }
        if let value = fields["distance"], !DiscoveryQueryValidation.isNull(value) {
            let data = try DiscoveryQueryValidation.object(value, keys: ["maximumMeters", "reference"])
            let max = try DiscoveryQueryValidation.requiredNumber(data["maximumMeters"], range: 0...Double.greatestFiniteMagnitude)
            guard max > 0 else { throw DiscoveryQueryValidation.invalid() }
            distance = .init(maximumMeters: max, reference: try DiscoveryQueryValidation.reference(data["reference"]))
        }
    }
    public static let cuisineTaxonomy = ["中餐", "杭帮菜", "江浙菜", "川菜", "粤菜", "湘菜", "日料", "韩餐", "泰餐", "越南菜", "西餐", "意大利菜", "法国菜", "墨西哥菜", "印度菜", "中东菜"]
    public static let typeTaxonomy = ["正餐", "火锅", "烧烤", "咖啡", "甜品", "小吃", "面馆", "快餐", "酒吧", "海鲜", "早午餐"]
}

public struct TasteMapDiscoverySessionPreferences: Codable, Equatable, Sendable {
    public struct Budget: Codable, Equatable, Sendable {
        public let minimum: Double
        public let maximumExclusive: Double?
        public let currency: String
        private enum CodingKeys: String, CodingKey { case minimum, maximumExclusive, currency }
        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(minimum, forKey: .minimum)
            try values.encode(maximumExclusive, forKey: .maximumExclusive)
            try values.encode(currency, forKey: .currency)
        }
    }
    public var exploration = "balanced"
    public var budget: Budget? = nil
    public var occasion = "any"
    public var nearby = false
    public var reference: TasteMapDiscoveryReference? = nil
    public init() {}
    public init(from decoder: Decoder) throws {
        let data = try DiscoveryQueryValidation.object(TasteMapHybridJSONValue(from: decoder), keys: ["exploration", "budget", "occasion", "nearby", "reference"])
        exploration = try DiscoveryQueryValidation.string(data["exploration"] ?? .string("balanced"), allowed: ["familiar", "balanced", "adventurous"])
        occasion = try DiscoveryQueryValidation.string(data["occasion"] ?? .string("any"), allowed: ["any", "solo", "two", "group"])
        if let value = data["nearby"], !DiscoveryQueryValidation.isNull(value) {
            guard case let .bool(flag) = value else { throw DiscoveryQueryValidation.invalid() }; nearby = flag
        }
        if let value = data["reference"], !DiscoveryQueryValidation.isNull(value) { reference = try DiscoveryQueryValidation.reference(value) }
        guard !nearby || reference != nil else { throw DiscoveryQueryValidation.invalid() }
        if let value = data["budget"], !DiscoveryQueryValidation.isNull(value) {
            let fields = try DiscoveryQueryValidation.object(value, keys: ["minimum", "maximumExclusive", "currency"])
            let min = try DiscoveryQueryValidation.requiredNumber(fields["minimum"], range: 0...Double.greatestFiniteMagnitude)
            let max = try DiscoveryQueryValidation.optionalNumber(fields["maximumExclusive"], range: 0...Double.greatestFiniteMagnitude)
            guard max == nil || max! > min else { throw DiscoveryQueryValidation.invalid() }
            budget = .init(minimum: min, maximumExclusive: max, currency: try DiscoveryQueryValidation.currency(fields["currency"], required: true)!)
        }
    }
}

public struct TasteMapDiscoveryAppliedQuery: Codable, Equatable, Sendable {
    public let filters: TasteMapDiscoveryFilters
    public let sort: String
    public let preferences: TasteMapDiscoverySessionPreferences

    static func normalized(mode: String, filters: TasteMapDiscoveryFilters?, sort: String?, preferences: TasteMapDiscoverySessionPreferences?) throws -> Self {
        let allowed: [String]
        switch mode {
        case "for_you": allowed = ["recommended", "taste", "predicted_liking", "public_rating", "distance"]
        case "similar_taste": allowed = ["recommended", "similar_rating", "distance"]
        case "trending": allowed = ["trend"]
        case "following", "latest": allowed = ["latest"]
        default: throw DiscoveryQueryValidation.invalid()
        }
        let filters = filters ?? .init(); let preferences = preferences ?? .init()
        guard mode == "for_you" || (filters.minimumPredictedLikingOutOfTen == nil && filters.minimumTasteMatchPercent == nil) else {
            throw DiscoveryQueryValidation.unsupported()
        }
        let sort = sort ?? allowed[0]
        guard allowed.contains(sort), sort != "distance" || filters.distance != nil else { throw DiscoveryQueryValidation.invalid() }
        guard ["for_you", "similar_taste"].contains(mode) || preferences == .init() else {
            throw DiscoveryQueryValidation.unsupported()
        }
        // Lafayette approved all historical currency-less amounts as CNY.
        if let price = filters.priceRange {
            guard price.basis == "reference_per_person", price.currency == "CNY" else { throw DiscoveryQueryValidation.unsupported() }
        }
        return .init(filters: filters, sort: sort, preferences: preferences)
    }
    var fingerprint: String { (try? Self.json(self)) ?? "invalid" }
    func isDefault(mode: String) -> Bool { self == (try? Self.normalized(mode: mode, filters: nil, sort: nil, preferences: nil)) }
    var references: [TasteMapDiscoveryReference] { [filters.distance?.reference, preferences.reference].compactMap { $0 } }
    static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
    func queryItems(mode: String) throws -> [URLQueryItem] {
        guard !isDefault(mode: mode) else { return [] }
        return [.init(name: "filters", value: try Self.json(filters)), .init(name: "sort", value: sort),
                .init(name: "preferences", value: try Self.json(preferences))]
    }
    func verify(_ applied: Self?, mode: String) throws {
        if isDefault(mode: mode) { return }
        guard let applied, applied.sort == sort, applied.preferences == preferences else { throw DiscoveryQueryValidation.unsupported() }
        // The acknowledgement normalizes all optional fields. Presence is a
        // request/fingerprint distinction, not an additional server filter.
        var expected = filters; var actual = applied.filters
        expected.viewerStatesWereSpecified = true; actual.viewerStatesWereSpecified = true
        guard expected == actual else { throw DiscoveryQueryValidation.unsupported() }
    }
}

enum DiscoveryQueryValidation {
    static func isNull(_ value: TasteMapHybridJSONValue) -> Bool { if case .null = value { return true }; return false }
    static func invalid() -> TasteMapHybridBridgeErrorDTO { .init(code: "invalid_discovery_filter", message: "发现筛选条件无效，请重新选择。", recoverable: true, details: nil) }
    static func unsupported() -> TasteMapHybridBridgeErrorDTO { .init(code: "unsupported_discovery_filter", message: "当前服务尚未支持这组筛选条件，请调整后重试。", recoverable: true, details: nil) }
    static func object(_ value: TasteMapHybridJSONValue, keys: [String]) throws -> [String: TasteMapHybridJSONValue] {
        guard case let .object(data) = value, data.keys.allSatisfy(keys.contains) else { throw invalid() }; return data
    }
    static func string(_ value: TasteMapHybridJSONValue?, allowed: [String]) throws -> String {
        guard case let .string(text) = value, allowed.contains(text) else { throw invalid() }; return text
    }
    static func selection(_ value: TasteMapHybridJSONValue?, allowed: [String]) throws -> [String] {
        guard let value, !isNull(value) else { return [] }
        guard case let .array(items) = value else { throw invalid() }
        return try Array(Set(items.map { try string($0, allowed: allowed) })).sorted()
    }
    static func optionalNumber(_ value: TasteMapHybridJSONValue?, range: ClosedRange<Double>) throws -> Double? {
        guard let value, !isNull(value) else { return nil }; return try requiredNumber(value, range: range)
    }
    static func requiredNumber(_ value: TasteMapHybridJSONValue?, range: ClosedRange<Double>) throws -> Double {
        guard case let .number(number) = value, number.isFinite, range.contains(number) else { throw invalid() }; return number == 0 ? 0 : number
    }
    static func currency(_ value: TasteMapHybridJSONValue?, required: Bool) throws -> String? {
        guard let value, !isNull(value) else { if required { throw invalid() }; return nil }
        guard case let .string(text) = value, text.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else { throw invalid() }; return text
    }
    static func reference(_ value: TasteMapHybridJSONValue?) throws -> TasteMapDiscoveryReference {
        guard let value else { throw invalid() }
        let data = try object(value, keys: ["latitude", "longitude", "source"])
        return .init(latitude: try requiredNumber(data["latitude"], range: -90...90),
                     longitude: try requiredNumber(data["longitude"], range: -180...180),
                     source: try string(data["source"], allowed: ["device_location", "user_selected_point"]))
    }
}

/// Proofs originate only from Native's authorized location.getCurrent result.
/// A continuation keeps its original point; a new query needs a fresh fix.
struct TasteMapDiscoveryLocationProofs {
    private var values: [String: (owner: String, timestamp: Date)] = [:]
    mutating func reset() { values.removeAll() }
    mutating func register(_ reference: TasteMapDiscoveryReference, owner: String, timestamp: Date, now: Date = .now) throws {
        values = values.filter { now.timeIntervalSince($0.value.timestamp) <= 600 }
        values[try TasteMapDiscoveryAppliedQuery.json(reference)] = (owner, timestamp)
    }
    func validate(_ query: TasteMapDiscoveryAppliedQuery, owner: String, permissionAllowed: Bool, continuation: Bool, now: Date = .now) throws {
        for reference in query.references where reference.source == "device_location" {
            let proof = values[try TasteMapDiscoveryAppliedQuery.json(reference)]
            guard permissionAllowed, let proof, proof.owner == owner,
                  (-5...(continuation ? 600 : 300)).contains(now.timeIntervalSince(proof.timestamp)) else {
                throw TasteMapHybridBridgeErrorDTO(code: "location_reference_required", message: "请重新获取当前位置后再使用距离筛选。", recoverable: true, details: nil)
            }
        }
    }
}
