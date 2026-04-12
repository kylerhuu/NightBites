import SwiftUI

struct StudentMenuCategoryChipsRow: View {
    let categories: [String]
    @Binding var selectedCategory: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(categories, id: \.self) { name in
                    chip(title: name, isSelected: selectedCategory == name) {
                        selectedCategory = name
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? NightBitesTheme.ember.opacity(0.22) : NightBitesTheme.mutedCard.opacity(0.9))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isSelected ? NightBitesTheme.ember.opacity(0.55) : NightBitesTheme.border, lineWidth: 1)
                )
                .foregroundStyle(isSelected ? NightBitesTheme.ember : NightBitesTheme.label)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }
}
