import Foundation
import Combine

@MainActor
public final class ExternalImportCoordinator: ObservableObject {
    public enum State {
        case idle
        case resolving
        case resolved(ExternalRestaurantResolveResponse)
        case failed(String)
    }

    @Published public private(set) var state: State = .idle
    private let store: PendingExternalRestaurantImportStore
    private let session: URLSession
    private let apiBaseURL: URL
    private let ownerSubject: () -> String?
    private let authorizeRequest: (inout URLRequest) -> Void

    public init(
        store: PendingExternalRestaurantImportStore,
        session: URLSession = .shared,
        apiBaseURL: URL,
        ownerSubject: @escaping () -> String?,
        authorizeRequest: @escaping (inout URLRequest) -> Void = { _ in }
    ) {
        self.store = store
        self.session = session
        self.apiBaseURL = apiBaseURL
        self.ownerSubject = ownerSubject
        self.authorizeRequest = authorizeRequest
    }

    public func handle(deepLink: URL, currentCity: String?) async {
        guard deepLink.scheme == "tastemap",
              deepLink.host == "external-import",
              let rawId = deepLink.pathComponents.dropFirst().first,
              let importId = UUID(uuidString: rawId),
              let pending = store.item(id: importId, ownerSubject: ownerSubject()) else {
            state = .failed("这条分享已处理或不属于当前账号。")
            return
        }
        state = .resolving
        do {
            let endpoint = apiBaseURL.appending(path: "api/external-place/resolve")
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            authorizeRequest(&request)
            request.httpBody = try JSONEncoder().encode(ExternalRestaurantResolveRequest(pending: pending, currentCity: currentCity))
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                throw ExternalImportCoordinatorError.resolveFailed
            }
            let resolved = try JSONDecoder().decode(ExternalRestaurantResolveResponse.self, from: data)
            try store.remove(id: importId, ownerSubject: ownerSubject())
            state = .resolved(resolved)
        } catch {
            try? store.updateFailure(id: importId, ownerSubject: ownerSubject(), error: error.localizedDescription)
            state = .failed("餐厅识别失败，原分享已保留，可以稍后重试。")
        }
    }
}

private enum ExternalImportCoordinatorError: Error {
    case resolveFailed
}
