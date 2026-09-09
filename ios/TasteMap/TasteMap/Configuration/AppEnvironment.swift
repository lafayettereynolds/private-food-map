import Foundation

nonisolated enum TasteMapAppEnvironment: String, Codable, Sendable {
    case development
    case production

    static var current: Self {
// Internal upgrades retain the accepted Private Preview local store/cache/outbox.
// Their Development API and auth namespace are selected independently below.
#if DEBUG || TASTEMAP_SANDBOX_BUILD
        .development
#else
        .production
#endif
    }
}

nonisolated enum APIConfigurationError: Error, Equatable {
    case invalidBaseURL
    case missingBaseURL(TasteMapAppEnvironment)
    case invalidPath
}

nonisolated struct APIConfiguration: Equatable, Sendable {
    // Decode only the fields owned by the API client. Other signed product
    // configuration fields may be booleans or objects (for example Referral).
    private struct ProductionEndpoint: Decodable {
        let apiBaseURL: String
    }

    static let developmentKey = "TASTEMAP_API_DEV_BASE_URL"
    static let productionKey = "TASTEMAP_API_PROD_BASE_URL"
    static let fallbackKey = "TASTEMAP_API_BASE_URL"

    let environment: TasteMapAppEnvironment
    let baseURL: URL?

    static func current(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> APIConfiguration {
#if TASTEMAP_PRIVATE_PREVIEW
        // Private device QA resumes the existing Development account while
        // retaining its current local store. Formal Release remains pinned below.
        return (try? resolve(environment: .development, values: [developmentKey: "https://api-dev.tastemap.cn"]))
            ?? APIConfiguration(environment: .development, baseURL: nil)
#elseif TASTEMAP_INTERNAL_BUILD
        // Signed Internal TestFlight configuration: normal product UI with the
        // existing Development account/credential namespace. No runtime override.
        return (try? resolve(environment: .development, values: [developmentKey: "https://api-dev.tastemap.cn"]))
            ?? APIConfiguration(environment: .development, baseURL: nil)
#elseif TASTEMAP_SANDBOX_BUILD
        // A separately named Release configuration for TestFlight Sandbox only.
        // Compiled only into the dedicated Sandbox artifact; no runtime override.
        let endpoint = "https://api-dev.tastemap.cn"
        return (try? resolve(environment: .development, values: [developmentKey: endpoint]))
            ?? APIConfiguration(environment: .development, baseURL: nil)
#elseif !DEBUG
        // This signed resource is also imported by Browser and Worker builds.
        // Production must never take its endpoint from process/.env overrides.
        guard let url = bundle.url(forResource: "ProductionEnvironment", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode(ProductionEndpoint.self, from: data) else {
            return APIConfiguration(environment: .production, baseURL: nil)
        }
        return (try? resolve(environment: .production, values: [productionKey: values.apiBaseURL]))
            ?? APIConfiguration(environment: .production, baseURL: nil)
#else
        let keys = [developmentKey, productionKey, fallbackKey]
        var values = bundledValues(bundle: bundle, keys: keys)
#if DEBUG
        // Development has a deliberate, non-secret endpoint default. Keeping
        // it behind DEBUG means Release artifacts cannot silently connect to
        // or even contain the Development Worker URL.
        if values[developmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            values[developmentKey] = "https://api-dev.tastemap.cn"
        }
#endif
        keys.forEach { key in
            if let value = bundle.object(forInfoDictionaryKey: key) as? String {
                values[key] = value
            }
        }
        processInfo.environment.forEach { values[$0.key] = $0.value }
        return (try? resolve(environment: .current, values: values))
            ?? APIConfiguration(environment: .current, baseURL: nil)
#endif
    }

    private static func bundledValues(bundle: Bundle, keys: [String]) -> [String: String] {
        guard let url = bundle.url(forResource: "APIEnvironment", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return keys.reduce(into: [String: String]()) { result, key in
            if let value = dictionary[key] as? String { result[key] = value }
        }
    }

    static func resolve(
        environment: TasteMapAppEnvironment,
        values: [String: String]
    ) throws -> APIConfiguration {
        let environmentKey = environment == .development ? developmentKey : productionKey
        let configured = [values[environmentKey], values[fallbackKey]]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let configured else {
            return APIConfiguration(environment: environment, baseURL: nil)
        }
        guard var components = URLComponents(string: configured),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw APIConfigurationError.invalidBaseURL
        }
        components.path = components.path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard let url = components.url else { throw APIConfigurationError.invalidBaseURL }
        return APIConfiguration(environment: environment, baseURL: url)
    }

    func url(for path: String) throws -> URL {
        guard path.hasPrefix("/") else { throw APIConfigurationError.invalidPath }
        guard let baseURL else { throw APIConfigurationError.missingBaseURL(environment) }
        guard let url = URL(string: String(path.dropFirst()), relativeTo: baseURL.appendingPathComponent("/"))?.absoluteURL else {
            throw APIConfigurationError.invalidPath
        }
        return url
    }
}
