// Run without DEBUG to exercise the actual shipping configuration branch:
// xcrun swiftc ios/TasteMap/TasteMap/Configuration/AppEnvironment.swift scripts/test-ios-production-api-configuration.swift -o /tmp/tastemap-api-config-test
import Foundation

@main struct ProductionAPIConfigurationRegression {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let signed = try Data(contentsOf: URL(fileURLWithPath: "ios/TasteMap/TasteMap/Configuration/ProductionEnvironment.json"))
        let cases: [(Data, String?)] = [
            (signed, "https://api.tastemap.cn"),
            (Data(#"{"apiBaseURL":"https://api.tastemap.cn","referralAvailable":false,"future":{"enabled":true}}"#.utf8), "https://api.tastemap.cn"),
            (Data(#"{"referralAvailable":false}"#.utf8), nil),
            (Data(#"{"apiBaseURL":false}"#.utf8), nil),
            (Data(#"{"apiBaseURL":"not a URL"}"#.utf8), nil),
        ]
        for (index, item) in cases.enumerated() {
            let path = root.appendingPathComponent("Case\(index).bundle")
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            try item.0.write(to: path.appendingPathComponent("ProductionEnvironment.json"))
            let config = APIConfiguration.current(bundle: Bundle(path: path.path)!)
            precondition(config.environment == .production)
            precondition(config.baseURL?.absoluteString == item.1, "Production endpoint case \(index) failed")
            if item.1 != nil {
                let endpoint = try config.url(for: "/api/v1/discovery/for-you")
                precondition(endpoint.host == "api.tastemap.cn")
            }
        }
        print("PASS: 5 production API configuration cases, real signed resource and fail-closed invalid configurations")
    }
}
