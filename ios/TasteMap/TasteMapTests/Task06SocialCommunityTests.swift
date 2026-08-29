import Foundation
import Testing
@testable import TasteMap

@Suite("Task 06 Social and Community", .serialized)
@MainActor
struct Task06SocialCommunityTests {
    @Test("Old cached community cards decode with zero engagement")
    func legacyCommunityCardRemainsCompatible() throws {
        let page = try JSONDecoder().decode(CommunityFeedPageV1.self, from: Data(Self.legacyPageJSON.utf8))
        let item = try #require(page.items.first)
        #expect(item.engagement == .zero)
    }

    @Test("Shared Meal contract preserves Apple Maps identity and participant")
    func sharedMealContractDecodes() throws {
        let invitation = try JSONDecoder().decode(
            SharedMealInvitationV1.self,
            from: Data(Self.sharedMealJSON.utf8)
        )
        #expect(invitation.inviter.userId == "tm_a")
        #expect(invitation.participant.userId == "tm_b")
        #expect(invitation.restaurant.placeIdentities.first?.provider == .appleMaps)
        #expect(invitation.restaurant.placeIdentities.first?.externalId == "apple-only-place")
        #expect(invitation.visitId == nil)
    }

    @Test("Shared Meal reference survives Visit validation")
    func sharedMealReferenceSurvivesVisitDraftValidation() throws {
        let draft = try VisitDraft(sharedMealID: "meal-06").validated()
        #expect(draft.sharedMealID == "meal-06")
        #expect(draft.rating == nil)
    }

    @Test("Invitation outbox persists, isolates users, deduplicates and flushes idempotently")
    func sharedMealOutboxPersistenceAndIsolation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("task06-outbox-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("outbox.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let credential = AuthCredential(
            user: .init(id: "tm_a", email: nil),
            accessToken: "access", accessTokenExpiresAt: .now.addingTimeInterval(600),
            refreshToken: "refresh", refreshTokenExpiresAt: .now.addingTimeInterval(3_600)
        )
        let session = AuthSessionManager(
            api: Task06AuthAPI(),
            credentialStore: Task06CredentialStore(credential)
        )
        let api = Task06CollaborationAPI()
        let first = SocialCollaborationOutbox(api: api, sessionManager: session, fileURL: fileURL)
        try first.enqueue(
            ownerUserID: "tm_a", sourceVisitID: "visit-a",
            participantUserIDs: ["tm_b", "tm_b", "tm_a"]
        )
        try first.enqueue(
            ownerUserID: "tm_a", sourceVisitID: "visit-a",
            participantUserIDs: ["tm_b"]
        )
        try first.enqueue(
            ownerUserID: "tm_other", sourceVisitID: "visit-other",
            participantUserIDs: ["tm_b"]
        )
        #expect(first.pendingCount(ownerUserID: "tm_a") == 1)
        #expect(first.pendingCount(ownerUserID: "tm_other") == 1)

        let relaunched = SocialCollaborationOutbox(api: api, sessionManager: session, fileURL: fileURL)
        #expect(relaunched.pendingCount(ownerUserID: "tm_a") == 1)
        await relaunched.flush()

        #expect(await api.invitationCount == 1)
        #expect(await api.lastMutationID == "ios-shared-meal:tm_a:visit-a:tm_b")
        #expect(relaunched.pendingCount(ownerUserID: "tm_a") == 0)
        #expect(relaunched.pendingCount(ownerUserID: "tm_other") == 1)
    }

    private static let legacyPageJSON = """
    {"apiVersion":1,"scope":"latest","generatedAt":"2026-08-30T00:00:00.000Z","items":[{"id":"visit:legacy","kind":"visit","eventAt":"2026-08-30T00:00:00.000Z","updatedAt":"2026-08-30T00:00:00.000Z","user":{"userId":"tm_a","displayName":"A","bio":null,"city":null,"avatarPhotoId":null,"avatarPresetId":"otter","friendshipId":null,"friendshipState":"none","isFollowing":false},"restaurant":{"globalKey":"place:legacy","placeIdentities":[],"name":"Legacy","address":"","city":"","latitude":0,"longitude":0,"tags":[],"pricePerPerson":null,"merchantImageUrl":null,"markerEmoji":"🍽️","photo":null},"visit":{"id":"visit-legacy","ownerUserId":"tm_a","restaurantGlobalKey":"place:legacy","visitedAt":"2026-08-30T00:00:00.000Z","rating":null,"note":null,"visibility":"public","photos":[],"updatedAt":"2026-08-30T00:00:00.000Z"},"viewerState":"none","cacheScope":"public"}],"nextCursor":null}
    """

