import Foundation

enum CompanionLinkScopeV1: String, Codable, CaseIterable, Sendable {
    case incoming, outgoing, active
}

enum CompanionLinkActionV1: String, Codable, Sendable {
    case accept, reject, cancel, unlink
}

struct SocialSuggestionV1: Codable, Equatable, Identifiable, Sendable {
    let user: SocialUserResultV1
    let reasons: [String]
    var id: String { user.id }
}

struct SocialSuggestionPageV1: Codable, Equatable, Sendable {
    let apiVersion: Int
    let items: [SocialSuggestionV1]
    let nextCursor: String?
}

struct CompanionLinkRequestV1: Codable, Equatable, Identifiable, Sendable {
    let apiVersion: Int
    let id: String
    let companionId: String
    let companionDisplayName: String
    let requesterUserId: String
    let targetUserId: String
    let status: String
    let otherUser: SocialUserSummaryV1
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let serverVersion: Int
}

struct CompanionLinkPageV1: Codable, Equatable, Sendable {
    let apiVersion: Int
    let scope: CompanionLinkScopeV1
    let items: [CompanionLinkRequestV1]
    let nextCursor: String?
}

enum SharedMealScopeV1: String, Codable, CaseIterable, Sendable {
    case incoming, sent, accepted
}

enum SharedMealParticipantActionV1: String, Codable, Sendable {
    case accept, decline, attach
}

struct SharedMealInvitationV1: Codable, Equatable, Identifiable, Sendable {
    let apiVersion: Int
    let mealId: String
    let participantId: String
    let sourceVisitId: String
    let inviter: SocialUserSummaryV1
    let participant: SocialUserSummaryV1
    let participantUserId: String
    let restaurant: PublicContentRestaurantV1
    let occurredAt: String
    let visibility: ProfileVisibility
    let status: String
    let visitId: String?
    let createdAt: String
    let updatedAt: String
    let revokedAt: String?
    let serverVersion: Int
    var id: String { participantId }
}

struct SharedMealPageV1: Codable, Equatable, Sendable {
    let apiVersion: Int
    let scope: SharedMealScopeV1
    let items: [SharedMealInvitationV1]
    let nextCursor: String?
}

struct SharedMealInviteResponseV1: Codable, Equatable, Sendable {
    let apiVersion: Int
    let mealId: String
    let duplicate: Bool
    let invitations: [SharedMealInvitationV1]
}
