import Foundation

struct RecommendationPreferenceEvent: Codable, Equatable, Sendable {
    struct Intent: Codable, Equatable, Sendable {
        let classifierVersion: Int
        let brandID: String?
        let context: String?
        enum CodingKeys: String, CodingKey { case classifierVersion, brandID, context }
        func encode(to encoder: Encoder) throws {
            var value = encoder.container(keyedBy: CodingKeys.self)
            try value.encode(classifierVersion, forKey: .classifierVersion)
            try value.encode(brandID, forKey: .brandID)
            try value.encode(context, forKey: .context)
        }
    }
    let eventID: String
    let aliases: [String]
    let source: String
    let occurredAt: String?
    let intent: Intent?
    enum CodingKeys: String, CodingKey { case eventID, aliases, source, occurredAt, intent }
    func encode(to encoder: Encoder) throws {
        var value = encoder.container(keyedBy: CodingKeys.self)
        try value.encode(eventID, forKey: .eventID)
        try value.encode(aliases, forKey: .aliases)
        try value.encode(source, forKey: .source)
        try value.encode(occurredAt, forKey: .occurredAt)
        try value.encode(intent, forKey: .intent)
    }
}

struct RecommendationPreferencePull: Decodable, Sendable {
    let apiVersion: Int
    let ownerID: String
    let events: [RecommendationPreferenceEvent]
    let cursor: String
    let hasMore: Bool
}
struct RecommendationPreferencePush: Decodable, Sendable {
    struct Receipt: Decodable, Sendable { let eventID: String; let revision: Int }
    let apiVersion: Int
    let ownerID: String
    let receipts: [Receipt]
}

