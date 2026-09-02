import UIKit
import Capacitor
import TasteMapHybridBridge

@objc(TasteMapNativePlugin)
final class TasteMapNativePlugin: CAPPlugin, CAPBridgedPlugin {
    let identifier = "TasteMapNativePlugin"
    let jsName = "TasteMapNative"
    let pluginMethods: [CAPPluginMethod] = [CAPPluginMethod(name: "invoke", returnType: CAPPluginReturnPromise)]
    private var dispatcher: TasteMapHybridBridgeDispatcher?

    @objc func invoke(_ call: CAPPluginCall) {
        guard let request = call.getObject("request") else {
            call.reject("A typed bridge request is required.", "invalid_bridge_envelope")
            return
        }
        Task { @MainActor in
            let started = ContinuousClock.now
            let method = request["method"] as? String ?? "invalid"
            let requestID = request["requestId"] as? String ?? "invalid"
            do {
                let requestData = try JSONSerialization.data(withJSONObject: request)
                let responseData = try await loadedDispatcher().responseDataAsync(for: requestData)
                guard let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                      let object = jsObject(response) else {
                    throw BridgeHostError.responseEncodingFailed
                }
#if DEBUG
                let duration = started.duration(to: .now)
                NSLog("TasteMapNative.v1 method=%@ request=%@ duration=%@", method, requestID, String(describing: duration))
#endif
                call.resolve(object)
            } catch {
#if DEBUG
                NSLog("TasteMapNative.v1 method=%@ request=%@ error=bridge_host_failure", method, requestID)
#endif
                call.reject("Taste Map could not process this bridge request.", "bridge_host_failure")
            }
        }
    }

    @MainActor
    private func loadedDispatcher() throws -> TasteMapHybridBridgeDispatcher {
        if let dispatcher { return dispatcher }
        let bundle = Bundle.main
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
#if DEBUG
        let fixtureURL = bundle.bundleURL
            .appendingPathComponent("public", isDirectory: true)
            .appendingPathComponent("_hybrid_debug", isDirectory: true)
            .appendingPathComponent("profile-restaurant-rich.json")
        let service = try TasteMapHybridDebugFixture.makeService(fixtureData: Data(contentsOf: fixtureURL))
        let dispatcher = TasteMapHybridBridgeDispatcher(
            service: service,
            appVersion: appVersion,
            build: build,
            dataSource: "native-swiftdata-debug-fixture",
            authState: {
                TasteMapHybridAuthStateDTO(
                    state: "authenticated",
                    userID: TasteMapHybridDebugFixture.ownerUserID,
                    displayName: "Lafayette Hybrid"
                )
            },
            nativeAction: { method in
                guard method == .hapticsSelection else { return }
                let generator = UISelectionFeedbackGenerator()
                generator.prepare()
                generator.selectionChanged()
            }
        )
#else
        let dispatcher = TasteMapHybridBridgeDispatcher(
            service: nil,
            appVersion: appVersion,
            build: build,
            dataSource: "native-swiftdata",
            authState: { TasteMapHybridAuthStateDTO(state: "signedOut", userID: nil, displayName: nil) }
        )
#endif
        self.dispatcher = dispatcher
        return dispatcher
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
        if value is NSNull { return NSNull() }
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

private enum BridgeHostError: Error { case responseEncodingFailed }

final class TasteMapBridgeViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(TasteMapNativePlugin())
    }
    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool { true }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
