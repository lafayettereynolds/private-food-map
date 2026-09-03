import AuthenticationServices
import AVFoundation
import CoreLocation
import Foundation
import Observation
import Photos
import PhotosUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

@Observable
@MainActor
final class TasteMapHybridRuntime {
    let mode: TasteMapHybridRuntimeMode
    let navigation = TasteMapHybridNavigationCoordinator()

    private let container: ModelContainer
    private let authServices: NativeAuthServices
    private let premiumEntitlementService: PremiumEntitlementService
    private let syncCoordinator: SyncCoordinator
    private let photoFiles: any LocalPhotoFileStoring
    private let photoTransferCoordinator: PhotoTransferCoordinator
    private let locationPermissionManager = LocationPermissionManager()
    private let restaurantSearchService: any RestaurantSearching
    private weak var plugin: TasteMapProductionNativePlugin?
    private weak var mapSurfaceHost: TasteMapHybridMapSurfaceHost?
    private var pendingEvents: [TasteMapHybridEventEnvelope] = []
    private var sequence = 0
    private var lastLifecycleState: TasteMapHybridLifecycleState?
    private var bridgeControllerStorage: TasteMapHybridBridgeViewController?
    private(set) var pendingSharedImport: PendingRestaurantImport?
    private var pendingPhotoSelections: [String: PendingHybridPhotoSelection] = [:]
    private var pendingAcquisitionCandidates: [String: PendingHybridAcquisitionCandidate] = [:]
    private var photoPickerSession: HybridPhotoPickerSession?
    private var cameraCaptureSession: HybridCameraCaptureSession?

