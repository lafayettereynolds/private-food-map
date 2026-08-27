import Foundation

struct DishDraft: Identifiable, Equatable {
    let id: UUID
    var dishID: UUID?
    var name: String
    var taste: String
    var rating: Double?
    var price: Decimal?
    var photoID: UUID?

    init(
        id: UUID = UUID(),
        dishID: UUID? = nil,
        name: String = "",
        taste: String = "",
        rating: Double? = nil,
        price: Decimal? = nil,
        photoID: UUID? = nil
    ) {
        self.id = id
        self.dishID = dishID
        self.name = name
        self.taste = taste
        self.rating = rating
        self.price = price
        self.photoID = photoID
    }

    init(dish: Dish, photoID: UUID? = nil) {
        self.init(
            dishID: dish.id,
            name: dish.name,
            taste: dish.taste,
            rating: dish.rating,
            price: dish.price,
            photoID: photoID
        )
    }

    func validated() throws -> DishDraft {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.taste = taste.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.name.isEmpty else { throw DishDraftError.missingName }
        guard Visit.validatedRating(copy.rating) == copy.rating else { throw DishDraftError.invalidRating }
        guard copy.price.map({ $0 >= 0 }) ?? true else { throw DishDraftError.invalidPrice }
        return copy
    }
}

enum DishDraftError: LocalizedError, Equatable {
    case missingName
    case invalidRating
    case invalidPrice

    var errorDescription: String? {
        switch self {
        case .missingName: "请填写菜名。"
        case .invalidRating: "菜品评分必须是 0.5 到 5.0 的半星。"
        case .invalidPrice: "菜品价格不能为负数。"
        }
    }
}
