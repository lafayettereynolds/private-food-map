import Foundation

struct PendingSharedMealInvitation: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let ownerUserID: String
    let sourceVisitID: String
    let participantUserIDs: [String]
    let mutationID: String
    let createdAt: Date
    var retryCount: Int
}

@MainActor
final class SocialCollaborationOutbox {
    private let api: any SocialCollaborationAPI
    private let sessionManager: AuthSessionManager
    private let fileURL: URL
    private var observers: [NSObjectProtocol] = []
    private var flushing = false

    init(
        api: any SocialCollaborationAPI,
        sessionManager: AuthSessionManager,
        fileURL overrideFileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.api = api
        self.sessionManager = sessionManager
        let directory: URL
        if let overrideFileURL {
            directory = overrideFileURL.deletingLastPathComponent()
            fileURL = overrideFileURL
        } else {
            let root = (try? fileManager.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )) ?? fileManager.temporaryDirectory
            directory = root.appendingPathComponent(TasteMapAppEnvironment.current == .development ? "TasteMapDevelopment/SocialOutbox" : "TasteMap/SocialOutbox", isDirectory: true)
            fileURL = directory.appendingPathComponent("shared-meal-invitations-v1.json")
        }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        start()
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func enqueue(ownerUserID: String, sourceVisitID: String, participantUserIDs: [String]) throws {
        let participants = Array(Set(participantUserIDs.filter { !$0.isEmpty && $0 != ownerUserID })).sorted()
        guard !participants.isEmpty else { return }
        var values = load()
        let mutationID = "ios-shared-meal:\(ownerUserID):\(sourceVisitID):\(participants.joined(separator: ","))"
        guard !values.contains(where: { $0.mutationID == mutationID }) else { return }
        values.append(.init(
            id: UUID(), ownerUserID: ownerUserID, sourceVisitID: sourceVisitID,
            participantUserIDs: participants, mutationID: mutationID,
            createdAt: .now, retryCount: 0
        ))
        try save(values)
    }

    func flush() async {
        guard !flushing, let userID = await sessionManager.restoredUser()?.id else { return }
        flushing = true; defer { flushing = false }
        var values = load()
        var retained: [PendingSharedMealInvitation] = []
        for var value in values {
            guard value.ownerUserID == userID else { retained.append(value); continue }
            do {
                _ = try await api.inviteSharedMeal(
                    sourceVisitID: value.sourceVisitID,
                    participantUserIDs: value.participantUserIDs,
                    mutationID: value.mutationID
                )
            } catch {
                value.retryCount += 1
                retained.append(value)
            }
        }
        values = retained
        try? save(values)
    }

    func pendingCount(ownerUserID: String) -> Int {
        load().filter { $0.ownerUserID == ownerUserID }.count
    }

    private func start() {
        for name in [Notification.Name.tasteMapSyncDidComplete, .tasteMapAuthSessionAvailable] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.flush() }
            })
        }
    }

    private func load() -> [PendingSharedMealInvitation] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([PendingSharedMealInvitation].self, from: data)) ?? []
    }

    private func save(_ values: [PendingSharedMealInvitation]) throws {
        let data = try JSONEncoder().encode(values)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
