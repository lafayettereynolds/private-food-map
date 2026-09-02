import UIKit
import Capacitor
import TasteMapNativePOC

@objc(TasteMapNativePlugin)
final class TasteMapNativePlugin: CAPPlugin, CAPBridgedPlugin {
    let identifier = "TasteMapNativePlugin"
    let jsName = "TasteMapNative"
    let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "runtimeInfo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "profileGetCurrent", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "restaurantGet", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "hapticsSelection", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "authSessionStatus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "authSignInWithApple", returnType: CAPPluginReturnPromise),
    ]

    private var service: TasteMapHybridPOCService?

    @objc func runtimeInfo(_ call: CAPPluginCall) {
        withService(call) { service in try self.resolveJSON(service.runtimeJSON(), call: call) }
    }

    @objc func profileGetCurrent(_ call: CAPPluginCall) {
        withService(call) { service in try self.resolveJSON(service.profileJSON(), call: call) }
    }

    @objc func restaurantGet(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), !id.isEmpty else {
            call.reject("A Restaurant ID is required.", "restaurant_id_required")
            return
        }
        withService(call) { service in try self.resolveJSON(service.restaurantJSON(id: id), call: call) }
    }

    @objc func hapticsSelection(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
            call.resolve([:])
        }
    }

    @objc func authSessionStatus(_ call: CAPPluginCall) {
        // Shape-only proof. No Apple token, Keychain credential, or backend auth
        // bypass exists in this isolated POC.
        call.resolve([
            "state": "authenticated",
            "provider": "local-poc",
            "userID": "tm_capacitor_poc",
        ])
    }

    @objc func authSignInWithApple(_ call: CAPPluginCall) {
        call.resolve([
            "state": "unavailable",
            "reason": "POC validates the native auth boundary without requesting an Apple credential.",
        ])
    }

    private func withService(
        _ call: CAPPluginCall,
        operation: @escaping @MainActor (TasteMapHybridPOCService) throws -> Void
    ) {
        Task { @MainActor in
            do {
                let service = try self.loadedService()
                try operation(service)
            } catch {
                call.reject(error.localizedDescription, "native_bridge_error", error)
            }
        }
    }

    @MainActor
    private func loadedService() throws -> TasteMapHybridPOCService {
        if let service { return service }
        let service = try TasteMapHybridPOCService()
        let bundleRoot = Bundle.main.bundleURL
        let fixtureURL = bundleRoot
            .appendingPathComponent("public", isDirectory: true)
            .appendingPathComponent("hybrid-poc", isDirectory: true)
            .appendingPathComponent("dataset.json")
        try service.bootstrap(fixtureData: Data(contentsOf: fixtureURL))
        self.service = service
        return service
    }

    @MainActor
    private func resolveJSON(_ value: String, call: CAPPluginCall) throws {
        let data = Data(value.utf8)
        guard let rawObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let object = jsObject(rawObject) else {
            throw TasteMapHybridPOCError.fixtureInvalid
        }
        call.resolve(object)
    }

    private func jsObject(_ value: [String: Any]) -> JSObject? {
        var object: JSObject = [:]
        for (key, rawValue) in value {
            guard let converted = jsValue(rawValue) else { return nil }
            object[key] = converted
        }
        return object
    }

    private func jsValue(_ value: Any) -> (any JSValue)? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value }
        if let value = value as? NSNull { return value }
        if let value = value as? [String: Any] { return jsObject(value) }
        if let value = value as? [Any] {
            var array: JSArray = []
            for item in value {
                guard let converted = jsValue(item) else { return nil }
                array.append(converted)
            }
            return array
        }
        return nil
    }
}

final class TasteMapBridgeViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(TasteMapNativePlugin())
    }
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration",
                                          sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}
