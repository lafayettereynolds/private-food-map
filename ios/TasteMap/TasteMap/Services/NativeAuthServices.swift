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
        appleSignIn = AppleSignInService(api: authAPI, sessionManager: sessionManager)
    }
}
