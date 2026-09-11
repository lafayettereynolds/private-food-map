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

private struct TasteMapHybridCachedMapSurfaceResources {
    let ownerUserID: String
    let photosByID: [UUID: PhotoAsset]
    let photosByReference: [String: PhotoAsset]
    let profileAvatarReference: String?
}

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
    private let locationRequestCoordinator = RestaurantLocationRequestCoordinator()
    private var discoveryLocationProofs = TasteMapDiscoveryLocationProofs()
    private let restaurantSearchService: any RestaurantSearching
    private weak var plugin: TasteMapProductionNativePlugin?
    private weak var mapSurfaceHost: TasteMapHybridMapSurfaceHost?
    private var pendingEvents: [TasteMapHybridEventEnvelope] = []
    private var sequence = 0
    @ObservationIgnored private var storefrontUpdatesTask: Task<Void, Never>?
    private var moderationAccountEpoch = 0
    private var lastLifecycleState: TasteMapHybridLifecycleState?
    private var bridgeControllerStorage: TasteMapHybridBridgeViewController?
    private var cachedBridgeService: TasteMapHybridBridgeService?
    private var cachedBridgeServiceOwnerUserID: String?
    private var cachedBridgeServiceMembershipTier: String?
    private var cachedMapSurfaceResources: TasteMapHybridCachedMapSurfaceResources?
    private let discoveryRefreshCoordinator = TasteMapDiscoveryRefreshCoordinator()
    private let discoveryPageCoordinator = TasteMapDiscoveryPageCoordinator()
    private let discoveryCitySession = TasteMapDiscoveryCitySession()
    private var listService: TasteMapHybridListService?
    private(set) var pendingSharedImport: PendingRestaurantImport?
    private var pendingPhotoSelections: [String: PendingHybridPhotoSelection] = [:]
    private var pendingAcquisitionCandidates: [String: PendingHybridAcquisitionCandidate] = [:]
    private struct AcquisitionSearchPage {
        let owner: String
        let query: String
        let city: String
        let candidates: [RestaurantCandidate]
        let location: TasteMapHybridLocationDTO?
        let expiresAt: Date
    }
    private var acquisitionSearchPages: [String: AcquisitionSearchPage] = [:]
    private var acquisitionSearchGeneration = 0
    private var acquisitionNearbyGeneration = 0
    private var acquisitionLocation: (location: CLLocation, dto: TasteMapHybridLocationDTO)?
    private var acquisitionLocationTask: Task<(location: CLLocation, dto: TasteMapHybridLocationDTO), Error>?
    private var photoPickerSession: HybridPhotoPickerSession?
    private var cameraCaptureSession: HybridCameraCaptureSession?
    private var debugEngagementByVisit: [String: TasteMapHybridCommunityEngagementDTO] = [:]
    private var debugCommentsByVisit: [String: [TasteMapHybridCommunityCommentDTO]] = [:]
    private var debugViewerStateByRestaurant: [String: String] = [:]

    init(
        mode: TasteMapHybridRuntimeMode,
        container: ModelContainer,
        authServices: NativeAuthServices,
        premiumEntitlementService: PremiumEntitlementService,
        syncCoordinator: SyncCoordinator,
        photoFiles: any LocalPhotoFileStoring,
        photoTransferCoordinator: PhotoTransferCoordinator,
        restaurantSearchService: any RestaurantSearching = WorldwideRestaurantSearchService()
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
            self?.mapSurfaceHost?.setRouteAllowsMap(state.route.owner == .hybrid && state.route.surface == .map)
            self?.emit(.navigationRoute, payload: state)
        }
        storefrontUpdatesTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .tasteMapStoreKitProductsChanged) {
                guard !Task.isCancelled else { return }
                self?.emit(.premiumProductsChanged, payload: [String: String]())
            }
        }
    }

    deinit { storefrontUpdatesTask?.cancel() }

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
        let route = navigation.current.route
        mapSurfaceHost.setRouteAllowsMap(route.owner == .hybrid && route.surface == .map)
    }

    func mapSurfaceDidChangeViewport(_ viewport: TasteMapHybridMapViewportDTO) {
        emit(.mapViewportChanged, payload: viewport)
    }

    func mapSurfaceDidSelect(restaurantID: String?) {
        emit(.mapRestaurantSelected, payload: TasteMapHybridMapSelectionEventDTO(restaurantID: restaurantID))
    }

    func mapSurfaceDidSelectGroup(restaurantIDs: [String]) {
        emit(.mapRestaurantGroupSelected, payload: TasteMapHybridMapGroupSelectionEventDTO(restaurantIDs: restaurantIDs))
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
        let envelope = try? JSONDecoder().decode(TasteMapHybridBridgeRequest.self, from: requestData)
        let requestMethod = envelope?.method
        if let envelope, TasteMapHybridBridgeDispatcher.isNavigationMethod(envelope.method) {
            // Navigation only mutates local presentation/history. It never
            // requires session restoration or a data service. Dispatch through
            // the same envelope/capability validation, synchronously before the
            // first await, so independent invoke Tasks cannot reorder intents.
            let dispatcher = TasteMapHybridBridgeDispatcher(
                service: nil, appVersion: "", build: "", dataSource: "native-navigation",
                authState: { TasteMapHybridAuthStateDTO(state: "signedOut", userID: nil, displayName: nil) },
                capabilityOverrides: [.nativeNavigation: true],
                navigationAction: { [unowned self] request in
                    try self.performNavigation(method: request.method, payload: request.payload, sourceRequestID: request.requestId)
                }
            )
            return try JSONEncoder().encode(dispatcher.dispatch(envelope))
        }
        // Every invoke runs in its own Task. Allocate ordering before session
        // restoration suspends, so an older show cannot overtake a newer hide.
        var mapSurfaceRevision: UInt64?
        if requestMethod == .mapSurfaceUpdate, let payload = envelope?.payload,
           let request: TasteMapHybridMapSurfaceUpdateRequest = try? decode(payload) {
            mapSurfaceRevision = mapSurfaceHost?.receiveUpdate(visible: request.visible)
        }
        var authState = await ensureSessionRestored()
        if requestMethod == .contentSnapshot, let userID = authState.userID {
            if let profile = try container.mainContext.fetch(FetchDescriptor<UserProfile>()).first(where: { $0.tasteMapUserID == userID && $0.deletedAt == nil }) {
                try LocalUserProfileStore(context: container.mainContext).synchronizeFootprintVisibility(profile)
            }
            let options: TasteMapHybridContentSnapshotRequest? = envelope.flatMap { request in
                try? decode(request.payload)
            }
            await refreshDiscoveryContentIfNeeded(for: userID, force: options?.forceRefresh == true)
            // Session changes may happen while the three independent requests
            // await. Never project an old owner's snapshot after that boundary.
            authState = await safeSessionState()
        }
        let service = try bridgeService(for: authState)
        if requestMethod == .contentSnapshot, let userID = authState.userID {
            service?.discoveryRefreshStatus = discoveryRefreshCoordinator.snapshot(
                ownerUserID: userID, city: discoveryCity(for: userID), windowDays: 7)
            service?.discoveryEvidenceAvailability = discoveryRefreshCoordinator.evidenceSnapshot(
                ownerUserID: userID, city: discoveryCity(for: userID), windowDays: 7)
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
                .referrals: ReferralInvitationStore.isAvailable,
                .permissions: true,
                .sync: true,
                .backup: true,
                .accountDelete: true,
                .recommendationPreferences: true,
                .share: true,
                .listsRead: true,
                .listShare: true,
                .photoPicker: true,
                .communityInteraction: true,
                .discoveryPage: true,
                .discoveryCityPage: true,
                .restaurantViewerState: true,
            ],
            asynchronousAction: { [weak self] method, payload in
                guard let self else { throw Self.bridgeError("hybrid_runtime_unavailable", recoverable: true) }
                return try await self.perform(method: method, payload: payload, mapSurfaceRevision: mapSurfaceRevision)
            }
        )
        let response = try await dispatcher.responseDataAsync(for: requestData)
        if requestMethod == .visitSave || requestMethod == .visitDelete || requestMethod == .restaurantSetAvatar {
            // These writes can replace the photo set used by native map markers.
            // Keep the bridge service (it invalidates its own projections), but
            // rebuild only the map's small resource index on its next update.
            cachedMapSurfaceResources = nil
        }
        return response
    }

    private func refreshDiscoveryContentIfNeeded(for userID: String, force: Bool) async {
#if DEBUG
        if userID == TasteMapHybridDebugFixture.ownerUserID || TasteMapUITestFixtures.usesVisualQA { return }
#endif
        let city = discoveryCity(for: userID)
        // Only For You supplies the canonical Map/Discovery snapshot. Other
        // tabs already request their own owner/city-bound page on activation.
        // Do not pay for hidden modes on every content.snapshot/Map refresh.
        await refreshDiscoveryMode(.forYou, userID: userID, city: city, force: force)
    }

    private func refreshDiscoveryMode(_ mode: DiscoveryModeV1, userID: String, city: String, force: Bool) async {
        // A failed cache transaction must not mutate the context that owns
        // unsaved editor drafts or replace the last valid on-disk page.
        let cacheContext = ModelContext(container)
        cacheContext.autosaveEnabled = false
        let store = LocalDiscoveryStore(context: cacheContext)
        _ = await discoveryRefreshCoordinator.refresh(
            scope: .init(ownerUserID: userID, mode: mode.rawValue, city: city, windowDays: 7),
            force: force,
            isCurrent: { [weak self] in self?.authServices.localAccountScope == .authenticated(userID) },
            load: { [self] in
                let page = try await authServices.discoveryAPI.page(
                    mode: mode, city: city, trendWindowDays: 7, cursor: nil, limit: 20)
                guard page.mode == mode else { throw SyncAPIError.invalidResponse }
                // A remote failure (including capacity/permission) never
                // masquerades as empty evidence or triggers provider fallback.
                if mode == .forYou, page.items.isEmpty,
                   let provider = try await providerForYouPage(for: userID, city: city) { return provider }
                return page
            },
            save: { page in
                do { try store.replaceCache(page: page, currentUserID: userID, trendWindowDays: 7) }
                catch { cacheContext.rollback(); throw error }
            },
            generatedAt: { $0.generatedAt },
            resolvedCity: { $0.city },
            evidenceAvailability: { $0.evidenceAvailability },
            cachedGeneratedAt: { [self] in
                let resolvedCity = discoveryRefreshCoordinator.snapshot(ownerUserID: userID, city: city, windowDays: 7)[mode.rawValue]?.city ?? city
                return try store.cachedPage(mode: mode, city: resolvedCity, currentUserID: userID, trendWindowDays: 7)
                    .map { ISO8601DateFormatter().string(from: $0.updatedAt) }
            })
    }

    private func discoveryPage(_ payload: TasteMapHybridJSONValue) async throws -> TasteMapHybridJSONValue {
        let request: TasteMapHybridDiscoveryPageRequest
        do { request = try decode(payload) }
        catch { throw Self.bridgeError("invalid_discovery_query", method: .discoveryPage) }
        let authState = await safeSessionState()
        guard authState.state == "authenticated", let userID = authState.userID,
              let service = try bridgeService(for: authState),
              let mode = DiscoveryModeV1(rawValue: request.mode.rawValue) else {
            throw Self.bridgeError("auth_required", method: .discoveryPage)
        }
        let result = try await discoveryPageCoordinator.page(
            ownerUserID: userID, request: request,
            isCurrent: { [weak self] in self?.authServices.localAccountScope == .authenticated(userID) },
            load: { [self] city, cursor in
                let query = try TasteMapDiscoveryAppliedQuery.normalized(mode: mode.rawValue, filters: request.filters, sort: request.sort, preferences: request.preferences)
                try validateDiscoveryReferences(query, owner: userID, continuation: cursor != nil)
                // No profile-city substitution, local filtering, provider
                // fallback or raw-visit cap: these are real server page inputs.
                let page = try await authServices.discoveryAPI.page(
                    mode: mode, city: city, trendWindowDays: request.windowDays, cursor: cursor, limit: 20, query: query)
                return try service.discoveryPageSource(page)
            })
        return try encode(result)
    }

    private func discoveryCityPage(_ payload: TasteMapHybridJSONValue) async throws -> TasteMapHybridJSONValue {
        let request: TasteMapHybridDiscoveryCityPageRequest
        do { request = try decode(payload) }
        catch { throw Self.bridgeError("invalid_discovery_query", method: .discoveryCityPage) }
        let state = await safeSessionState()
        guard state.state == "authenticated", let userID = state.userID,
              let service = try bridgeService(for: state) else { throw Self.bridgeError("auth_required", method: .discoveryCityPage) }
        let result = try await discoveryCitySession.page(ownerUserID: userID, request: request,
            isCurrent: { [weak self] in self?.authServices.localAccountScope == .authenticated(userID) },
            load: { [self] city, cursor in
                let query = try TasteMapDiscoveryAppliedQuery.normalized(mode: request.mode, filters: request.filters, sort: request.sort, preferences: request.preferences)
                try validateDiscoveryReferences(query, owner: userID, continuation: cursor != nil)
#if DEBUG
                if TasteMapUITestFixtures.usesVisualQA {
#if targetEnvironment(simulator)
                    if ProcessInfo.processInfo.environment["TASTEMAP_ALGORITHM_LAB"] == "1" {
                        // Explicit isolated Simulator-only laboratory. Never accepts
                        // a caller-supplied host or sends real auth credentials.
                        let paths = ["for_you": "discovery/for-you", "similar_taste": "discovery/similar-taste", "trending": "discovery/trending", "latest": "community/feed", "following": "community/feed"]
                        guard let path = paths[request.mode] else { throw SyncAPIError.invalidResponse }
                        var url = URLComponents(string: "http://127.0.0.1:4187/api/v1/\(path)")!
                        url.queryItems = [URLQueryItem(name: "city", value: city), URLQueryItem(name: "limit", value: "20"),
                            URLQueryItem(name: "windowDays", value: String(request.windowDays ?? 7)),
                            URLQueryItem(name: "scope", value: request.mode),
                            URLQueryItem(name: "filters", value: try TasteMapDiscoveryAppliedQuery.json(query.filters)),
                            URLQueryItem(name: "sort", value: query.sort),
                            URLQueryItem(name: "preferences", value: try TasteMapDiscoveryAppliedQuery.json(query.preferences))]
                        if let cursor { url.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
                        var localRequest = URLRequest(url: url.url!); localRequest.timeoutInterval = 15
                        let session = URLSession(configuration: .ephemeral)
                        defer { session.invalidateAndCancel() }
                        // Forward the isolated owner's real durable events into
                        // the local test DB; use the same server event contract.
                        let events = try RecommendationPreferenceLedger.load(owner: userID).events
                        struct LabPush: Encodable { let apiVersion = 1; let events: [RecommendationPreferenceEvent] }
                        for start in stride(from: 0, to: events.count, by: 100) {
                            var push = URLRequest(url: URL(string: "http://127.0.0.1:4187/api/v1/recommendation-preferences/push")!)
                            push.httpMethod = "POST"; push.timeoutInterval = 15
                            push.setValue("application/json", forHTTPHeaderField: "Content-Type")
                            push.httpBody = try JSONEncoder().encode(LabPush(events: Array(events[start..<min(start + 100, events.count)])))
                            let (_, response) = try await session.data(for: push)
                            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw SyncAPIError.invalidResponse }
                        }
                        let (data, response) = try await session.data(for: localRequest)
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw SyncAPIError.invalidResponse }
                        if DiscoveryModeV1(rawValue: request.mode) != nil {
                            return try service.discoveryCitySource(JSONDecoder().decode(DiscoveryPageV1.self, from: data))
                        }
                        return try service.communityCitySource(JSONDecoder().decode(CommunityFeedPageV1.self, from: data))
                    }
#endif
                    return try service.debugCitySource(mode: request.mode, city: city, cursor: cursor,
                        windowDays: request.windowDays ?? 7, query: query, limit: 20)
                }
#endif
                if let mode = DiscoveryModeV1(rawValue: request.mode) {
                    let page = try await authServices.discoveryAPI.page(mode: mode, city: city, trendWindowDays: request.windowDays ?? 7, cursor: cursor, limit: 20, query: query)
                    guard page.mode == mode else { throw SyncAPIError.invalidResponse }
                    return try service.discoveryCitySource(page)
                }
                guard let scope = CommunityFeedScopeV1(rawValue: request.mode) else { throw SyncAPIError.invalidResponse }
                let page = try await authServices.communityAPI.feed(scope: scope, city: city, cursor: cursor, limit: 20, query: query)
                guard page.scope == scope else { throw SyncAPIError.invalidResponse }
                return try service.communityCitySource(page)
            })
        return try encode(result)
    }

    private var discoveryLocationCity: (owner: String, city: String, timestamp: Date)?

    private func discoveryCity(for userID: String) -> String {
        if let current = discoveryLocationCity, current.owner == userID, Date().timeIntervalSince(current.timestamp) < 300 { return current.city }
        let context = container.mainContext
        if let profileCity = try? context.fetch(FetchDescriptor<UserProfile>()).first(where: {
            $0.tasteMapUserID == userID && $0.deletedAt == nil && !$0.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.city {
            return Self.canonicalDiscoveryCity(profileCity)
        }

        let restaurants = ((try? context.fetch(FetchDescriptor<Restaurant>())) ?? []).filter {
            $0.ownerUserID == userID && $0.deletedAt == nil
        }
        let restaurantByID = Dictionary(uniqueKeysWithValues: restaurants.map { ($0.id, $0) })
        let recentVisits = ((try? context.fetch(FetchDescriptor<Visit>())) ?? [])
            .filter { $0.ownerUserID == userID && $0.deletedAt == nil }
            .sorted { $0.visitedAt > $1.visitedAt }
        let recentCity = recentVisits.lazy.compactMap { visit -> String? in
            guard let value = restaurantByID[visit.restaurantId]?.city.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }.first ?? ""
        return Self.canonicalDiscoveryCity(recentCity)
    }

    private static func canonicalDiscoveryCity(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 2, trimmed.hasSuffix("市") else { return trimmed }
        return String(trimmed.dropLast())
    }

    private func providerForYouPage(
        for userID: String,
        city: String
    ) async throws -> DiscoveryPageV1? {
        let context = container.mainContext
        let restaurants = ((try? context.fetch(FetchDescriptor<Restaurant>())) ?? []).filter {
            $0.ownerUserID == userID && $0.deletedAt == nil
        }
        let restaurantByID = Dictionary(uniqueKeysWithValues: restaurants.map { ($0.id, $0) })
        let visits = ((try? context.fetch(FetchDescriptor<Visit>())) ?? [])
            .filter { $0.ownerUserID == userID && $0.deletedAt == nil }
            .sorted { $0.visitedAt > $1.visitedAt }

        var latestRatingByRestaurantID: [UUID: Double] = [:]
        var orderedRatedRestaurants: [(restaurant: Restaurant, rating: Double)] = []
        for visit in visits {
            guard latestRatingByRestaurantID[visit.restaurantId] == nil,
                  let rating = visit.rating,
                  rating.isFinite,
                  rating > 0,
                  rating <= 5,
                  let restaurant = restaurantByID[visit.restaurantId] else { continue }
            latestRatingByRestaurantID[visit.restaurantId] = rating
            orderedRatedRestaurants.append((restaurant, rating))
        }
        guard orderedRatedRestaurants.count >= 3 else { return nil }

        let originRestaurant = orderedRatedRestaurants.first?.restaurant
        let origin = originRestaurant.map {
            RestaurantCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }.flatMap { $0.isValid ? $0 : nil }
        let preference = Self.discoveryPreference(from: orderedRatedRestaurants)
        let candidates = try await restaurantSearchService.search(
            query: Self.discoverySearchTerm(for: preference.category),
            scope: RestaurantSearchScope(
                city: origin == nil ? city : "",
                center: origin,
                radiusMeters: 30_000
            )
        )
        let visible = candidates.filter { candidate in
            !restaurants.contains { restaurant in
                let sameName = Self.normalizedRestaurantName(restaurant.name)
                    == Self.normalizedRestaurantName(candidate.name)
                guard sameName else { return false }
                let existing = RestaurantCoordinate(
                    latitude: restaurant.latitude,
                    longitude: restaurant.longitude
                )
                return existing.isValid && RestaurantDistanceOrdering.distance(
                    from: existing,
                    to: candidate.coordinate
                ) < 300
            }
        }
        guard !visible.isEmpty else { return nil }

        let emptyRating = DiscoveryRatingProjectionV1(value: nil, sampleCount: 0)
        let ratings = DiscoveryRatingsV1(
            mine: emptyRating,
            community: emptyRating,
            friends: emptyRating,
            similarTaste: emptyRating
        )
        let reasonText: String
        if preference.category == .other {
            reasonText = "基于你已评分的 \(orderedRatedRestaurants.count) 家餐厅和常用区域推测"
        } else {
            reasonText = "基于你已评分的 \(orderedRatedRestaurants.count) 家餐厅、常用区域和\(Self.discoveryCategoryTitle(preference.category))偏好推测"
        }
        let cards = Array(visible.prefix(20)).enumerated().map { index, candidate in
            let identities = candidate.placeIdentities.map {
                DiscoveryPlaceIdentityV1(
                    provider: $0.provider,
                    externalId: $0.externalID,
                    isPrimary: $0.isPrimary
                )
            }
            let primary = identities.first(where: \.isPrimary) ?? identities.first
            let globalKey = primary.map { "\($0.provider.rawValue):\($0.externalId)" }
                ?? "provider:\(candidate.id.uuidString.lowercased())"
            let distance = candidate.distanceMeters ?? origin.map {
                RestaurantDistanceOrdering.distance(from: $0, to: candidate.coordinate)
            }
            let proximity = distance.map { max(0, 1 - min($0, 30_000) / 30_000) } ?? 0
            let maturity = min(8, Double(orderedRatedRestaurants.count) * 0.4)
            let categoryEvidence = preference.category == .other ? 0 : preference.strength * 8
            let percent = Int(min(93, max(70, 70 + maturity + categoryEvidence + proximity * 6)).rounded())
            let projection = DiscoveryRestaurantProjectionV1(
                globalKey: globalKey,
                placeIdentities: identities,
                name: candidate.name,
                address: candidate.address,
                city: candidate.city.isEmpty ? city : Self.canonicalDiscoveryCity(candidate.city),
                latitude: candidate.latitude,
                longitude: candidate.longitude,
                tags: candidate.categoryHints,
                pricePerPerson: nil,
                merchantImageUrl: candidate.photoURL?.absoluteString,
                markerEmoji: "",
                photo: nil,
                phone: candidate.phone,
                websiteUrl: candidate.websiteURL?.absoluteString,
                openingHours: candidate.openingHours
            )
            return DiscoveryCardV1(
                id: "for_you:\(globalKey)",
                mode: .forYou,
                restaurant: projection,
                viewerState: .none,
                ratings: ratings,
                reasons: [DiscoveryReasonV1(code: "PROVIDER_HISTORY_MATCH", text: reasonText)],
                sourceUser: nil,
                similarity: nil,
                trend: nil,
                cacheScope: .public,
                rank: index + 1,
                score: Double(percent) * 1_000 - (distance ?? 30_000) / 1_000,
                personalTastePercent: percent
            )
        }
        return DiscoveryPageV1(
            apiVersion: 1,
            mode: .forYou,
            city: city,
            personalizationConfidence: orderedRatedRestaurants.count >= 8 ? .high : .medium,
            generatedAt: Self.dateFormatter.string(from: .now),
            items: cards,
            nextCursor: nil
        )
    }

    private static func discoveryPreference(
        from history: [(restaurant: Restaurant, rating: Double)]
    ) -> (category: FoodCategoryVisualID, strength: Double) {
        var scores: [FoodCategoryVisualID: Double] = [:]
        for value in history where value.rating >= DiscoveryEvidencePolicy.minimumQualifiedRatingOutOfFive {
            let category = FoodCategoryVisualResolver.resolve(name: value.restaurant.name)
            guard category != .other else { continue }
            scores[category, default: 0] += max(0.5, value.rating - 3)
        }
        guard let best = scores.max(by: { left, right in
            left.value == right.value
                ? left.key.rawValue > right.key.rawValue
                : left.value < right.value
        }) else { return (.other, 0) }
        let total = scores.values.reduce(0, +)
        return (best.key, total > 0 ? best.value / total : 0)
    }

    private static func discoverySearchTerm(for category: FoodCategoryVisualID) -> String {
        switch category {
        case .chinese: "中餐"
        case .japaneseKorean: "日料"
        case .western: "西餐"
        case .hotpotBBQ: "火锅 烧烤"
        case .noodles: "面馆"
        case .cafeBakery: "咖啡 烘焙"
        case .drinksDessert: "甜品"
        case .seafood: "海鲜"
        case .fastFood: "小吃"
        case .vegetarianLight: "轻食"
        case .other: "餐厅"
        }
    }

    private static func discoveryCategoryTitle(_ category: FoodCategoryVisualID) -> String {
        switch category {
        case .chinese: "中餐"
        case .japaneseKorean: "日料与韩餐"
        case .western: "西餐"
        case .hotpotBBQ: "火锅与烧烤"
        case .noodles: "面食"
        case .cafeBakery: "咖啡与烘焙"
        case .drinksDessert: "甜品饮品"
        case .seafood: "海鲜"
        case .fastFood: "小吃快餐"
        case .vegetarianLight: "轻食"
        case .other: "餐饮"
        }
    }

    private static func normalizedRestaurantName(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "zh_CN")
            )
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private func bridgeService(
        for authState: TasteMapHybridAuthStateDTO
    ) throws -> TasteMapHybridBridgeService? {
        guard authState.state == "authenticated", let userID = authState.userID else {
            invalidateBridgeReadCaches()
            return nil
        }
        let membershipTier = [.premium, .gracePeriod].contains(premiumEntitlementService.membershipStatus)
            ? "member"
            : "free"
        if cachedBridgeServiceOwnerUserID == userID,
           cachedBridgeServiceMembershipTier == membershipTier,
           let cachedBridgeService {
            return cachedBridgeService
        }
        let service = try TasteMapHybridBridgeService(
            container: container,
            ownerUserID: userID,
            membershipTier: membershipTier,
            enqueueSharedMealInvitations: { [authServices = self.authServices] sourceVisitID, participantUserIDs in
                try authServices.socialCollaborationOutbox.enqueue(
                    ownerUserID: userID,
                    sourceVisitID: sourceVisitID,
                    participantUserIDs: participantUserIDs
                )
            },
            attachPendingPhotos: { [weak self] attachments, restaurantID, visitID, dishIDsByDraftID, _ in
                guard let self else { return attachments.count }
                let profile = try? self.container.mainContext.fetch(FetchDescriptor<UserProfile>()).first(where: { $0.tasteMapUserID == userID && $0.deletedAt == nil })
                return self.attachPendingPhotos(
                    attachments,
                    restaurantID: restaurantID,
                    visitID: visitID,
                    dishIDsByDraftID: dishIDsByDraftID,
                    visibility: PhotoVisibility(rawValue: profile?.visibility.rawValue ?? "private") ?? .private,
                    ownerUserID: userID
                )
            }
        )
        cachedBridgeService = service
        service.didDeleteRestaurantWithVisit = { [weak self] restaurantIDs, visitIDs in
            guard let self, self.cachedBridgeServiceOwnerUserID == userID else { return }
            self.navigation.completeVisitDeletion(restaurantIDs: restaurantIDs, visitIDs: visitIDs)
        }
        service.sessionRestaurantReference = { [weak self] id in
            guard let self, self.authServices.localAccountScope == .authenticated(userID) else { return nil }
            return self.discoveryCitySession.reference(id, ownerUserID: userID)
        }
        cachedBridgeServiceOwnerUserID = userID
        cachedBridgeServiceMembershipTier = membershipTier
        return service
    }

    private func invalidateBridgeReadCaches() {
        cachedBridgeService = nil
        cachedBridgeServiceOwnerUserID = nil
        cachedBridgeServiceMembershipTier = nil
        cachedMapSurfaceResources = nil
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
        if url.scheme == "tastemap-resource", url.host == "directory-avatar" {
            guard case .authenticated(let owner) = authServices.localAccountScope,
                  url.pathComponents.count == 4,
                  url.pathComponents[1] == owner else { throw TasteMapHybridResourceError.authRequired }
            let kind = url.pathComponents[2], id = url.pathComponents[3]
            guard ["companion","source"].contains(kind), let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))) else { throw TasteMapHybridResourceError.notFound }
            let data = try await authServices.premiumAPI.directoryRequest(path: "/api/v1/directory/avatar/\(kind)/\(encoded)")
            guard authServices.localAccountScope == .authenticated(owner) else { throw TasteMapHybridResourceError.authRequired }
            return (data,"image/jpeg")
        }
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
        func isLocallyDeleted() throws -> Bool {
            try container.mainContext.fetch(FetchDescriptor<PhotoAsset>()).contains {
                $0.ownerUserID == ownerUserID && $0.deletedAt != nil &&
                    ($0.id.uuidString.caseInsensitiveCompare(identifier) == .orderedSame ||
                     $0.remoteID?.caseInsensitiveCompare(identifier) == .orderedSame)
            }
        }
        guard try !isLocallyDeleted() else { throw TasteMapHybridResourceError.notFound }
        // Use the coordinator's context so downloaded cache paths are persisted
        // on the same owner-scoped model, rather than a detached read context.
        let context = container.mainContext
        let ownedPhoto = try context.fetch(FetchDescriptor<PhotoAsset>()).first(where: {
            $0.ownerUserID == ownerUserID
                && $0.deletedAt == nil
                && $0.binaryDeletedAt == nil
                && ($0.id.uuidString.caseInsensitiveCompare(identifier) == .orderedSame
                    || $0.remoteID?.caseInsensitiveCompare(identifier) == .orderedSame)
        })
        if let ownedPhoto {
            let variant = PhotoBinaryVariant(rawValue: parts[2]) ?? .thumbnail
            let data = try await photoTransferCoordinator.imageData(for: ownedPhoto, variant: variant)
            guard authServices.localAccountScope == .authenticated(ownerUserID),
                  ownedPhoto.ownerUserID == ownerUserID,
                  ownedPhoto.deletedAt == nil, ownedPhoto.binaryDeletedAt == nil,
                  try !isLocallyDeleted() else { throw TasteMapHybridResourceError.notFound }
            return (data, Self.imageMimeType(data))
        }

        guard parts[0] == "public-photo",
              (discoveryCitySession.permitsPhoto(identifier, ownerUserID: ownerUserID) || Self.isOwnerVisibleCachedPhoto(
                identifier,
                ownerUserID: ownerUserID,
                context: context
              )),
              let remoteID = UUID(uuidString: identifier) else {
            throw TasteMapHybridResourceError.notFound
        }
        let variant = PhotoBinaryVariant(rawValue: parts[2]) ?? .thumbnail
        let data = try await authServices.photoAPI.download(photoID: remoteID, variant: variant)
        guard try !isLocallyDeleted() else { throw TasteMapHybridResourceError.notFound }
        guard authServices.localAccountScope == .authenticated(ownerUserID),
              discoveryCitySession.permitsPhoto(identifier, ownerUserID: ownerUserID)
                || Self.isOwnerVisibleCachedPhoto(identifier, ownerUserID: ownerUserID, context: context) else {
            throw TasteMapHybridResourceError.notFound
        }
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

        let discoveryActivityContainsPhoto = ((try? context.fetch(FetchDescriptor<CachedDiscoveryPlacement>())) ?? [])
            .contains { cached in
                guard cached.currentUserID == ownerUserID, cached.mode == .similarTaste,
                      let value = cached.context, let activity = value.activity,
                      let authorID = value.sourceUser?.userId else { return false }
                return DiscoveryPhotoProjectionV1.activityAlbum(activity.photos, visitID: activity.visitId, authorID: authorID)?
                    .contains { $0.photoId.lowercased() == normalized } == true
            }
        if discoveryActivityContainsPhoto { return true }

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
            try? PendingRestaurantImportStore.live().markPresented(id: sharedImport.id)
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
        if state == .background { acquisitionNearbyGeneration += 1 }
        if eventState == .resume || eventState == .memoryWarning {
            invalidateBridgeReadCaches()
        }
        emit(.appLifecycle, payload: TasteMapHybridLifecycleEventPayload(state: eventState))
    }

    private func performNavigation(
        method: TasteMapHybridBridgeMethod,
        payload: TasteMapHybridJSONValue,
        sourceRequestID: String?
    ) throws -> TasteMapHybridJSONValue {
        switch method {
        case .navigationOpenNative:
            let request: TasteMapHybridNativeRouteRequest = try decode(payload)
            let route = try TasteMapHybridRouteDTO(surface: request.route, identifier: request.identifier)
            guard route.owner == .native else {
                throw Self.bridgeError("hybrid_route_requires_openHybrid", method: .navigationOpenNative)
            }
            return try encode(navigation.openNative(route, sourceRequestID: sourceRequestID))
        case .navigationOpenHybrid:
            let route: TasteMapHybridRouteDTO = try decode(payload)
            let options: TasteMapHybridNavigationOpenOptions = try decode(payload)
            return try encode(navigation.openHybrid(route, sourceRequestID: sourceRequestID, replaceCurrent: options.replaceCurrent == true))
        case .navigationBack:
            return try encode(navigation.back(sourceRequestID: sourceRequestID))
        case .navigationCurrent:
            return try encode(navigation.current)
        default:
            throw Self.bridgeError("invalid_navigation_method", method: method)
        }
    }

    private func perform(
        method: TasteMapHybridBridgeMethod,
        payload: TasteMapHybridJSONValue,
        mapSurfaceRevision: UInt64?
    ) async throws -> TasteMapHybridJSONValue {
        switch method {
        case .discoveryPage:
            return try await discoveryPage(payload)
        case .discoveryCityPage:
            return try await discoveryCityPage(payload)
        case .recommendationsPreference:
            guard case .authenticated(let owner) = authServices.localAccountScope else {
                throw Self.bridgeError("auth_required", method: method)
            }
            struct PreferenceRequest: Decodable { let restaurantID: String? }
            struct PreferenceResult: Encodable {
                let ownerID: String
                let excludedIDs: [String]
                let intentFeedback: RestaurantRecommendationIntentFeedback?
            }
            let request: PreferenceRequest = try decode(payload)
            let preference = try RestaurantRecommendationPreferences.snapshot(
                ownerID: owner, context: container.mainContext, adding: request.restaurantID,
                authorizedSessionIdentityGroups: discoveryCitySession.identityGroups(ownerUserID: owner),
                authorizedSessionMetadata: discoveryCitySession.recommendationIntentMetadata(ownerUserID: owner)
            )
            return try encode(PreferenceResult(ownerID: owner, excludedIDs: preference.excludedIDs,
                                               intentFeedback: preference.intentFeedback))
        case .authSignInWithApple:
            return try await signInWithApple()
        case .authLogout:
            return await logout()
        case .communitySetLike:
            return try await setCommunityLike(payload)
        case .listsGet, .listsCreateShareLink:
            guard case .authenticated(let owner) = authServices.localAccountScope else {
                throw Self.bridgeError("auth_required", method: method, recoverable: true)
            }
            if listService?.ownerUserID != owner {
                listService = TasteMapHybridListService(
                    container: container, ownerUserID: owner, api: authServices.restaurantListAPI,
                    sharing: authServices.publicSharingAPI, currentOwner: { [weak self] in
                        guard case .authenticated(let current) = self?.authServices.localAccountScope else { return nil }
                        return current
                    })
            }
            let request: TasteMapHybridListGetRequest = try decode(payload)
            if method == .listsGet { return try encode(await listService!.get(request)) }
            return try encode(await listService!.createShareLink(id: request.id))
        case .communityComments:
            return try await communityComments(payload)
        case .communitySafety, .communityReport, .communityBlock, .communityDeleteComment:
            return try await moderateCommunity(method, payload: payload)
        case .communityAddComment:
            return try await addCommunityComment(payload)
        case .restaurantSetWantToGo:
            return try setRestaurantWantToGo(payload)
        case .restaurantSetAvatar:
            return try await setRestaurantAvatar(payload)
        case .navigationOpenNative, .navigationOpenHybrid, .navigationBack, .navigationCurrent:
            return try performNavigation(method: method, payload: payload, sourceRequestID: nil)
        case .locationCurrent:
            return try await currentLocation()
        case .mapSurfaceUpdate:
            return try updateMapSurface(payload, revision: mapSurfaceRevision)
        case .acquisitionSearch:
            return try await searchRestaurants(payload)
        case .acquisitionNearby:
            return try await nearbyRestaurants()
        case .acquisitionShared:
            return try await sharedRestaurantCandidates()
        case .acquisitionManual:
            return try await manualRestaurantCandidate(payload)
        case .acquisitionSelect:
            let result = try selectRestaurantCandidate(payload)
            invalidateBridgeReadCaches()
            return result
        case .premiumTrialEligibility:
            await premiumEntitlementService.refreshTrialEligibility()
            guard let result = premiumEntitlementService.trialEligibility else { throw Self.bridgeError("unavailable", method: method) }
            return try encode(result)
        case .premiumClaimTrial:
            let result = try await premiumEntitlementService.claimTrial()
            return .object(["expiresAt": .string(result.expiresAt), "status": premiumStatus()])
        case .premiumStatus:
            await premiumEntitlementService.refresh()
            return premiumStatus()
        case .directorySearchUsers:
            guard case .authenticated(let owner)=authServices.localAccountScope,
                  case .object(let fields)=payload,case .string(let query)=fields["query"],query.count>=2 else { throw Self.bridgeError("invalid_request",method:method) }
            let page=try await authServices.socialAPI.search(query:query,cursor:nil,limit:20)
            guard authServices.localAccountScope == .authenticated(owner) else { throw Self.bridgeError("account_changed",method:method) }
            return try encode(page.items.map { PrivateDirectoryDashboard.Person(id:$0.profile.userId,displayName:$0.profile.displayName) })
        case .directoryDashboard, .directoryMutate, .directoryRespond:
            guard case .authenticated(let owner) = authServices.localAccountScope else { throw Self.bridgeError("auth_required",method:method) }
            if method == .directoryDashboard {
                await syncCoordinator.synchronizeNow()
                var result = try await authServices.premiumAPI.directoryDashboard(userID: owner)
                guard authServices.localAccountScope == .authenticated(owner) else { throw Self.bridgeError("account_changed",method:method) }
                for index in result.entries.indices where result.entries[index].avatarURL != nil {
                    let entry = result.entries[index]
                    let encoded = entry.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn:"/?#%"))) ?? ""
                    let revision = entry.avatarURL?.components(separatedBy:"?").dropFirst().joined(separator:"?") ?? ""
                    result.entries[index].avatarURL = "tastemap-resource://directory-avatar/\(owner)/\(entry.kind)/\(encoded)?\(revision)"
                }
                return try encode(result)
            }
            let encodedPayload = try JSONEncoder().encode(payload)
            guard var body = try JSONSerialization.jsonObject(with: encodedPayload) as? [String:Any] else { throw Self.bridgeError("invalid_request",method:method) }
            var endpoint = "/api/v1/directory"
            if method == .directoryRespond {
                guard let id=body["id"] as? String, let escaped=id.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed.subtracting(CharacterSet(charactersIn:"/?#%"))) else { throw Self.bridgeError("invalid_request",method:method) }
                endpoint = "/api/v1/social/companion-links/\(escaped)"
            } else if body["action"] as? String == "avatar" {
                if let id=body["photoID"] as? String {
                    guard let pending=pendingPhotoSelections[id],pending.ownerUserID==owner else { throw Self.bridgeError("photo_not_found",method:method) }
                    let bytes=try await photoFiles.load(relativePath:pending.prepared.thumbnailFileRelativePath)
                    body["avatarData"]=try PrivateDirectoryAvatar.encoded(bytes)
                } else { body["avatarData"]=NSNull() }
            }
            guard authServices.localAccountScope == .authenticated(owner) else { throw Self.bridgeError("account_changed",method:method) }
            _ = try await authServices.premiumAPI.directoryRequest(path:endpoint,body:JSONSerialization.data(withJSONObject:body))
            guard authServices.localAccountScope == .authenticated(owner) else { throw Self.bridgeError("account_changed",method:method) }
            if let id=body["photoID"] as? String { _ = try? await discardPhoto(.object(["photoID":.string(id)])) }
            await syncCoordinator.synchronizeNow()
            return .object(["saved":.bool(true)])
        case .referralsDashboard:
            guard ReferralInvitationStore.isAvailable else {
                throw Self.bridgeError("capability_unavailable", method: .referralsDashboard)
            }
            guard case .authenticated(let owner) = authServices.localAccountScope else {
                throw Self.bridgeError("auth_required", method: .referralsDashboard)
            }
            let result = try await authServices.premiumAPI.referralDashboard(userID: owner)
            guard authServices.localAccountScope == .authenticated(owner), result.userID == owner else {
                throw Self.bridgeError("account_changed", method: .referralsDashboard)
            }
            return try encode(result)
        case .referralsPrepareRegistration:
            guard ReferralInvitationStore.isAvailable else {
                throw Self.bridgeError("capability_unavailable", method: .referralsPrepareRegistration)
            }
            guard authServices.localAccountScope == .guest else {
                throw Self.bridgeError("new_account_only", method: .referralsPrepareRegistration)
            }
            let request: ReferralRegistrationPayload = try decode(payload)
            try ReferralInvitationStore.prepare(request.code)
            return .object(["prepared": .bool(true)])
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
            await syncCoordinator.retryNow()
            invalidateBridgeReadCaches()
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
            let result = try await discardPhoto(payload)
            localDataDidChange(reason: "photoDeleted")
            return result
        case .photoRetry:
            let result = try retryPhoto(payload)
            invalidateBridgeReadCaches()
            return result
        default:
            throw Self.bridgeError("capability_unavailable", method: method)
        }
    }

    private func updateMapSurface(_ payload: TasteMapHybridJSONValue, revision: UInt64?) throws -> TasteMapHybridJSONValue {
        let request: TasteMapHybridMapSurfaceUpdateRequest = try decode(payload)
        guard case .authenticated(let ownerUserID) = authServices.localAccountScope else {
            throw Self.bridgeError("auth_required", method: .mapSurfaceUpdate, recoverable: true)
        }
        guard let mapSurfaceHost else {
            throw Self.bridgeError("native_map_surface_unavailable", method: .mapSurfaceUpdate, recoverable: true)
        }
        guard let revision else {
            throw Self.bridgeError("native_map_surface_unavailable", method: .mapSurfaceUpdate, recoverable: true)
        }
        if !request.visible {
            try mapSurfaceHost.apply(
                request,
                revision: revision,
                resources: TasteMapHybridMapSurfaceResources(
                    photosByID: [:],
                    userAvatarPhoto: nil,
                    photoCoordinator: photoTransferCoordinator,
                    photoAPI: authServices.photoAPI
                )
            )
            return try encode(TasteMapHybridMapSurfaceUpdateResponse(requestID: request.requestID))
        }
        let cachedResources = mapSurfaceResources(ownerUserID: ownerUserID)
        let avatarReference = request.userAvatarPhotoID ?? cachedResources.profileAvatarReference
        let avatarPhoto = avatarReference.flatMap {
            cachedResources.photosByReference[$0.lowercased()]
        }
        try mapSurfaceHost.apply(
            request,
            revision: revision,
            resources: TasteMapHybridMapSurfaceResources(
                photosByID: cachedResources.photosByID,
                userAvatarPhoto: avatarPhoto,
                photoCoordinator: photoTransferCoordinator,
                photoAPI: authServices.photoAPI
            )
        )
        return try encode(TasteMapHybridMapSurfaceUpdateResponse(requestID: request.requestID))
    }

    private func mapSurfaceResources(ownerUserID: String) -> TasteMapHybridCachedMapSurfaceResources {
        if let cachedMapSurfaceResources, cachedMapSurfaceResources.ownerUserID == ownerUserID {
            return cachedMapSurfaceResources
        }
        let photos = ((try? container.mainContext.fetch(FetchDescriptor<PhotoAsset>())) ?? []).filter {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil && $0.binaryDeletedAt == nil
        }
        var photosByReference: [String: PhotoAsset] = [:]
        for photo in photos {
            photosByReference[photo.id.uuidString.lowercased()] = photo
            if let remoteID = photo.remoteID?.lowercased() { photosByReference[remoteID] = photo }
        }
        let profile = ((try? container.mainContext.fetch(FetchDescriptor<UserProfile>())) ?? []).first {
            $0.tasteMapUserID == ownerUserID && $0.deletedAt == nil
        }
        let resources = TasteMapHybridCachedMapSurfaceResources(
            ownerUserID: ownerUserID,
            photosByID: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) }),
            photosByReference: photosByReference,
            profileAvatarReference: profile?.avatarPhotoID
        )
        cachedMapSurfaceResources = resources
        return resources
    }

    private func setCommunityLike(_ payload: TasteMapHybridJSONValue) async throws -> TasteMapHybridJSONValue {
        let request: TasteMapHybridLikeRequest = try decode(payload)
#if DEBUG
        if TasteMapUITestFixtures.usesVisualQA {
            try validateDebugInteractionTarget(request.target)
            let current = debugEngagement(request.target.visitID)
            let count = max(0, current.likeCount + (request.liked == current.likedByViewer ? 0 : request.liked ? 1 : -1))
            let result = TasteMapHybridCommunityEngagementDTO(
                likedByViewer: request.liked, likeCount: count, commentCount: current.commentCount
            )
            debugEngagementByVisit[request.target.visitID] = result
            return try encode(result)
        }
#endif
        try validateInteractionTarget(request.target)
        let result = try await authServices.socialCollaborationAPI.setLike(
            request.liked, visitID: request.target.visitID
        )
        try cacheEngagement(
            visitID: request.target.visitID, likedByViewer: result.likedByViewer,
            likeCount: result.likeCount, commentCount: result.commentCount
        )
        return try encode(TasteMapHybridCommunityEngagementDTO(
            likedByViewer: result.likedByViewer,
            likeCount: result.likeCount,
            commentCount: result.commentCount
        ))
    }

    private func communityComments(_ payload: TasteMapHybridJSONValue) async throws -> TasteMapHybridJSONValue {
        let request: TasteMapHybridInteractionRequest = try decode(payload)
#if DEBUG
        if TasteMapUITestFixtures.usesVisualQA {
            try validateDebugInteractionTarget(request.target)
            return try encode(TasteMapHybridCommunityCommentPageDTO(
                items: debugComments(request.target.visitID), nextCursor: nil
            ))
        }
#endif
        try validateInteractionTarget(request.target)
        let page = try await authServices.socialCollaborationAPI.comments(
            visitID: request.target.visitID, cursor: nil, limit: 20
        )
        return try encode(TasteMapHybridCommunityCommentPageDTO(
            items: page.items.map(communityCommentDTO), nextCursor: page.nextCursor
        ))
    }

    private func addCommunityComment(_ payload: TasteMapHybridJSONValue) async throws -> TasteMapHybridJSONValue {
        let request: TasteMapHybridAddCommentRequest = try decode(payload)
        let body = request.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 280 else {
            throw Self.bridgeError("invalid_comment", method: .communityAddComment, recoverable: true)
        }
#if DEBUG
        if TasteMapUITestFixtures.usesVisualQA {
            try validateDebugInteractionTarget(request.target)
            let profile = ((try? container.mainContext.fetch(FetchDescriptor<UserProfile>())) ?? []).first {
                authServices.localAccountScope.contains(ownerUserID: $0.tasteMapUserID) && $0.deletedAt == nil
            }
            let comment = TasteMapHybridCommunityCommentDTO(
                id: UUID().uuidString.lowercased(), visitID: request.target.visitID, body: body,
                author: .init(
                    id: profile?.tasteMapUserID ?? "tm_hybrid_debug",
                    name: profile?.displayName ?? "Lafayette", city: profile?.city,
                    avatarPhotoID: profile?.avatarPhotoID,
                    avatarPresetID: profile?.avatarPreset.rawValue ?? "otter", isFollowing: false
                ),
                createdAt: ISO8601DateFormatter().string(from: .now)
            )
            var comments = debugComments(request.target.visitID)
            comments.append(comment)
            debugCommentsByVisit[request.target.visitID] = comments
            let current = debugEngagement(request.target.visitID)
            let engagement = TasteMapHybridCommunityEngagementDTO(
                likedByViewer: current.likedByViewer, likeCount: current.likeCount,
                commentCount: current.commentCount + 1
            )
            debugEngagementByVisit[request.target.visitID] = engagement
            return try encode(TasteMapHybridCommunityCommentMutationDTO(
                likedByViewer: engagement.likedByViewer, likeCount: engagement.likeCount,
                commentCount: engagement.commentCount, comment: comment
            ))
        }
#endif
        try validateInteractionTarget(request.target)
        let result = try await authServices.socialCollaborationAPI.addComment(
            visitID: request.target.visitID, body: body
        )
        let likedByViewer = cachedEngagement(visitID: request.target.visitID)?.likedByViewer ?? false
        try cacheEngagement(
            visitID: request.target.visitID, likedByViewer: likedByViewer,
            likeCount: result.likeCount, commentCount: result.commentCount
        )
        return try encode(TasteMapHybridCommunityCommentMutationDTO(
            likedByViewer: likedByViewer, likeCount: result.likeCount, commentCount: result.commentCount,
            comment: communityCommentDTO(result.comment)
        ))
    }

    private func setRestaurantWantToGo(_ payload: TasteMapHybridJSONValue) throws -> TasteMapHybridJSONValue {
        let request: TasteMapHybridRestaurantViewerStateRequest = try decode(payload)
#if DEBUG
        if TasteMapUITestFixtures.usesVisualQA {
            let state = request.wanted ? "want_to_go" : "none"
            debugViewerStateByRestaurant[request.restaurantID] = state
            invalidateBridgeReadCaches()
            return try encode(TasteMapHybridRestaurantViewerStateMutationDTO(
                restaurantID: request.restaurantID, viewerState: state,
                updatedAt: ISO8601DateFormatter().string(from: .now)
            ))
        }
#endif
        guard case .authenticated(let ownerUserID) = authServices.localAccountScope,
              let reference = try discoveryCitySession.reference(request.restaurantID, ownerUserID: ownerUserID) ?? TasteMapHybridRestaurantReferenceResolver.resolve(
                identifier: request.restaurantID, ownerUserID: ownerUserID, context: container.mainContext
              ) else {
            throw Self.bridgeError("restaurant_not_found", method: .restaurantSetWantToGo, recoverable: true)
        }
        let context = container.mainContext
        let store = LocalDiscoveryStore(context: context)
        let restaurants = try context.fetch(FetchDescriptor<Restaurant>()).filter {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil
        }
        let state: DiscoveryViewerRestaurantStateV1
        if reference.viewerState == .visited {
            state = .visited
        } else if request.wanted {
            _ = try store.addToWantToGo(
                projection: reference.projection, among: restaurants, currentUserID: ownerUserID
            )
            state = .wantToGo
        } else {
            if let local = store.localRestaurant(for: reference.projection, among: restaurants), local.status != .visited {
                try LocalTasteMapStore(context: context).delete(local, actorUserID: ownerUserID)
            }
            state = .none
        }
        try store.updateViewerState(
            globalKey: reference.projection.globalKey, currentUserID: ownerUserID, state: state
        )
        try LocalCommunityStore(context: context).updateViewerState(
            globalKey: reference.projection.globalKey, currentUserID: ownerUserID, state: state
        )
        invalidateBridgeReadCaches()
        Task { await syncCoordinator.synchronizeNow() }
        return try encode(TasteMapHybridRestaurantViewerStateMutationDTO(
            restaurantID: request.restaurantID, viewerState: state.rawValue,
            updatedAt: ISO8601DateFormatter().string(from: .now)
        ))
    }

    private func setRestaurantAvatar(_ payload: TasteMapHybridJSONValue) async throws -> TasteMapHybridJSONValue {
        let request: TasteMapHybridRestaurantAvatarRequest = try decode(payload)
        guard case .authenticated(let ownerUserID) = authServices.localAccountScope else {
            throw Self.bridgeError("auth_required", method: .restaurantSetAvatar)
        }
        let context = container.mainContext
        guard let restaurant = try context.fetch(FetchDescriptor<Restaurant>()).first(where: {
            $0.ownerUserID == ownerUserID && $0.deletedAt == nil && (
                $0.remoteID?.caseInsensitiveCompare(request.restaurantID) == .orderedSame ||
                $0.id.uuidString.caseInsensitiveCompare(request.restaurantID) == .orderedSame
            )
        }) else {
            throw Self.bridgeError("restaurant_not_found", method: .restaurantSetAvatar, recoverable: true)
        }

        let metadata = RestaurantDetailMetadata(restaurant: restaurant)
        let store = LocalTasteMapStore(context: context)
        let markerType: RestaurantJSONContractV1.RestaurantMarkerTypeContract
        let markerPhotoID: String?
        let markerEmoji: String
        var attachedPhoto: PhotoAsset?

        switch request.kind {
        case "emoji":
            guard let value = Self.normalizedRestaurantAvatarEmoji(request.emoji) else {
                throw Self.bridgeError("invalid_restaurant_avatar_emoji", method: .restaurantSetAvatar, recoverable: true)
            }
            markerType = .emoji
            markerPhotoID = nil
            markerEmoji = value
        case "photo":
            guard let photoID = request.photoID?.lowercased(),
                  let pending = pendingPhotoSelections[photoID],
                  pending.ownerUserID == ownerUserID else {
                throw Self.bridgeError("photo_not_found", method: .restaurantSetAvatar, recoverable: true)
            }
            do {
                let photo = try photoTransferCoordinator.attachPreparedRestaurantMarker(
                    pending.prepared,
                    restaurantID: restaurant.id,
                    queueForUpload: true
                )
                attachedPhoto = photo
                try photoTransferCoordinator.enqueue(photo)
                markerType = .image
                markerPhotoID = photo.remoteID ?? photo.id.uuidString.lowercased()
                markerEmoji = metadata.markerEmoji
            } catch {
                pendingPhotoSelections[photoID] = nil
                if let attachedPhoto { try? await photoTransferCoordinator.discardLocalPhoto(attachedPhoto) }
                else { await photoTransferCoordinator.discardPrepared(pending.prepared) }
                throw Self.bridgeError("restaurant_avatar_photo_save_failed", method: .restaurantSetAvatar, recoverable: true)
            }
        default:
            throw Self.bridgeError("invalid_restaurant_avatar_kind", method: .restaurantSetAvatar, recoverable: true)
        }

        do {
            try store.updateDetails(
                restaurant,
                update: RestaurantDetailsUpdate(
                    name: restaurant.name,
                    address: restaurant.address,
                    city: restaurant.city,
                    status: restaurant.status,
                    phone: metadata.storedPhone,
                    openingHours: metadata.openingHours,
                    referencePrice: metadata.referencePrice,
                    longTermNote: metadata.longTermNote,
                    markerType: markerType,
                    markerPhotoID: markerPhotoID,
                    markerEmoji: markerEmoji
                ),
                actorUserID: ownerUserID
            )
        } catch {
            if let attachedPhoto { try? await photoTransferCoordinator.discardLocalPhoto(attachedPhoto) }
            if let photoID = request.photoID?.lowercased() { pendingPhotoSelections[photoID] = nil }
            throw Self.bridgeError("restaurant_avatar_save_failed", method: .restaurantSetAvatar, recoverable: true)
        }
        if let photoID = request.photoID?.lowercased() { pendingPhotoSelections[photoID] = nil }
        invalidateBridgeReadCaches()
        Task { await syncCoordinator.synchronizeNow() }
        return try encode(TasteMapHybridRestaurantAvatarMutationDTO(
            restaurantID: request.restaurantID,
            markerType: markerType.rawValue,
            markerEmoji: markerEmoji,
            updatedAt: Self.dateFormatter.string(from: restaurant.updatedAt)
        ))
    }

    private static func normalizedRestaurantAvatarEmoji(_ input: String?) -> String? {
        RestaurantOwnerAvatarEmojiPolicy.normalized(input)
    }

    private func moderateCommunity(_ method: TasteMapHybridBridgeMethod, payload: TasteMapHybridJSONValue) async throws -> TasteMapHybridJSONValue {
        let request: TasteMapHybridUGCRequest = try decode(payload)
        guard case .authenticated(let owner) = authServices.localAccountScope,
              let type = ModerationContentTypeV1(rawValue: request.target.type),
              !request.target.id.isEmpty else { throw Self.bridgeError("auth_required") }
        let epoch = moderationAccountEpoch
        func requireCurrentAccount() throws {
            guard epoch == moderationAccountEpoch, authServices.localAccountScope == .authenticated(owner) else {
                throw Self.bridgeError("account_changed")
            }
        }
        let authorization = UGCRequestAuthorization(capturedHeaders: try await authServices.sessionManager.headers())
        try requireCurrentAccount()
        let safetyAPI = authServices.releaseSafetyAPI.scoped(to: authorization)
        let interactionAPI = authServices.socialCollaborationAPI.scoped(to: authorization)
        // DELETE is already owner-authorized and idempotent on the server. A
        // post-timeout retry must not depend on a now-deleted eligibility read.
        if method == .communityDeleteComment {
            guard type == .comment else { throw Self.bridgeError("comment_delete_not_allowed") }
            let result = try await interactionAPI.deleteComment(id: request.target.id)
            try requireCurrentAccount()
            try cacheEngagement(visitID: result.comment.contentId,
                likedByViewer: cachedEngagement(visitID: result.comment.contentId)?.likedByViewer ?? false,
                likeCount: result.likeCount, commentCount: result.commentCount)
            localDataDidChange(reason: "communityCommentDeleted")
            return try encode(result)
        }
        let capabilities = try await safetyAPI.safetyCapabilities(type: type.rawValue, id: request.target.id)
        try requireCurrentAccount()
        switch method {
        case .communitySafety:
            return try encode(capabilities)
        case .communityReport:
            guard capabilities.canReport, let reason = ModerationReasonV1(rawValue: request.reason ?? ""),
                  let requestID = UUID(uuidString: request.requestID ?? "") else { throw Self.bridgeError("report_not_allowed") }
            let result = try await safetyAPI.report(type: type, id: request.target.id,
                reason: reason, details: request.details ?? "", requestID: requestID)
            try requireCurrentAccount()
            return try encode(result)
        case .communityBlock:
            guard capabilities.canBlock else { throw Self.bridgeError("block_not_allowed") }
            let result = try await safetyAPI.setBlocked(true, userID: capabilities.ownerID)
            try requireCurrentAccount()
            try LocalCommunityStore(context: container.mainContext).invalidateOwner(capabilities.ownerID, currentUserID: owner)
            // Derived projections only. Never touch owned entities or the sync queue.
            for row in try container.mainContext.fetch(FetchDescriptor<CachedDiscoveryPlacement>()) where row.currentUserID == owner {
                container.mainContext.delete(row)
            }
            for row in try container.mainContext.fetch(FetchDescriptor<CachedDiscoveryRestaurant>()) where row.currentUserID == owner {
                container.mainContext.delete(row)
            }
            try container.mainContext.save()
            discoveryRefreshCoordinator.reset()
            discoveryPageCoordinator.reset()
            discoveryCitySession.reset()
            localDataDidChange(reason: "communityUserBlocked")
            return try encode(result)
        default: throw Self.bridgeError("capability_unavailable")
        }
    }

    private func validateInteractionTarget(_ target: TasteMapHybridActivityInteractionDTO) throws {
        guard case .authenticated(let ownerUserID) = authServices.localAccountScope,
              !target.visitID.isEmpty, !target.authorID.isEmpty, !target.restaurantID.isEmpty else {
            throw Self.bridgeError("invalid_interaction_target", recoverable: false)
        }
        if discoveryCitySession.permits(target, ownerUserID: ownerUserID) { return }
#if DEBUG
        if TasteMapUITestFixtures.usesVisualQA, target.visitID.hasPrefix("demo-visit-") { return }
#endif
        let context = container.mainContext
        let community = ((try? context.fetch(FetchDescriptor<CachedCommunityContent>())) ?? [])
            .filter { $0.currentUserID == ownerUserID }
        if community.contains(where: { cached in
            guard let item = cached.item else { return false }
            return item.visit?.id == target.visitID
                && item.user.userId == target.authorID
                && item.restaurant.globalKey == target.restaurantID
                && (target.activityID == nil || item.id == target.activityID)
        }) { return }
        let discovery = ((try? context.fetch(FetchDescriptor<CachedDiscoveryPlacement>())) ?? [])
            .filter { $0.currentUserID == ownerUserID }
        if discovery.contains(where: { placement in
            guard let value = placement.context else { return false }
            return value.activity?.visitId == target.visitID
                && value.sourceUser?.userId == target.authorID
                && placement.globalKey == target.restaurantID
                && target.activityID == nil
        }) { return }
        throw Self.bridgeError("interaction_target_mismatch", recoverable: false)
    }

    private func cacheEngagement(
        visitID: String, likedByViewer: Bool, likeCount: Int, commentCount: Int
    ) throws {
        guard case .authenticated(let ownerUserID) = authServices.localAccountScope else { return }
        discoveryCitySession.setEngagement(.init(likedByViewer: likedByViewer, likeCount: likeCount, commentCount: commentCount),
                                           visitID: visitID, ownerUserID: ownerUserID)
        try LocalCommunityStore(context: container.mainContext).updateEngagement(
            visitID: visitID, currentUserID: ownerUserID,
            engagement: .init(
                likedByViewer: likedByViewer, likeCount: likeCount, commentCount: commentCount
            )
        )
    }

    private func cachedEngagement(visitID: String) -> CommunityEngagementSummaryV1? {
        guard case .authenticated(let ownerUserID) = authServices.localAccountScope else { return nil }
        if let value = discoveryCitySession.engagement(visitID, ownerUserID: ownerUserID) { return value }
        return ((try? container.mainContext.fetch(FetchDescriptor<CachedCommunityContent>())) ?? [])
            .first { $0.currentUserID == ownerUserID && $0.item?.visit?.id == visitID }?
            .item?.engagement
    }

    private func communityCommentDTO(_ value: CommunityCommentV1) -> TasteMapHybridCommunityCommentDTO {
        .init(
            id: value.id, visitID: value.contentId, body: value.body,
            author: .init(
                id: value.author.userId, name: value.author.displayName, city: value.author.city,
                avatarPhotoID: value.author.avatarPhotoId,
                avatarPresetID: value.author.avatarPresetId.rawValue,
                isFollowing: value.author.isFollowing
            ),
            createdAt: value.createdAt
        )
    }

