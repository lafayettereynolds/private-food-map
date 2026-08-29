import Foundation

nonisolated enum SettingsFeature: String, CaseIterable, Sendable {
    case exportBackup
    case importData
    case restoreBackup
    case migrateLegacyWebData
    case deleteAccount
    case privacyPolicy
    case termsOfService
    case support
    case clearCache
    case manageSubscription
}

nonisolated enum SettingsFeatureState: String, Equatable, Sendable {
    case implemented
    case notConfigured
    case developmentOnly
}

nonisolated struct SettingsFeatureAvailability: Equatable, Sendable {
    private let states: [SettingsFeature: SettingsFeatureState]

    init(
        releaseConfiguration: ReleaseConfiguration,
        purchaseCapabilities: MembershipPurchaseCapabilities = [],
        exposesFutureArchitecture: Bool = false
    ) {
        let futureState: SettingsFeatureState = exposesFutureArchitecture
            ? .developmentOnly
            : .notConfigured
        states = [
            .exportBackup: .implemented,
            // F1-C2 is a real read-only capability, but it remains gated to
            // Development until the write/merge stages exist.
            .importData: .developmentOnly,
            .restoreBackup: futureState,
            .migrateLegacyWebData: futureState,
            .deleteAccount: futureState,
            .privacyPolicy: releaseConfiguration.legalLinks.privacyPolicyURL == nil
                ? .notConfigured : .implemented,
            .termsOfService: releaseConfiguration.legalLinks.termsOfServiceURL == nil
                ? .notConfigured : .implemented,
            .support: releaseConfiguration.legalLinks.supportURL == nil
                ? .notConfigured : .implemented,
            .clearCache: futureState,
            .manageSubscription: purchaseCapabilities.contains(.manageSubscription)
                ? .implemented : .notConfigured,
        ]
    }

    func state(for feature: SettingsFeature) -> SettingsFeatureState {
        states[feature] ?? .notConfigured
    }

    func isVisible(_ feature: SettingsFeature, includeDevelopmentOnly: Bool = false) -> Bool {
        switch state(for: feature) {
        case .implemented: true
        case .developmentOnly: includeDevelopmentOnly
        case .notConfigured: false
        }
    }
}

nonisolated struct LegalLinks: Equatable, Sendable {
    let privacyPolicyURL: URL?
    let termsOfServiceURL: URL?
    let supportURL: URL?

    static let empty = LegalLinks(
        privacyPolicyURL: nil,
        termsOfServiceURL: nil,
        supportURL: nil
    )
}

nonisolated enum ReleaseConfigurationValidationIssue: Equatable, Sendable {
    case invalidURL(key: String)
    case missingPrivacyPolicy
    case missingTermsOfService
}

nonisolated struct ReleaseConfiguration: Equatable, Sendable {
    static let developmentPrivacyKey = "TASTEMAP_PRIVACY_POLICY_DEV_URL"
    static let developmentTermsKey = "TASTEMAP_TERMS_OF_SERVICE_DEV_URL"
    static let developmentSupportKey = "TASTEMAP_SUPPORT_DEV_URL"
    static let productionPrivacyKey = "TASTEMAP_PRIVACY_POLICY_PROD_URL"
    static let productionTermsKey = "TASTEMAP_TERMS_OF_SERVICE_PROD_URL"
    static let productionSupportKey = "TASTEMAP_SUPPORT_PROD_URL"

    let environment: TasteMapAppEnvironment
    let legalLinks: LegalLinks
    private let configuredIssues: [ReleaseConfigurationValidationIssue]

    init(
        environment: TasteMapAppEnvironment,
        legalLinks: LegalLinks,
        configuredIssues: [ReleaseConfigurationValidationIssue] = []
    ) {
        self.environment = environment
        self.legalLinks = legalLinks
        self.configuredIssues = configuredIssues
    }

    static func current(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> ReleaseConfiguration {
        let keys = [
            developmentPrivacyKey, developmentTermsKey, developmentSupportKey,
            productionPrivacyKey, productionTermsKey, productionSupportKey,
        ]
        var values = bundledValues(bundle: bundle, keys: keys)
        for key in keys {
            if let value = bundle.object(forInfoDictionaryKey: key) as? String {
                values[key] = value
            }
        }
        for (key, value) in processInfo.environment where keys.contains(key) {
            values[key] = value
        }
        return resolve(environment: .current, values: values)
    }

    static func resolve(
        environment: TasteMapAppEnvironment,
        values: [String: String]
    ) -> ReleaseConfiguration {
        let keys: (privacy: String, terms: String, support: String) = environment == .development
            ? (developmentPrivacyKey, developmentTermsKey, developmentSupportKey)
            : (productionPrivacyKey, productionTermsKey, productionSupportKey)
        var issues: [ReleaseConfigurationValidationIssue] = []
        let privacy = validatedURL(values[keys.privacy], key: keys.privacy, issues: &issues)
        let terms = validatedURL(values[keys.terms], key: keys.terms, issues: &issues)
        let support = validatedURL(values[keys.support], key: keys.support, issues: &issues)
        return ReleaseConfiguration(
            environment: environment,
            legalLinks: LegalLinks(
                privacyPolicyURL: privacy,
                termsOfServiceURL: terms,
                supportURL: support
            ),
            configuredIssues: issues
        )
    }

    var releaseValidationIssues: [ReleaseConfigurationValidationIssue] {
        var issues = configuredIssues
        guard environment == .production else { return issues }
        if legalLinks.privacyPolicyURL == nil { issues.append(.missingPrivacyPolicy) }
        if legalLinks.termsOfServiceURL == nil { issues.append(.missingTermsOfService) }
        return issues
    }

    private static func bundledValues(bundle: Bundle, keys: [String]) -> [String: String] {
        guard let url = bundle.url(forResource: "LegalEnvironment", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return keys.reduce(into: [String: String]()) { result, key in
            if let value = dictionary[key] as? String { result[key] = value }
        }
    }

    private static func validatedURL(
        _ rawValue: String?,
        key: String,
        issues: inout [ReleaseConfigurationValidationIssue]
    ) -> URL? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              let url = components.url else {
            issues.append(.invalidURL(key: key))
            return nil
        }
        return url
    }
}

nonisolated struct AppVersionInfo: Equatable, Sendable {
    let displayName: String
    let version: String
    let build: String

    init(bundle: Bundle = .main) {
        self.init(infoDictionary: bundle.infoDictionary ?? [:])
    }

    init(infoDictionary: [String: Any]) {
        displayName = (infoDictionary["CFBundleDisplayName"] as? String)
            ?? (infoDictionary["CFBundleName"] as? String)
            ?? "Taste Map"
        version = (infoDictionary["CFBundleShortVersionString"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        build = (infoDictionary["CFBundleVersion"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "—"
    }
}
