import Capacitor
import Foundation
import UIKit

@objc(TasteMapProductionNativePlugin)
final class TasteMapProductionNativePlugin: CAPPlugin, CAPBridgedPlugin {
    let identifier = "TasteMapProductionNativePlugin"
    let jsName = "TasteMapNative"
    let pluginMethods: [CAPPluginMethod] = [CAPPluginMethod(name: "invoke", returnType: CAPPluginReturnPromise)]
    private weak var runtime: TasteMapHybridRuntime?

    init(runtime: TasteMapHybridRuntime) {
        self.runtime = runtime
        super.init()
    }

    @objc func invoke(_ call: CAPPluginCall) {
        guard let request = call.getObject("request") else {
            call.reject("A typed bridge request is required.", "invalid_bridge_envelope")
            return
        }
        Task { @MainActor [weak self] in
            guard let self, let runtime else {
                call.reject("The Hybrid runtime is unavailable.", "hybrid_runtime_unavailable")
                return
            }
            do {
                let requestData = try JSONSerialization.data(withJSONObject: request)
                let responseData = try await runtime.responseData(for: requestData)
                guard let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                      let object = self.jsObject(response) else {
                    throw TasteMapHybridPluginError.responseEncodingFailed
                }
                call.resolve(object)
            } catch {
                call.reject("Taste Map could not process this bridge request.", "bridge_host_failure")
            }
        }
    }

    func publish(_ event: TasteMapHybridEventEnvelope) {
        guard let data = try? JSONEncoder().encode(event),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let object = jsObject(raw) else { return }
        notifyListeners("event", data: object, retainUntilConsumed: true)
    }

    var presentationWindow: UIWindow? { bridge?.viewController?.view.window }

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

private enum TasteMapHybridPluginError: Error { case responseEncodingFailed }

final class TasteMapHybridBridgeViewController: CAPBridgeViewController {
    private let runtime: TasteMapHybridRuntime

    init(runtime: TasteMapHybridRuntime) {
        self.runtime = runtime
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func capacitorDidLoad() {
        let plugin = TasteMapProductionNativePlugin(runtime: runtime)
        bridge?.registerPluginInstance(plugin)
        runtime.attach(plugin: plugin)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
}
