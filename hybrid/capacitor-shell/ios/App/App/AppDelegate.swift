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
        let explicitFixture = ProcessInfo.processInfo.arguments.contains("-hybrid-rich-fixture")
            || ProcessInfo.processInfo.environment["TASTEMAP_HYBRID_FIXTURE"] == "rich"
        if explicitFixture {
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
            self.dispatcher = dispatcher
            return dispatcher
        }
#endif
        let dispatcher = TasteMapHybridBridgeDispatcher(
            service: nil,
            appVersion: appVersion,
            build: build,
            dataSource: "native-swiftdata",
            authState: { TasteMapHybridAuthStateDTO(state: "signedOut", userID: nil, displayName: nil) }
        )
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
#if DEBUG
    private var mapDiagnosticsTimer: Timer?
    private var pendingMapDiagnosticsRoot: [String: Any]?
    private var pendingMapDiagnosticsRecordCount = 0
    private var publishedMapDiagnosticsRecordCount = 0
    private var mapDiagnosticsStableTicks = 0
#endif

    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(TasteMapNativePlugin())
#if DEBUG
        startMapScopeDiagnosticsCapture()
#endif
    }
    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

#if DEBUG
    private func startMapScopeDiagnosticsCapture() {
        mapDiagnosticsTimer?.invalidate()
        mapDiagnosticsTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let webView = self.bridge?.webView else { return }
            webView.evaluateJavaScript("document.getElementById('tm-map-scope-performance')?.textContent || ''") { [weak self] value, _ in
                guard let self, let payload = value as? String, !payload.isEmpty,
                      let data = payload.data(using: .utf8),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let records = root["records"] as? [[String: Any]] else { return }
                if records.count != self.pendingMapDiagnosticsRecordCount {
                    self.pendingMapDiagnosticsRecordCount = records.count
                    self.pendingMapDiagnosticsRoot = root
                    self.mapDiagnosticsStableTicks = 0
                    return
                }
                self.mapDiagnosticsStableTicks += 1
                if self.mapDiagnosticsStableTicks >= 3,
                   records.count > self.publishedMapDiagnosticsRecordCount,
                   let pending = self.pendingMapDiagnosticsRoot,
                   let summaryData = try? JSONSerialization.data(withJSONObject: self.mapDiagnosticsSummary(pending)),
                   let summary = String(data: summaryData, encoding: .utf8) {
                    self.publishedMapDiagnosticsRecordCount = records.count
                    NSLog("TasteMapMapScopeDiagnostics %@", summary)
                }
            }
        }
    }

    private func mapDiagnosticsSummary(_ root: [String: Any]) -> [String: Any] {
        let records = root["records"] as? [[String: Any]] ?? []
        func duration(_ record: [String: Any], end: String, start: String = "tapAt") -> Double? {
            guard let startValue = (record[start] as? NSNumber)?.doubleValue,
                  let endValue = (record[end] as? NSNumber)?.doubleValue else { return nil }
            return endValue - startValue
        }
        func statistics(_ values: [Double]) -> [String: Any] {
            let sorted = values.sorted()
            guard !sorted.isEmpty else { return ["count": 0] }
            func percentile(_ value: Double) -> Double {
                let index = min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * value)) - 1))
                return (sorted[index] * 100).rounded() / 100
            }
            return [
                "count": sorted.count,
                "medianMs": percentile(0.5),
                "p95Ms": percentile(0.95),
                "worstMs": (sorted.last! * 100).rounded() / 100,
            ]
        }
        let perScope = Dictionary(grouping: records, by: { $0["to"] as? String ?? "unknown" })
            .mapValues { values in
                [
                    "itemCount": (values.last?["itemCount"] as? NSNumber)?.intValue ?? 0,
                    "selected": statistics(values.compactMap { duration($0, end: "selectedVisualAt") }),
                    "content": statistics(values.compactMap { duration($0, end: "contentCommittedAt") }),
                ] as [String: Any]
            }
        return [
            "recordCount": records.count,
            "selected": statistics(records.compactMap { duration($0, end: "selectedVisualAt") }),
            "dataReady": statistics(records.compactMap { duration($0, end: "dataReadyAt") }),
            "content": statistics(records.compactMap { duration($0, end: "contentCommittedAt") }),
            "imagesStable": statistics(records.compactMap { duration($0, end: "imagesStableAt") }),
            "bridge": statistics(records.compactMap { ($0["bridgeDurationMs"] as? NSNumber)?.doubleValue }),
            "cacheHits": records.filter { ($0["cacheHit"] as? Bool) == true }.count,
            "staleResponsesRejected": records.reduce(0) { $0 + (($1["staleResponsesRejected"] as? NSNumber)?.intValue ?? 0) },
            "mapInstanceCreations": (root["mapInstanceCreations"] as? NSNumber)?.intValue ?? 0,
            "markerReconciliations": (root["markerReconciliations"] as? [[String: Any]])?.count ?? 0,
            "perScope": perScope,
        ]
    }
#endif
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
