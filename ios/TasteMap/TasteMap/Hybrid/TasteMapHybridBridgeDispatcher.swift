import Foundation

@MainActor
public final class TasteMapHybridBridgeDispatcher {
    public static let bridgeVersion = TasteMapHybridBridgeContract.version

    private let service: (any TasteMapHybridServiceProviding)?
    private let authState: @MainActor () -> TasteMapHybridAuthStateDTO
    private let nativeAction: @MainActor (TasteMapHybridBridgeMethod) throws -> Void
    private let navigationAction: (@MainActor (TasteMapHybridBridgeRequest) throws -> TasteMapHybridJSONValue)?
    private let asynchronousAction: @MainActor (TasteMapHybridBridgeMethod, TasteMapHybridJSONValue) async throws -> TasteMapHybridJSONValue
    private let runtime: TasteMapHybridRuntimeDTO

    public init(
        service: (any TasteMapHybridServiceProviding)?,
        appVersion: String,
        build: String,
        dataSource: String,
        authState: @escaping @MainActor () -> TasteMapHybridAuthStateDTO,
        nativeAction: @escaping @MainActor (TasteMapHybridBridgeMethod) throws -> Void = { _ in },
        capabilityOverrides: [TasteMapHybridCapability: Bool] = [:],
        navigationAction: (@MainActor (TasteMapHybridBridgeRequest) throws -> TasteMapHybridJSONValue)? = nil,
        asynchronousAction: @escaping @MainActor (TasteMapHybridBridgeMethod, TasteMapHybridJSONValue) async throws -> TasteMapHybridJSONValue = { method, _ in
            throw TasteMapHybridBridgeErrorDTO(
                code: "capability_unavailable",
                message: "This capability is not available in this Hybrid runtime.",
                recoverable: false,
                details: ["method": .string(method.rawValue)]
            )
        }
    ) {
        self.service = service
        self.authState = authState
        self.nativeAction = nativeAction
        self.navigationAction = navigationAction
        self.asynchronousAction = asynchronousAction
        let dataReady = service != nil
        var capabilities: [TasteMapHybridCapability: Bool] = [
            .appleSignIn: false,
            .logout: false,
            .profileRead: dataReady,
            .restaurantRead: dataReady,
            .restaurantAcquisition: false,
            .mapBrowse: dataReady,
            .contentRead: dataReady,
            .listsRead: false,
            .listShare: false,
            .discoveryPage: false,
            .discoveryCityPage: false,
            .communityInteraction: false,
            .restaurantViewerState: false,
            .visitContract: true,
            .sync: false,
            .haptics: true,
            .share: false,
            .location: false,
            .photoPicker: false,
            .premium: false,
            .permissions: false,
            .nativeNavigation: false,
            .backup: false,
            .accountDelete: false,
        ]
        for (capability, enabled) in capabilityOverrides { capabilities[capability] = enabled }
        runtime = TasteMapHybridRuntimeDTO(
            bridgeVersion: Self.bridgeVersion,
            platform: "ios",
            appVersion: appVersion,
            build: build,
            dataSource: dataSource,
            localBundle: true,
            offlineCapable: true,
            supportedCapabilities: Dictionary(uniqueKeysWithValues: capabilities.map { ($0.key.rawValue, $0.value) })
        )
    }

    public func responseData(for requestData: Data) throws -> Data {
        let request = try Self.decoder.decode(TasteMapHybridBridgeRequest.self, from: requestData)
        let response = dispatch(request)
        return try Self.encoder.encode(response)
    }

    public func responseDataAsync(for requestData: Data) async throws -> Data {
        let request = try Self.decoder.decode(TasteMapHybridBridgeRequest.self, from: requestData)
        let response = await dispatchAsync(request)
        return try Self.encoder.encode(response)
    }

