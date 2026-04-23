import PhotosUI
import SwiftUI

/// Edit an item’s photo and customizations; persists via `FoodTruckViewModel`.
struct OwnerMenuItemEditorView: View {
    let truck: FoodTruck
    let item: MenuItem

    @Environment(FoodTruckViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var groups: [MenuModifierGroup] = []
    @State private var newGroupName = ""
    @State private var newGroupRequired = true
    @State private var newGroupMaxSelection = 1
    @State private var addOptionName: [UUID: String] = [:]
    @State private var addOptionPrice: [UUID: String] = [:]
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isReuploadingPhoto = false

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    menuThumb
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name)
                            .font(.headline)
                        Text(item.formattedPrice)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NightBitesTheme.saffron)
                        if isReuploadingPhoto {
                            ProgressView("Uploading…")
                                .font(.caption)
                        }
                    }
                }
                .listRowBackground(NightBitesTheme.mutedCard)

                if viewModel.isRemoteEnabled {
                    PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                        Label("Change photo from library", systemImage: "photo.on.rectangle.angled")
                    }
                } else {
                    Text("Connect Supabase in this build to upload item photos from your library.")
                        .font(.footnote)
                        .foregroundStyle(NightBitesTheme.labelSecondary)
                }
            } header: {
                Text("Photo")
            }

            Section {
                if groups.isEmpty {
                    Text("No add-ons yet. Add a group below, then options like “Single / Double” or “Bacon (+$2)”.")
                        .font(.subheadline)
                        .foregroundStyle(NightBitesTheme.labelSecondary)
                }
                ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
                    modifierGroupContent(groupIndex: groupIndex, group: group)
                }
            } header: {
                Text("Customizations")
            }

            Section {
                TextField("New group (e.g. Size, Toppings)", text: $newGroupName)
                    .textFieldStyle(.roundedBorder)
                Toggle("This choice is required", isOn: $newGroupRequired)
                Stepper("Most a customer can pick: \(newGroupMaxSelection)", value: $newGroupMaxSelection, in: 1...20)
                Button {
                    addNewGroup()
                } label: {
                    Label("Add group", systemImage: "plus.circle.fill")
                }
                .disabled(newGroupName.trimmed.isEmpty)
            } header: {
                Text("Add customization group")
            }
            Section {
                Button {
                    viewModel.replaceModifierGroups(itemID: item.id, groups: groups)
                    dismiss()
                } label: {
                    Text("Save customizations")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(NightBitesTheme.ember)
            }
        }
        .navigationTitle("Edit item")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { groups = item.modifierGroups }
        .onChange(of: pickedPhoto) { _, new in
            guard let new, viewModel.isRemoteEnabled else { return }
            Task { @MainActor in
                isReuploadingPhoto = true
                defer {
                    isReuploadingPhoto = false
                    pickedPhoto = nil
                }
                guard let data = try? await new.loadTransferable(type: Data.self) else { return }
                let ct = MenuItemImageContentType.guess(data)
                await viewModel.replaceMenuItemImageFromPhoto(itemID: item.id, data: data, contentType: ct)
            }
        }
    }

    @ViewBuilder
    private var menuThumb: some View {
        if let urlString = viewModel.menuItems.first(where: { $0.id == item.id })?.imageURL ?? item.imageURL,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            NightBitesTheme.mutedCard
            Image(systemName: "photo")
                .foregroundStyle(NightBitesTheme.labelSecondary)
        }
    }

    @ViewBuilder
    private func modifierGroupContent(groupIndex: Int, group: MenuModifierGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(group.name)
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    groups.removeAll { $0.id == group.id }
                } label: {
                    Image(systemName: "trash")
                }
            }

            Toggle("Required", isOn: Binding(
                get: { groups[groupIndex].isRequired },
                set: { isOn in
                    groups[groupIndex].isRequired = isOn
                    if isOn {
                        groups[groupIndex].minSelection = 1
                        if groups[groupIndex].maxSelection < 1 { groups[groupIndex].maxSelection = 1 }
                    } else {
                        groups[groupIndex].minSelection = 0
                    }
                }
            ))

            Stepper(
                "Max selections: \(groups[groupIndex].maxSelection)",
                value: Binding(
                    get: { groups[groupIndex].maxSelection },
                    set: { newValue in
                        let floor = groups[groupIndex].isRequired ? 1 : 0
                        groups[groupIndex].maxSelection = max(newValue, floor)
                    }
                ),
                in: (groups[groupIndex].isRequired ? 1 : 0)...20
            )

            if !groups[groupIndex].options.isEmpty {
                ForEach(groups[groupIndex].options) { option in
                    HStack {
                        Text(option.name)
                        Spacer()
                        if option.priceDelta != 0 {
                            Text(formatPriceDelta(option.priceDelta))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(NightBitesTheme.labelSecondary)
                        }
                    }
                }
            }

            HStack {
                TextField("Option name", text: Binding(
                    get: { addOptionName[group.id] ?? "" },
                    set: { addOptionName[group.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                TextField("+$0", text: Binding(
                    get: { addOptionPrice[group.id] ?? "0" },
                    set: { addOptionPrice[group.id] = $0 }
                ))
                .keyboardType(.decimalPad)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
            }
            Button {
                addOptionToGroup(groupID: group.id, groupIndex: groupIndex)
            } label: {
                Label("Add option", systemImage: "plus")
            }
            .font(.caption.weight(.semibold))
        }
    }

    private func addNewGroup() {
        let name = newGroupName.trimmed
        guard !name.isEmpty, !groups.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        let minSel = newGroupRequired ? 1 : 0
        let maxSel = max(newGroupMaxSelection, minSel)
        groups.append(
            MenuModifierGroup(
                name: name,
                isRequired: newGroupRequired,
                minSelection: minSel,
                maxSelection: maxSel
            )
        )
        newGroupName = ""
        newGroupMaxSelection = 1
    }

    private func addOptionToGroup(groupID: UUID, groupIndex: Int) {
        let oname = (addOptionName[groupID] ?? "").trimmed
        let priceText = (addOptionPrice[groupID] ?? "0").replacingOccurrences(of: ",", with: "")
        guard !oname.isEmpty, let p = Double(priceText) else { return }
        guard let idx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[idx].options.append(MenuModifierOption(name: oname, priceDelta: p))
        addOptionName[groupID] = ""
        addOptionPrice[groupID] = "0"
    }

    private func formatPriceDelta(_ v: Double) -> String {
        if v < 0 { return String(format: "-$%.2f", -v) }
        if v == 0 { return "Included" }
        return String(format: "+$%.2f", v)
    }
}

enum MenuItemImageContentType {
    static func guess(_ data: Data) -> String {
        guard data.count >= 2 else { return "image/jpeg" }
        if data.count >= 4, data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47 { return "image/png" }
        if data[0] == 0xFF, data[1] == 0xD8 { return "image/jpeg" }
        return "image/jpeg"
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
