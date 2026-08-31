import Foundation

struct ParsedExternalRestaurantLink: Equatable, Sendable {
    let source: ExternalRestaurantLinkSource
    let name: String
    let address: String
    let city: String
    let coordinate: RestaurantCoordinate?
    let identity: RestaurantCandidatePlaceIdentity?

    var candidate: RestaurantCandidate? {
        guard !name.isEmpty, let coordinate, let identity else { return nil }
        let identities = [identity]
        return RestaurantCandidate(
            name: name,
            address: address,
            city: city,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            appleMapItemIdentifier: identity.provider == .appleMaps ? identity.externalID : nil,
            placeIdentities: identities
        )
    }
}

enum ExternalRestaurantLinkParserError: Error, Equatable {
    case invalidInput
    case insecureURL
}

enum ExternalRestaurantLinkParser {
    private static let urlPattern = try! NSRegularExpression(pattern: #"https://[^\s<>\"'）)]+"#)

    static func parse(_ input: String, currentCity: String = "") throws -> ParsedExternalRestaurantLink? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw ExternalRestaurantLinkParserError.invalidInput }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = urlPattern.firstMatch(in: input, range: range),
              let urlRange = Range(match.range, in: input),
              let components = URLComponents(string: String(input[urlRange])),
              let scheme = components.scheme?.lowercased(),
              scheme == "https",
              let host = components.host?.lowercased() else {
            if input.localizedCaseInsensitiveContains("http://") {
                throw ExternalRestaurantLinkParserError.insecureURL
            }
            return sharedTextEvidence(input, currentCity: currentCity)
        }

        let source: ExternalRestaurantLinkSource
        if host == "maps.apple.com" || host.hasSuffix(".maps.apple.com") {
            source = .appleMaps
        } else if host == "amap.com" || host.hasSuffix(".amap.com")
                    || host == "gaode.com" || host.hasSuffix(".gaode.com") {
            source = .amap
        } else {
            source = .genericURL
        }

        let query = components.queryItems ?? []
        let name = value(in: query, keys: ["name", "q", "query", "title", "placeName"])
        let address = value(in: query, keys: ["address", "addr", "daddr"])
        let city = value(in: query, keys: ["city", "cityname"]).nilIfEmpty ?? currentCity
        let coordinate = parseCoordinate(value(in: query, keys: ["ll", "location", "position", "center"]))
        let explicitID = value(in: query, keys: ["id", "poiid", "poiId", "place-id"])
        let pathID = source == .amap
            ? firstMatch(#"\b(B0[A-Z0-9]{6,})\b"#, in: components.path)
            : nil
        let externalID = explicitID.nilIfEmpty ?? pathID
        let provider: RestaurantPlaceProvider? = source == .appleMaps
            ? .appleMaps
            : source == .amap ? .amap : externalID == nil ? nil : .other
        let identity = provider.flatMap { provider in
            externalID.map {
                RestaurantCandidatePlaceIdentity(provider: provider, externalID: $0, isPrimary: true)
            }
        }
        return ParsedExternalRestaurantLink(
            source: source,
            name: name,
            address: address,
            city: city,
            coordinate: coordinate,
            identity: identity
        )
    }

    private static func value(in items: [URLQueryItem], keys: [String]) -> String {
        for key in keys {
            if let value = items.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private static func parseCoordinate(_ value: String) -> RestaurantCoordinate? {
        let values = value
            .replacingOccurrences(of: "，", with: ",")
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard values.count == 2 else { return nil }
        let first = values[0]
        let second = values[1]
        let coordinate = abs(first) <= 90 && abs(second) <= 180
            ? RestaurantCoordinate(latitude: first, longitude: second)
            : RestaurantCoordinate(latitude: second, longitude: first)
        return coordinate.isValid ? coordinate : nil
    }

    private static func firstMatch(_ pattern: String, in value: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.firstMatch(in: value, range: range), match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[valueRange])
    }

    private static func sharedTextEvidence(
        _ input: String,
        currentCity: String
    ) -> ParsedExternalRestaurantLink {
        let coordinate = firstCoordinate(in: input)
        let lines = input
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && parseCoordinate($0) == nil }
        let first = lines.first ?? ""
        let looksLikeAddress = first.range(
            of: #"(路|街|巷|道|号|road|street|avenue|lane|district)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let name = looksLikeAddress ? "" : first
        let address = looksLikeAddress ? first : (lines.dropFirst().first ?? "")
        return ParsedExternalRestaurantLink(
            source: .sharedText,
            name: name,
            address: address,
            city: currentCity,
            coordinate: coordinate,
            identity: nil
        )
    }

    private static func firstCoordinate(in input: String) -> RestaurantCoordinate? {
        guard let expression = try? NSRegularExpression(
            pattern: #"(-?\d{1,3}(?:\.\d+)?)\s*[,，]\s*(-?\d{1,3}(?:\.\d+)?)"#
        ) else { return nil }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = expression.firstMatch(in: input, range: range),
              let matchRange = Range(match.range, in: input) else { return nil }
        return parseCoordinate(String(input[matchRange]))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