    public func dispatchAsync(_ request: TasteMapHybridBridgeRequest) async -> TasteMapHybridBridgeResponse {
        if navigationAction != nil, Self.isNavigationMethod(request.method) { return dispatch(request) }
        switch request.method {
        case .recommendationsPreference, .discoveryPage, .discoveryCityPage, .listsGet, .listsCreateShareLink,
                .authSignInWithApple, .authLogout, .syncStatus, .syncRun, .shareOpen, .locationCurrent, .mapSurfaceUpdate,
                .acquisitionSearch, .acquisitionNearby, .acquisitionShared, .acquisitionManual, .acquisitionSelect,
                .photoPick, .photoCapture, .photoDiscard, .photoRetry, .premiumTrialEligibility, .premiumClaimTrial, .premiumStatus, .premiumProducts, .premiumPurchase,
                .premiumRestore, .premiumManage, .referralsDashboard, .referralsPrepareRegistration, .directoryDashboard, .directoryMutate, .directoryRespond, .directorySearchUsers, .permissionsStatus, .permissionsOpenSettings,
                .backupOpenExport, .backupOpenImport, .accountOpenDelete,
                .communitySetLike, .communityComments, .communityAddComment, .restaurantSetWantToGo, .restaurantSetAvatar,
                .navigationOpenNative, .navigationOpenHybrid,
                .navigationBack, .navigationCurrent:
            guard request.version == Self.bridgeVersion else {
                return failure(request, code: "bridge_version_mismatch", message: "This bridge version is not supported.")
            }
            guard request.requestId.count >= 8, request.requestId.count <= 128 else {
                return failure(request, code: "invalid_request_id", message: "The bridge request identifier is invalid.")
            }
            do {
                if request.method == .discoveryPage || request.method == .discoveryCityPage {
                    let capability: TasteMapHybridCapability = request.method == .discoveryPage ? .discoveryPage : .discoveryCityPage
                    guard runtime.supportedCapabilities[capability.rawValue] == true else {
                        throw TasteMapHybridBridgeErrorDTO(code: "capability_unavailable", message: "Server-scoped Discovery pages are unavailable.", recoverable: false, details: nil)
                    }
                    guard authState().state == "authenticated", authState().userID != nil else {
                        throw TasteMapHybridBridgeErrorDTO(code: "auth_required", message: "Authentication is required.", recoverable: false, details: nil)
                    }
                }
                let value = try await asynchronousAction(request.method, request.payload)
                return TasteMapHybridBridgeResponse(version: Self.bridgeVersion, requestId: request.requestId, result: value, error: nil)
            } catch let error as TasteMapHybridBridgeErrorDTO {
                return TasteMapHybridBridgeResponse(version: Self.bridgeVersion, requestId: request.requestId, result: nil, error: error)
            } catch {
                return failure(request, code: "native_bridge_failure", message: "Taste Map could not complete this request.", recoverable: true)
            }
        default:
            return dispatch(request)
        }
    }

