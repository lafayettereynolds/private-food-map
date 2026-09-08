import Foundation

/// Mirrors the shared React payment policy. No schema migration or inferred
/// Restaurant/reference price is involved in a personal expenditure.
enum VisitSpendPolicy {
    static func valid(_ value: Decimal?) -> Decimal? {
        guard let value, !value.isNaN, value >= 0 else { return nil }
        var source = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 2, .plain)
        return rounded
    }

    static func resolve(actual: Decimal?, amount: Decimal?, mode: String?, partySize: Int?) -> Decimal? {
        if let actual = valid(actual) { return actual }
        let mode = mode?.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == "treated" { return 0 }
        guard let amount = valid(amount) else { return nil }
        switch mode {
        case nil, "": return partySize == 1 ? amount : nil
        case "my_treat": return amount
        case "aa":
            guard let partySize, partySize > 0 else { return nil }
            return valid(amount / Decimal(partySize))
        default: return nil
        }
    }

    static func inputAmount(actual: Decimal?, total: Decimal?, mode: String?, partySize: Int?) -> Decimal? {
        if mode == "separate" || mode == "other" { return valid(actual) }
        if let total = valid(total) { return total }
        guard let actual = valid(actual) else { return nil }
        if mode == "aa", let partySize, partySize > 0 { return valid(actual * Decimal(partySize)) }
        return actual
    }

    static func calculate(amount: Decimal?, mode: String?, partySize: Int?) -> (total: Decimal?, actual: Decimal?) {
        if mode == "separate" || mode == "other" { return (nil, valid(amount)) }
        return (valid(amount), resolve(actual: nil, amount: amount, mode: mode, partySize: partySize))
    }
}

extension Visit {
    var resolvedActualSpend: Decimal? {
        guard deletedAt == nil else { return nil }
        return VisitSpendPolicy.resolve(actual: myActualSpend, amount: totalPrice, mode: paymentModeRawValue, partySize: partySize)
    }
}
