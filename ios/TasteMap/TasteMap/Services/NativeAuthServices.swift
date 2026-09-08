import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class NativeAuthServices {
    private(set) var localAccountScope: LocalAccountScope = .restoring
    let authAPI: URLSessionAuthAPIClient
    let sessionManager: AuthSessionManager
    let syncAPI: URLSessionSyncAPIClient
    let photoAPI: URLSessionPhotoBinaryAPIClient
    let profileAPI: URLSessionProfileAPIClient
    let socialAPI: URLSessionSocialAPIClient
    let discoveryAPI: URLSessionDiscoveryAPIClient
    let communityAPI: URLSessionCommunityAPIClient
    let socialCollaborationAPI: URLSessionSocialCollaborationAPIClient
    let socialCollaborationOutbox: SocialCollaborationOutbox
    let restaurantListAPI: URLSessionRestaurantListAPIClient
    let externalRestaurantLinkAPI: URLSessionExternalRestaurantLinkAPIClient
    let premiumAPI: URLSessionPremiumEntitlementAPIClient
    let premiumCommerceAPI: URLSessionPremiumCommerceAPIClient
    let publicSharingAPI: URLSessionPublicSharingAPIClient
    let releaseSafetyAPI: URLSessionReleaseSafetyAPIClient
    let appleSignIn: AppleSignInService
    let recommendationPreferenceSync: RecommendationPreferenceSync
    @ObservationIgnored private var preferenceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var appleObservers: AppleCredentialObservers?
    @ObservationIgnored var credentialInvalidationHandler: (() -> Void)?
    private var scopeGeneration = UUID()
    private var recommendationSyncSuspendedForVisualQA = false

    init(
        configuration: APIConfiguration,
        session: URLSession = .shared,
        credentialStore: any AuthCredentialStoring = KeychainCredentialStore(),
        socialOutboxFileURL: URL? = nil,
        appleState: @escaping @Sendable (String) async throws -> AppleCredentialStatus = AppleCredentialStateProvider.state
    ) {
        let authAPI = URLSessionAuthAPIClient(configuration: configuration, session: session)
        let sessionManager = AuthSessionManager(api: authAPI, credentialStore: credentialStore, appleState: appleState)
        self.authAPI = authAPI
        self.sessionManager = sessionManager
        syncAPI = URLSessionSyncAPIClient(
            configuration: configuration,
            authorization: sessionManager,
            session: session
        )
        photoAPI = URLSessionPhotoBinaryAPIClient(
            configuration: configuration,
            authorization: sessionManager,
            session: session
        )
        profileAPI = URLSessionProfileAPIClient(
            configuration: configuration,
            authorization: sessionManager,
            session: session
        )
        socialAPI = URLSessionSocialAPIClient(
            configuration: configuration,
            authorization: sessionManager,
            session: session
        )
        discoveryAPI = URLSessionDiscoveryAPIClient(
            configuration: configuration,
            authorization: sessionManager,
            session: session
        )
        communityAPI = URLSessionCommunityAPIClient(
            configuration: configuration,
            authorization: sessionManager,
            session: session
        )
        let socialCollaborationAPI = URLSessionSocialCollaborationAPIClient(
            configuration: configuration,
            authorization: sessionManager,
            session: session
        )
        self.socialCollaborationAPI = socialCollaborationAPI
        socialCollaborationOutbox = SocialCollaborationOutbox(
            api: socialCollaborationAPI,
            sessionManager: sessionManager,
            fileURL: socialOutboxFileURL
        )
        restaurantListAPI = URLSessionRestaurantListAPIClient(
            configuration: configuration,
            authorization: sessionManager,
            session: session
        )
        externalRestaurantLinkAPI = URLSessionExternalRestaurantLinkAPIClient(
            configuration: configuration,
            authorization: sessionManager,
            session: session
        )
        premiumAPI = URLSessionPremiumEntitlementAPIClient(
            configuration: configuration,
            authorization: sessionManager,
            session: session
        )
        premiumCommerceAPI = URLSessionPremiumCommerceAPIClient(
            configuration: configuration,
            authorization: sessionManager,
            session: session
        )
        publicSharingAPI = URLSessionPublicSharingAPIClient(
            configuration: configuration,
            authorization: sessionManager,
            session: session
        )
        releaseSafetyAPI = URLSessionReleaseSafetyAPIClient(
            configuration: configuration,
            authorization: sessionManager,
            session: session
        )
        appleSignIn = AppleSignInService(api: authAPI, sessionManager: sessionManager)
        recommendationPreferenceSync = RecommendationPreferenceSync(api: URLSessionRecommendationPreferenceAPI(
            configuration: configuration, authorization: sessionManager, session: session))
        for name in [UIApplication.didBecomeActiveNotification, RestaurantRecommendationPreferences.didChange] {
            preferenceObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard notification.userInfo?["origin"] as? String != "remotePreferenceSync" else { return }
                Task { @MainActor [weak self] in self?.retryRecommendationPreferences() }
            })
        }
        appleObservers = AppleCredentialObservers { [weak self] in
            Task { @MainActor [weak self] in await self?.refreshAppleCredential() }
        }
    }

    func refreshAppleCredential() async {
        guard !recommendationSyncSuspendedForVisualQA else { return }
        let origin = scopeGeneration
        let invalidated = await sessionManager.validateAppleCredential()
        guard invalidated, scopeGeneration == origin else { return }
        endLocalAccountSession()
        credentialInvalidationHandler?()
    }

    @discardableResult
    func restoreLocalAccountScope() async -> AuthenticatedUserV1? {
        let origin = scopeGeneration
        await refreshAppleCredential()
        guard scopeGeneration == origin else { return nil }
        let user = await sessionManager.restoredUser()
        guard scopeGeneration == origin else { return nil }
        localAccountScope = user.map { .authenticated($0.id) } ?? .guest
        retryRecommendationPreferences()
        return user
    }

    func activateLocalAccount(_ user: AuthenticatedUserV1) {
        if localAccountScope != .authenticated(user.id) { scopeGeneration = UUID() }
        recommendationSyncSuspendedForVisualQA = false
        localAccountScope = .authenticated(user.id)
        retryRecommendationPreferences()
    }

    private func retryRecommendationPreferences() {
#if DEBUG
        // The fixture scope may be activated after session restoration. Block
        // fixture launches from the first lifecycle callback, not only after it.
        guard !TasteMapUITestFixtures.usesVisualQA else { return }
#endif
        guard !recommendationSyncSuspendedForVisualQA, let owner = localAccountScope.authenticatedUserID else { return }
        Task { @MainActor [weak self] in
            guard let self, !self.recommendationSyncSuspendedForVisualQA, self.localAccountScope.authenticatedUserID == owner,
                  await self.sessionManager.restoredUser()?.id == owner else { return }
            await self.recommendationPreferenceSync.synchronize(owner: owner) { [weak self] in
                self?.recommendationSyncSuspendedForVisualQA == false && self?.localAccountScope.authenticatedUserID == owner
            }
        }
    }

    func endLocalAccountSession() {
        scopeGeneration = UUID()
        ReferralInvitationStore.clear()
        localAccountScope = .guest
    }

#if DEBUG
    /// Activates only the isolated, compilation-gated Visual QA workspace.
    /// No credential is persisted and no server authorization is fabricated.
    func activateVisualQAFixture(userID: String) {
        recommendationSyncSuspendedForVisualQA = true
        localAccountScope = .authenticated(userID)
    }
#endif
}
