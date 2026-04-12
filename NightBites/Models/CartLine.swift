import Foundation

/// One cart row with optional modifier selections (Snackpass-style line item).
struct CartLine: Identifiable, Equatable, Hashable {
    let id: UUID
    var menuItem: MenuItem
    var quantity: Int
    /// Selected option IDs keyed by modifier group ID.
    var selectionsByGroupID: [UUID: Set<UUID>]
    /// Preserved from reorder / legacy orders.
    var lineNotes: String?

    init(
        id: UUID = UUID(),
        menuItem: MenuItem,
        quantity: Int,
        selectionsByGroupID: [UUID: Set<UUID>] = [:],
        lineNotes: String? = nil
    ) {
        self.id = id
        self.menuItem = menuItem
        self.quantity = quantity
        self.selectionsByGroupID = Self.normalizedSelections(menuItem: menuItem, raw: selectionsByGroupID)
        self.lineNotes = lineNotes
    }

    func unitPrice() -> Double {
        var total = menuItem.price
        for group in menuItem.modifierGroups {
            guard let picked = selectionsByGroupID[group.id] else { continue }
            for option in group.options where picked.contains(option.id) {
                total += option.priceDelta
            }
        }
        return total
    }

    func lineSubtotal() -> Double {
        unitPrice() * Double(quantity)
    }

    /// Snapshot used on `OrderItem` so subtotals include modifiers.
    func pricedMenuItemSnapshot() -> MenuItem {
        MenuItem(
            id: menuItem.id,
            name: menuItem.name,
            description: menuItem.description,
            price: unitPrice(),
            category: menuItem.category,
            isAvailable: menuItem.isAvailable,
            truckId: menuItem.truckId,
            imageURL: menuItem.imageURL,
            modifierGroups: menuItem.modifierGroups,
            tags: menuItem.tags
        )
    }

    func orderCustomizationText() -> String? {
        let modifierSummary = Self.formatModifierSummary(menuItem: menuItem, selectionsByGroupID: selectionsByGroupID)
        let trimmedNotes = lineNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [modifierSummary, trimmedNotes].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func normalizedSelections(menuItem: MenuItem, raw: [UUID: Set<UUID>]) -> [UUID: Set<UUID>] {
        var result: [UUID: Set<UUID>] = [:]
        for group in menuItem.modifierGroups {
            let picked = raw[group.id] ?? []
            let valid = Set(group.options.map(\.id)).intersection(picked)
            result[group.id] = valid
        }
        return result
    }

    static func formatModifierSummary(menuItem: MenuItem, selectionsByGroupID: [UUID: Set<UUID>]) -> String? {
        var segments: [String] = []
        for group in menuItem.modifierGroups {
            guard let picked = selectionsByGroupID[group.id], !picked.isEmpty else { continue }
            let names = group.options.filter { picked.contains($0.id) }.map(\.name)
            if !names.isEmpty {
                segments.append("\(group.name): \(names.joined(separator: ", "))")
            }
        }
        return segments.isEmpty ? nil : segments.joined(separator: " · ")
    }

    func matchesConfiguration(menuItem other: MenuItem, selections raw: [UUID: Set<UUID>]) -> Bool {
        menuItem.id == other.id && selectionsByGroupID == Self.normalizedSelections(menuItem: other, raw: raw)
    }
}
