import SwiftUI
import Testing
import UIKit
@testable import TasteMap

@MainActor
@Suite("Persistent Hybrid controller account remount", .serialized)
struct HybridControllerRemountTests {
    @Test("Native retains per-account presentation invalidation")
    func nativeAccountIdentity() {
        #expect(TasteMapRootPresentationIdentity.value(mode: .nativePrimary, ownerID: nil) == nil)
        #expect(TasteMapRootPresentationIdentity.value(mode: .nativePrimary, ownerID: "A") == "A")
        #expect(TasteMapRootPresentationIdentity.value(mode: .nativePrimary, ownerID: "B") == "B")
    }

    @Test("Account root identity changes retain a mounted, single persistent controller")
    func accountRootRemount() async throws {
        let state = RemountAccountState()
        let child = UIViewController()
        child.loadViewIfNeeded()
        let originalView = child.view
        let host = UIHostingController(rootView: RemountHarness(state: state, controller: child))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        // Restore completes during the first mount, like ContentView.task.
        // Wait for UIKit's actual initial presentation, not a fixed frame delay.
        for _ in 0..<100 {
            window.layoutIfNeeded()
            host.view.layoutIfNeeded()
            if child.view.window === window { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(child.view.window === window, "Cold-launch restoration detached the controller")
        for owner: String? in ["A", nil, "B", "A"] {
            state.owner = owner
            for _ in 0..<10 { try await Task.sleep(for: .milliseconds(20)) }
            host.view.layoutIfNeeded()
            #expect(child.view === originalView)
            #expect(child.parent != nil, "Controller detached after owner \(owner)")
            #expect(child.view.window === window, "Blank root after owner \(owner)")
            #expect(child.view.bounds.width > 0)
            #expect(child.view.bounds.height > 0)
        }
    }
}

@MainActor @Observable
private final class RemountAccountState { var owner: String? }

private struct RemountHarness: View {
    let state: RemountAccountState
    let controller: UIViewController
    var body: some View {
        TasteMapPersistentHybridController(controller: controller)
            .id(TasteMapRootPresentationIdentity.value(mode: .hybridDevelopment, ownerID: state.owner))
            .task { if state.owner == nil { state.owner = "A" } }
    }
}
