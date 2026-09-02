import AuthenticationServices
import CoreLocation
import Foundation
import Observation
import SwiftData
import UIKit

@Observable
@MainActor
final class TasteMapHybridRuntime {
    let mode: TasteMapHybridRuntimeMode
    let navigation = TasteMapHybridNavigationCoordinator()

    private let container: ModelContainer
    private let authServices: NativeAuthServices
    private let premiumEntitlementService: PremiumEntitlementService
    private let photoFiles: any LocalPhotoFileStoring
    private let locationPermissionManager = LocationPermissionManager()
    private weak var plugin: TasteMapProductionNativePlugin?
    private var pendingEvents: [TasteMapHybridEventEnvelope] = []
    private var sequence = 0
    private var lastLifecycleState: TasteMapHybridLifecycleState?
    private var bridgeControllerStorage: TasteMapHybridBridgeViewController?
    private(set) var pendingSharedImport: PendingRestaurantImport?

    init(
        mode: TasteMapHybridRuntimeMode,
        container: ModelContainer,
        authServices: NativeAuthServices,
        premiumEntitlementService: PremiumEntitlementService,
        photoFiles: any LocalPhotoFileStoring
    ) {
        self.mode = mode
        self.container = container
        self.authServices = authServices
        self.premiumEntitlementService = premiumEntitlementService
        self.photoFiles = photoFiles
        navigation.didChange = { [weak self] state in
            self?.emit(.navigationRoute, payload: state)
        }
    }

    var bridgeController: TasteMapHybridBridgeViewController {
        if let bridgeControllerStorage { return bridgeControllerStorage }
        let value = TasteMapHybridBridgeViewController(runtime: self)
        bridgeControllerStorage = value
        return value
    }

    var persistentControllerIdentity: ObjectIdentifier { ObjectIdentifier(bridgeController) }

    func attach(plugin: TasteMapProductionNativePlugin) {
        self.plugin = plugin
        for event in pendingEvents { plugin.publish(event) }
        pendingEvents.removeAll(keepingCapacity: true)
    }

    func ensureSessionRestored() async -> TasteMapHybridAuthStateDTO {
        if authServices.localAccountScope == .restoring {
            let user = await authServices.restoreLocalAccountScope()
            if let user {
                try? LocalAccountOwnershipMigrator(context: container.mainContext).activate(userID: user.id)
                await premiumEntitlementService.activate(userID: user.id)
            }
        }
        return await safeSessionState()
    }

    func restoredUser() async -> AuthenticatedUserV1? {
        _ = await ensureSessionRestored()
        return await authServices.sessionManager.restoredUser()
    }

    func logoutFromNative() async -> String {
        _ = await logout()
        return "已退出登录。"
    }

    func responseData(for requestData: Data) async throws -> Data {
        let authState = await ensureSessionRestored()
        let service: (any TasteMapHybridServiceProviding)?
        if authState.state == "authenticated", let userID = authState.userID {
            service = try TasteMapHybridBridgeService(
                container: container,
                ownerUserID: userID,
                membershipTier: [.premium, .gracePeriod].contains(premiumEntitlementService.membershipStatus) ? "member" : "free"
            )
        } else {
            service = nil
        }
        let bundle = Bundle.main
        let dispatcher = TasteMapHybridBridgeDispatcher(
            service: service,
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            dataSource: "native-swiftdata",
            authState: { authState },
            nativeAction: { method in
                guard method == .hapticsSelection else { return }
                let generator = UISelectionFeedbackGenerator()
                generator.prepare()
                generator.selectionChanged()
            },
            capabilityOverrides: [
                .appleSignIn: true,
                .logout: true,
                .nativeNavigation: true,
                .location: true,
            ],
            asynchronousAction: { [weak self] method, payload in
                guard let self else { throw Self.bridgeError("hybrid_runtime_unavailable", recoverable: true) }
                return try await self.perform(method: method, payload: payload)
            }
        )
        return try await dispatcher.responseDataAsync(for: requestData)
    }

    func receive(url: URL) {
        do {
            let route = try TasteMapHybridDeepLinkParser.route(from: url)
            let state = try navigation.handleExternalRoute(route)
            emit(.deepLinkReceived, payload: state)
        } catch {
            // Unsupported URLs remain with the current owner. They are never
            // converted into an arbitrary React or SwiftUI type name.
        }
    }