/// One durable owner-scoped record commits pending IDs and pull checkpoint with
/// merged events. The old v1 arrays are never replaced by a remote snapshot.
@MainActor
enum RecommendationPreferenceLedger {
    private static var generations: [String: Int] = [:]
    static func generation(owner: String) -> Int { generations[owner, default: 0] }
    static func purge(owner: String, defaults: UserDefaults = .standard) {
        generations[owner, default: 0] += 1
        for prefix in ["tastemap.recommendation-sync.v1.", "tastemap.recommendation-exclusions.v1.", "tastemap.recommendation-intent.v1."] {
            defaults.removeObject(forKey: prefix + owner)
        }
    }
    struct State: Codable, Sendable {
        var events: [RecommendationPreferenceEvent] = []
        var pending: Set<String> = []
        var cursor: String? = nil
    }
    static func load(owner: String, defaults: UserDefaults = .standard) throws -> State {
        let key = "tastemap.recommendation-sync.v1.\(owner)"
        guard defaults.object(forKey: key) != nil else { return State() }
        guard let data = defaults.data(forKey: key) else { throw SyncAPIError.invalidResponse }
        return try JSONDecoder().decode(State.self, from: data)
    }
    private static func save(_ state: State, owner: String, defaults: UserDefaults) throws {
        defaults.set(try JSONEncoder().encode(state), forKey: "tastemap.recommendation-sync.v1.\(owner)")
    }
    static func values(owner: String, defaults: UserDefaults = .standard) throws -> (excluded: Set<String>, votes: [RestaurantRecommendationIntentVote]) {
        let events = try load(owner: owner, defaults: defaults).events
        let groups = events.map { Set($0.aliases) }
        let allAliases = Set(events.flatMap(\.aliases))
        var seen = Set<String>(); var votes: [RestaurantRecommendationIntentVote] = []
        for event in events where event.intent != nil && seen.isDisjoint(with: event.aliases) {
            let aliases = RestaurantRecommendationIntentPolicy.expand(Set(event.aliases), through: groups)
            seen.formUnion(aliases)
            let intents = events.filter { !aliases.isDisjoint(with: $0.aliases) }.compactMap(\.intent)
            let brands = Set(intents.compactMap(\.brandID)); let contexts = Set(intents.compactMap(\.context))
            votes.append(.init(aliases: aliases, brandID: brands.count == 1 ? brands.first : nil,
                               context: contexts.count == 1 ? contexts.first : nil))
        }
        return (allAliases, votes)
    }
    static func capture(owner: String, excluded: Set<String>, votes: [RestaurantRecommendationIntentVote],
                        explicitAliases: Set<String>? = nil, now: Date = .now, defaults: UserDefaults = .standard) throws {
        var state = try load(owner: owner, defaults: defaults)
        func append(_ aliases: Set<String>, intent: RecommendationPreferenceEvent.Intent?, explicit: Bool) {
            guard !aliases.isEmpty else { return }
            // Untransmittable legacy identifiers stay local, never coerced to a
            // different restaurant identity. Remaining valid aliases can sync.
            let valid = aliases.filter { !$0.isEmpty && $0.count <= 256 && $0.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil }.sorted()
            guard let anchor = valid.first else { return }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            for offset in stride(from: 0, to: valid.count, by: 31) {
                let chunk = Array(Set([anchor] + Array(valid[offset..<min(offset + 31, valid.count)])).sorted())
                let event = RecommendationPreferenceEvent(eventID: UUID().uuidString.lowercased(), aliases: chunk,
                    source: explicit ? "explicit_dismissal" : intent == nil ? "legacy_exclusion" : "legacy_intent",
                    occurredAt: explicit ? formatter.string(from: now) : nil, intent: intent)
                state.events.append(event); state.pending.insert(event.eventID)
            }
        }
        for vote in votes {
            guard !state.events.contains(where: { $0.intent != nil && !vote.aliases.isDisjoint(with: $0.aliases) }) else { continue }
            append(vote.aliases, intent: .init(classifierVersion: 1, brandID: vote.brandID, context: vote.context),
                   explicit: explicitAliases.map { !$0.isDisjoint(with: vote.aliases) } ?? false)
        }
        let missing = excluded.subtracting(state.events.flatMap(\.aliases))
        if !missing.isEmpty {
            // Include known aliases to preserve alias connectivity across devices.
            for aliases in votes.map(\.aliases) where !aliases.isDisjoint(with: missing) { append(aliases, intent: nil, explicit: false) }
            // A flat old exclusion list does NOT establish identity equivalence.
            for alias in excluded.subtracting(state.events.flatMap(\.aliases)).sorted() {
                append([alias], intent: nil, explicit: false)
            }
        }
        try save(state, owner: owner, defaults: defaults)
    }
    static func merge(_ response: RecommendationPreferencePull, owner: String, defaults: UserDefaults = .standard) throws {
        guard response.apiVersion == 1, response.ownerID == owner, !response.cursor.isEmpty else { throw SyncAPIError.invalidResponse }
        var state = try load(owner: owner, defaults: defaults)
        for event in response.events {
            guard !event.eventID.isEmpty, !event.aliases.isEmpty, event.aliases.count <= 32,
                  event.aliases.allSatisfy({ !$0.isEmpty && $0.count <= 256 && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    && $0.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil }),
                  ["explicit_dismissal", "legacy_exclusion", "legacy_intent"].contains(event.source),
                  event.source != "legacy_exclusion" || (event.intent == nil && event.occurredAt == nil),
                  event.source != "legacy_intent" || event.intent != nil,
                  event.source != "explicit_dismissal" || event.occurredAt != nil,
                  event.intent.map({ $0.classifierVersion == 1
                    && ($0.brandID == nil || RestaurantRecommendationIntentPolicy.brands.contains($0.brandID!))
                    && ($0.context == nil || RestaurantRecommendationIntentPolicy.contexts.contains($0.context!)) }) ?? true else { throw SyncAPIError.invalidResponse }
            if let old = state.events.first(where: { $0.eventID == event.eventID }) {
                guard old == event else { throw SyncAPIError.invalidResponse }
            } else { state.events.append(event) }
        }
        state.cursor = response.cursor
        try save(state, owner: owner, defaults: defaults)
    }
    static func acknowledge(_ response: RecommendationPreferencePush, sent: [RecommendationPreferenceEvent], owner: String, defaults: UserDefaults = .standard) throws {
        let ids = Set(sent.map(\.eventID))
        guard response.apiVersion == 1, response.ownerID == owner,
              response.receipts.allSatisfy({ ids.contains($0.eventID) && $0.revision > 0 }) else { throw SyncAPIError.invalidResponse }
        var state = try load(owner: owner, defaults: defaults)
        state.pending.subtract(response.receipts.map(\.eventID))
        try save(state, owner: owner, defaults: defaults)
    }
}

@MainActor
protocol RecommendationPreferenceAPI {
    func pull(owner: String, cursor: String?) async throws -> RecommendationPreferencePull
    func push(owner: String, events: [RecommendationPreferenceEvent]) async throws -> RecommendationPreferencePush
}