    init(
        mode: TasteMapHybridRuntimeMode,
        container: ModelContainer,
        authServices: NativeAuthServices,
        premiumEntitlementService: PremiumEntitlementService,
        syncCoordinator: SyncCoordinator,
        photoFiles: any LocalPhotoFileStoring,
        photoTransferCoordinator: PhotoTransferCoordinator,
        restaurantSearchService: any RestaurantSearching = MapKitRestaurantSearchService()
    ) {
        self.mode = mode
        self.container = container
        self.authServices = authServices
        self.premiumEntitlementService = premiumEntitlementService
        self.syncCoordinator = syncCoordinator
        self.photoFiles = photoFiles
        self.photoTransferCoordinator = photoTransferCoordinator
        self.restaurantSearchService = restaurantSearchService
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

    func attach(mapSurfaceHost: TasteMapHybridMapSurfaceHost) {
        self.mapSurfaceHost = mapSurfaceHost
    }

    func mapSurfaceDidChangeViewport(_ viewport: TasteMapHybridMapViewportDTO) {
        emit(.mapViewportChanged, payload: viewport)
    }

    func mapSurfaceDidSelect(restaurantID: String?) {
        emit(.mapRestaurantSelected, payload: TasteMapHybridMapSelectionEventDTO(restaurantID: restaurantID))
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
                membershipTier: [.premium, .gracePeriod].contains(premiumEntitlementService.membershipStatus) ? "member" : "free",
                enqueueSharedMealInvitations: { [authServices = self.authServices] sourceVisitID, participantUserIDs in
                    try authServices.socialCollaborationOutbox.enqueue(
                        ownerUserID: userID,
                        sourceVisitID: sourceVisitID,
                        participantUserIDs: participantUserIDs
                    )
                },
                attachPendingPhotos: { [weak self] attachments, restaurantID, visitID, dishIDsByDraftID, visibility in
                    self?.attachPendingPhotos(
                        attachments,
                        restaurantID: restaurantID,
                        visitID: visitID,
                        dishIDsByDraftID: dishIDsByDraftID,
                        visibility: PhotoVisibility(rawValue: visibility) ?? .private,
                        ownerUserID: userID
                    ) ?? attachments.count
                }
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
                .restaurantAcquisition: true,
                .location: true,
                .premium: true,
                .permissions: true,
                .sync: true,
                .backup: true,
                .accountDelete: true,
                .share: true,
                .photoPicker: true,
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

    /// Resolves only owner-scoped or owner-visible cached photo descriptors
    /// emitted by the typed bridge. JavaScript never receives an absolute file
    /// path and cannot use this resource scheme as an arbitrary photo endpoint.
    func resourceData(for url: URL) async throws -> (data: Data, mimeType: String) {
        guard url.scheme == "tastemap-resource" else {
            throw TasteMapHybridResourceError.unsupportedResource
        }
        let parts = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 3,
              parts[0] == "photo" || parts[0] == "public-photo" || parts[0] == "photo-draft" else {
            throw TasteMapHybridResourceError.unsupportedResource
        }
        let identifier = parts[1].removingPercentEncoding ?? parts[1]
        guard case .authenticated(let ownerUserID) = authServices.localAccountScope else {
            throw TasteMapHybridResourceError.authRequired
        }
        if parts[0] == "photo-draft" {
            guard let pending = pendingPhotoSelections[identifier], pending.ownerUserID == ownerUserID else {
                throw TasteMapHybridResourceError.notFound
            }
            return (
                try await photoFiles.load(relativePath: pending.prepared.thumbnailFileRelativePath),
                pending.prepared.displayMimeType
            )
        }
        let context = ModelContext(container)
        let ownedPhoto = try context.fetch(FetchDescriptor<PhotoAsset>()).first(where: {
            $0.ownerUserID == ownerUserID
                && $0.deletedAt == nil
                && $0.binaryDeletedAt == nil
                && ($0.id.uuidString.caseInsensitiveCompare(identifier) == .orderedSame
                    || $0.remoteID?.caseInsensitiveCompare(identifier) == .orderedSame)
        })
        if let ownedPhoto {
            let relativePath = ownedPhoto.thumbnailFileRelativePath
                ?? ownedPhoto.displayFileRelativePath
                ?? ownedPhoto.localFileRelativePath
            if let relativePath {
                return (try await photoFiles.load(relativePath: relativePath), ownedPhoto.mimeType)
            }
        }

        guard parts[0] == "public-photo",
              Self.isOwnerVisibleCachedPhoto(
                identifier,
                ownerUserID: ownerUserID,
                context: context
              ),
              let remoteID = UUID(uuidString: identifier) else {
            throw TasteMapHybridResourceError.notFound
        }
        let variant = PhotoBinaryVariant(rawValue: parts[2]) ?? .thumbnail
        let data = try await authServices.photoAPI.download(photoID: remoteID, variant: variant)
        return (data, Self.imageMimeType(data))
    }

    /// Public/cached photo access is deliberately derived from the signed-in
    /// user's own Restaurants or owner-visible public projections. A guessed
    /// UUID that is absent from those scopes remains inaccessible.
    private static func isOwnerVisibleCachedPhoto(
        _ identifier: String,
        ownerUserID: String,
        context: ModelContext
    ) -> Bool {
        let normalized = identifier.lowercased()
        let ownerRestaurantContainsPhoto = ((try? context.fetch(FetchDescriptor<Restaurant>())) ?? [])
            .contains { restaurant in
                guard restaurant.ownerUserID == ownerUserID,
                      restaurant.deletedAt == nil,
                      let data = restaurant.remoteRecordData,
                      let contract = try? JSONDecoder().decode(RestaurantJSONContractV1.self, from: data),
                      contract.userId == ownerUserID else { return false }
                return contract.markerPhotoId?.lowercased() == normalized
            }
        if ownerRestaurantContainsPhoto { return true }

        let discoveryContainsPhoto = ((try? context.fetch(FetchDescriptor<CachedDiscoveryRestaurant>())) ?? [])
            .contains { cached in
                cached.currentUserID == ownerUserID
                    && cached.projection?.photo?.photoId.lowercased() == normalized
            }
        if discoveryContainsPhoto { return true }

        let communityContainsPhoto = ((try? context.fetch(FetchDescriptor<CachedCommunityContent>())) ?? [])
            .contains { cached in
                guard cached.currentUserID == ownerUserID, let item = cached.item else { return false }
                if item.restaurant.photo?.photoId.lowercased() == normalized { return true }
                return item.visit?.photos.contains { $0.photoId.lowercased() == normalized } == true
            }
        if communityContainsPhoto { return true }

        let publicListContainsPhoto = ((try? context.fetch(FetchDescriptor<CachedPublicRestaurantListItem>())) ?? [])
            .contains { cached in
                cached.viewerUserID == ownerUserID
                    && cached.item?.restaurant.markerPhotoId?.lowercased() == normalized
            }
        if publicListContainsPhoto { return true }

        return ((try? context.fetch(FetchDescriptor<CachedPublicRestaurantList>())) ?? [])
            .contains { cached in
                guard cached.viewerUserID == ownerUserID, let summary = cached.summary else { return false }
                if summary.customCoverPhotoId?.lowercased() == normalized { return true }
                return summary.previewRestaurants.contains { $0.photoId?.lowercased() == normalized }
            }
    }

    private static func imageMimeType(_ data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
        if data.starts(with: [0x52, 0x49, 0x46, 0x46]), data.count >= 12,
           data[8..<12].elementsEqual([0x57, 0x45, 0x42, 0x50]) { return "image/webp" }
        return "image/jpeg"
    }

    func receive(sharedImport: PendingRestaurantImport) {
        pendingSharedImport = sharedImport
        do {
            let target = try TasteMapHybridRouteDTO(surface: .add)
            let state = try navigation.openHybrid(target)
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
        case .mapSurfaceUpdate:
            return try updateMapSurface(payload)
        case .acquisitionSearch:
            return try await searchRestaurants(payload)
        case .acquisitionNearby:
            return try await nearbyRestaurants()
        case .acquisitionShared:
            return try await sharedRestaurantCandidates()
        case .acquisitionManual:
            return try await manualRestaurantCandidate(payload)
        case .acquisitionSelect:
            return try selectRestaurantCandidate(payload)
        case .premiumStatus:
            return premiumStatus()
        case .premiumProducts:
            return try await premiumProducts()
        case .premiumPurchase:
            return try await purchasePremium(payload)
        case .premiumRestore:
            return try await restorePremium()
        case .premiumManage:
            return try await managePremium()
        case .syncStatus:
            return try encode(syncStatus())
        case .syncRun:
            await syncCoordinator.synchronizeNow()
            return try encode(syncStatus())
        case .permissionsStatus:
            return try encode(permissionsStatus())
        case .permissionsOpenSettings:
            return try await openSystemSettings()
        case .backupOpenExport, .backupOpenImport:
            return try openNativeRoute(.dataBackup)
        case .accountOpenDelete:
            return try openNativeRoute(.accountDelete)
        case .shareOpen:
            return try await openShareSheet(payload)
        case .photoPick:
            return try await pickPhotos(payload)
        case .photoCapture:
            return try await capturePhoto()
        case .photoDiscard:
            return try await discardPhoto(payload)
        case .photoRetry:
            return try retryPhoto(payload)
        default:
            throw Self.bridgeError("capability_unavailable", method: method)
        }
    }

    private func updateMapSurface(_ payload: TasteMapHybridJSONValue) throws -> TasteMapHybridJSONValue {
        let request: TasteMapHybridMapSurfaceUpdateRequest = try decode(payload)
        guard case .authenticated(let ownerUserID) = authServices.localAccountScope else {
            throw Self.bridgeError("auth_required", method: .mapSurfaceUpdate, recoverable: true)
        }
        guard let mapSurfaceHost else {
            throw Self.bridgeError("native_map_surface_unavailable", method: .mapSurfaceUpdate, recoverable: true)
        }
        let photos = ((try? container.mainContext.fetch(FetchDescriptor<PhotoAsset>())) ?? []).filter {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil && $0.binaryDeletedAt == nil
        }
        let photosByID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        let profile = ((try? container.mainContext.fetch(FetchDescriptor<UserProfile>())) ?? []).first {
            $0.tasteMapUserID == ownerUserID && $0.deletedAt == nil
        }
        let avatarReference = request.userAvatarPhotoID ?? profile?.avatarPhotoID
        let avatarPhoto = avatarReference.flatMap { reference in
            photos.first {
                $0.id.uuidString.caseInsensitiveCompare(reference) == .orderedSame
                    || $0.remoteID?.caseInsensitiveCompare(reference) == .orderedSame
            }
        }
        try mapSurfaceHost.apply(
            request,
            resources: TasteMapHybridMapSurfaceResources(
                photosByID: photosByID,
                userAvatarPhoto: avatarPhoto,
                photoCoordinator: photoTransferCoordinator,
                photoAPI: authServices.photoAPI
            )
        )
        return try encode(TasteMapHybridMapSurfaceUpdateResponse(requestID: request.requestID))
    }

    private func searchRestaurants(_ payload: TasteMapHybridJSONValue) async throws -> TasteMapHybridJSONValue {
        let request: TasteMapHybridAcquisitionSearchRequest = try decode(payload)
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = request.city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 200, city.count <= 120 else {
            throw Self.bridgeError("invalid_acquisition_search", method: .acquisitionSearch)
        }
        let values = try await restaurantSearchService.search(
            query: query,
            scope: RestaurantSearchScope(city: city)
        )
        return try encode(acquisitionResults(
            candidates: Array(values.prefix(20)),
            location: nil,
            message: values.isEmpty ? "没有找到匹配的餐厅，请换一个名称、地址或城市。" : nil
        ))
    }

    private func nearbyRestaurants() async throws -> TasteMapHybridJSONValue {
        let fix = try await freshLocationFix(method: .acquisitionNearby)
        let center = RestaurantCoordinate(
            latitude: fix.location.coordinate.latitude,
            longitude: fix.location.coordinate.longitude
        )
        let values = try await restaurantSearchService.nearby(center: center, radiusMeters: 3_000)
        let ordered = RestaurantDistanceOrdering.measuringAndSorting(values, from: center)
            .filter { ($0.distanceMeters ?? .greatestFiniteMagnitude) <= 3_000 }
        return try encode(acquisitionResults(
            candidates: Array(ordered.prefix(12)),
            location: fix.dto,
            message: ordered.isEmpty ? "3 公里内暂时没有找到餐厅；搜索和手动添加仍可使用。" : nil
        ))
    }

    private func sharedRestaurantCandidates() async throws -> TasteMapHybridJSONValue {
        guard let shared = pendingSharedImport, !shared.isExpired else {
            return try encode(TasteMapHybridAcquisitionResultsDTO(
                candidates: [],
                location: nil,
                message: "当前没有待处理的外部分享。",
                sharedImportFingerprint: nil
            ))
        }
        let text = shared.acquisitionText
        var candidates: [RestaurantCandidate] = []
        var message: String? = nil
        let parsed = try? ExternalRestaurantLinkParser.parse(text, currentCity: "")
        if let direct = parsed?.candidate {
            candidates = [direct]
            message = "已从分享内容提取餐厅，请确认具体门店。"
        } else {
            do {
                let response = try await authServices.externalRestaurantLinkAPI.resolve(text: text, currentCity: "")
                candidates = response.candidates.map(\.restaurantCandidate)
                message = response.message
                if candidates.isEmpty, let fallback = response.searchFallback {
                    let center = fallback.latitude.flatMap { latitude in
                        fallback.longitude.map { RestaurantCoordinate(latitude: latitude, longitude: $0) }
                    }
                    candidates = try await restaurantSearchService.search(
                        query: fallback.keyword,
                        scope: RestaurantSearchScope(city: fallback.city, center: center, radiusMeters: center == nil ? 20_000 : 3_000)
                    )
                }
            } catch {
                if let parsed,
                   let semantic = [parsed.name, parsed.address]
                       .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                       .first(where: { !$0.isEmpty }) {
                    candidates = (try? await restaurantSearchService.search(
                        query: semantic,
                        scope: RestaurantSearchScope(city: parsed.city, center: parsed.coordinate)
                    )) ?? []
                }
                message = candidates.isEmpty
                    ? "分享内容暂时无法识别；仍可按名称搜索或手动添加。"
                    : "已从分享文字提取关键词，请确认具体门店。"
            }
        }
        return try encode(acquisitionResults(
            candidates: Array(candidates.prefix(20)),
            location: nil,
            message: message,
            sharedImportFingerprint: shared.id
        ))
    }

    private func manualRestaurantCandidate(_ payload: TasteMapHybridJSONValue) async throws -> TasteMapHybridJSONValue {
        let draft: TasteMapHybridManualRestaurantDraftDTO = try decode(payload)
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = draft.city.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = draft.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !city.isEmpty, !address.isEmpty,
              name.count <= 200, city.count <= 120, address.count <= 500 else {
            throw Self.bridgeError("invalid_manual_restaurant", method: .acquisitionManual)
        }
        let coordinate: RestaurantCoordinate
        if let latitude = draft.latitude, let longitude = draft.longitude {
            coordinate = RestaurantCoordinate(latitude: latitude, longitude: longitude)
            guard coordinate.isValid else { throw Self.bridgeError("invalid_coordinate", method: .acquisitionManual) }
        } else {
            do { coordinate = try await restaurantSearchService.coordinate(for: address, city: city) }
            catch { throw Self.bridgeError("manual_address_not_found", method: .acquisitionManual, recoverable: true) }
        }
        let candidate = RestaurantCandidate.manual(name: name, city: city, address: address, coordinate: coordinate)
        return try encode(acquisitionResults(
            candidates: [candidate],
            location: nil,
            message: "请确认餐厅信息。"
        ))
    }

    private func selectRestaurantCandidate(_ payload: TasteMapHybridJSONValue) throws -> TasteMapHybridJSONValue {
        let request: TasteMapHybridAcquisitionSelectionRequest = try decode(payload)
        guard case .authenticated(let ownerUserID) = authServices.localAccountScope,
              let pending = pendingAcquisitionCandidates[request.candidateID],
              pending.ownerUserID == ownerUserID else {
            throw Self.bridgeError("candidate_not_found", method: .acquisitionSelect, recoverable: true)
        }
        if pending.duplicateKind == "probableCrossProvider", !request.confirmProbableMatch {
            throw Self.bridgeError("probable_match_confirmation_required", method: .acquisitionSelect, recoverable: true)
        }
        let restaurantID: String
        if pending.duplicateKind == "exactProvider", let existing = pending.existingRestaurantID {
            restaurantID = existing
        } else {
            restaurantID = try TasteMapHybridRestaurantReferenceResolver.cacheCandidate(
                pending.candidate,
                ownerUserID: ownerUserID,
                context: container.mainContext
            )
        }
        if pending.sharedImportFingerprint != nil { consumePendingSharedImport() }
        return try encode(TasteMapHybridAcquisitionSelectionDTO(
            restaurantID: restaurantID,
            duplicateKind: pending.duplicateKind,
            existingRestaurantID: pending.existingRestaurantID
        ))
    }

    private func acquisitionResults(
        candidates: [RestaurantCandidate],
        location: TasteMapHybridLocationDTO?,
        message: String?,
        sharedImportFingerprint: String? = nil
    ) -> TasteMapHybridAcquisitionResultsDTO {
        guard case .authenticated(let ownerUserID) = authServices.localAccountScope else {
            return TasteMapHybridAcquisitionResultsDTO(candidates: [], location: location, message: "请先登录。", sharedImportFingerprint: sharedImportFingerprint)
        }
        let restaurants = ((try? container.mainContext.fetch(FetchDescriptor<Restaurant>())) ?? [])
            .filter { $0.ownerUserID == ownerUserID && $0.deletedAt == nil }
        let photos = ((try? container.mainContext.fetch(FetchDescriptor<PhotoAsset>())) ?? [])
            .filter {
                $0.ownerUserID == ownerUserID
                    && $0.deletedAt == nil
                    && $0.binaryDeletedAt == nil
                    && $0.uploadState != .deleted
            }
        let values = candidates.map { candidate -> TasteMapHybridAcquisitionCandidateDTO in
            let match = RestaurantDeduplicator.classifiedMatch(for: candidate, in: restaurants)
            let duplicateKind: String
            switch match?.kind {
            case .exactProviderIdentity: duplicateKind = "exactProvider"
            case .probableCrossProvider: duplicateKind = "probableCrossProvider"
            case nil: duplicateKind = "none"
            }
            let existingID = match.map { $0.restaurant.remoteID ?? $0.restaurant.id.uuidString.lowercased() }
            let token = candidate.id.uuidString.lowercased()
            pendingAcquisitionCandidates[token] = PendingHybridAcquisitionCandidate(
                ownerUserID: ownerUserID,
                candidate: candidate,
                duplicateKind: duplicateKind,
                existingRestaurantID: existingID,
                sharedImportFingerprint: sharedImportFingerprint
            )
            let canonicalResolution = RestaurantImagePriorityPolicy.acquisitionResolution(
                matchedRestaurant: match?.restaurant,
                authenticatedOwnerUserID: ownerUserID,
                ownerPhotos: photos,
                candidateProviderMerchantImageURL: candidate.photoURL
            )
            let imageResolution = acquisitionImageResolutionDescriptor(
                canonicalResolution,
                restaurantName: candidate.name,
                fallbackSeed: match?.restaurant.id.uuidString.lowercased() ?? token,
                ownerPhotos: photos
            )
            let image = imageResolution.sources.first ?? imageResolution.fallback
            return TasteMapHybridAcquisitionCandidateDTO(
                id: token,
                name: candidate.name,
                address: candidate.address,
                city: candidate.city,
                district: candidate.district,
                latitude: candidate.latitude,
                longitude: candidate.longitude,
                distanceMeters: candidate.distanceMeters,
                phone: candidate.phone,
                openingHours: candidate.openingHours,
                image: image,
                imageResolution: imageResolution,
                duplicateKind: duplicateKind,
                existingRestaurantID: existingID
            )
        }
        return TasteMapHybridAcquisitionResultsDTO(
            candidates: values,
            location: location,
            message: message,
            sharedImportFingerprint: sharedImportFingerprint
        )
    }

    private func acquisitionImageResolutionDescriptor(
        _ resolution: RestaurantImageResolution,
        restaurantName: String,
        fallbackSeed: String,
        ownerPhotos: [PhotoAsset]
    ) -> TasteMapHybridImageResolutionDTO {
        let label = "\(restaurantName)餐厅图片"
        let sources = resolution.sources.compactMap { source -> TasteMapHybridImageDescriptor? in
            switch source {
            case .localUserPhoto(let id):
                let value = id.uuidString.lowercased()
                return TasteMapHybridImageDescriptor(
                    kind: .nativeResource,
                    resourceURL: "tastemap-resource://photo/\(value)/display",
                    photoID: value,
                    accessibilityLabel: "\(label) · 用户实拍"
                )
            case .publicOrCachedPhoto(let id):
                let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
                let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
                let isOwnerCached = ownerPhotos.contains {
                    $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame
                        || $0.remoteID?.caseInsensitiveCompare(id) == .orderedSame
                }
                return TasteMapHybridImageDescriptor(
                    kind: .publicOrCached,
                    resourceURL: "tastemap-resource://\(isOwnerCached ? "photo" : "public-photo")/\(encoded)/display",
                    photoID: id,
                    accessibilityLabel: "\(label) · 公开图片"
                )
            case .providerMerchantImage(let url):
                return TasteMapHybridImageDescriptor(
                    kind: .providerMerchant,
                    resourceURL: url.absoluteString,
                    accessibilityLabel: "\(label) · 商户图片"
                )
            case .foodDiningFallback:
                return nil
            }
        }
        return TasteMapHybridImageResolutionDTO(
            sources: sources,
            fallback: TasteMapHybridImageDescriptor(
                kind: .foodDiningFallback,
                stableSeed: fallbackSeed,
                accessibilityLabel: "\(restaurantName)餐厅图片占位"
            )
        )
    }

    private func freshLocationFix(method: TasteMapHybridBridgeMethod) async throws -> (location: CLLocation, dto: TasteMapHybridLocationDTO) {
        do {
            let location = try await locationPermissionManager.requestCurrentLocation()
            guard RestaurantLocationFixPolicy.isUsable(location, accuracyAuthorization: locationPermissionManager.accuracyAuthorization) else {
                throw RestaurantLocationError.staleOrInaccurate
            }
            let dto = TasteMapHybridLocationDTO(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: Self.dateFormatter.string(from: location.timestamp),
                horizontalAccuracy: location.horizontalAccuracy,
                accuracyMode: locationPermissionManager.accuracyAuthorization == .fullAccuracy ? "full" : "reduced",
                authorizationStatus: "allowed"
            )
            emit(.locationChanged, payload: dto)
            return (location, dto)
        } catch RestaurantLocationError.permissionDenied {
            throw Self.bridgeError("location_permission_denied", method: method, recoverable: true)
        } catch {
            throw Self.bridgeError("location_stale_or_inaccurate", method: method, recoverable: true)
        }
    }

    private func pickPhotos(_ payload: TasteMapHybridJSONValue) async throws -> TasteMapHybridJSONValue {
        let request: TasteMapHybridPhotoPickRequest = try decode(payload)
        let limit = min(max(request.selectionLimit, 1), PhotoImportService.maximumSelectionCount)
        guard let presenter = presentationController else {
            throw Self.bridgeError("presentation_anchor_unavailable", method: .photoPick, recoverable: true)
        }
        guard case .authenticated(let ownerUserID) = authServices.localAccountScope else {
            throw TasteMapHybridBridgeErrorDTO(
                code: "auth_required",
                message: "Authentication is required.",
                recoverable: false,
                details: nil
            )
        }
        let results = await presentPhotoPicker(from: presenter, selectionLimit: limit)
        var picked: [TasteMapHybridPhotoPickItemDTO] = []
        for result in results.prefix(limit) {
            do {
                let provider = result.itemProvider
                let data = try await Self.photoData(from: provider)
                picked.append(try await registerPendingPhoto(
                    data: data,
                    suggestedContentType: provider.registeredTypeIdentifiers.compactMap {
                        UTType($0)?.preferredMIMEType
                    }.first,
                    originalFileName: provider.suggestedName,
                    ownerUserID: ownerUserID
                ))
            } catch {
                // One bad selection does not discard other prepared photos or
                // turn the later Visit save into an all-or-nothing photo flow.
                continue
            }
        }
        return try encode(TasteMapHybridPhotoPickResultDTO(photos: picked))
    }

    private func capturePhoto() async throws -> TasteMapHybridJSONValue {
        guard let presenter = presentationController else {
            throw Self.bridgeError("presentation_anchor_unavailable", method: .photoCapture, recoverable: true)
        }
        guard case .authenticated(let ownerUserID) = authServices.localAccountScope else {
            throw Self.bridgeError("auth_required", method: .photoCapture)
        }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            throw Self.bridgeError("camera_unavailable", method: .photoCapture, recoverable: true)
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            throw Self.bridgeError("camera_permission_denied", method: .photoCapture, recoverable: true)
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                throw Self.bridgeError("camera_permission_denied", method: .photoCapture, recoverable: true)
            }
        case .authorized:
            break
        @unknown default:
            throw Self.bridgeError("camera_permission_unavailable", method: .photoCapture, recoverable: true)
        }
        guard let data = await presentCamera(from: presenter) else {
            return try encode(TasteMapHybridPhotoPickResultDTO(photos: []))
        }
        let item = try await registerPendingPhoto(
            data: data,
            suggestedContentType: UTType.jpeg.preferredMIMEType,
            originalFileName: "tastemap-camera-\(UUID().uuidString.lowercased()).jpg",
            ownerUserID: ownerUserID
        )
        return try encode(TasteMapHybridPhotoPickResultDTO(photos: [item]))
    }

