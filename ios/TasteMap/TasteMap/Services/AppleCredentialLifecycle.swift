import AuthenticationServices
import Foundation
import UIKit

nonisolated enum AppleCredentialStatus: Sendable {
    case authorized, revoked, notFound, transferred, unknown
}

nonisolated enum AppleCredentialStateProvider {
    static func state(_ user: String) async throws -> AppleCredentialStatus {
        try await withCheckedThrowingContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: user) { state, error in
                if let error { continuation.resume(throwing: error); return }
                let result: AppleCredentialStatus
                switch state {
                case .authorized: result = .authorized
                case .revoked: result = .revoked
                case .notFound: result = .notFound
                case .transferred: result = .transferred
                @unknown default: result = .unknown
                }
                continuation.resume(returning: result)
            }
        }
    }
}

/// One registration owner. Cancellation unregisters both observers; callbacks
/// retain neither the service nor its session. Notification payloads are ignored.
nonisolated final class AppleCredentialObservers: @unchecked Sendable {
    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter = .default, refresh: @escaping @Sendable () -> Void) {
        self.center = center
        for name in [ASAuthorizationAppleIDProvider.credentialRevokedNotification, UIApplication.didBecomeActiveNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: nil) { _ in refresh() })
        }
    }

    deinit { tokens.forEach { center.removeObserver($0) } }
}