@MainActor
final class URLSessionRecommendationPreferenceAPI: RecommendationPreferenceAPI {
    let configuration: APIConfiguration
    let authorization: any SyncAuthorizationProviding
    let session: URLSession
    init(configuration: APIConfiguration, authorization: any SyncAuthorizationProviding, session: URLSession) {
        self.configuration = configuration; self.authorization = authorization; self.session = session
    }
    func pull(owner: String, cursor: String?) async throws -> RecommendationPreferencePull {
        var parts = URLComponents(url: try configuration.url(for: "/api/v1/recommendation-preferences/pull"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [.init(name: "apiVersion", value: "1"), .init(name: "limit", value: "100"), .init(name: "cursor", value: cursor)].filter { $0.value != nil }
        return try await send(URLRequest(url: parts.url!), owner: owner)
    }
    func push(owner: String, events: [RecommendationPreferenceEvent]) async throws -> RecommendationPreferencePush {
        struct Body: Encodable { let apiVersion = 1; let events: [RecommendationPreferenceEvent] }
        var request = URLRequest(url: try configuration.url(for: "/api/v1/recommendation-preferences/push"))
        request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(Body(events: events))
        return try await send(request, owner: owner)
    }
    private func send<T: Decodable>(_ original: URLRequest, owner: String) async throws -> T {
        var request = original
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(owner, forHTTPHeaderField: "X-Taste-Map-Preference-Owner")
        for (key, value) in try await authorization.headers() { request.setValue(value, forHTTPHeaderField: key) }
        var result = try await session.data(for: request)
        if (result.1 as? HTTPURLResponse)?.statusCode == 401,
           try await authorization.recoverUnauthorized(failedAuthorization: request.value(forHTTPHeaderField: "Authorization")) {
            for (key, value) in try await authorization.headers() { request.setValue(value, forHTTPHeaderField: key) }
            result = try await session.data(for: request)
        }
        guard let response = result.1 as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw SyncAPIError.invalidResponse }
        return try JSONDecoder().decode(T.self, from: result.0)
    }
}

@MainActor
final class RecommendationPreferenceSync {
    private let api: any RecommendationPreferenceAPI
    private let defaults: UserDefaults
    private var running = Set<String>()
    init(api: any RecommendationPreferenceAPI, defaults: UserDefaults = .standard) { self.api = api; self.defaults = defaults }
    func synchronize(owner: String, isCurrent: @escaping () -> Bool) async {
        guard isCurrent(), running.insert(owner).inserted else { return }
        defer { running.remove(owner) }
        let generation = RecommendationPreferenceLedger.generation(owner: owner)
        let stillCurrent = { isCurrent() && RecommendationPreferenceLedger.generation(owner: owner) == generation }
        do {
            // Migration is append-only and does not retroactively classify v1 IDs.
            let excluded = Set(defaults.stringArray(forKey: "tastemap.recommendation-exclusions.v1.\(owner)") ?? [])
            let votes = try defaults.data(forKey: "tastemap.recommendation-intent.v1.\(owner)").map { try JSONDecoder().decode([RestaurantRecommendationIntentVote].self, from: $0) } ?? []
            try RecommendationPreferenceLedger.capture(owner: owner, excluded: excluded, votes: votes, defaults: defaults)
            for _ in 0..<20 {
                guard stillCurrent() else { return }
                let cursor = try RecommendationPreferenceLedger.load(owner: owner, defaults: defaults).cursor
                let page = try await api.pull(owner: owner, cursor: cursor)
                guard stillCurrent() else { return }
                try RecommendationPreferenceLedger.merge(page, owner: owner, defaults: defaults)
                if !page.hasMore { break }
                guard page.cursor != cursor else { throw SyncAPIError.invalidResponse }
            }
            for _ in 0..<20 {
                guard stillCurrent() else { return }
                let state = try RecommendationPreferenceLedger.load(owner: owner, defaults: defaults)
                var pending: [RecommendationPreferenceEvent] = []
                var bytes = 64
                for event in state.events where state.pending.contains(event.eventID) {
                    let size = try JSONEncoder().encode(event).count + 1
                    if pending.count >= 100 || bytes + size > 131_072 { break }
                    pending.append(event); bytes += size
                }
                if pending.isEmpty { break }
                let ack = try await api.push(owner: owner, events: pending)
                guard stillCurrent() else { return }
                try RecommendationPreferenceLedger.acknowledge(ack, sent: pending, owner: owner, defaults: defaults)
                if ack.receipts.isEmpty { break }
            }
            NotificationCenter.default.post(name: RestaurantRecommendationPreferences.didChange, object: owner,
                userInfo: ["origin": "remotePreferenceSync"])
            NotificationCenter.default.post(name: .tasteMapLocalDataDidChange, object: nil,
                userInfo: ["reason": "recommendationPreferenceSynced"])
        } catch {
            // Offline/unavailable/not deployed never reverses local confirmation.
            // Durable events and unacknowledged IDs remain for next login/foreground.
        }
    }
}
