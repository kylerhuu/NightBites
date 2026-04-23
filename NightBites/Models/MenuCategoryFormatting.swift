import Foundation

/// Shared menu category strings and normalization so owner entry and student filters stay consistent.
enum MenuCategoryFormatting {
    static let suggested: [String] = ["Main", "Side", "Drink", "Dessert", "Snack", "Other"]

    /// Trims, collapses repeated spaces, and title-cases each word (e.g. `"  MAIN "` → `"Main"`).
    static func normalized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Main" }
        let collapsed = trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return collapsed.split(separator: " ").map { part in
            let s = String(part)
            if s.isEmpty { return "" }
            return s.prefix(1).uppercased() + s.dropFirst().lowercased()
        }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }
}