#if DEBUG
    private func validateDebugInteractionTarget(_ target: TasteMapHybridActivityInteractionDTO) throws {
        guard target.visitID.hasPrefix("demo-visit-"),
              !target.authorID.isEmpty,
              !target.restaurantID.isEmpty else {
            throw Self.bridgeError("invalid_interaction_target", recoverable: false)
        }
    }

    private func debugEngagement(_ visitID: String) -> TasteMapHybridCommunityEngagementDTO {
        if let value = debugEngagementByVisit[visitID] { return value }
        let index = Int(visitID.split(separator: "-").last ?? "0") ?? 0
        return .init(likedByViewer: index == 1, likeCount: 12 + index * 5, commentCount: 2 + index)
    }

    private func debugComments(_ visitID: String) -> [TasteMapHybridCommunityCommentDTO] {
        if let values = debugCommentsByVisit[visitID] { return values }
        let index = Int(visitID.split(separator: "-").last ?? "0") ?? 0
        let names = ["周予安", "林夏", "陈屿", "西湖小柚"]
        let bodies = [
            "招牌菜很好吃，下次还会再来。",
            "环境舒服，适合和朋友一起吃。",
            "这家已经收藏，准备再试其他菜。",
            "服务很细致，整体体验不错。",
        ]
        let presets = ["fox", "otter", "capybara", "polar-bear"]
        let count = debugEngagement(visitID).commentCount
        let values = (0..<count).map { commentIndex in
            TasteMapHybridCommunityCommentDTO(
                id: "demo-comment-\(index)-\(commentIndex)", visitID: visitID,
                body: bodies[commentIndex % bodies.count],
                author: .init(
                    id: "tm_demo_commenter_\(commentIndex % names.count)",
                    name: names[commentIndex % names.count], city: "杭州", avatarPhotoID: nil,
                    avatarPresetID: presets[commentIndex % presets.count], isFollowing: commentIndex.isMultiple(of: 2)
                ),
                createdAt: String(
                    format: "2026-08-%02dT%02d:00:00Z",
                    min(28, 18 + index), max(0, 20 - commentIndex)
                )
            )
        }
        debugCommentsByVisit[visitID] = values
        return values
    }