    private func registerPendingPhoto(
        data: Data,
        suggestedContentType: String?,
        originalFileName: String?,
        ownerUserID: String
    ) async throws -> TasteMapHybridPhotoPickItemDTO {
        let prepared = try await photoTransferCoordinator.preparePhoto(
            data: data,
            suggestedContentType: suggestedContentType,
            originalFileName: originalFileName
        )
        let identifier = prepared.id.uuidString.lowercased()
        pendingPhotoSelections[identifier] = PendingHybridPhotoSelection(
            ownerUserID: ownerUserID,
            prepared: prepared
        )
        return TasteMapHybridPhotoPickItemDTO(
            photoID: identifier,
            preview: TasteMapHybridImageDescriptor(
                kind: .nativeResource,
                resourceURL: "tastemap-resource://photo-draft/\(identifier)/thumbnail",
                photoID: identifier,
                accessibilityLabel: "待保存的到访照片"
            )
        )
    }

    private func discardPhoto(_ payload: TasteMapHybridJSONValue) async throws -> TasteMapHybridJSONValue {
        let request: TasteMapHybridPhotoIDRequest = try decode(payload)
        guard case .authenticated(let ownerUserID) = authServices.localAccountScope else {
            throw Self.bridgeError("auth_required", method: .photoDiscard)
        }
        let normalized = request.photoID.lowercased()
        if let pending = pendingPhotoSelections[normalized], pending.ownerUserID == ownerUserID {
            pendingPhotoSelections[normalized] = nil
            await photoTransferCoordinator.discardPrepared(pending.prepared)
            return .object([:])
        }
        guard let photo = try ownedPhoto(identifier: request.photoID, ownerUserID: ownerUserID) else {
            throw Self.bridgeError("photo_not_found", method: .photoDiscard, recoverable: true)
        }
        try await photoTransferCoordinator.delete(photo)
        return .object([:])
    }