    /// Resolves only owner-scoped photo descriptors emitted by the typed
    /// bridge. JavaScript never receives an absolute file path.
    func resourceData(for url: URL) async throws -> (data: Data, mimeType: String) {
        guard url.scheme == "tastemap-resource" else {
            throw TasteMapHybridResourceError.unsupportedResource
        }
        let parts = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 3,
              parts[0] == "photo" || parts[0] == "public-photo" else {
            throw TasteMapHybridResourceError.unsupportedResource
        }
        let identifier = parts[1].removingPercentEncoding ?? parts[1]
        guard case .authenticated(let ownerUserID) = authServices.localAccountScope else {
            throw TasteMapHybridResourceError.authRequired
        }
        let context = ModelContext(container)
        guard let photo = try context.fetch(FetchDescriptor<PhotoAsset>()).first(where: {
            $0.ownerUserID == ownerUserID
                && $0.deletedAt == nil
                && $0.binaryDeletedAt == nil
                && ($0.id.uuidString.caseInsensitiveCompare(identifier) == .orderedSame
                    || $0.remoteID?.caseInsensitiveCompare(identifier) == .orderedSame)
        }) else { throw TasteMapHybridResourceError.notFound }
        let relativePath = photo.thumbnailFileRelativePath
            ?? photo.displayFileRelativePath
            ?? photo.localFileRelativePath
        if let relativePath {
            return (try await photoFiles.load(relativePath: relativePath), photo.mimeType)
        }
        if parts[0] == "public-photo" {
            let remoteID = UUID(uuidString: identifier) ?? photo.id
            return (try await authServices.photoAPI.download(photoID: remoteID, variant: .thumbnail), photo.mimeType)
        }
        throw TasteMapHybridResourceError.notFound
    }

    func receive(sharedImport: PendingRestaurantImport) {
        pendingSharedImport = sharedImport
        do {
            let target = try TasteMapHybridRouteDTO(surface: .add)
            let state = try navigation.openNative(target)
            emit(.shareExtensionReceived, payload: TasteMapHybridShareEventPayload(
                fingerprint: sharedImport.id,
                target: state
            ))
        } catch { }
    }

    func consumePendingSharedImport() {
        guard let pendingSharedImport else { return }
        try? PendingRestaurantImportStore.live().consume(id: pendingSharedImport.id)
        self.pendingSharedImport = nil
    }

    func handleLifecycle(_ state: TasteMapHybridLifecycleState) {
        let eventState: TasteMapHybridLifecycleState
        if state == .foreground, lastLifecycleState == .background { eventState = .resume }
        else { eventState = state }
        lastLifecycleState = state
        emit(.appLifecycle, payload: TasteMapHybridLifecycleEventPayload(state: eventState))
    }

    private func perform(
        method: TasteMapHybridBridgeMethod,
        payload: TasteMapHybridJSONValue
    ) async throws -> TasteMapHybridJSONValue {
        switch method {
        case .authSignInWithApple:
            return try await signInWithApple()
        case .authLogout:
            return await logout()
        case .navigationOpenNative:
            let request: TasteMapHybridNativeRouteRequest = try decode(payload)
            let route = try TasteMapHybridRouteDTO(surface: request.route, identifier: request.identifier)
            return try encode(navigation.openNative(route))
        case .navigationOpenHybrid:
            let route: TasteMapHybridRouteDTO = try decode(payload)
            return try encode(navigation.openHybrid(route))
        case .navigationBack:
            return try encode(navigation.back())
        case .navigationCurrent:
            return try encode(navigation.current)
        case .locationCurrent:
            return try await currentLocation()
        default:
            throw Self.bridgeError("capability_unavailable", method: method)
        }
    }

    private func currentLocation() async throws -> TasteMapHybridJSONValue {
        do {
            let location = try await locationPermissionManager.requestCurrentLocation()
            let value = TasteMapHybridLocationDTO(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: Self.dateFormatter.string(from: location.timestamp),
                horizontalAccuracy: location.horizontalAccuracy,
                accuracyAuthorization: locationPermissionManager.accuracyAuthorization == .fullAccuracy ? "full" : "reduced",
                authorizationStatus: "allowed"
            )
            emit(.locationChanged, payload: value)
            return try encode(value)
        } catch RestaurantLocationError.permissionDenied {
            throw TasteMapHybridBridgeErrorDTO(
                code: "location_permission_denied",
                message: "定位权限未开启，可在系统设置中允许 Taste Map 使用位置。",
                recoverable: true,
                details: ["authorizationStatus": .string(locationAuthorizationStatus)]
            )
        } catch RestaurantLocationError.staleOrInaccurate {
            throw TasteMapHybridBridgeErrorDTO(
                code: "location_stale_or_inaccurate",
                message: "暂时无法取得足够新鲜且准确的位置。",
                recoverable: true,
                details: nil
            )
        }
    }

