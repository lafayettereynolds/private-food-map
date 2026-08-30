import Foundation

nonisolated enum ReleaseSafetyV1Contract {
    static let apiVersion = 1
}

nonisolated struct AccountDeletionPreviewV1: Codable, Equatable, Sendable {
    let apiVersion: Int
    let userId: String
    let requiresFreshAuthentication: Bool
    let pendingMutationCount: Int
    let entityCounts: [String: Int]
    let photoObjectCount: Int
}

nonisolated enum AccountDeletionStatusV1: String, Codable, Equatable, Sendable {
    case previewed
    case confirmed
    case deletingData = "deleting_data"
    case deletingObjects = "deleting_objects"
    case completed
    case failed
}

nonisolated struct AccountDeletionJobV1: Codable, Equatable, Sendable {
    let apiVersion: Int
    let jobId: String
    let status: AccountDeletionStatusV1
    let requestedAt: String
    let updatedAt: String
    let completedAt: String?
    let retryable: Bool
    let errorCode: String?
}

nonisolated enum ModerationContentTypeV1: String, Codable, CaseIterable, Sendable {
    case visit, comment, user
}

nonisolated enum ModerationReasonV1: String, Codable, CaseIterable, Identifiable, Sendable {
    case spam, harassment, hate, sexual, violence, privacy, other
    var id: Self { self }
    var title: String {
        switch self {
        case .spam: "垃圾或推广"
        case .harassment: "骚扰或欺凌"
        case .hate: "仇恨内容"
        case .sexual: "不适当色情内容"
        case .violence: "暴力或危险内容"
        case .privacy: "泄露隐私"
        case .other: "其他"
        }
    }
}

nonisolated struct ContentReportResponseV1: Codable, Equatable, Sendable {
    let apiVersion: Int
    let reportId: String
    let status: String
    let duplicate: Bool
}

nonisolated struct UserBlockMutationV1: Codable, Equatable, Sendable {
    let apiVersion: Int
    let blockedUserId: String
    let blocked: Bool
    let duplicate: Bool
}