    private func retryPhoto(_ payload: TasteMapHybridJSONValue) throws -> TasteMapHybridJSONValue {
        let request: TasteMapHybridPhotoIDRequest = try decode(payload)
        guard case .authenticated(let ownerUserID) = authServices.localAccountScope,
              let photo = try ownedPhoto(identifier: request.photoID, ownerUserID: ownerUserID) else {
            throw Self.bridgeError("photo_not_found", method: .photoRetry, recoverable: true)
        }
        try photoTransferCoordinator.retry(photo)
        return .object([:])
    }

    private func attachPendingPhotos(
        _ attachments: [TasteMapHybridPendingPhotoAttachmentDTO],
        restaurantID: UUID,
        visitID: UUID,
        dishIDsByDraftID: [String: String],
        visibility: PhotoVisibility,
        ownerUserID: String
    ) -> Int {
        var failureCount = 0
        var attachedCount = 0
        for attachment in attachments {
            let identifier = attachment.photoID.lowercased()
            guard let pending = pendingPhotoSelections[identifier], pending.ownerUserID == ownerUserID else {
                // Existing PhotoAsset IDs are expected in an edit draft and do
                // not need to be attached again.
                continue
            }
            var attachedPhoto: PhotoAsset?
            do {
                let photo = try photoTransferCoordinator.attachPreparedPhoto(
                    pending.prepared,
                    restaurantID: restaurantID,
                    visitID: visitID,
                    sortOrder: attachedCount,
                    visibility: visibility,
                    queueForUpload: true
                )
                attachedPhoto = photo
                if let draftID = attachment.dishDraftID?.lowercased(),
                   let dishIdentifier = dishIDsByDraftID[draftID],
                   let dishID = UUID(uuidString: dishIdentifier) {
                    let dish = try container.mainContext.fetch(FetchDescriptor<Dish>()).first(where: {
                        $0.id == dishID && $0.ownerUserID == ownerUserID && $0.deletedAt == nil
                    })
                    try photoTransferCoordinator.setDishRelationship(photo, dish: dish)
                }
                try photoTransferCoordinator.enqueue(photo)
                pendingPhotoSelections[identifier] = nil
                attachedCount += 1
            } catch {
                pendingPhotoSelections[identifier] = nil
                let photoToDiscard = attachedPhoto
                Task { @MainActor [photoTransferCoordinator] in
                    if let photoToDiscard {
                        try? await photoTransferCoordinator.discardLocalPhoto(photoToDiscard)
                    } else {
                        await photoTransferCoordinator.discardPrepared(pending.prepared)
                    }
                }
                failureCount += 1
            }
        }
        return failureCount
    }

