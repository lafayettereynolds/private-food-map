import XCTest
@testable import TasteMap

final class VisitSpendPolicyTests: XCTestCase {
    func testModesMatchPersonalExpenditureAndKeepDiningReference() {
        XCTAssertEqual(VisitSpendPolicy.calculate(amount: 200, mode: "aa", partySize: 4).actual, 50)
        XCTAssertEqual(VisitSpendPolicy.calculate(amount: 200, mode: "my_treat", partySize: 4).actual, 200)
        XCTAssertEqual(VisitSpendPolicy.calculate(amount: 200, mode: "treated", partySize: 4).actual, 0)
        XCTAssertEqual(VisitSpendPolicy.calculate(amount: 50, mode: "separate", partySize: 4).actual, 50)
        XCTAssertNil(VisitSpendPolicy.calculate(amount: 50, mode: "separate", partySize: 4).total)
        XCTAssertEqual(VisitSpendPolicy.calculate(amount: 100, mode: "aa", partySize: 3).actual, Decimal(string: "33.33"))
        for mode in [VisitPaymentMode.aa, .myTreat, .treated] {
            let payment = VisitSpendPolicy.calculate(amount: 200, mode: mode.rawValue, partySize: 4)
            let draft = VisitDraft(partySize: 4, myActualSpend: payment.actual, totalPrice: payment.total, paymentMode: mode)
            XCTAssertEqual(draft.calculatedPricePerPerson, 50)
        }
    }
    func testLegacyPaymentSafety() {
        XCTAssertEqual(VisitSpendPolicy.resolve(actual: nil, amount: 17, mode: nil, partySize: 1), 17)
        XCTAssertNil(VisitSpendPolicy.resolve(actual: nil, amount: 200, mode: nil, partySize: 4))
        XCTAssertNil(VisitSpendPolicy.resolve(actual: nil, amount: 200, mode: "legacy_unknown", partySize: 1))
        XCTAssertEqual(VisitSpendPolicy.resolve(actual: 301, amount: 175, mode: "aa", partySize: 4), 301)
        XCTAssertEqual(VisitSpendPolicy.calculate(amount: nil, mode: "treated", partySize: 4).actual, 0)
        XCTAssertNil(VisitSpendPolicy.calculate(amount: nil, mode: "aa", partySize: 4).actual)
    }
}