#endif
    private func searchRestaurants(_ payload: TasteMapHybridJSONValue) async throws -> TasteMapHybridJSONValue {
        let request: TasteMapHybridAcquisitionSearchRequest = try decode(payload)
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = request.city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 200, city.count <= 120 else {
            throw Self.bridgeError("invalid_acquisition_search", method: .acquisitionSearch)
        }
        guard case .authenticated(let owner) = authServices.localAccountScope else {
            throw Self.bridgeError("auth_required", method: .acquisitionSearch)
        }
        acquisitionSearchPages = acquisitionSearchPages.filter { $0.value.expiresAt > Date() && $0.value.owner == owner }
        if let cursor = request.cursor {
            guard let page = acquisitionSearchPages.removeValue(forKey: cursor), page.query == query, page.city == city else {
                throw Self.bridgeError("search_cursor_expired", method: .acquisitionSearch, recoverable: true)
            }
            return try encode(searchPage(page))
        }
        acquisitionSearchGeneration += 1
        let generation = acquisitionSearchGeneration
        acquisitionSearchPages.removeAll(keepingCapacity: true)
        var searchAuthorization = locationPermissionManager.authorizationStatus
        var searchAccuracy = locationPermissionManager.accuracyAuthorization
#if DEBUG
        if TasteMapUITestFixtures.usesRestaurantAcquisitionFixture {
            searchAuthorization = .authorizedWhenInUse
            searchAccuracy = .fullAccuracy
        }
#endif
        let searchLocation = await RestaurantSearchLocationPolicy.location(
            accepted: acquisitionLocation?.location,
            authorizationStatus: searchAuthorization,
            accuracyAuthorization: searchAccuracy
        ) { try await self.freshLocationFix(method: .acquisitionSearch).location }
        guard acquisitionSearchGeneration == generation,
              case .authenticated(let locationOwner) = authServices.localAccountScope,
              locationOwner == owner else {
            throw Self.bridgeError("search_request_superseded", method: .acquisitionSearch, recoverable: true)
        }
        // Preserve the last accepted fix after a failed refresh so the next
        // submitted search can retry. Only this request's valid fix is used.
        let fix = searchLocation.map { location in
            (location: location, dto: TasteMapHybridLocationDTO(
                latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                timestamp: Self.dateFormatter.string(from: location.timestamp),
                horizontalAccuracy: location.horizontalAccuracy,
                accuracyMode: "full", authorizationStatus: "allowed"))
        }
        if let fix { acquisitionLocation = fix }
        let locationCenter = fix.map { RestaurantCoordinate(latitude: $0.location.coordinate.latitude, longitude: $0.location.coordinate.longitude, reference: .wgs84) }
        let locationCity: String?
        if let locationCenter, !city.isEmpty {
            locationCity = try? await restaurantSearchService.locationContext(for: locationCenter).city
        } else { locationCity = nil }
        let normalizedCity = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "市", with: "").lowercased() }
        // A manually chosen remote city always wins. If reverse geocoding
        // cannot establish that GPS belongs to that city, omit the GPS bias.
        let center = city.isEmpty || locationCity.map({ normalizedCity($0) == normalizedCity(city) }) == true ? locationCenter : nil
        var values = RestaurantSearchRelevancePolicy.rankedMatches(
            try await restaurantSearchService.search(
                query: query,
                scope: RestaurantSearchScope(city: city, center: center)
            ),
            query: query,
            scopeCity: city
        )
        guard acquisitionSearchGeneration == generation,
              case .authenticated(let currentOwner) = authServices.localAccountScope,
              currentOwner == owner else {
            throw Self.bridgeError("search_request_superseded", method: .acquisitionSearch, recoverable: true)
        }
        if let center { values = RestaurantDistanceOrdering.measuringAndSorting(values, from: center) }
        return try encode(searchPage(AcquisitionSearchPage(owner: owner, query: query, city: city,
            candidates: values, location: center == nil ? nil : fix?.dto, expiresAt: Date().addingTimeInterval(300))))
    }

    private func searchPage(_ page: AcquisitionSearchPage) -> TasteMapHybridAcquisitionResultsDTO {
        var nextCursor: String?
        if page.candidates.count > 20 {
            let cursor = UUID().uuidString.lowercased()
            acquisitionSearchPages[cursor] = AcquisitionSearchPage(owner: page.owner, query: page.query, city: page.city,
                candidates: Array(page.candidates.dropFirst(20)), location: page.location, expiresAt: page.expiresAt)
            nextCursor = cursor
        }
        return acquisitionResults(candidates: Array(page.candidates.prefix(20)), location: page.location,
            message: page.candidates.isEmpty ? "没有找到匹配的餐厅，请换一个名称、地址或城市。" : nil,
            nextCursor: nextCursor)
    }

    private func nearbyRestaurants() async throws -> TasteMapHybridJSONValue {
        guard case .authenticated(let owner) = authServices.localAccountScope else {
            throw Self.bridgeError("auth_required", method: .acquisitionNearby, recoverable: false)
        }
        acquisitionNearbyGeneration += 1
        let generation = acquisitionNearbyGeneration
        let fix = try await freshLocationFix(method: .acquisitionNearby)
        guard acquisitionNearbyGeneration == generation,
              case .authenticated(let currentOwner) = authServices.localAccountScope, currentOwner == owner else {
            throw Self.bridgeError("nearby_request_superseded", method: .acquisitionNearby, recoverable: true)
        }
        acquisitionLocation = fix
        let center = RestaurantCoordinate(
            latitude: fix.location.coordinate.latitude,
            longitude: fix.location.coordinate.longitude,
            reference: .wgs84
        )
        async let contextTask: RestaurantLocationContext? = try? restaurantSearchService.locationContext(for: center)
        async let nearbyTask = restaurantSearchService.nearby(center: center, radiusMeters: 3_000)
        let locationContext = await contextTask
        let values = try await nearbyTask
        guard acquisitionNearbyGeneration == generation,
              case .authenticated(let currentOwner) = authServices.localAccountScope, currentOwner == owner else {
            throw Self.bridgeError("nearby_request_superseded", method: .acquisitionNearby, recoverable: true)
        }
        let resolvedCity = locationContext?.city.trimmingCharacters(in: .whitespacesAndNewlines)
        let ordered = RestaurantDistanceOrdering.measuringAndSorting(values, from: center)
            .filter { ($0.distanceMeters ?? .greatestFiniteMagnitude) <= 3_000 }
#if DEBUG
        RestaurantAcquisitionDebugTrace.record("nearby_results", location: fix.location, fields: [
            "provider": "MapKit",
            "city": resolvedCity ?? "",
            "candidateCount": ordered.count,
            "candidates": ordered.prefix(24).map { candidate in
                ["name": candidate.name, "latitude": candidate.latitude, "longitude": candidate.longitude,
                 "distanceMeters": candidate.distanceMeters ?? -1] as [String: Any]
            },
        ])
#endif
        return try encode(acquisitionResults(
            // The full accepted snapshot crosses the typed boundary once.
            // React expands local batches without another GPS/provider query.
            candidates: ordered,
            location: fix.dto,
            detectedCity: resolvedCity?.isEmpty == false ? resolvedCity : nil,
            message: ordered.isEmpty ? "3 公里内暂时没有找到餐厅；搜索和手动添加仍可使用。" : nil
        ))
    }

    private func sharedRestaurantCandidates() async throws -> TasteMapHybridJSONValue {
        if pendingSharedImport == nil {
            pendingSharedImport = try PendingRestaurantImportStore.live().pending().first
        }
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
        let confirmedExistingMatch = pending.duplicateKind == "exactProvider"
            || (pending.duplicateKind == "probableCrossProvider" && request.confirmProbableMatch)
        if confirmedExistingMatch, let existing = pending.existingRestaurantID {
            // Selecting the same real Provider place is also a safe metadata
            // refresh. A cross-provider probable match reaches this branch only
            // after the user explicitly confirms it is the same Restaurant.
            // This backfills categories/images that older clients dropped
            // without creating a duplicate Restaurant.
            let restaurants = try container.mainContext.fetch(FetchDescriptor<Restaurant>())
            _ = try LocalTasteMapStore(context: container.mainContext).restaurant(
                for: pending.candidate,
                among: restaurants,
                actorUserID: ownerUserID
            )
            try container.mainContext.save()
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
        detectedCity: String? = nil,
        message: String?,
        sharedImportFingerprint: String? = nil,
        nextCursor: String? = nil
    ) -> TasteMapHybridAcquisitionResultsDTO {
        guard case .authenticated(let ownerUserID) = authServices.localAccountScope else {
            return TasteMapHybridAcquisitionResultsDTO(
                candidates: [],
                location: location,
                detectedCity: detectedCity,
                message: "请先登录。",
                sharedImportFingerprint: sharedImportFingerprint
            )
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
        let discoveryPublicRestaurants = ((try? container.mainContext.fetch(FetchDescriptor<CachedDiscoveryRestaurant>())) ?? [])
            .filter { $0.currentUserID == ownerUserID }
            .compactMap(\.projection)
        let communityPublicRestaurants = ((try? container.mainContext.fetch(FetchDescriptor<CachedCommunityContent>())) ?? [])
            .filter { $0.currentUserID == ownerUserID }
            .compactMap { cached -> DiscoveryRestaurantProjectionV1? in
                guard let item = cached.item,
                      item.restaurant.photo?.visibility == nil || item.restaurant.photo?.visibility == "public" else { return nil }
                return item.restaurant.discoveryProjection
            }
        let cachedPublicRestaurants = discoveryPublicRestaurants + communityPublicRestaurants
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
                ownerPhotos: photos,
                ownerUserID: ownerUserID,
                matchedRestaurantID: match?.restaurant.remoteID ?? match?.restaurant.id.uuidString.lowercased(),
                publicPhoto: cachedPublicRestaurants.first {
                    cachedProjection($0, matches: candidate)
                }?.photo,
                categoryHints: candidate.categoryHints
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
                websiteUrl: candidate.websiteURL?.absoluteString,
                openingHours: candidate.openingHours,
                categoryHints: candidate.categoryHints,
                image: image,
                imageResolution: imageResolution,
                duplicateKind: duplicateKind,
                existingRestaurantID: existingID
            )
        }
        return TasteMapHybridAcquisitionResultsDTO(
            candidates: values,
            location: location,
            detectedCity: detectedCity,
            message: message,
            sharedImportFingerprint: sharedImportFingerprint,
            nextCursor: nextCursor
        )
    }

    private func acquisitionImageResolutionDescriptor(
        _ resolution: RestaurantImageResolution,
        restaurantName: String,
        fallbackSeed: String,
        ownerPhotos: [PhotoAsset],
        ownerUserID: String,
        matchedRestaurantID: String?,
        publicPhoto: DiscoveryPhotoProjectionV1?,
        categoryHints: [String]
    ) -> TasteMapHybridImageResolutionDTO {
        let label = "\(restaurantName)餐厅图片"
        let sources = resolution.sources.compactMap { source -> TasteMapHybridImageDescriptor? in
            switch source {
            case .localUserPhoto(let id):
                let value = id.uuidString.lowercased()
                let photo = ownerPhotos.first { $0.id == id }
                return TasteMapHybridImageDescriptor(
                    kind: .ownerPhoto,
                    resourceURL: "tastemap-resource://photo/\(value)/display",
                    photoID: value,
                    restaurantID: matchedRestaurantID,
                    visitID: photo?.visitId.map { $0.uuidString.lowercased() },
                    sourceOwnerID: ownerUserID,
                    visibility: photo?.visibility.rawValue ?? "private",
                    exportAllowed: true,
                    attributionRequired: false,
                    accessibilityLabel: "\(label) · 用户实拍"
                )
            case .providerMerchantImage(let url):
                return TasteMapHybridImageDescriptor(
                    kind: .providerMerchant,
                    resourceURL: url.absoluteString,
                    restaurantID: matchedRestaurantID,
                    exportAllowed: false,
                    attributionRequired: false,
                    accessibilityLabel: "\(label) · Provider 商户图片"
                )
            case .publicOrCachedPhoto, .foodDiningFallback: return nil
            }
        }
        var orderedSources = sources
        if let publicPhoto,
           publicPhoto.visibility == nil || publicPhoto.visibility == "public" {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            let encoded = publicPhoto.photoId.addingPercentEncoding(withAllowedCharacters: allowed) ?? publicPhoto.photoId
            orderedSources.append(TasteMapHybridImageDescriptor(
                kind: publicPhoto.sourceType == "currentOwnerPhoto" ? .ownerPhoto : .publicUGC,
                resourceURL: "tastemap-resource://public-photo/\(encoded)/display",
                photoID: publicPhoto.photoId,
                restaurantID: publicPhoto.restaurantId,
                visitID: publicPhoto.visitId,
                sourceOwnerID: publicPhoto.ownerUserId,
                visibility: publicPhoto.visibility ?? "public",
                exportAllowed: publicPhoto.exportAllowed ?? false,
                attributionRequired: false,
                accessibilityLabel: "\(label) · 公开用户实拍"
            ))
        }
        let category = FoodCategoryVisualResolver.resolve(name: restaurantName, tags: categoryHints)
        return TasteMapHybridImageResolutionDTO(
            sources: orderedSources,
            fallback: TasteMapHybridImageDescriptor(
                kind: .foodCategoryVisual,
                stableSeed: fallbackSeed,
                categoryVisualID: category.rawValue,
                exportAllowed: false,
                attributionRequired: false,
                accessibilityLabel: "\(restaurantName)餐饮分类图示"
            )
        )
    }

    private func cachedProjection(
        _ projection: DiscoveryRestaurantProjectionV1,
        matches candidate: RestaurantCandidate
    ) -> Bool {
        let candidateKeys = Set(candidate.placeIdentities.map { "\($0.provider.rawValue):\($0.externalID)" })
        let projectionKeys = Set(projection.placeIdentities.map { "\($0.provider.rawValue):\($0.externalId)" })
        if !candidateKeys.isEmpty && !candidateKeys.isDisjoint(with: projectionKeys) { return true }
        let normalizedName = candidate.name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .filter { !$0.isWhitespace && !$0.isPunctuation }
        let projectedName = projection.name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .filter { !$0.isWhitespace && !$0.isPunctuation }
        guard normalizedName == projectedName else { return false }
        return CLLocation(latitude: candidate.latitude, longitude: candidate.longitude).distance(
            from: CLLocation(latitude: projection.latitude, longitude: projection.longitude)
        ) < 80
    }

    private func freshLocationFix(method: TasteMapHybridBridgeMethod) async throws -> (location: CLLocation, dto: TasteMapHybridLocationDTO) {
        if let acquisitionLocationTask { return try await acquisitionLocationTask.value }
        let task = Task { try await self.obtainFreshLocationFix(method: method) }
        acquisitionLocationTask = task
        defer { acquisitionLocationTask = nil }
        return try await task.value
    }

    private func obtainFreshLocationFix(method: TasteMapHybridBridgeMethod) async throws -> (location: CLLocation, dto: TasteMapHybridLocationDTO) {
#if DEBUG
        // Synthetic coordinates are allowed only alongside the explicitly
        // synthetic acquisition provider, never an ordinary QA real search.
        if TasteMapUITestFixtures.usesRestaurantAcquisitionFixture {
            let location = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 30.2741, longitude: 120.1551),
                altitude: 8,
                horizontalAccuracy: 12,
                verticalAccuracy: 8,
                timestamp: Date()
            )
            let dto = TasteMapHybridLocationDTO(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: Self.dateFormatter.string(from: location.timestamp),
                horizontalAccuracy: location.horizontalAccuracy,
                accuracyMode: "full",
                authorizationStatus: "allowed"
            )
            emit(.locationChanged, payload: dto)
            return (location, dto)
        }
