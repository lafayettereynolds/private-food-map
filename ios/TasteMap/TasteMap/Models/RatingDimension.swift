import Foundation

enum RatingDimension: String, CaseIterable, Codable, Identifiable, Sendable {
    case value
    case environment
    case service

    var id: String { rawValue }

    var title: String {
        switch self {
        case .value: "性价比"
        case .environment: "环境"
        case .service: "服务"
        }
    }

    var systemImage: String {
        switch self {
        case .value: "yensign.circle.fill"
        case .environment: "leaf.fill"
        case .service: "hand.raised.fingers.spread.fill"
        }
    }

    @MainActor
    func value(in visit: Visit) -> Double? {
        switch self {
        case .value: visit.valueRating
        case .environment: visit.environmentRating
        case .service: visit.serviceRating
        }
    }

    func value(in draft: VisitDraft) -> Double? {
        switch self {
        case .value: draft.valueRating
        case .environment: draft.environmentRating
        case .service: draft.serviceRating
        }
    }

    func setValue(_ value: Double?, in draft: inout VisitDraft) {
        switch self {
        case .value: draft.valueRating = value
        case .environment: draft.environmentRating = value
        case .service: draft.serviceRating = value
        }
    }
}
