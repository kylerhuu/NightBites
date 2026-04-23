import Foundation

struct MenuItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let description: String
    var price: Double
    var category: String
    var isAvailable: Bool
    let truckId: UUID
    var imageURL: String?
    var modifierGroups: [MenuModifierGroup]
    /// Short merchandising labels, e.g. "Best Seller", "Sells Out Fast".
    var tags: [String]

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        price: Double,
        category: String,
        isAvailable: Bool,
        truckId: UUID,
        imageURL: String?,
        modifierGroups: [MenuModifierGroup] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.price = price
        self.category = category
        self.isAvailable = isAvailable
        self.truckId = truckId
        self.imageURL = imageURL
        self.modifierGroups = modifierGroups
        self.tags = tags
    }

    var formattedPrice: String {
        String(format: "$%.2f", price)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MenuItem, rhs: MenuItem) -> Bool {
        lhs.id == rhs.id
    }
}

extension MenuItem {
    var hasModifiers: Bool {
        !modifierGroups.isEmpty
    }
}

struct MenuModifierGroup: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    var isRequired: Bool
    var minSelection: Int
    var maxSelection: Int
    var options: [MenuModifierOption]

    init(
        id: UUID = UUID(),
        name: String,
        isRequired: Bool,
        minSelection: Int,
        maxSelection: Int,
        options: [MenuModifierOption] = []
    ) {
        self.id = id
        self.name = name
        self.isRequired = isRequired
        self.minSelection = minSelection
        self.maxSelection = max(maxSelection, minSelection)
        self.options = options
    }
}

struct MenuModifierOption: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let priceDelta: Double

    init(id: UUID = UUID(), name: String, priceDelta: Double = 0) {
        self.id = id
        self.name = name
        self.priceDelta = priceDelta
    }
}
