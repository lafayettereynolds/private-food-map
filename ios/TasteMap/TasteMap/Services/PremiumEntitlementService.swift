import Foundation
import Observation

@Observable
@MainActor
final class PremiumEntitlementService {
    private var storedMembershipStatus: MembershipStatus = .unknown
    private(set) var membershipStatus: MembershipStatus {
        get {
            if storedMembershipStatus == .premium, let snapshot, !snapshot.isUsable(at: now()) { return .expired }
            return storedMembershipStatus
        }
        set { storedMembershipStatus = newValue }
    }
    private(set) var snapshot: PremiumEntitlementSnapshot?
    private(set) var activeUserID: String?
    private(set) var isRefreshing = false
    private(set) var isUsingOfflineCache = false
    private(set) var lastErrorMessage: String?
    private(set) var trialEligibility: PremiumTrialEligibility?
    private(set) var isClaimingTrial = false
    private(set) var trialMessage: String?
    var presentedSource: PremiumEntrySource?

    @ObservationIgnored private let api: any PremiumEntitlementAPI
    @ObservationIgnored private let cache: any PremiumEntitlementCaching
    @ObservationIgnored private let purchaseProvider: any MembershipPurchaseProviding
    @ObservationIgnored private let environment: TasteMapAppEnvironment
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let cacheMaximumAge: TimeInterval
    @ObservationIgnored private var commerceNotificationTask: Task<Void, Never>?
    @ObservationIgnored private var sessionGeneration = UUID()
    @ObservationIgnored private var refreshID: UUID?
    @ObservationIgnored private var trialRequestID = UUID()
#if DEBUG
    @ObservationIgnored private var developmentOverride: DevelopmentPremiumOverride?
#endif

    init(
        api: any PremiumEntitlementAPI,
        cache: any PremiumEntitlementCaching = KeychainPremiumEntitlementCache(),
        purchaseProvider: any MembershipPurchaseProviding = UnconfiguredMembershipPurchaseProvider(),
        environment: TasteMapAppEnvironment = .current,
        cacheMaximumAge: TimeInterval = 7 * 24 * 60 * 60,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.api = api
        self.cache = cache
        self.purchaseProvider = purchaseProvider
        self.environment = environment
        self.cacheMaximumAge = cacheMaximumAge
        self.now = now
        purchaseProvider.startObserving()
        commerceNotificationTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: .tasteMapPremiumEntitlementChanged
            ) {
                guard let self,
                      let userID = notification.object as? String,
                      userID == self.activeUserID else { continue }
                await self.refresh()
            }
        }
    }

    var productsProvider: any MembershipPurchaseProviding { purchaseProvider }

#if DEBUG
    var developmentOverrideAvailable: Bool {
        DevelopmentPremiumOverridePolicy.isAvailable(buildIsDebug: true, environment: environment)
    }