#endif
        do {
            let location = try await locationRequestCoordinator.request {
                try await self.locationPermissionManager.requestCurrentLocation()
            }
            guard locationPermissionManager.accuracyAuthorization == .fullAccuracy else {
                throw RestaurantLocationError.preciseLocationRequired
            }
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
        } catch RestaurantLocationError.preciseLocationRequired {
            throw Self.bridgeError("location_precise_required", method: method, recoverable: true)
        } catch {
            throw Self.bridgeError("location_stale_or_inaccurate", method: method, recoverable: true)
        }
    }

    private func pickPhotos(_ payload: TasteMapHybridJSONValue) async throws -> TasteMapHybridJSONValue {
        let request: TasteMapHybridPhotoPickRequest = try decode(payload)
        let limit = min(max(request.selectionLimit, 1), PhotoImportService.maximumSelectionCount, premiumEntitlementService.visitPhotoLimit)
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
        guard let photo = try container.mainContext.fetch(FetchDescriptor<PhotoAsset>()).first(where: {
            $0.ownerUserID == ownerUserID && ($0.id.uuidString.caseInsensitiveCompare(request.photoID) == .orderedSame
                || $0.remoteID?.caseInsensitiveCompare(request.photoID) == .orderedSame)
        }) else {
            throw Self.bridgeError("photo_not_found", method: .photoDiscard, recoverable: true)
        }
        try await photoTransferCoordinator.delete(photo)
        return .object([:])
    }

    private func retryPhoto(_ payload: TasteMapHybridJSONValue) throws -> TasteMapHybridJSONValue {
        let request: TasteMapHybridPhotoIDRequest = try decode(payload)
        guard case .authenticated(let ownerUserID) = authServices.localAccountScope,
              let photo = try container.mainContext.fetch(FetchDescriptor<PhotoAsset>()).first(where: {
                  $0.ownerUserID == ownerUserID && ($0.id.uuidString.caseInsensitiveCompare(request.photoID) == .orderedSame
                      || $0.remoteID?.caseInsensitiveCompare(request.photoID) == .orderedSame)
              }) else {
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
            "source": premiumEntitlementService.snapshot?.source.map { .string($0.rawValue) } ?? .null,
            "startedAt": premiumEntitlementService.snapshot?.startsAt.map { .string(Self.dateFormatter.string(from: $0)) } ?? .null,
            "statusText": premiumEntitlementService.snapshot?.giftStatusText.map { .string($0) } ?? .null,
            "canManageSubscription": .bool(status == "premium" && premiumEntitlementService.snapshot?.source?.isAppStoreSubscription == true),
        ])
    }

    private func premiumProducts() async throws -> TasteMapHybridJSONValue {
        do {
            let products = try await premiumEntitlementService.productsProvider.products().filter { $0.period == .monthly || $0.period == .annual }.map {
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
            let result = try await StoreKitPurchaseTiming.$tappedAtMilliseconds.withValue(request.tappedAtMilliseconds) {
                try await premiumEntitlementService.productsProvider.purchase(productID: productID)
            }
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
        guard premiumEntitlementService.snapshot?.source?.isAppStoreSubscription == true else {
            throw Self.bridgeError("premium_management_unavailable", method: .premiumManage, recoverable: false)
        }
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
        return TasteMapHybridPermissionsStatusDTO(
            location: value.location.rawValue,
            camera: value.camera.rawValue,
            photoAddOnly: value.photoAddOnly.rawValue,
            canOpenSystemSettings: value.location.canOpenSystemSettings
                || value.photoAddOnly.canOpenSystemSettings
                || value.camera.canOpenSystemSettings
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
            let location = try await locationRequestCoordinator.request {
                try await self.locationPermissionManager.requestCurrentLocation()
            }
            guard RestaurantLocationFixPolicy.isUsable(
                location, accuracyAuthorization: locationPermissionManager.accuracyAuthorization
            ) else { throw RestaurantLocationError.staleOrInaccurate }
            var value = TasteMapHybridLocationDTO(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: Self.dateFormatter.string(from: location.timestamp),
                horizontalAccuracy: location.horizontalAccuracy,
                accuracyMode: locationPermissionManager.accuracyAuthorization == .fullAccuracy ? "full" : "reduced",
                authorizationStatus: "allowed"
            )
            let cityContext = try? await restaurantSearchService.locationContext(for: RestaurantCoordinate(
                latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, reference: .wgs84))
            value.detectedCity = cityContext?.city.trimmingCharacters(in: .whitespacesAndNewlines)
            if let owner = authServices.localAccountScope.authenticatedUserID {
                if let city = value.detectedCity, !city.isEmpty {
                    discoveryLocationCity = (owner, Self.canonicalDiscoveryCity(city), location.timestamp)
                }
                let reference = TasteMapDiscoveryReference(latitude: value.latitude, longitude: value.longitude, source: "device_location")
                try discoveryLocationProofs.register(reference, owner: owner, timestamp: location.timestamp)
            }
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

    private func validateDiscoveryReferences(_ query: TasteMapDiscoveryAppliedQuery, owner: String, continuation: Bool) throws {
        try discoveryLocationProofs.validate(query, owner: owner, permissionAllowed: locationAuthorizationStatus == "allowed", continuation: continuation)
    }

    private func signInWithApple() async throws -> TasteMapHybridJSONValue {
        guard let window = presentationWindow else { throw Self.bridgeError("presentation_anchor_unavailable", recoverable: true) }
        do {
            let user = try await authServices.appleSignIn.signIn(presentationAnchor: window)
            authServices.activateLocalAccount(user)
            acquisitionNearbyGeneration += 1
            pendingAcquisitionCandidates.removeAll(keepingCapacity: false)
            pendingPhotoSelections.removeAll(keepingCapacity: false)
            try LocalAccountOwnershipMigrator(context: container.mainContext).activate(userID: user.id)
            await premiumEntitlementService.activate(userID: user.id)
            await syncCoordinator.sessionDidBecomeAvailable(userID: user.id)
            invalidateBridgeReadCaches()
            let session = TasteMapHybridAuthStateDTO(state: "authenticated", userID: user.id, displayName: nil)
            resetToCurrentProfileIfNeeded()
            emit(.authChanged, payload: session)
            return try encode(TasteMapHybridAuthResultDTO(state: "authenticated", session: session))
        } catch let error as ASAuthorizationError where error.code == .canceled {
            let session = await safeSessionState()
            return try encode(TasteMapHybridAuthResultDTO(state: "cancelled", session: session))
        }
    }

    /// Revocation has already cleared the authoritative credential. Reuse only
    /// the in-memory logout context cleanup, never Account Delete/data purging.
    func appleCredentialDidInvalidate() {
        acquisitionNearbyGeneration += 1
        pendingAcquisitionCandidates.removeAll(keepingCapacity: false)
        pendingPhotoSelections.removeAll(keepingCapacity: false)
        premiumEntitlementService.sessionDidEnd()
        syncCoordinator.sessionDidEnd()
        invalidateBridgeReadCaches()
        resetToCurrentProfileIfNeeded()
        emit(.authChanged, payload: TasteMapHybridAuthStateDTO(state: "signedOut", userID: nil, displayName: nil))
    }

    private func logout() async -> TasteMapHybridJSONValue {
        acquisitionNearbyGeneration += 1
        do { try await authServices.sessionManager.logout() }
        catch { /* Local logout is authoritative; server revocation remains bounded by expiry. */ }
        authServices.endLocalAccountSession()
        pendingAcquisitionCandidates.removeAll(keepingCapacity: false)
        pendingPhotoSelections.removeAll(keepingCapacity: false)
        premiumEntitlementService.sessionDidEnd()
        syncCoordinator.sessionDidEnd()
        invalidateBridgeReadCaches()
        resetToCurrentProfileIfNeeded()
        let session = TasteMapHybridAuthStateDTO(state: "signedOut", userID: nil, displayName: nil)
        emit(.authChanged, payload: session)
        return (try? encode(session)) ?? .object(["state": .string("signedOut"), "userID": .null, "displayName": .null])
    }

    func accountDeletionDidComplete() async {
        acquisitionNearbyGeneration += 1
        authServices.endLocalAccountSession()
        pendingAcquisitionCandidates.removeAll(keepingCapacity: false)
        pendingPhotoSelections.removeAll(keepingCapacity: false)
        premiumEntitlementService.sessionDidEnd()
        syncCoordinator.sessionDidEnd()
        invalidateBridgeReadCaches()
        resetToCurrentProfileIfNeeded()
        let session = TasteMapHybridAuthStateDTO(state: "signedOut", userID: nil, displayName: nil)
        emit(.authChanged, payload: session)
    }

    func localDataDidClear() {
        acquisitionNearbyGeneration += 1
        pendingAcquisitionCandidates.removeAll(keepingCapacity: false)
        pendingPhotoSelections.removeAll(keepingCapacity: false)
        localDataDidChange(reason: "localDataCleared")
    }

    /// Refreshes the already-running Hybrid app after a Native SwiftData
    /// transaction. Rebuilding the service also creates a fresh ModelContext,
    /// so the next content/profile request can see externally imported rows.
    func localDataDidChange(reason: String) {
        invalidateBridgeReadCaches()
        emit(.dataChanged, payload: ["reason": reason])
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
        if name == .authChanged {
            moderationAccountEpoch += 1
            discoveryLocationProofs.reset()
            discoveryRefreshCoordinator.reset()
            discoveryPageCoordinator.reset()
            discoveryCitySession.reset()
        }
        if name == .authChanged { listService?.invalidate(); listService = nil }
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
    let tappedAtMilliseconds: Double?
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
private struct ReferralRegistrationPayload: Codable { let code: String }