    public func dispatch(_ request: TasteMapHybridBridgeRequest) -> TasteMapHybridBridgeResponse {
        guard request.version == Self.bridgeVersion else {
            return failure(request, code: "bridge_version_mismatch", message: "This bridge version is not supported.")
        }
        guard request.requestId.count >= 8, request.requestId.count <= 128 else {
            return failure(request, code: "invalid_request_id", message: "The bridge request identifier is invalid.")
        }
        do {
            let result: TasteMapHybridJSONValue
            switch request.method {
            case .runtimeInfo:
                result = try encodeValue(runtime)
            case .authSessionStatus:
                result = try encodeValue(authState())
            case .profileGetCurrent:
                result = try encodeValue(requiredService().profileDashboard())
            case .restaurantGet:
                let payload: TasteMapHybridRestaurantGetRequest = try decodePayload(request.payload)
                guard !payload.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw TasteMapHybridServiceError.invalidRequest
                }
                result = try encodeValue(requiredService().restaurantDetail(id: payload.id))
            case .restaurantList:
                let payload: TasteMapHybridRestaurantListRequest = try decodePayload(request.payload)
                result = try encodeValue(requiredService().restaurants(request: payload))
            case .mapViewport:
                let payload: TasteMapHybridMapBrowseRequest = try decodePayload(request.payload)
                result = try encodeValue(requiredService().mapViewport(request: payload))
            case .contentSnapshot:
                result = try encodeValue(requiredService().contentSnapshot())
            case .visitContract:
                result = .object(["version": .number(1), "writeUIReady": .bool(true)])
            case .visitSave:
                let payload: TasteMapHybridVisitWriteRequest = try decodePayload(request.payload)
                result = try encodeValue(requiredService().saveVisit(request: payload))
            case .visitDelete:
                let payload: TasteMapHybridVisitDeleteRequest = try decodePayload(request.payload)
                result = try encodeValue(requiredService().deleteVisit(id: payload.visitID))
            case .hapticsSelection:
                try nativeAction(.hapticsSelection)
                result = .object([:])
            case .navigationOpenNative, .navigationOpenHybrid, .navigationBack, .navigationCurrent:
                guard runtime.supportedCapabilities[TasteMapHybridCapability.nativeNavigation.rawValue] == true,
                      let navigationAction else {
                    throw TasteMapHybridBridgeErrorDTO(code: "capability_unavailable", message: "Native navigation is unavailable.", recoverable: false, details: nil)
                }
                result = try navigationAction(request)
            case .recommendationsPreference, .discoveryPage, .discoveryCityPage, .listsGet, .listsCreateShareLink,
                    .authSignInWithApple, .authLogout, .syncStatus, .syncRun, .shareOpen, .locationCurrent, .mapSurfaceUpdate,
                    .acquisitionSearch, .acquisitionNearby, .acquisitionShared, .acquisitionManual, .acquisitionSelect,
                    .photoPick, .photoCapture, .photoDiscard, .photoRetry, .premiumTrialEligibility, .premiumClaimTrial, .premiumStatus, .premiumProducts, .premiumPurchase,
                    .premiumRestore, .premiumManage, .referralsDashboard, .referralsPrepareRegistration, .directoryDashboard, .directoryMutate, .directoryRespond, .directorySearchUsers, .permissionsStatus, .permissionsOpenSettings,
                    .backupOpenExport, .backupOpenImport, .accountOpenDelete,
                    .communitySetLike, .communityComments, .communityAddComment, .restaurantSetWantToGo, .restaurantSetAvatar:
                throw TasteMapHybridBridgeErrorDTO(
                    code: "capability_unavailable",
                    message: "This capability is not available in Hybrid Migration Phase 1.",
                    recoverable: false,
                    details: ["method": .string(request.method.rawValue)]
                )
            }
            return TasteMapHybridBridgeResponse(version: Self.bridgeVersion, requestId: request.requestId, result: result, error: nil)
        } catch let error as TasteMapHybridBridgeErrorDTO {
            return TasteMapHybridBridgeResponse(version: Self.bridgeVersion, requestId: request.requestId, result: nil, error: error)
        } catch let error as TasteMapHybridServiceError {
            return serviceFailure(request, error: error)
        } catch {
            return failure(request, code: "native_bridge_failure", message: "Taste Map could not complete this request.", recoverable: true)
        }
    }

    public static func isNavigationMethod(_ method: TasteMapHybridBridgeMethod) -> Bool {
        switch method {
        case .navigationOpenNative, .navigationOpenHybrid, .navigationBack, .navigationCurrent: true
        default: false
        }
    }

    private func requiredService() throws -> any TasteMapHybridServiceProviding {
        guard let service else {
            if authState().state != "authenticated" { throw TasteMapHybridServiceError.authRequired }
            throw TasteMapHybridBridgeErrorDTO(
                code: "hybrid_service_unavailable",
                message: "The Hybrid data service is not configured in this build.",
                recoverable: false,
                details: nil
            )
        }
        return service
    }

    private func serviceFailure(
        _ request: TasteMapHybridBridgeRequest,
        error: TasteMapHybridServiceError
    ) -> TasteMapHybridBridgeResponse {
        switch error {
        case .authRequired:
            failure(request, code: "auth_required", message: "Authentication is required.")
        case .profileMissing:
            failure(request, code: "profile_not_found", message: "The current profile is unavailable.", recoverable: true)
        case .restaurantMissing:
            failure(request, code: "restaurant_not_found", message: "The Restaurant is unavailable.", recoverable: true)
        case .invalidRequest:
            failure(request, code: "invalid_request", message: "The request payload is invalid.")
        }
    }

    private func failure(
        _ request: TasteMapHybridBridgeRequest,
        code: String,
        message: String,
        recoverable: Bool = false
    ) -> TasteMapHybridBridgeResponse {
        TasteMapHybridBridgeResponse(
            version: Self.bridgeVersion,
            requestId: request.requestId,
            result: nil,
            error: TasteMapHybridBridgeErrorDTO(code: code, message: message, recoverable: recoverable, details: nil)
        )
    }

    private func decodePayload<T: Decodable>(_ payload: TasteMapHybridJSONValue) throws -> T {
        try Self.decoder.decode(T.self, from: Self.encoder.encode(payload))
    }

    private func encodeValue<T: Encodable>(_ value: T) throws -> TasteMapHybridJSONValue {
        try Self.decoder.decode(TasteMapHybridJSONValue.self, from: Self.encoder.encode(value))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}