#endif

    func activate(userID: String, refreshFromServer: Bool = true) async {
        let userID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userID.isEmpty else { return sessionDidEnd() }
        if activeUserID != userID {
            sessionGeneration = UUID()
            refreshID = nil
            isRefreshing = false
            trialEligibility = nil
            trialMessage = nil
            isClaimingTrial = false
            activeUserID = userID
            snapshot = nil
            membershipStatus = .loading
            isUsingOfflineCache = false
            lastErrorMessage = nil
        }
        let generation = sessionGeneration
        await purchaseProvider.activate(userID: userID)
        guard activeUserID == userID, sessionGeneration == generation else { return }
#if DEBUG
        if let developmentOverride, environment == .development {
            apply(developmentOverride.snapshot(userID: userID, now: now()), offline: false)
            return
        }
#endif
        applyCachedSnapshot(for: userID)
        guard refreshFromServer else {
            if snapshot == nil { membershipStatus = .unknown }
            return
        }
        await refresh()
    }

    func refresh() async {
        guard let userID = activeUserID else { return }
#if DEBUG
        if let developmentOverride, environment == .development {
            apply(developmentOverride.snapshot(userID: userID, now: now()), offline: false)
            return
        }
#endif
        if isRefreshing { return }
        let generation = sessionGeneration
        let requestID = UUID()
        refreshID = requestID
        isRefreshing = true
        defer {
            if refreshID == requestID { isRefreshing = false; refreshID = nil }
        }
        do {
            let next = try PremiumEntitlementSnapshot(response: try await api.entitlement())
            guard next.userID == userID, activeUserID == userID, sessionGeneration == generation, refreshID == requestID else {
                throw PremiumEntitlementContractError.invalidResponse
            }
            try cache.save(next)
            apply(next, offline: false)
            lastErrorMessage = nil
        } catch {
            guard activeUserID == userID, sessionGeneration == generation, refreshID == requestID else { return }
            if let cached = validCachedSnapshot(for: userID) {
                apply(cached, offline: true)
            } else {
                snapshot = nil
                membershipStatus = .unknown
                isUsingOfflineCache = false
            }
            lastErrorMessage = "会员状态暂时无法在线刷新。"
        }
    }

    func refreshTrialEligibility() async {
        guard let userID = activeUserID else { return }
        let generation = sessionGeneration
        let requestID = UUID()
        trialRequestID = requestID
        do {
            let result = try await api.trialEligibility()
            guard activeUserID == userID, sessionGeneration == generation, trialRequestID == requestID else { return }
            guard result.apiVersion == 1, result.userId == userID, result.trialDays == 7 else {
                throw PremiumEntitlementAPIError.invalidResponse
            }
            trialEligibility = result
        } catch {
            guard activeUserID == userID, sessionGeneration == generation, trialRequestID == requestID else { return }
            trialEligibility = nil
        }
    }

    @discardableResult
    func claimTrial() async throws -> PremiumTrialClaim {
        guard let userID = activeUserID, !isClaimingTrial else { throw PremiumEntitlementAPIError.invalidResponse }
        let generation = sessionGeneration
        isClaimingTrial = true
        trialMessage = nil
        defer { if sessionGeneration == generation { isClaimingTrial = false } }
        do {
            let result = try await api.claimTrial()
            guard activeUserID == userID, sessionGeneration == generation else { throw PremiumEntitlementAPIError.invalidResponse }
            guard result.apiVersion == 1, result.userId == userID, result.source == "signup_trial", result.isPremium,
                  let expiry = PremiumEntitlementSnapshot.date(result.expiresAt) else { throw PremiumEntitlementAPIError.invalidResponse }
            let next = try PremiumEntitlementSnapshot(response: result.membership)
            guard next.userID == userID else { throw PremiumEntitlementAPIError.invalidResponse }
            // Invalidate older refreshes; the claim response contains the server's union of all entitlements.
            refreshID = nil
            isRefreshing = false
            try? cache.save(next)
            apply(next, offline: false)
            trialRequestID = UUID()
            trialEligibility = PremiumTrialEligibility(apiVersion: 1, userId: userID, eligible: false, trialDays: 7)
            trialMessage = "领取成功，7 天 Premium 有效期至 \(TasteMapDisplayDate.numericDateTime(expiry))"
            return result
        } catch {
            guard activeUserID == userID, sessionGeneration == generation else { throw error }
            trialMessage = error.localizedDescription
            await refreshTrialEligibility()
            await refresh()
            throw error
        }
    }

    func sessionDidEnd() {
        sessionGeneration = UUID()
        refreshID = nil
        let previousUserID = activeUserID
        let endedGeneration = sessionGeneration
        Task {
            guard activeUserID == nil, sessionGeneration == endedGeneration else { return }
            await purchaseProvider.sessionDidEnd(userID: previousUserID)
        }
        if let previousUserID { try? cache.delete(userID: previousUserID) }
        trialEligibility = nil
        trialMessage = nil
        isClaimingTrial = false
        activeUserID = nil
        snapshot = nil
        membershipStatus = .unknown
        isUsingOfflineCache = false
        isRefreshing = false
        lastErrorMessage = nil
        presentedSource = nil
#if DEBUG
        developmentOverride = nil
#endif
    }

    func access(
        for feature: PremiumFeature,
        operation: PremiumProtectedOperation = .view
    ) -> PremiumAccessDecision {
        PremiumFeatureAccessPolicy.decision(
            for: feature,
            operation: operation,
            membershipStatus: membershipStatus
        )
    }

    var visitPhotoLimit: Int {
        PremiumFeatureAccessPolicy.visitPhotoLimit(membershipStatus: membershipStatus)
    }

    func openPaywall(from source: PremiumEntrySource) {
        presentedSource = source
    }

    func dismissPaywall() {
        presentedSource = nil
    }

