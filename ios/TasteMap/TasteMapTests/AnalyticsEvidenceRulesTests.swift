import Foundation
import Testing
@testable import TasteMap

@Suite("Native analytics evidence parity")
struct AnalyticsEvidenceRulesTests {
    private struct Meal {
        let restaurant: Int
        let at: Date
        let rating: Double?
    }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test("Repeated visits refine one restaurant score without adding votes")
    func representativeMeans() {
        let at = date(2026, 9, 1)
        let meals = (0..<20).map { _ in Meal(restaurant: 1, at: at, rating: 5) }
            + [Meal(restaurant: 2, at: at, rating: 1), Meal(restaurant: 3, at: at, rating: nil)]
        let values = AnalysisStatisticsDefinitions.representativeRatings(in: meals, restaurantID: \.restaurant, rating: \.rating)
        #expect(values == [1, 5])
        #expect(AnalysisStatisticsDefinitions.mean(values) == 3)
    }

    @Test("90-day periods are disjoint and do not include all-time or future meals")
    func recentWindows() {
        let now = date(2026, 9, 7)
        let start = calendar.date(byAdding: .day, value: -90, to: now)!
        let prior = calendar.date(byAdding: .day, value: -180, to: now)!
        var meals = (0..<10).map { Meal(restaurant: $0 % 5, at: start, rating: 4) }
        meals += (0..<10).map { Meal(restaurant: $0 % 5, at: prior, rating: 3) }
        meals += [Meal(restaurant: 99, at: prior.addingTimeInterval(-1), rating: 1),
                  Meal(restaurant: 98, at: now.addingTimeInterval(1), rating: 5)]
        let result = AnalysisStatisticsDefinitions.recentComparison(in: meals, now: now, calendar: calendar,
            visitedAt: \.at, restaurantID: \.restaurant, rating: \.rating)
        #expect(result.currentVisitCount == 10)
        #expect(result.previousVisitCount == 10)
        #expect(result.frequencyAvailable)
        #expect(result.scoreDeltaOutOfTen == 2)
        let repeats = meals.map { Meal(restaurant: 1, at: $0.at, rating: $0.rating) }
        let insufficient = AnalysisStatisticsDefinitions.recentComparison(in: repeats, now: now, calendar: calendar,
            visitedAt: \.at, restaurantID: \.restaurant, rating: \.rating)
        #expect(!insufficient.frequencyAvailable)
        #expect(insufficient.scoreDeltaOutOfTen == nil)
    }

    @Test("Current month compares corresponding dates and clamps short prior month")
    func comparableMonth() {
        let march = MonthlyPeriod(year: 2026, month: 3, calendar: calendar)
        let ends = AnalysisStatisticsDefinitions.comparableMonthEnds(period: march, now: date(2026, 3, 31))
        #expect(calendar.component(.day, from: ends.current) == 29)
        #expect(ends.previous == march.start)
        let early = AnalysisStatisticsDefinitions.comparableMonthEnds(period: march, now: date(2026, 3, 7))
        #expect(calendar.component(.day, from: early.current) == 8)
        #expect(calendar.component(.day, from: early.previous) == 8)
        let complete = AnalysisStatisticsDefinitions.comparableMonthEnds(period: march, now: date(2026, 4, 1))
        #expect(complete.current == march.end)
        #expect(complete.previous == march.start)
        #expect(MonthlyRecapSufficiencyPolicy.tasteChangeLevel(visitCount: 10, restaurantCount: 5) != .insufficient)
        #expect(MonthlyRecapSufficiencyPolicy.tasteChangeLevel(visitCount: 100, restaurantCount: 4) == .insufficient)
    }
}
