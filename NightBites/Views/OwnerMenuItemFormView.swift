import PhotosUI
import SwiftUI
import UIKit

/// Full-screen create or edit flow for a single menu item: basics, photo (with preview), category, and modifier groups.
struct OwnerMenuItemFormView: View {
    let truck: FoodTruck
    /// `nil` = create a new item.
    let editingItem: MenuItem?

    @Environment(FoodTruckViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var priceText = ""
    @State private var category = "Main"
    @State private var imageURLText = ""
    @State private var localPhotoData: Data?
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var groups: [MenuModifierGroup] = []

    @State private var newGroupName = ""
    @State private var newGroupRequired = false
    @State private var newGroupStyle: ModifierPickStyle = .one
    @State private var newGroupSeveralMax = 3
    @State private var optionDraftName: [UUID: String] = [:]
    @State private var optionDraftPrice: [UUID: String] = [:]

    @State private var isSaving = false
    @State private var isUploadingPhoto = false
    @State private var validationNotice: String?
    @State private var showSaveSuccess = false
    @State private var saveStatus: SaveStatus?

    private var isEditing: Bool { editingItem != nil }

    private var resolvedItem: MenuItem? {
        guard let id = editingItem?.id else { return editingItem }
        return viewModel.menuItems.first(where: { $0.id == id }) ?? editingItem
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                basicsSection
                photoSection
                categorySection
                customizationsSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .nightBitesScreenBackground()
        .navigationTitle(isEditing ? "Menu item" : "New menu item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let saveStatus {
                saveStatusBanner(saveStatus)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
        .onAppear {
            if let item = resolvedItem {
                name = item.name
                description = item.description
                priceText = String(format: "%.2f", item.price)
                category = item.category
                imageURLText = item.imageURL ?? ""
                groups = item.modifierGroups
                if localPhotoData == nil { localPhotoData = nil }
            }
        }
        .onChange(of: pickedPhotoItem) { _, new in
            guard let new else { return }
            Task { @MainActor in
                if let data = try? await new.loadTransferable(type: Data.self) {
                    localPhotoData = data
                }
                pickedPhotoItem = nil
            }
        }
        .alert("Check the form", isPresented: Binding(
            get: { validationNotice != nil },
            set: { if !$0 { validationNotice = nil } }
        )) {
            Button("OK", role: .cancel) { validationNotice = nil }
        } message: {
            if let validationNotice { Text(validationNotice) }
        }
        .alert("Saved", isPresented: $showSaveSuccess) {
            Button("Done") { dismiss() }
        } message: {
            Text("Menu item saved and synced.")
        }
    }

    private var basicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Basics", subtitle: "What students see on your truck’s menu.")
            textFieldBlock("Name", text: $name, caps: .words)
            textFieldBlock("Description", text: $description, caps: .sentences, axis: .vertical)
            textFieldBlock("Price (USD)", text: $priceText, caps: .never, keyboard: .decimalPad)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightBitesCard()
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Photo", subtitle: "Shown on the item card. You’ll see a preview as soon as you pick one.")

            photoPreview
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(NightBitesTheme.border, lineWidth: 1)
                )

            if viewModel.isRemoteEnabled {
                PhotosPicker(selection: $pickedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    Label(localPhotoData == nil && (resolvedItem?.imageURL).map { !$0.isEmpty } != true ? "Choose photo" : "Replace photo", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(NightBitesTheme.ember)
            } else {
                Text("Connect Supabase to upload photos from your library.")
                    .font(.footnote)
                    .foregroundStyle(NightBitesTheme.labelSecondary)
            }

            if localPhotoData != nil, isEditing {
                Button("Clear new photo (keep saved image until you save)") {
                    localPhotoData = nil
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(NightBitesTheme.info)
            }

            if isUploadingPhoto {
                ProgressView("Uploading photo…")
                    .font(.caption)
            }

            DisclosureGroup("Use an image URL instead") {
                textFieldBlock("Image URL", text: $imageURLText, caps: .never)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightBitesCard()
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let data = localPhotoData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
        } else if let urlStr = resolvedItem?.imageURL ?? (imageURLText.isEmpty ? nil : imageURLText),
                  let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(img):
                    img.resizable().scaledToFill()
                case .failure, .empty:
                    photoPlaceholder
                @unknown default:
                    photoPlaceholder
                }
            }
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        ZStack {
            NightBitesTheme.mutedCard
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(NightBitesTheme.labelSecondary)
                Text("No photo yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NightBitesTheme.labelSecondary)
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Category", subtitle: "Used for filters on the student menu.")
            ownerCategoryChips()
            textFieldBlock("Custom category", text: $category, caps: .words)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightBitesCard()
    }

    private var customizationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(
                "Customizations",
                subtitle: "Build groups like Toppings, Meat choice, or Sauces. Each group has options and clear rules."
            )

            Text("Required: customer must make a choice in that group before checkout. Optional: they can skip the group or pick within the limit you set.")
            .font(.footnote)
            .foregroundStyle(NightBitesTheme.labelSecondary)

            if groups.isEmpty {
                Text("No add-on groups yet. Add your first group below—e.g. “Toppings” with lettuce, salsa, cheese, or “Meat” with chicken, beef, veggie.")
                    .font(.subheadline)
                    .foregroundStyle(NightBitesTheme.labelSecondary)
            }

            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                existingGroupCard(index: index, group: group)
            }

            addGroupCard
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightBitesCard()
    }

    private func existingGroupCard(index: Int, group: MenuModifierGroup) -> some View {
        let style: ModifierPickStyle = group.maxSelection <= 1 ? .one : .several
        let severalN = max(2, group.maxSelection)

        return VStack(alignment: .leading, spacing: 12) {
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

            Toggle("Customers must choose from this group", isOn: Binding(
                get: { groups[index].isRequired },
                set: { on in
                    groups[index].isRequired = on
                    recomputeMinMax(at: index)
                }
            ))

            Picker("How choices work", selection: Binding(
                get: { groups[index].maxSelection <= 1 ? ModifierPickStyle.one : ModifierPickStyle.several },
                set: { newStyle in
                    if newStyle == .one {
                        groups[index].maxSelection = 1
                        groups[index].minSelection = groups[index].isRequired ? 1 : 0
                    } else {
                        let n = max(2, groups[index].maxSelection == 1 ? 3 : groups[index].maxSelection)
                        groups[index].maxSelection = n
                        recomputeMinMax(at: index)
                    }
                }
            )) {
                Text("Pick one option").tag(ModifierPickStyle.one)
                Text("Pick several (up to a limit)").tag(ModifierPickStyle.several)
            }
            .pickerStyle(.segmented)

            if style == .several {
                Stepper("Up to \(severalN) options", value: Binding(
                    get: { max(2, groups[index].maxSelection) },
                    set: { newMax in
                        groups[index].maxSelection = max(2, newMax)
                        recomputeMinMax(at: index)
                    }
                ), in: 2 ... 15)

                if !groups[index].options.isEmpty {
                    Button("Allow selecting all \(groups[index].options.count) options") {
                        groups[index].maxSelection = max(2, groups[index].options.count)
                        recomputeMinMax(at: index)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                }
            }

            Divider().overlay(NightBitesTheme.border.opacity(0.5))

            ForEach(group.options) { opt in
                HStack {
                    Text(opt.name)
                    Spacer()
                    Text(formatPriceDelta(opt.priceDelta))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NightBitesTheme.labelSecondary)
                    Button {
                        groups[index].options.removeAll { $0.id == opt.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                TextField("Option name (e.g. Chicken)", text: Binding(
                    get: { optionDraftName[group.id] ?? "" },
                    set: { optionDraftName[group.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                TextField("+$0", text: Binding(
                    get: { optionDraftPrice[group.id] ?? "0" },
                    set: { optionDraftPrice[group.id] = $0 }
                ))
                .keyboardType(.decimalPad)
                .frame(width: 72)
                .textFieldStyle(.roundedBorder)
            }
            Button {
                addOptionToGroup(at: index, groupID: group.id)
            } label: {
                Label("Add option", systemImage: "plus.circle.fill")
            }
            .font(.caption.weight(.semibold))
            .disabled((optionDraftName[group.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(NightBitesTheme.ink.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var addGroupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a group")
                .font(.subheadline.weight(.bold))
            Text("Quick start")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NightBitesTheme.labelSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(OwnerMenuItemFormView.groupNameTemplates, id: \.self) { t in
                        Button(t) { newGroupName = t }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(NightBitesTheme.mutedCard)
                            .clipShape(Capsule())
                    }
                }
            }
            Text("Preset groups")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NightBitesTheme.labelSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.groupPresets, id: \.name) { preset in
                        Button("Add \(preset.name)") { addPresetGroup(preset) }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(NightBitesTheme.card)
                            .clipShape(Capsule())
                    }
                }
            }
            TextField("Group name (e.g. Toppings, Meat, Sauce)", text: $newGroupName)
                .textFieldStyle(.roundedBorder)
            Toggle("Customers must choose from this group", isOn: $newGroupRequired)
            Picker("Style", selection: $newGroupStyle) {
                Text("Pick one").tag(ModifierPickStyle.one)
                Text("Pick several").tag(ModifierPickStyle.several)
            }
            .pickerStyle(.segmented)
            if newGroupStyle == .several {
                Stepper("Up to \(newGroupSeveralMax) options", value: $newGroupSeveralMax, in: 2 ... 15)
            }
            Button {
                addNewGroupFromForm()
            } label: {
                Label("Add this group", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(NightBitesTheme.ember)
            .disabled(newGroupName.trimmed.isEmpty || groups.contains(where: { $0.name.caseInsensitiveCompare(newGroupName.trimmed) == .orderedSame }))
        }
        .padding(12)
        .background(NightBitesTheme.midnight.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static let groupNameTemplates = ["Toppings", "Meat", "Sauce", "Size", "Side", "Cheese", "Extras"]
    private static let groupPresets: [ModifierGroupPreset] = [
        ModifierGroupPreset(
            name: "Meat",
            isRequired: true,
            style: .one,
            options: [("Chicken", 0), ("Beef", 0), ("Pork", 0), ("Veggie", 0)]
        ),
        ModifierGroupPreset(
            name: "Toppings",
            isRequired: false,
            style: .several,
            maxSelection: 4,
            options: [("Lettuce", 0), ("Tomato", 0), ("Onion", 0), ("Cheese", 1.00), ("Guac", 1.50)]
        ),
        ModifierGroupPreset(
            name: "Sauce",
            isRequired: false,
            style: .several,
            maxSelection: 3,
            options: [("Mild", 0), ("Hot", 0), ("Chipotle", 0.50), ("Ranch", 0.50)]
        )
    ]

    private func addNewGroupFromForm() {
        let n = newGroupName.trimmed
        guard !n.isEmpty, !groups.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { return }
        let maxSel: Int
        let minSel: Int
        switch newGroupStyle {
        case .one:
            maxSel = 1
            minSel = newGroupRequired ? 1 : 0
        case .several:
            maxSel = max(2, newGroupSeveralMax)
            minSel = newGroupRequired ? 1 : 0
        }
        groups.append(
            MenuModifierGroup(
                name: n,
                isRequired: newGroupRequired,
                minSelection: minSel,
                maxSelection: maxSel
            )
        )
        newGroupName = ""
        newGroupRequired = false
        newGroupStyle = .one
        newGroupSeveralMax = 3
    }

    private func addPresetGroup(_ preset: ModifierGroupPreset) {
        guard !groups.contains(where: { $0.name.caseInsensitiveCompare(preset.name) == .orderedSame }) else { return }
        let minSel = preset.isRequired ? 1 : 0
        let maxSel = preset.style == .one ? 1 : max(2, preset.maxSelection)
        groups.append(
            MenuModifierGroup(
                name: preset.name,
                isRequired: preset.isRequired,
                minSelection: minSel,
                maxSelection: maxSel,
                options: preset.options.map { MenuModifierOption(name: $0.name, priceDelta: $0.delta) }
            )
        )
    }

    private func recomputeMinMax(at index: Int) {
        let g = groups[index]
        if g.maxSelection <= 1 {
            groups[index].minSelection = g.isRequired ? 1 : 0
        } else {
            groups[index].minSelection = g.isRequired ? 1 : 0
            groups[index].maxSelection = max(g.maxSelection, groups[index].minSelection)
        }
    }

    private func addOptionToGroup(at index: Int, groupID: UUID) {
        let oname = (optionDraftName[groupID] ?? "").trimmed
        let priceText = (optionDraftPrice[groupID] ?? "0").replacingOccurrences(of: ",", with: "")
        guard !oname.isEmpty, let p = Double(priceText) else { return }
        guard let idx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[idx].options.append(MenuModifierOption(name: oname, priceDelta: p))
        optionDraftName[groupID] = ""
        optionDraftPrice[groupID] = "0"
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.bold))
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(NightBitesTheme.labelSecondary)
        }
    }

    private func textFieldBlock(
        _ title: String,
        text: Binding<String>,
        caps: TextInputAutocapitalization,
        keyboard: UIKeyboardType = .default,
        axis: Axis = .horizontal
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(NightBitesTheme.labelSecondary)
            TextField(title, text: text, axis: axis)
                .textInputAutocapitalization(caps)
                .keyboardType(keyboard)
                .lineLimit(axis == .vertical ? 3 ... 8 : 1 ... 1)
                .padding(12)
                .background(NightBitesTheme.mutedCard)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func ownerCategoryChips() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MenuCategoryFormatting.suggested, id: \.self) { name in
                    let isOn = category.caseInsensitiveCompare(name) == .orderedSame
                    Button { category = name } label: {
                        Text(name)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isOn ? NightBitesTheme.ember.opacity(0.22) : NightBitesTheme.ink.opacity(0.3))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(isOn ? NightBitesTheme.ember : NightBitesTheme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isOn ? NightBitesTheme.ember : NightBitesTheme.label)
                }
            }
        }
    }

    private var validationIssues: [String] {
        var issues: [String] = []
        if name.trimmed.isEmpty { issues.append("Add an item name.") }
        if description.trimmed.isEmpty { issues.append("Add a description.") }
        if Double(priceText.replacingOccurrences(of: ",", with: "")) == nil {
            issues.append("Enter a valid numeric price.")
        } else if let p = Double(priceText.replacingOccurrences(of: ",", with: "")), p <= 0 {
            issues.append("Price must be greater than $0.")
        }
        return issues
    }

    @MainActor
    private func save() async {
        guard validationIssues.isEmpty else {
            validationNotice = validationIssues.joined(separator: "\n")
            saveStatus = SaveStatus(kind: .failed, message: "Check required fields and try again.")
            return
        }
        let cleanedGroups = groups.filter { !$0.options.isEmpty }
        isSaving = true
        saveStatus = SaveStatus(kind: .saving, message: "Saving item…")
        defer { isSaving = false }

        if isEditing, let item = editingItem {
            do {
                let p = Double(priceText.replacingOccurrences(of: ",", with: ""))!
                let urlOverride = imageURLText.trimmed.isEmpty ? nil : imageURLText.trimmed
                if localPhotoData != nil { isUploadingPhoto = true }
                try await viewModel.saveMenuItemFromOwnerForm(
                    itemID: item.id,
                    name: name,
                    description: description,
                    price: p,
                    category: category,
                    imageURL: urlOverride,
                    groups: cleanedGroups,
                    localImageData: localPhotoData,
                    localImageContentType: localPhotoData.map { MenuItemImageContentType.guess($0) } ?? "image/jpeg"
                )
                isUploadingPhoto = false
                localPhotoData = nil
                saveStatus = SaveStatus(kind: .success, message: "Saved and synced.")
                showSaveSuccess = true
            } catch {
                isUploadingPhoto = false
                validationNotice = (error as? LocalizedError)?.errorDescription ?? "Could not save this item right now."
                saveStatus = SaveStatus(kind: .failed, message: "Sync failed. Your changes were not fully saved.")
            }
        } else {
            do {
                let p = Double(priceText.replacingOccurrences(of: ",", with: ""))!
                let fromURL: String? = (localPhotoData == nil) ? (imageURLText.trimmed.isEmpty ? nil : imageURLText.trimmed) : nil
                let id = try await viewModel.addMenuItem(
                    to: truck.id,
                    name: name,
                    description: description,
                    price: p,
                    category: category,
                    imageURL: fromURL,
                    localImageData: localPhotoData,
                    localImageContentType: localPhotoData.map { MenuItemImageContentType.guess($0) } ?? "image/jpeg"
                )
                viewModel.replaceModifierGroups(itemID: id, groups: cleanedGroups)
                saveStatus = SaveStatus(kind: .success, message: "Saved and synced.")
                showSaveSuccess = true
            } catch {
                validationNotice = (error as? LocalizedError)?.errorDescription ?? "Could not save this item right now."
                saveStatus = SaveStatus(kind: .failed, message: "Sync failed. Try again.")
            }
        }
    }

    private func saveStatusBanner(_ status: SaveStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: status.kind.symbol)
                .font(.subheadline.weight(.bold))
            Text(status.message)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            if status.kind != .saving {
                Button {
                    saveStatus = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NightBitesTheme.labelSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(status.kind.background)
        .foregroundStyle(status.kind.foreground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(NightBitesTheme.border, lineWidth: 1)
        )
    }

    private func formatPriceDelta(_ v: Double) -> String {
        if v < -0.001 { return String(format: "-$%.2f", -v) }
        if v < 0.001 { return "Included" }
        return String(format: "+$%.2f", v)
    }
}

private enum ModifierPickStyle: Hashable {
    case one
    case several
}

private struct ModifierGroupPreset {
    let name: String
    let isRequired: Bool
    let style: ModifierPickStyle
    var maxSelection: Int = 3
    let options: [(name: String, delta: Double)]
}

private struct SaveStatus {
    enum Kind {
        case saving
        case success
        case failed

        var symbol: String {
            switch self {
            case .saving: return "arrow.triangle.2.circlepath"
            case .success: return "checkmark.circle.fill"
            case .failed: return "exclamationmark.triangle.fill"
            }
        }

        var background: Color {
            switch self {
            case .saving: return NightBitesTheme.info.opacity(0.18)
            case .success: return NightBitesTheme.success.opacity(0.18)
            case .failed: return Color.red.opacity(0.20)
            }
        }

        var foreground: Color {
            switch self {
            case .saving: return NightBitesTheme.info
            case .success: return NightBitesTheme.success
            case .failed: return Color.red.opacity(0.95)
            }
        }
    }

    let kind: Kind
    let message: String
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
