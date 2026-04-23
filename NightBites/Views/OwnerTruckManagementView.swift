import PhotosUI
import SwiftUI

struct OwnerTruckManagementView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(FoodTruckViewModel.self) private var viewModel

    @State private var truckName = ""
    @State private var cuisineType = ""
    @State private var selectedCampusName = ""
    @State private var coverImageURL = ""
    @State private var profileImageURL = ""

    @State private var menuName = ""
    @State private var menuDescription = ""
    @State private var menuPrice = ""
    @State private var menuCategory = "Main"
    @State private var menuImageURL = ""
    @State private var newMenuPhoto: PhotosPickerItem?

    @State private var activeHoursDraft = ""
    @State private var latitudeDraft = ""
    @State private var longitudeDraft = ""
    @State private var prepMinutesDraft = "15"
    @State private var menuPriceDrafts: [UUID: String] = [:]
    @State private var menuCategoryDrafts: [UUID: String] = [:]

    @State private var expandedSection: TruckSection?

    private enum TruckSection {
        case orderControls
        case truckSettings
        case menuComposer
        case existingMenu
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let truck = ownerTruck {
                        truckSummaryCard(truck)
                        orderControlsSection(truck)
                        truckSettingsSection(truck)
                        menuComposerSection(truck)
                        existingMenuSection(truck)

                        if ownerTrucks.count > 1 {
                            Text("This MVP is set up for one truck per account. Additional trucks are hidden from the main workflow.")
                                .font(.footnote)
                                .foregroundStyle(NightBitesTheme.labelSecondary)
                                .padding(.horizontal, 4)
                        }
                    } else {
                        createTruckCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .nightBitesScreenBackground()
            .navigationTitle("My Truck")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                if selectedCampusName.isEmpty {
                    selectedCampusName = viewModel.campuses.first?.name ?? ""
                }
                syncDrafts()
            }
            .onChange(of: ownerTruck?.id) {
                syncDrafts()
            }
        }
    }

    private var ownerTrucks: [FoodTruck] {
        guard let ownerID = authViewModel.currentUser?.id else { return [] }
        return viewModel.trucksOwned(by: ownerID)
    }

    private var ownerTruck: FoodTruck? {
        ownerTrucks.first
    }

    private var createTruckCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Your Truck")
                .font(.title2.weight(.bold))

            Text("Each owner account uses one truck in the MVP. Set it up here, then manage everything from collapsible sections.")
                .foregroundStyle(NightBitesTheme.labelSecondary)

            HStack(spacing: 10) {
                textInput("Truck name", text: $truckName)
                textInput("Cuisine", text: $cuisineType)
            }

            textInput("Cover image URL", text: $coverImageURL, disableAutoCaps: true)
            textInput("Profile logo URL", text: $profileImageURL, disableAutoCaps: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Campus")
                    .font(.caption)
                    .foregroundStyle(NightBitesTheme.labelSecondary)
                Picker("Campus", selection: $selectedCampusName) {
                    ForEach(viewModel.campuses, id: \.name) { campus in
                        Text(campus.name).tag(campus.name)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(NightBitesTheme.mutedCard)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Button("Create Truck") {
                createTruck()
            }
            .buttonStyle(.borderedProminent)
            .tint(NightBitesTheme.ember)
            .disabled(!canCreateTruck)
        }
        .nightBitesCard()
    }

    private func truckSummaryCard(_ truck: FoodTruck) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(truck.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(NightBitesTheme.label)
                    Text("\(truck.cuisineType) • \(truck.campusName)")
                        .foregroundStyle(NightBitesTheme.labelSecondary)
                }

                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(NightBitesTheme.ink.opacity(0.45))
                        .frame(width: 52, height: 52)
                    Image(systemName: "truck.box.fill")
                        .font(.title2)
                        .foregroundColor(NightBitesTheme.ember)
                }
            }

            HStack(spacing: 8) {
                NightBitesChip(text: truck.liveStatusLabel, tint: NightBitesTheme.ember, foreground: NightBitesTheme.ember)
                Text("\(viewModel.getOwnerMenuItems(for: truck.id).count) menu items")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NightBitesTheme.labelSecondary)
                Text("Prep \(viewModel.prepMinutes(for: truck.id)) min")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NightBitesTheme.labelSecondary)
            }

            HStack(spacing: 10) {
                NightBitesMetricTile(
                    title: "Orders",
                    value: "\(activeOrderCount(for: truck))",
                    tint: NightBitesTheme.ember
                )
                NightBitesMetricTile(
                    title: "Pickup ETA",
                    value: truck.formattedWait,
                    tint: NightBitesTheme.saffron
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightBitesCard()
    }

    private func orderControlsSection(_ truck: FoodTruck) -> some View {
        DisclosureGroup(isExpanded: sectionBinding(.orderControls)) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(
                    "Auto-accept orders",
                    isOn: Binding(
                        get: { viewModel.isAutoAcceptEnabled(for: truck.id) },
                        set: { viewModel.setAutoAcceptEnabled($0, for: truck.id) }
                    )
                )

                Toggle(
                    "Pause new orders",
                    isOn: Binding(
                        get: { truck.ordersPaused },
                        set: { viewModel.setOrdersPaused(truckID: truck.id, paused: $0) }
                    )
                )

                Toggle(
                    "Busy mode",
                    isOn: Binding(
                        get: { viewModel.isBusyModeEnabled(for: truck.id) },
                        set: { viewModel.setBusyMode(truckID: truck.id, enabled: $0) }
                    )
                )

                HStack(spacing: 10) {
                    textInput("Prep minutes", text: $prepMinutesDraft, keyboard: .numberPad)
                    Button("Save") {
                        if let minutes = Int(prepMinutesDraft) {
                            viewModel.setPrepMinutes(truckID: truck.id, minutes: minutes)
                            prepMinutesDraft = String(viewModel.prepMinutes(for: truck.id))
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(Int(prepMinutesDraft) == nil)
                }

                HStack(spacing: 8) {
                    Button(truck.isOpen ? "Go Offline" : "Go Live") {
                        if truck.isOpen {
                            viewModel.goDark(truckID: truck.id)
                        } else {
                            viewModel.goLive(truckID: truck.id)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(truck.isOpen ? .gray : NightBitesTheme.success)

                    Button("Close Early") {
                        viewModel.closeEarly(truckID: truck.id)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!truck.isOpen)
                }

                Divider().overlay(NightBitesTheme.border)

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        "Accept online payments",
                        isOn: Binding(
                            get: { viewModel.acceptsOnlinePayments(for: truck.id) },
                            set: { viewModel.setAcceptsOnlinePayments($0, for: truck.id) }
                        )
                    )

                    Toggle(
                        "Offer Apple Pay",
                        isOn: Binding(
                            get: { viewModel.acceptsApplePay(for: truck.id) },
                            set: { viewModel.setAcceptsApplePay($0, for: truck.id) }
                        )
                    )
                    .disabled(!viewModel.acceptsOnlinePayments(for: truck.id))

                    Picker(
                        "Payout setup",
                        selection: Binding(
                            get: { viewModel.payoutAccountStatus(for: truck.id) },
                            set: { viewModel.setPayoutAccountStatus($0, for: truck.id) }
                        )
                    ) {
                        ForEach(OwnerPayoutAccountStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(paymentSetupMessage(for: truck))
                        .font(.footnote)
                        .foregroundStyle(NightBitesTheme.labelSecondary)
                }
            }
            .padding(.top, 12)
        } label: {
            sectionLabel(
                "Order Controls",
                subtitle: "Open, pause, prep, intake, and payments",
                systemImage: "switch.2",
                accent: .orange
            )
        }
        .nightBitesCard()
    }

    private func truckSettingsSection(_ truck: FoodTruck) -> some View {
        DisclosureGroup(isExpanded: sectionBinding(.truckSettings)) {
            VStack(alignment: .leading, spacing: 12) {
                textInput("Hours", text: $activeHoursDraft)

                HStack(spacing: 10) {
                    textInput("Latitude", text: $latitudeDraft, disableAutoCaps: true, keyboard: .decimalPad)
                    textInput("Longitude", text: $longitudeDraft, disableAutoCaps: true, keyboard: .decimalPad)
                }

                HStack(spacing: 8) {
                    Button("Save Hours") {
                        viewModel.updateActiveHours(truckID: truck.id, activeHours: activeHoursDraft)
                    }
                    .buttonStyle(.bordered)
                    .disabled(trimmed(activeHoursDraft) == truck.activeHours)

                    Button("Save Location") {
                        guard let latitude = Double(latitudeDraft), let longitude = Double(longitudeDraft) else { return }
                        viewModel.updateLiveLocation(truckID: truck.id, latitude: latitude, longitude: longitude)
                    }
                    .buttonStyle(.bordered)
                    .disabled(Double(latitudeDraft) == nil || Double(longitudeDraft) == nil)
                }
            }
            .padding(.top, 12)
        } label: {
            sectionLabel(
                "Truck Settings",
                subtitle: "Hours and published location",
                systemImage: "slider.horizontal.3",
                accent: .blue
            )
        }
        .nightBitesCard()
    }

    private func menuComposerSection(_ truck: FoodTruck) -> some View {
        DisclosureGroup(isExpanded: sectionBinding(.menuComposer)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    textInput("Item name", text: $menuName)
                    textInput("Category", text: $menuCategory)
                }

                textInput("Description", text: $menuDescription)

                HStack(spacing: 10) {
                    textInput("Price", text: $menuPrice, disableAutoCaps: true, keyboard: .decimalPad)
                    if viewModel.isRemoteEnabled {
                        PhotosPicker(selection: $newMenuPhoto, matching: .images, photoLibrary: .shared()) {
                            Label("Item photo", systemImage: "photo.badge.plus")
                        }
                        .labelStyle(.titleAndIcon)
                    }
                }
                if newMenuPhoto != nil {
                    Text("Photo will upload when you add the item")
                        .font(.caption2)
                        .foregroundStyle(NightBitesTheme.labelSecondary)
                }
                DisclosureGroup("Optional: paste an image link instead") {
                    textInput("Image URL", text: $menuImageURL, disableAutoCaps: true)
                }
                .font(.subheadline.weight(.semibold))

                Button("Add Menu Item") {
                    addMenuItem(to: truck)
                }
                .buttonStyle(.borderedProminent)
                .tint(NightBitesTheme.ember)
                .disabled(!canAddMenuItem)
            }
            .padding(.top, 12)
        } label: {
            sectionLabel(
                "Menu",
                subtitle: "Add new items",
                systemImage: "plus.square.on.square",
                accent: .green
            )
        }
        .nightBitesCard()
    }

    private func existingMenuSection(_ truck: FoodTruck) -> some View {
        DisclosureGroup(isExpanded: sectionBinding(.existingMenu)) {
            VStack(alignment: .leading, spacing: 12) {
                let menuItems = viewModel.getOwnerMenuItems(for: truck.id)

                if menuItems.isEmpty {
                    Text("No menu items yet.")
                        .foregroundStyle(NightBitesTheme.labelSecondary)
                        .padding(.top, 12)
                } else {
                    ForEach(menuItems) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.headline)
                                    Text(item.description)
                                        .font(.caption)
                                        .foregroundStyle(NightBitesTheme.labelSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    if item.isAvailable {
                                        viewModel.markMenuItemSoldOut(itemID: item.id)
                                    } else {
                                        viewModel.setMenuItemAvailability(itemID: item.id, isAvailable: true)
                                    }
                                } label: {
                                    Text(item.isAvailable ? "Out" : "Back on")
                                }
                                .font(.subheadline.weight(.bold))
                                .buttonStyle(.bordered)
                                .tint(item.isAvailable ? .orange : .green)
                            }

                            HStack(spacing: 10) {
                                textInput(
                                    "Price",
                                    text: Binding(
                                        get: { menuPriceDrafts[item.id] ?? String(format: "%.2f", item.price) },
                                        set: { menuPriceDrafts[item.id] = $0 }
                                    ),
                                    disableAutoCaps: true,
                                    keyboard: .decimalPad
                                )

                                textInput(
                                    "Category",
                                    text: Binding(
                                        get: { menuCategoryDrafts[item.id] ?? item.category },
                                        set: { menuCategoryDrafts[item.id] = $0 }
                                    )
                                )
                            }

                            HStack(spacing: 8) {
                                Button("Save Price") {
                                    guard let price = Double(menuPriceDrafts[item.id] ?? "") else { return }
                                    viewModel.updateMenuItemPrice(itemID: item.id, price: price)
                                }
                                .buttonStyle(.bordered)
                                .disabled(!canSavePrice(for: item))

                                Button("Save Category") {
                                    let category = menuCategoryDrafts[item.id] ?? ""
                                    viewModel.updateMenuItemCategory(itemID: item.id, category: category)
                                }
                                .buttonStyle(.bordered)
                                .disabled(!canSaveCategory(for: item))
                            }

                            HStack(spacing: 10) {
                                NavigationLink {
                                    OwnerMenuItemEditorView(truck: truck, item: item)
                                } label: {
                                    Label("Edit item", systemImage: "slider.horizontal.3")
                                }
                                .font(.subheadline.weight(.semibold))

                                Button {
                                    viewModel.duplicateMenuItem(itemID: item.id)
                                } label: {
                                    Label("Duplicate", systemImage: "doc.on.doc")
                                }
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 8)

                        if item.id != menuItems.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(.top, 12)
        } label: {
            sectionLabel(
                "Existing Menu",
                subtitle: "Mark items out, edit prices, duplicate a plate",
                systemImage: "fork.knife.circle",
                accent: NightBitesTheme.info
            )
        }
        .nightBitesCard()
    }

    private func syncDrafts() {
        guard let truck = ownerTruck else { return }
        activeHoursDraft = truck.activeHours
        latitudeDraft = String(format: "%.5f", truck.liveLatitude)
        longitudeDraft = String(format: "%.5f", truck.liveLongitude)
        prepMinutesDraft = String(viewModel.prepMinutes(for: truck.id))

        for item in viewModel.getOwnerMenuItems(for: truck.id) {
            if menuPriceDrafts[item.id] == nil {
                menuPriceDrafts[item.id] = String(format: "%.2f", item.price)
            }
            if menuCategoryDrafts[item.id] == nil {
                menuCategoryDrafts[item.id] = item.category
            }
        }
    }

    private var canCreateTruck: Bool {
        ownerTruck == nil &&
            !isBlank(truckName) &&
            !isBlank(cuisineType) &&
            !selectedCampusName.isEmpty &&
            authViewModel.currentUser != nil
    }

    private func createTruck() {
        guard let ownerID = authViewModel.currentUser?.id else { return }

        viewModel.createTruck(
            name: truckName,
            cuisineType: cuisineType,
            campusName: selectedCampusName,
            ownerUserID: ownerID,
            plan: .free,
            coverImageURL: nilIfBlank(coverImageURL),
            profileImageURL: nilIfBlank(profileImageURL)
        )

        truckName = ""
        cuisineType = ""
        coverImageURL = ""
        profileImageURL = ""
    }

    private var canAddMenuItem: Bool {
        !isBlank(menuName) &&
            !isBlank(menuDescription) &&
            Double(menuPrice) != nil
    }

    private func addMenuItem(to truck: FoodTruck) {
        guard let price = Double(menuPrice) else { return }
        Task { @MainActor in
            var data: Data?
            var contentType = "image/jpeg"
            if let item = newMenuPhoto,
               let loaded = try? await item.loadTransferable(type: Data.self) {
                data = loaded
                contentType = menuItemImageContentType(loaded)
            }
            let category = isBlank(menuCategory) ? "Main" : trimmed(menuCategory)
            let fromURL: String? = (data == nil) ? nilIfBlank(menuImageURL) : nil
            viewModel.addMenuItem(
                to: truck.id,
                name: menuName,
                description: menuDescription,
                price: price,
                category: category,
                imageURL: fromURL,
                localImageData: data,
                localImageContentType: contentType
            )
            menuName = ""
            menuDescription = ""
            menuPrice = ""
            menuCategory = "Main"
            menuImageURL = ""
            newMenuPhoto = nil
        }
    }

    private func menuItemImageContentType(_ data: Data) -> String {
        guard data.count >= 4 else { return "image/jpeg" }
        if data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47 { return "image/png" }
        if data[0] == 0xFF, data[1] == 0xD8 { return "image/jpeg" }
        return "image/jpeg"
    }

    private func activeOrderCount(for truck: FoodTruck) -> Int {
        guard let ownerID = authViewModel.currentUser?.id else { return 0 }
        return viewModel.ordersQueue(for: ownerID)
            .filter { $0.status != .completed && $0.status != .cancelled }
            .count
    }

    private func canSavePrice(for item: MenuItem) -> Bool {
        guard let draft = menuPriceDrafts[item.id], let value = Double(draft), value >= 0 else { return false }
        return abs(value - item.price) > 0.001
    }

    private func canSaveCategory(for item: MenuItem) -> Bool {
        guard let draft = menuCategoryDrafts[item.id] else { return false }
        let normalized = trimmed(draft)
        return !normalized.isEmpty && normalized != item.category
    }

    private func paymentSetupMessage(for truck: FoodTruck) -> String {
        if !AppReleaseConfig.enableDigitalPayments {
            return "Digital payments are disabled in this build. Keep cash on until Stripe and Apple Pay are configured."
        }
        switch viewModel.payoutAccountStatus(for: truck.id) {
        case .notStarted:
            return "Truck is not connected for payouts yet. Students will only see pay at pickup."
        case .pending:
            return "Payout onboarding is not finished yet. Online payments stay hidden until setup is complete."
        case .connected:
            if viewModel.acceptsOnlinePayments(for: truck.id) {
                return "This truck can accept in-app card payments. Apple Pay appears only if you also enable it."
            }
            return "Payouts are connected. Turn on online payments when you are ready to accept card orders."
        }
    }

    private func sectionLabel(_ title: String, subtitle: String, systemImage: String, accent: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(accent.opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: systemImage)
                    .foregroundColor(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(NightBitesTheme.labelSecondary)
            }

            Spacer()

            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(NightBitesTheme.labelSecondary)
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isBlank(_ value: String) -> Bool {
        trimmed(value).isEmpty
    }

    private func nilIfBlank(_ value: String) -> String? {
        let trimmedValue = trimmed(value)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func sectionBinding(_ section: TruckSection) -> Binding<Bool> {
        Binding(
            get: { expandedSection == section },
            set: { isExpanded in
                withAnimation(.spring(duration: 0.26)) {
                    expandedSection = isExpanded ? section : nil
                }
            }
        )
    }

    private func textInput(
        _ title: String,
        text: Binding<String>,
        disableAutoCaps: Bool = false,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(NightBitesTheme.labelSecondary)
            TextField(title, text: text)
                .textInputAutocapitalization(disableAutoCaps ? .never : .words)
                .autocorrectionDisabled(disableAutoCaps)
                .keyboardType(keyboard)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(NightBitesTheme.mutedCard)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
