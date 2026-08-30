import AuthenticationServices
import CryptoKit
import Foundation

enum AppleSignInServiceError: Error, Equatable {
    case signInAlreadyInProgress
    case missingCredential
    case stateMismatch
    case accountMismatch
}

@MainActor
final class AppleSignInService: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private let api: any AuthAPI
    private let sessionManager: AuthSessionManager
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var presentationAnchor: ASPresentationAnchor?
    private var controller: ASAuthorizationController?

    init(api: any AuthAPI, sessionManager: AuthSessionManager) {
        self.api = api
        self.sessionManager = sessionManager
    }

    func signIn(presentationAnchor: ASPresentationAnchor) async throws -> AuthenticatedUserV1 {
        let response = try await exchangeAppleCredential(presentationAnchor: presentationAnchor)
        return try await sessionManager.accept(response)
    }

    /// Performs a fresh Apple authorization without allowing a different
    /// Apple identity to replace the currently selected Taste Map session.
    func reauthenticate(
        expectedUserID: String,
        presentationAnchor: ASPresentationAnchor
    ) async throws -> AuthenticatedUserV1 {
        let response = try await exchangeAppleCredential(presentationAnchor: presentationAnchor)
        guard response.user.id == expectedUserID else {
            // Exchange creates an isolated server session. Revoke it before
            // returning the mismatch and never persist it to Keychain.
            try? await api.logout(
                accessToken: response.session.accessToken,
                refreshToken: response.session.refreshToken
            )
            throw AppleSignInServiceError.accountMismatch
        }
        return try await sessionManager.accept(response)
    }

    private func exchangeAppleCredential(
        presentationAnchor: ASPresentationAnchor
    ) async throws -> AuthSessionResponseV1 {
        guard continuation == nil else { throw AppleSignInServiceError.signInAlreadyInProgress }
        let challenge = try await api.challenge()
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.email, .fullName]
        request.state = challenge.state
        request.nonce = Self.sha256(challenge.nonce)

        self.presentationAnchor = presentationAnchor
        let credential = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            self.controller = controller
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
        guard credential.state == challenge.state else { throw AppleSignInServiceError.stateMismatch }
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AppleSignInServiceError.missingCredential
        }
        return try await api.exchangeAppleToken(
            identityToken: identityToken,
            state: challenge.state,
            nonce: challenge.nonce,
            givenName: credential.fullName?.givenName,
            familyName: credential.fullName?.familyName
        )
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { finish() }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AppleSignInServiceError.missingCredential)
            return
        }
        continuation?.resume(returning: credential)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        defer { finish() }
        continuation?.resume(throwing: error)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        presentationAnchor!
    }

    private func finish() {
        continuation = nil
        controller = nil
        presentationAnchor = nil
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
