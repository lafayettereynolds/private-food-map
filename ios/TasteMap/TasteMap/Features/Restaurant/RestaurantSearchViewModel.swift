import Combine
import Foundation

@MainActor
final class RestaurantSearchViewModel: ObservableObject {
    @Published private(set) var results: [RestaurantCandidate] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let searchService: any RestaurantSearching
    private var lastSubmittedQuery = ""

    init(searchService: any RestaurantSearching = WorldwideRestaurantSearchService()) {
        self.searchService = searchService
    }

    func search(query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            results = []
            errorMessage = nil
            return
        }

        lastSubmittedQuery = trimmedQuery
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            results = try await searchService.search(query: trimmedQuery)
        } catch is CancellationError {
            return
        } catch {
            results = []
            errorMessage = "搜索失败，请检查网络连接后重试。"
        }
    }

    func retry() async {
        guard !lastSubmittedQuery.isEmpty else { return }
        await search(query: lastSubmittedQuery)
    }
}
