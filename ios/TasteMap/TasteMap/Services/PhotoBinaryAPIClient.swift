import Foundation

nonisolated enum PhotoBinaryVariant: String, Codable, Sendable {
    case display
    case thumbnail
}

nonisolated struct PhotoBinaryUploadResponse: Decodable, Equatable, Sendable {
    let apiVersion: Int
    let photoId: String
    let variant: PhotoBinaryVariant
    let storageProvider: PhotoStorageProviderID
    let storageKey: String
    let contentType: String
    let byteSize: Int64
    let checksum: String
    let duplicate: Bool
}

nonisolated protocol PhotoBinaryAPI: Sendable {
    func upload(
        photoID: UUID,
        mutationID: UUID,
        variant: PhotoBinaryVariant,
        data: Data,
        contentType: String,
        checksum: String
    ) async throws -> PhotoBinaryUploadResponse
    func download(photoID: UUID, variant: PhotoBinaryVariant) async throws -> Data
    func delete(photoID: UUID) async throws
}

nonisolated enum PhotoBinaryAPIError: LocalizedError, Equatable {
    case invalidResponse
    case unsupportedVersion
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "照片服务返回了无法识别的内容。"
        case .unsupportedVersion: "照片服务版本与当前 App 不兼容。"
        case .server(_, let message): message
        }
    }
}

actor URLSessionPhotoBinaryAPIClient: PhotoBinaryAPI {
    private let configuration: APIConfiguration
    private let authorization: any SyncAuthorizationProviding
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(
        configuration: APIConfiguration,
        authorization: any SyncAuthorizationProviding = MissingSyncAuthorization(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.authorization = authorization
        self.session = session
    }

    func upload(
        photoID: UUID,
        mutationID: UUID,
        variant: PhotoBinaryVariant,
        data: Data,
        contentType: String,
        checksum: String
    ) async throws -> PhotoBinaryUploadResponse {
        var request = try await request(
            photoID: photoID,
            variant: variant,
            method: "PUT"
        )
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(checksum, forHTTPHeaderField: "X-Taste-Map-Content-SHA256")
        request.setValue(mutationID.uuidString.lowercased(), forHTTPHeaderField: "X-Taste-Map-Upload-ID")
        request.httpBody = data
        let (responseData, response) = try await send(request)
        try validate(responseData, response)
        let value = try decoder.decode(PhotoBinaryUploadResponse.self, from: responseData)
        guard value.apiVersion == 1 else { throw PhotoBinaryAPIError.unsupportedVersion }
        return value
    }

    func download(photoID: UUID, variant: PhotoBinaryVariant) async throws -> Data {
        let original = try await request(photoID: photoID, variant: variant, method: "GET")
        let (data, response) = try await send(original)
        try validate(data, response)
        return data
    }

    func delete(photoID: UUID) async throws {
        let original = try await request(photoID: photoID, variant: nil, method: "DELETE")
        let (data, response) = try await send(original)
        try validate(data, response)
    }

    private func request(
        photoID: UUID,
        variant: PhotoBinaryVariant?,
        method: String
    ) async throws -> URLRequest {
        var path = "/api/v1/photos/\(photoID.uuidString.lowercased())/content"
        if let variant { path += "?variant=\(variant.rawValue)" }
        var request = URLRequest(url: try configuration.url(for: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in try await authorization.headers() {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    private func send(_ original: URLRequest) async throws -> (Data, URLResponse) {
        var request = original
        var result = try await session.data(for: request)
        if let response = result.1 as? HTTPURLResponse,
           response.statusCode == 401,
           try await authorization.recoverUnauthorized(
               failedAuthorization: request.value(forHTTPHeaderField: "Authorization")
           ) {
            for (name, value) in try await authorization.headers() {
                request.setValue(value, forHTTPHeaderField: name)
            }
            result = try await session.data(for: request)
        }
        return result
    }

    private func validate(_ data: Data, _ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw PhotoBinaryAPIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw PhotoBinaryAPIError.server(
                status: response.statusCode,
                message: body?["error"] as? String ?? "照片请求失败，请稍后重试。"
            )
        }
    }
}
