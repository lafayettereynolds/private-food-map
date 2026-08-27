import Foundation

enum SyncFailureDisposition: String, Equatable, Sendable {
    case retryable
    case authentication
    case permanent
    case cancelled
}

enum SyncErrorClassifier {
    static func disposition(for error: Error) -> SyncFailureDisposition {
        if error is CancellationError { return .cancelled }

        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return .cancelled }
            switch urlError.code {
            case .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .dnsLookupFailed,
                 .notConnectedToInternet,
                 .resourceUnavailable,
                 .internationalRoamingOff,
                 .callIsActive,
                 .dataNotAllowed:
                return .retryable
            default:
                return .permanent
            }
        }

        if let apiError = error as? SyncAPIError {
            switch apiError {
            case .invalidResponse, .unsupportedVersion:
                return .permanent
            case .server(let status, _):
                if status == 401 { return .authentication }
                if status == 408 || status == 425 || status == 429 || (500...599).contains(status) {
                    return .retryable
                }
                return .permanent
            }
        }

        if let authError = error as? AuthSessionError {
            switch authError {
            case .notAuthenticated, .sessionExpired:
                return .authentication
            }
        }

        if let authError = error as? AuthClientError {
            switch authError {
            case .invalidResponse:
                return .permanent
            case .server(let status, _, _):
                if status == 401 { return .authentication }
                if status == 408 || status == 425 || status == 429 || (500...599).contains(status) {
                    return .retryable
                }
                return .permanent
            }
        }

        if error is DecodingError || error is EncodingError || error is APIConfigurationError {
            return .permanent
        }

        if error is SyncEngineError { return .permanent }
        return .retryable
    }

    static func storedReason(for error: Error, disposition: SyncFailureDisposition) -> String {
        let code: String
        switch error {
        case let error as URLError:
            code = "url_\(error.code.rawValue)"
        case let SyncAPIError.server(status, _):
            code = "http_\(status)"
        case SyncAPIError.invalidResponse:
            code = "invalid_response"
        case SyncAPIError.unsupportedVersion:
            code = "unsupported_version"
        case AuthSessionError.notAuthenticated:
            code = "not_authenticated"
        case AuthSessionError.sessionExpired:
            code = "session_expired"
        default:
            code = String(describing: type(of: error))
        }
        return "\(disposition.rawValue):\(code)"
    }
}
