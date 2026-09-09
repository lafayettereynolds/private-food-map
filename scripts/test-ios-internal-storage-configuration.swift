import Foundation

@main struct InternalStorageConfigurationRegression {
    static func main() {
        let api = APIConfiguration.current()
        let storage = TasteMapAppEnvironment.current
#if DEBUG || TASTEMAP_SANDBOX_BUILD
        let expectedStorage = TasteMapAppEnvironment.development
#else
        let expectedStorage = TasteMapAppEnvironment.production
#endif
        guard storage == expectedStorage,
              api.environment == .development,
              api.baseURL?.absoluteString == "https://api-dev.tastemap.cn" else {
            print("FAIL: storage=\(storage.rawValue), API=\(api.environment.rawValue); retained namespace or Development endpoint mismatch")
            exit(1)
        }
        print("PASS: storage=\(storage.rawValue), API=development; no credentials read or network requests")
    }
}
