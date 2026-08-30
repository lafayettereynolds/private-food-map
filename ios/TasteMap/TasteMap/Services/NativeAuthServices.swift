import Foundation
import Observation

@Observable
@MainActor
final class NativeAuthServices {
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
    let appleSignIn: AppleSignInService

    init(
        configuration: APIConfiguration,
        session: URLSession = .shared,
        credentialStore: any AuthCredentialStoring = KeychainCredentialStore()
    ) {
        let authAPI = URLSessionAuthAPIClient(configuration: configuration, session: session)
        let sessionManager = AuthSessionManager(api: authAPI, credentialStore: credentialStore)
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
            sessionManager: sessionManager
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
        appleSignIn = AppleSignInService(api: authAPI, sessionManager: sessionManager)
    }
}
