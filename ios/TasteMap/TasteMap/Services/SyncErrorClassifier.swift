import Foundation

enum SyncFailureDisposition: String, Equatable, Sendable {
    case retryable
    case authentication
    case permanent
    case cancelled
}

enum SyncFailureCategory: String, Equatable, Sendable {
    case authentication
    case timeout
    case transport
    case rateLimited
    case server
    case contract
    case cursor
    case reconciliation
    case cancelled
    case unknown
}

struct SyncFailureDiagnostic: Equatable, Sendable {
    let stage: SyncStage
    let requestCategory: String
    let category: SyncFailureCategory
    let httpStatus: Int?
    let durationMilliseconds: Int
    let retryCount: Int
    let finalDisposition: SyncFailureDisposition
}

enum SyncErrorClassifier {
    static func disposition(for error: Error) -> SyncFailureDisposition {
        let error = rootError(error)
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

        if let apiError = error as? PhotoBinaryAPIError {
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

        if error is PhotoImportError { return .permanent }

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

        if let engineError = error as? SyncEngineError {
            return engineError == .pullPageLimitReached ? .retryable : .permanent
        }
        return .retryable
    }

    static func storedReason(for error: Error, disposition: SyncFailureDisposition) -> String {
        let error = rootError(error)
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
        case let PhotoBinaryAPIError.server(status, _):
            code = "photo_http_\(status)"
        case PhotoBinaryAPIError.invalidResponse:
            code = "photo_invalid_response"
        case PhotoBinaryAPIError.unsupportedVersion:
            code = "photo_unsupported_version"
        case is PhotoImportError:
            code = "photo_import"
        case AuthSessionError.notAuthenticated:
            code = "not_authenticated"
        case AuthSessionError.sessionExpired:
            code = "session_expired"
        default:
            code = String(describing: type(of: error))
        }
        return "\(disposition.rawValue):\(code)"
    }

    static func diagnostic(
        for error: Error,
        duration: TimeInterval,
        retryCount: Int
    ) -> SyncFailureDiagnostic {
        let stage = (error as? SyncStageFailure)?.stage ?? .reconciliation
        let root = rootError(error)
        let disposition = disposition(for: root)
        let status: Int?
        switch root {
        case let SyncAPIError.server(code, _), let PhotoBinaryAPIError.server(code, _):
            status = code
        case let AuthClientError.server(code, _, _):
            status = code
        default:
            status = nil
        }
        let category: SyncFailureCategory
        switch root {
        case is CancellationError:
            category = .cancelled
        case let error as URLError where error.code == .timedOut:
            category = .timeout
        case is URLError:
            category = .transport
        case let SyncAPIError.server(code, _) where code == 401 || code == 403:
            category = .authentication
        case let PhotoBinaryAPIError.server(code, _) where code == 401 || code == 403:
            category = .authentication
        case let AuthClientError.server(code, _, _) where code == 401 || code == 403:
            category = .authentication
        case let SyncAPIError.server(code, _) where code == 429:
            category = .rateLimited
        case let PhotoBinaryAPIError.server(code, _) where code == 429:
            category = .rateLimited
        case let AuthClientError.server(code, _, _) where code == 429:
            category = .rateLimited
        case is SyncAPIError, is PhotoBinaryAPIError, is AuthClientError:
            category = status.map { (500...599).contains($0) ? .server : .contract } ?? .contract
        case SyncEngineError.cursorDidNotAdvance, SyncEngineError.pullPageLimitReached:
            category = .cursor
        case is SyncEngineError:
            category = .reconciliation
        case is DecodingError, is EncodingError, is APIConfigurationError:
            category = .contract
        default:
            category = disposition == .authentication ? .authentication : .unknown
        }
        return SyncFailureDiagnostic(
            stage: stage,
            requestCategory: stage == .mutationPush ? "push" : (stage == .pull ? "pull" : "local"),
            category: category,
            httpStatus: status,
            durationMilliseconds: max(0, Int((duration * 1_000).rounded())),
            retryCount: retryCount,
            finalDisposition: disposition
        )
    }

    private static func rootError(_ error: Error) -> Error {
        var current = error
        while let stageFailure = current as? SyncStageFailure {
            current = stageFailure.underlyingError
        }
        return current
    }
}