    private func ownedPhoto(identifier: String, ownerUserID: String) throws -> PhotoAsset? {
        try container.mainContext.fetch(FetchDescriptor<PhotoAsset>()).first(where: {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil
                && ($0.id.uuidString.caseInsensitiveCompare(identifier) == .orderedSame
                    || $0.remoteID?.caseInsensitiveCompare(identifier) == .orderedSame)
        })
    }

    private func presentPhotoPicker(
        from presenter: UIViewController,
        selectionLimit: Int
    ) async -> [PHPickerResult] {
        await withCheckedContinuation { continuation in
            var configuration = PHPickerConfiguration(photoLibrary: .shared())
            configuration.filter = .images
            configuration.selectionLimit = selectionLimit
            configuration.selection = .ordered
            let picker = PHPickerViewController(configuration: configuration)
            let session = HybridPhotoPickerSession { [weak self, weak picker] results in
                picker?.dismiss(animated: true) {
                    self?.photoPickerSession = nil
                    continuation.resume(returning: results)
                }
            }
            photoPickerSession = session
            picker.delegate = session
            presenter.present(picker, animated: true)
        }
    }

    private func presentCamera(from presenter: UIViewController) async -> Data? {
        await withCheckedContinuation { continuation in
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            picker.mediaTypes = [UTType.image.identifier]
            let session = HybridCameraCaptureSession { [weak self, weak picker] data in
                picker?.dismiss(animated: true) {
                    self?.cameraCaptureSession = nil
                    continuation.resume(returning: data)
                }
            }
            cameraCaptureSession = session
            picker.delegate = session
            presenter.present(picker, animated: true)
        }
    }

