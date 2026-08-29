#if DEBUG
import SwiftUI

private enum PremiumPreviewFixtures {
    static let date = Date(timeIntervalSince1970: 1_788_000_000)

    @MainActor static func service(
        status: MembershipStatus,
        offline: Bool = false,
        provider: any MembershipPurchaseProviding = UnconfiguredMembershipPurchaseProvider()
    ) -> PremiumEntitlementService {
        let snapshot: PremiumEntitlementSnapshot? = switch status {
        case .premium, .gracePeriod:
            PremiumEntitlementSnapshot(
                userID: "tm_preview",
                state: status == .gracePeriod ? .gracePeriod : .active,
                source: .development,
                kind: .lifetime,
                startsAt: date,
                updatedAt: date,
                verifiedAt: date
            )
        case .expired:
            PremiumEntitlementSnapshot(
                userID: "tm_preview",
                state: .expired,
                source: .promo,
                kind: .fixedTerm,
                startsAt: date.addingTimeInterval(-86_400 * 30),
                expiresAt: date.addingTimeInterval(-86_400),
                updatedAt: date,
                verifiedAt: date
            )
        default: nil
        }
        let service = PremiumEntitlementService.preview(
            status: status,
            snapshot: snapshot,
            purchaseProvider: provider
        )
        service.setPreviewOfflineState(offline)
        return service
    }
}

private struct PreviewMembershipPurchaseProvider: MembershipPurchaseProviding {
    let capabilities: MembershipPurchaseCapabilities = [.purchase, .restore]
    func products() async throws -> [MembershipProduct] {
        [
            MembershipProduct(
                id: "development.test.product",
                displayName: "Development 测试方案",
                valueDescription: "仅用于验证 Store Product 展示抽象",
                displayPrice: "StoreKit 测试价格",
                period: .annual,
                billingPeriodDescription: "每年续订"
            ),
        ]
    }
    func purchase(productID: String) async throws -> MembershipPurchaseResult {
        .init(transactionID: "development-only", requiresEntitlementRefresh: false, outcome: .completed)
    }
    func restore() async throws -> MembershipPurchaseResult {
        .init(transactionID: nil, requiresEntitlementRefresh: false, outcome: .completed)
    }
    func manageSubscription() async throws {}
}

private struct PremiumPreviewHost<Content: View>: View {
    let service: PremiumEntitlementService
    private let content: () -> Content

    init(
        service: PremiumEntitlementService,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.service = service
        self.content = content
    }

    var body: some View {
        content().environment(service)
    }
}

#Preview("01 Free") {
    PremiumPreviewHost(service: PremiumPreviewFixtures.service(status: .free)) {
        PremiumPaywallView(source: .profile)
    }
}

#Preview("02 Premium") {
    PremiumPreviewHost(service: PremiumPreviewFixtures.service(status: .premium)) {
        PremiumPaywallView(source: .settings)
    }
}

#Preview("03 Loading entitlement") {
    PremiumPreviewHost(service: PremiumPreviewFixtures.service(status: .loading)) {
        PremiumPaywallView(source: .feature(.fullTasteProfile))
    }
}

#Preview("04 Offline cached Premium") {
    PremiumPreviewHost(service: PremiumPreviewFixtures.service(status: .premium, offline: true)) {
        PremiumPaywallView(source: .settings)
    }
}

#Preview("05 Expired future state") {
    PremiumPreviewHost(service: PremiumPreviewFixtures.service(status: .expired)) {
        PremiumPaywallView(source: .settings)
    }
}

#Preview("06 Paywall normal") {
    PremiumPreviewHost(service: PremiumPreviewFixtures.service(status: .free)) {
        PremiumPaywallView(source: .feature(.annualRecap))
    }
}

#Preview("07 No Store Product configured") {
    PremiumPreviewHost(service: PremiumPreviewFixtures.service(status: .free)) {
        PremiumPaywallView(source: .settings)
    }
}

#Preview("08 Development test product") {
    PremiumPreviewHost(service: PremiumPreviewFixtures.service(
        status: .free,
        provider: PreviewMembershipPurchaseProvider()
    )) {
        PremiumPaywallView(source: .profile)
    }
}

#Preview("09 Long feature names") {
    PremiumPreviewHost(service: PremiumPreviewFixtures.service(status: .free)) {
        NavigationStack {
            PremiumFeatureLockedView(feature: .recommendationSourceAnalysis)
        }
    }
}

#Preview("10 Small screen", traits: .fixedLayout(width: 320, height: 568)) {
    PremiumPreviewHost(service: PremiumPreviewFixtures.service(status: .free)) {
        PremiumPaywallView(source: .profile)
    }
}

#Preview("11 Large Type") {
    PremiumPreviewHost(service: PremiumPreviewFixtures.service(status: .free)) {
        PremiumPaywallView(source: .feature(.companionAnalysis))
            .environment(\.dynamicTypeSize, .accessibility3)
    }
}

#Preview("12 Dark Mode behavior") {
    PremiumPreviewHost(service: PremiumPreviewFixtures.service(status: .premium)) {
        PremiumPaywallView(source: .settings)
            .preferredColorScheme(.dark)
    }
}
#endif