    private static let sharedMealJSON = """
    {"apiVersion":1,"mealId":"meal-06","participantId":"participant-06","sourceVisitId":"visit-a","inviter":{"userId":"tm_a","displayName":"Alice","bio":null,"city":"杭州","avatarPhotoId":null,"avatarPresetId":"otter"},"participant":{"userId":"tm_b","displayName":"Bob","bio":null,"city":"杭州","avatarPhotoId":null,"avatarPresetId":"polar-bear"},"participantUserId":"tm_b","restaurant":{"globalKey":"place:apple","placeIdentities":[{"provider":"apple_maps","externalId":"apple-only-place","isPrimary":true}],"name":"Apple Restaurant","address":"West Lake","city":"杭州","latitude":30.2,"longitude":120.1,"tags":[],"pricePerPerson":null,"merchantImageUrl":null,"markerEmoji":"🍜","photo":null},"occurredAt":"2026-08-30T00:00:00.000Z","visibility":"friends","status":"accepted","visitId":null,"createdAt":"2026-08-30T00:00:00.000Z","updatedAt":"2026-08-30T00:00:00.000Z","revokedAt":null,"serverVersion":2}
    """
}

nonisolated private final class Task06CredentialStore: AuthCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: AuthCredential?

    init(_ value: AuthCredential?) { self.value = value }
    func load() throws -> AuthCredential? { lock.withLock { value } }
    func save(_ credential: AuthCredential) throws { lock.withLock { value = credential } }
    func delete() throws { lock.withLock { value = nil } }
}

private actor Task06AuthAPI: AuthAPI {
    func challenge() async throws -> AuthChallengeV1 { throw AuthClientError.invalidResponse }
    func exchangeAppleToken(
        identityToken: String, state: String, nonce: String,
        givenName: String?, familyName: String?
    ) async throws -> AuthSessionResponseV1 { throw AuthClientError.invalidResponse }
    func refresh(refreshToken: String) async throws -> AuthSessionResponseV1 { throw AuthClientError.invalidResponse }
    func logout(accessToken: String?, refreshToken: String) async throws {}
}

@MainActor
private final class Task06CollaborationAPI: SocialCollaborationAPI {
    private(set) var invitationCount = 0
    private(set) var lastMutationID: String?

    func suggestions(cursor: String?, limit: Int) async throws -> SocialSuggestionPageV1 {
        throw SyncAPIError.invalidResponse
    }
    func companionLinks(scope: CompanionLinkScopeV1, cursor: String?, limit: Int) async throws -> CompanionLinkPageV1 {
        throw SyncAPIError.invalidResponse
    }
    func requestCompanionLink(companionID: String, targetUserID: String) async throws -> CompanionLinkRequestV1 {
        throw SyncAPIError.invalidResponse
    }
    func mutateCompanionLink(id: String, action: CompanionLinkActionV1) async throws -> CompanionLinkRequestV1 {
        throw SyncAPIError.invalidResponse
    }
    func sharedMeals(scope: SharedMealScopeV1, cursor: String?, limit: Int) async throws -> SharedMealPageV1 {
        throw SyncAPIError.invalidResponse
    }
    func inviteSharedMeal(
        sourceVisitID: String,
        participantUserIDs: [String],
        mutationID: String
    ) async throws -> SharedMealInviteResponseV1 {
        invitationCount += 1
        lastMutationID = mutationID
        return .init(apiVersion: 1, mealId: "meal-06", duplicate: false, invitations: [])
    }
    func mutateSharedMealParticipant(
        id: String, action: SharedMealParticipantActionV1, visitID: String?
    ) async throws -> SharedMealInvitationV1 { throw SyncAPIError.invalidResponse }
    func revokeSharedMeal(id: String) async throws -> SharedMealInvitationV1 {
        throw SyncAPIError.invalidResponse
    }
}
