import SwiftUI

struct MenuItemDetailSheet: View {
    @Environment(FoodTruckViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    let menuItem: MenuItem
    let truckSupportsOrdering: Bool
    let onAdded: () -> Void

    @State private var selections: [UUID: Set<UUID>] = [:]
    @State private var quantity = 1
    @State private var validationMessage: String?

    private var estimatedUnitPriceFormatted: String {
        String(
            format: "$%.2f",
            CartLine(
                menuItem: menuItem,
                quantity: 1,
                selectionsByGroupID: selections
            ).unitPrice()
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero

                    HStack(alignment: .top, spacing: 12) {
                        Text(menuItem.name)
                            .font(.title2.weight(.heavy))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(estimatedUnitPriceFormatted)
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(NightBitesTheme.saffron)
                            .monospacedDigit()
                    }

                    Text(menuItem.description)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    if !menuItem.tags.isEmpty {
                        FlowTagRow(tags: menuItem.tags)
                    }

                    if !menuItem.isAvailable {
                        unavailableBanner
                    } else if !truckSupportsOrdering {
                        pausedBanner
                    }

                    ForEach(menuItem.modifierGroups) { group in
                        modifierSection(group)
                    }

                    quantityRow

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.red.opacity(0.9))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .nightBitesScreenBackground()
            .safeAreaInset(edge: .bottom) {
                addBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                seedDefaultSelectionsIfNeeded()
            }
        }
    }

    private var hero: some View {
        Group {
            if let imageURL = menuItem.imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    case .failure:
                        heroPlaceholder
                    case .empty:
                        ZStack {
                            NightBitesTheme.mutedCard
                            ProgressView().tint(NightBitesTheme.ember)
                        }
                    @unknown default:
                        heroPlaceholder
                    }
                }
            } else {
                heroPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(NightBitesTheme.border, lineWidth: 1)
        )
    }

    private var heroPlaceholder: some View {
        ZStack {
            NightBitesTheme.mutedCard
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }

    private var unavailableBanner: some View {
        Label("Sold out for tonight", systemImage: "moon.stars.fill")
            .font(.subheadline.weight(.semibold))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.12))
            .foregroundStyle(Color.red.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var pausedBanner: some View {
        Label("Ordering is paused — you can still browse the menu.", systemImage: "pause.circle.fill")
            .font(.subheadline.weight(.semibold))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NightBitesTheme.warning.opacity(0.14))
            .foregroundStyle(NightBitesTheme.warning)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func modifierSection(_ group: MenuModifierGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(group.name.uppercased())
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.secondary)
                if group.isRequired {
                    Text("Required")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NightBitesTheme.ember.opacity(0.18))
                        .foregroundStyle(NightBitesTheme.ember)
                        .clipShape(Capsule())
                }
                Spacer()
                if group.maxSelection > 1 {
                    Text("Pick up to \(group.maxSelection)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(spacing: 8) {
                ForEach(group.options) { option in
                    optionRow(group: group, option: option)
                }
            }
        }
        .padding(14)
        .background(NightBitesTheme.card.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(NightBitesTheme.border, lineWidth: 1)
        )
    }

    private func optionRow(group: MenuModifierGroup, option: MenuModifierOption) -> some View {
        let picked = selections[group.id] ?? []
        let isOn = picked.contains(option.id)
        return Button {
            toggleSelection(group: group, option: option)
            validationMessage = nil
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                        .font(.body.weight(.semibold))
                    if option.priceDelta > 0.001 {
                        Text("+\(String(format: "$%.2f", option.priceDelta))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NightBitesTheme.saffron)
                    }
                }
                Spacer()
                Image(systemName: group.maxSelection == 1 ? (isOn ? "largecircle.fill.circle" : "circle") : (isOn ? "checkmark.square.fill" : "square"))
                    .font(.title3)
                    .foregroundStyle(isOn ? NightBitesTheme.ember : .secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!menuItem.isAvailable || !truckSupportsOrdering)
    }

    private var quantityRow: some View {
        HStack {
            Text("Quantity")
                .font(.headline)
            Spacer()
            Stepper(value: $quantity, in: 1 ... 20) {
                Text("\(quantity)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .frame(minWidth: 36)
            }
            .tint(NightBitesTheme.ember)
        }
        .padding(14)
        .background(NightBitesTheme.mutedCard.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var addBar: some View {
        let line = CartLine(menuItem: menuItem, quantity: quantity, selectionsByGroupID: selections)
        let canAdd = menuItem.isAvailable && truckSupportsOrdering && selectionsAreValid

        return VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(String(format: "$%.2f", line.lineSubtotal()))
                        .font(.title2.weight(.heavy))
                }
                Spacer()
            }

            Button {
                addToCart(line: line)
            } label: {
                Text("Add to bag")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background {
                        if canAdd {
                            NightBitesTheme.heroGradient
                        } else {
                            Color.gray.opacity(0.35)
                        }
                    }
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(!canAdd)
            .nightBitesPrimaryGlow(radius: canAdd ? 14 : 0, y: canAdd ? 6 : 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var selectionsAreValid: Bool {
        for group in menuItem.modifierGroups {
            let count = (selections[group.id] ?? []).count
            if count < group.minSelection || count > group.maxSelection {
                return false
            }
        }
        return true
    }

    private func seedDefaultSelectionsIfNeeded() {
        guard selections.isEmpty else { return }
        var draft: [UUID: Set<UUID>] = [:]
        for group in menuItem.modifierGroups where group.isRequired && group.maxSelection == 1 {
            guard let first = group.options.first else { continue }
            draft[group.id] = [first.id]
        }
        selections = draft
    }

    private func toggleSelection(group: MenuModifierGroup, option: MenuModifierOption) {
        var current = selections[group.id] ?? []
        if group.maxSelection <= 1 {
            current = [option.id]
        } else {
            if current.contains(option.id) {
                current.remove(option.id)
            } else if current.count < group.maxSelection {
                current.insert(option.id)
            }
        }
        selections[group.id] = current
    }

    private func addToCart(line _: CartLine) {
        guard selectionsAreValid else {
            validationMessage = "Choose the required options to continue."
            return
        }
        viewModel.addCartLine(menuItem: menuItem, selections: selections, quantity: quantity)
        onAdded()
        dismiss()
    }
}

private struct FlowTagRow: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag.uppercased())
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(NightBitesTheme.ember.opacity(0.16))
                        .foregroundStyle(NightBitesTheme.ember)
                        .clipShape(Capsule())
                }
            }
        }
    }
}