    private var locationAuthorizationStatus: String {
        switch locationPermissionManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: "allowed"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "notDetermined"
        @unknown default: "restricted"
        }
    }

    private func signInWithApple() async throws -> TasteMapHybridJSONValue {
        guard let window = presentationWindow else { throw Self.bridgeError("presentation_anchor_unavailable", recoverable: true) }
        do {
            let user = try await authServices.appleSignIn.signIn(presentationAnchor: window)
            authServices.activateLocalAccount(user)
            try LocalAccountOwnershipMigrator(context: container.mainContext).activate(userID: user.id)
            await premiumEntitlementService.activate(userID: user.id)
            let session = TasteMapHybridAuthStateDTO(state: "authenticated", userID: user.id, displayName: nil)
            resetToCurrentProfileIfNeeded()
            emit(.authChanged, payload: session)
            return try encode(TasteMapHybridAuthResultDTO(state: "authenticated", session: session))
        } catch let error as ASAuthorizationError where error.code == .canceled {
            let session = await safeSessionState()
            return try encode(TasteMapHybridAuthResultDTO(state: "cancelled", session: session))
        }
    }

    private func logout() async -> TasteMapHybridJSONValue {
        do { try await authServices.sessionManager.logout() }
        catch { /* Local logout is authoritative; server revocation remains bounded by expiry. */ }
        authServices.endLocalAccountSession()
        premiumEntitlementService.sessionDidEnd()
        resetToCurrentProfileIfNeeded()
        let session = TasteMapHybridAuthStateDTO(state: "signedOut", userID: nil, displayName: nil)
        emit(.authChanged, payload: session)
        return (try? encode(session)) ?? .object(["state": .string("signedOut"), "userID": .null, "displayName": .null])
    }

    private func safeSessionState() async -> TasteMapHybridAuthStateDTO {
        switch authServices.localAccountScope {
        case .restoring:
            return TasteMapHybridAuthStateDTO(state: "restoring", userID: nil, displayName: nil)
        case .guest:
            return TasteMapHybridAuthStateDTO(state: "signedOut", userID: nil, displayName: nil)
        case .authenticated(let scopedID):
            guard let user = await authServices.sessionManager.restoredUser(), user.id == scopedID else {
#if DEBUG
                if TasteMapUITestFixtures.usesVisualQA {
                    return TasteMapHybridAuthStateDTO(state: "authenticated", userID: scopedID, displayName: nil)
                }
#endif
                return TasteMapHybridAuthStateDTO(state: "signedOut", userID: nil, displayName: nil)
            }
            return TasteMapHybridAuthStateDTO(state: "authenticated", userID: user.id, displayName: nil)
        }
    }

    private func resetToCurrentProfileIfNeeded() {
        if let route = try? TasteMapHybridRouteDTO(surface: .profile) { _ = try? navigation.openHybrid(route) }
    }

    private var presentationWindow: UIWindow? {
        plugin?.presentationWindow
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
    }

    private func emit<T: Encodable>(_ name: TasteMapHybridEventName, payload: T) {
        guard let value = try? encode(payload) else { return }
        sequence += 1
        let event = TasteMapHybridEventEnvelope(sequence: sequence, name: name, payload: value)
        if let plugin { plugin.publish(event) }
        else { pendingEvents.append(event) }
    }

    private func decode<T: Decodable>(_ payload: TasteMapHybridJSONValue) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(payload))
    }

    private func encode<T: Encodable>(_ value: T) throws -> TasteMapHybridJSONValue {
        try JSONDecoder().decode(TasteMapHybridJSONValue.self, from: JSONEncoder().encode(value))
    }

    private static func bridgeError(
        _ code: String,
        method: TasteMapHybridBridgeMethod? = nil,
        recoverable: Bool = false
    ) -> TasteMapHybridBridgeErrorDTO {
        TasteMapHybridBridgeErrorDTO(
            code: code,
            message: code == "capability_unavailable" ? "This Native route or capability is not available." : "Taste Map could not complete this Native operation.",
            recoverable: recoverable,
            details: method.map { ["method": .string($0.rawValue)] }
        )
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return value
    }()
}

private enum TasteMapHybridResourceError: Error {
    case unsupportedResource, authRequired, notFound
}

private struct TasteMapHybridShareEventPayload: Codable {
    let fingerprint: String
    let target: TasteMapHybridNavigationStateDTO
}

private struct TasteMapHybridLifecycleEventPayload: Codable { let state: TasteMapHybridLifecycleState }