    private static func photoData(from provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? PhotoImportError.invalidImage) }
            }
        }
    }

    private func premiumStatus() -> TasteMapHybridJSONValue {
        let status: String
        switch premiumEntitlementService.membershipStatus {
        case .premium, .gracePeriod: status = "premium"
        case .free, .expired: status = "free"
        case .loading, .unknown: status = "unavailable"
        }
        return .object([
            "state": .string(status),
            "expiresAt": premiumEntitlementService.snapshot?.expiresAt.map {
                .string(Self.dateFormatter.string(from: $0))
            } ?? .null,
        ])
    }

    private func premiumProducts() async throws -> TasteMapHybridJSONValue {
        do {
            let products = try await premiumEntitlementService.productsProvider.products().map {
                TasteMapHybridPremiumProductDTO(
                    id: $0.id,
                    displayName: $0.displayName,
                    valueDescription: $0.valueDescription,
                    displayPrice: $0.displayPrice,
                    period: $0.period.rawValue,
                    billingPeriodDescription: $0.billingPeriodDescription
                )
            }
            return try encode(products)
        } catch {
            throw Self.bridgeError("premium_products_unavailable", method: .premiumProducts, recoverable: true)
        }
    }

    private func purchasePremium(_ payload: TasteMapHybridJSONValue) async throws -> TasteMapHybridJSONValue {
        let request: HybridPremiumPurchaseRequest = try decode(payload)
        let productID = request.productID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !productID.isEmpty, productID.count <= 240 else {
            throw Self.bridgeError("invalid_premium_product", method: .premiumPurchase)
        }
        do {
            let result = try await premiumEntitlementService.productsProvider.purchase(productID: productID)
            if result.requiresEntitlementRefresh { await premiumEntitlementService.refresh() }
            return try encode(TasteMapHybridPremiumActionResultDTO(
                outcome: Self.premiumOutcome(result.outcome),
                status: premiumStatus()
            ))
        } catch {
            throw Self.bridgeError("premium_purchase_failed", method: .premiumPurchase, recoverable: true)
        }
    }

    private func restorePremium() async throws -> TasteMapHybridJSONValue {
        do {
            let result = try await premiumEntitlementService.productsProvider.restore()
            if result.requiresEntitlementRefresh { await premiumEntitlementService.refresh() }
            return try encode(TasteMapHybridPremiumActionResultDTO(
                outcome: Self.premiumOutcome(result.outcome),
                status: premiumStatus()
            ))
        } catch {
            throw Self.bridgeError("premium_restore_failed", method: .premiumRestore, recoverable: true)
        }
    }

    private func managePremium() async throws -> TasteMapHybridJSONValue {
        do {
            try await premiumEntitlementService.productsProvider.manageSubscription()
            return try encode(TasteMapHybridPremiumActionResultDTO(outcome: "opened", status: premiumStatus()))
        } catch {
            throw Self.bridgeError("premium_management_unavailable", method: .premiumManage, recoverable: true)
        }
    }

    private func syncStatus() -> HybridSyncStatusDTO {
        let value = syncCoordinator.presentation
        let state: String = switch value.phase {
        case .synced, .pending: "idle"
        case .waitingForNetwork: "offline"
        case .syncing: "syncing"
        case .failed, .conflicted: "error"
        case .signedOut: "unavailable"
        }
        return HybridSyncStatusDTO(
            state: state,
            pendingMutationCount: value.pendingCount,
            pendingPhotoCount: value.pendingPhotoCount,
            failedPhotoCount: value.failedPhotoCount,
            conflictCount: value.conflictCount,
            lastSuccessfulSyncAt: value.lastSyncedAt.map(Self.dateFormatter.string(from:)),
            errorCode: value.diagnostic?.category.rawValue ?? (value.phase == .conflicted ? "conflict" : nil)
        )
    }

    private func permissionsStatus() -> TasteMapHybridPermissionsStatusDTO {
        let value = SettingsPermissionSnapshot.live(locationStatus: locationPermissionManager.authorizationStatus)
        let camera = switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: "allowed"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "notDetermined"
        @unknown default: "restricted"
        }
        return TasteMapHybridPermissionsStatusDTO(
            location: value.location.rawValue,
            camera: camera,
            photoAddOnly: value.photoAddOnly.rawValue,
            canOpenSystemSettings: value.location.canOpenSystemSettings
                || value.photoAddOnly.canOpenSystemSettings
                || camera == "denied"
                || camera == "restricted"
        )
    }

    private func openSystemSettings() async throws -> TasteMapHybridJSONValue {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            throw Self.bridgeError("system_settings_unavailable", method: .permissionsOpenSettings)
        }
        let opened = await UIApplication.shared.open(url)
        guard opened else {
            throw Self.bridgeError("system_settings_unavailable", method: .permissionsOpenSettings, recoverable: true)
        }
        return .object([:])
    }

    private func openNativeRoute(_ surface: TasteMapHybridRouteSurface) throws -> TasteMapHybridJSONValue {
        _ = try navigation.openNative(TasteMapHybridRouteDTO(surface: surface))
        return .object([:])
    }

    private static func premiumOutcome(_ outcome: MembershipPurchaseOutcome) -> String {
        switch outcome {
        case .completed: "completed"
        case .pending: "pending"
        case .userCancelled: "cancelled"
        }
    }

    private func openShareSheet(_ payload: TasteMapHybridJSONValue) async throws -> TasteMapHybridJSONValue {
        let request: HybridShareRequest = try decode(payload)
        var items: [Any] = []
        if let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            items.append(title)
        }
        if let text = request.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            items.append(text)
        }
        if let rawURL = request.url, let url = URL(string: rawURL), ["https", "http"].contains(url.scheme?.lowercased()) {
            items.append(url)
        }
        if let resource = request.nativeResourceURL,
           let url = URL(string: resource), url.scheme == "tastemap-resource",
           let loaded = try? await resourceData(for: url),
           let image = UIImage(data: loaded.data) {
            items.append(image)
        }
        if let dataURL = request.imageDataURL,
           let image = Self.generatedShareImage(dataURL: dataURL) {
            items.append(image)
        }
        guard !items.isEmpty, let presenter = presentationController else {
            throw Self.bridgeError("share_payload_invalid", method: .shareOpen, recoverable: true)
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = presenter.view
        controller.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX,
            y: presenter.view.bounds.maxY - 1,
            width: 1,
            height: 1
        )
        presenter.present(controller, animated: true)
        return .object(["presented": .bool(true)])
    }

    private func currentLocation() async throws -> TasteMapHybridJSONValue {
        do {
            let location = try await locationPermissionManager.requestCurrentLocation()
            let value = TasteMapHybridLocationDTO(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: Self.dateFormatter.string(from: location.timestamp),
                horizontalAccuracy: location.horizontalAccuracy,
                accuracyMode: locationPermissionManager.accuracyAuthorization == .fullAccuracy ? "full" : "reduced",
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
            pendingAcquisitionCandidates.removeAll(keepingCapacity: false)
            pendingPhotoSelections.removeAll(keepingCapacity: false)
            try LocalAccountOwnershipMigrator(context: container.mainContext).activate(userID: user.id)
            await premiumEntitlementService.activate(userID: user.id)
            await syncCoordinator.sessionDidBecomeAvailable(userID: user.id)
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
        pendingAcquisitionCandidates.removeAll(keepingCapacity: false)
        pendingPhotoSelections.removeAll(keepingCapacity: false)
        premiumEntitlementService.sessionDidEnd()
        syncCoordinator.sessionDidEnd()
        resetToCurrentProfileIfNeeded()
        let session = TasteMapHybridAuthStateDTO(state: "signedOut", userID: nil, displayName: nil)
        emit(.authChanged, payload: session)
        return (try? encode(session)) ?? .object(["state": .string("signedOut"), "userID": .null, "displayName": .null])
    }

    func accountDeletionDidComplete() async {
        authServices.endLocalAccountSession()
        pendingAcquisitionCandidates.removeAll(keepingCapacity: false)
        pendingPhotoSelections.removeAll(keepingCapacity: false)
        premiumEntitlementService.sessionDidEnd()
        syncCoordinator.sessionDidEnd()
        resetToCurrentProfileIfNeeded()
        let session = TasteMapHybridAuthStateDTO(state: "signedOut", userID: nil, displayName: nil)
        emit(.authChanged, payload: session)
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

    private var presentationController: UIViewController? {
        var controller = presentationWindow?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }

    private static func generatedShareImage(dataURL: String) -> UIImage? {
        let prefix = "data:image/png;base64,"
        guard dataURL.hasPrefix(prefix), dataURL.utf8.count <= 12_000_000,
              let data = Data(base64Encoded: String(dataURL.dropFirst(prefix.count)), options: .ignoreUnknownCharacters),
              data.count <= 9_000_000 else { return nil }
        return UIImage(data: data)
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

private struct HybridShareRequest: Decodable {
    let title: String?
    let text: String?
    let url: String?
    let nativeResourceURL: String?
    let imageDataURL: String?
}

private struct HybridPremiumPurchaseRequest: Decodable {
    let productID: String
}

private struct HybridSyncStatusDTO: Encodable {
    let state: String
    let pendingMutationCount: Int
    let pendingPhotoCount: Int
    let failedPhotoCount: Int
    let conflictCount: Int
    let lastSuccessfulSyncAt: String?
    let errorCode: String?
}

private struct PendingHybridPhotoSelection {
    let ownerUserID: String
    let prepared: PreparedLocalPhoto
}

private struct PendingHybridAcquisitionCandidate {
    let ownerUserID: String
    let candidate: RestaurantCandidate
    let duplicateKind: String
    let existingRestaurantID: String?
    let sharedImportFingerprint: String?
}

@MainActor
private final class HybridPhotoPickerSession: NSObject, PHPickerViewControllerDelegate {
    private let completion: ([PHPickerResult]) -> Void

    init(completion: @escaping ([PHPickerResult]) -> Void) {
        self.completion = completion
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        completion(results)
    }
}

@MainActor
private final class HybridCameraCaptureSession: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let completion: (Data?) -> Void

    init(completion: @escaping (Data?) -> Void) {
        self.completion = completion
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        completion(nil)
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let image = info[.originalImage] as? UIImage
        completion(image?.jpegData(compressionQuality: 0.94))
    }
}

private enum TasteMapHybridResourceError: Error {
    case unsupportedResource, authRequired, notFound
}

private struct TasteMapHybridShareEventPayload: Codable {
    let fingerprint: String
    let target: TasteMapHybridNavigationStateDTO
}

private struct TasteMapHybridLifecycleEventPayload: Codable { let state: TasteMapHybridLifecycleState }