#if DEBUG
    @discardableResult
    func setDevelopmentOverride(_ override: DevelopmentPremiumOverride?) -> Bool {
        guard DevelopmentPremiumOverridePolicy.isAvailable(
            buildIsDebug: true,
            environment: environment
        ) else { return false }
        developmentOverride = override
        if let userID = activeUserID {
            if let override {
                apply(override.snapshot(userID: userID, now: now()), offline: false)
            } else {
                snapshot = nil
                membershipStatus = .loading
                Task { await refresh() }
            }
        }
        return true
    }

    /// Synchronous fixture activation for the isolated Visual QA runtime. This
    /// is compiled out of Release and never writes StoreKit, Keychain, or the
    /// entitlement backend.
    func activateVisualQAFixture(userID: String, override: DevelopmentPremiumOverride) {
        activeUserID = userID
        developmentOverride = override
        apply(override.snapshot(userID: userID, now: now()), offline: false)
    }

#endif

    static func preview(
        status: MembershipStatus,
        userID: String = "tm_preview",
        snapshot: PremiumEntitlementSnapshot? = nil,
        purchaseProvider: any MembershipPurchaseProviding = UnconfiguredMembershipPurchaseProvider()
    ) -> PremiumEntitlementService {
        let service = PremiumEntitlementService(
            api: StaticPremiumEntitlementAPI(error: PremiumEntitlementAPIError.invalidResponse),
            cache: InMemoryPremiumEntitlementCache(),
            purchaseProvider: purchaseProvider,
            environment: .development
        )
        service.activeUserID = userID
        service.snapshot = snapshot
        service.membershipStatus = status
        service.isUsingOfflineCache = status == .premium && snapshot != nil
        return service
    }

    func setPreviewOfflineState(_ isOffline: Bool) {
        isUsingOfflineCache = isOffline
    }

    private func applyCachedSnapshot(for userID: String) {
        guard let cached = validCachedSnapshot(for: userID) else {
            if snapshot == nil { membershipStatus = .loading }
            return
        }
        apply(cached, offline: true)
    }

    private func validCachedSnapshot(for userID: String) -> PremiumEntitlementSnapshot? {
        guard let cached = try? cache.load(userID: userID),
              cached.userID == userID,
              cached.verifiedAt <= now(),
              now().timeIntervalSince(cached.verifiedAt) <= cacheMaximumAge,
              cached.expiresAt.map({ $0 > now() }) ?? (cached.isLifetime || !cached.isPremium),
              cached.isUsable(at: now()) || !cached.isPremium else { return nil }
        return cached
    }

    private func apply(_ snapshot: PremiumEntitlementSnapshot, offline: Bool) {
        guard snapshot.userID == activeUserID else { return }
        self.snapshot = snapshot
        isUsingOfflineCache = offline
        switch snapshot.state {
        case .active:
            membershipStatus = snapshot.isUsable(at: now()) ? .premium : .expired
        case .gracePeriod:
            membershipStatus = .gracePeriod
        case .expired:
            membershipStatus = .expired
        case .free:
            membershipStatus = .free
        }
    }
}

#if DEBUG
nonisolated enum DevelopmentPremiumOverride: String, Sendable {
    case free
    case premium
    case giftAnnual
    case giftLifetime

    func snapshot(userID: String, now: Date) -> PremiumEntitlementSnapshot {
        switch self {
        case .free:
            PremiumEntitlementSnapshot(userID: userID, state: .free, verifiedAt: now)
        case .giftAnnual, .giftLifetime:
            PremiumEntitlementSnapshot(
                userID: userID, state: .active,
                source: self == .giftLifetime ? .giftLifetime : .giftAnnual,
                kind: self == .giftLifetime ? .lifetime : .fixedTerm,
                startsAt: now,
                expiresAt: self == .giftLifetime ? nil : Calendar(identifier: .gregorian).date(byAdding: .year, value: 1, to: now),
                updatedAt: now, verifiedAt: now
            )
        case .premium:
            PremiumEntitlementSnapshot(
                userID: userID,
                state: .active,
                source: .development,
                kind: .lifetime,
                startsAt: now,
                updatedAt: now,
                verifiedAt: now
            )
        }
    }
}

nonisolated enum DevelopmentPremiumOverridePolicy {
    static func isAvailable(buildIsDebug: Bool, environment: TasteMapAppEnvironment) -> Bool {
        buildIsDebug && environment == .development
    }
}
#endif

@MainActor
private struct StaticPremiumEntitlementAPI: PremiumEntitlementAPI {
    let response: PremiumEntitlementResponseV1?
    let error: Error?

    init(response: PremiumEntitlementResponseV1) {
        self.response = response
        error = nil
    }

    init(error: Error) {
        response = nil
        self.error = error
    }

    func entitlement() async throws -> PremiumEntitlementResponseV1 {
        if let error { throw error }
        guard let response else { throw PremiumEntitlementAPIError.invalidResponse }
        return response
    }
}
