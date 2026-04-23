import SwiftUI

struct OwnerTruckManagementView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(FoodTruckViewModel.self) private var viewModel

    @State private var truckName = ""
    @State private var cuisineType = ""
    @State private var selectedCampusName = ""
    @State private var coverImageURL = ""
    @State private var profileImageURL = ""

    @State private var activeHoursDraft = ""
    @State private var latitudeDraft = ""
    @State private var longitudeDraft = ""
    @State private var prepMinutesDraft = "15"

    @State private var truckWorkspaceTab: OwnerTruckWorkspaceTab = .today
    @State private var hasAppliedEmptyMenuDefaultTab = false

    private enum OwnerTruckWorkspaceTab: String, CaseIterable, Identifiable {
        case today = "Today"
        case truck = "Truck"
        case menu = "Menu"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let truck = ownerTruck {
                        Picker("Workspace", selection: $truckWorkspaceTab) {
                            ForEach(OwnerTruckWorkspaceTab.allCases) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch truckWorkspaceTab {
                        case .today:
                            truckSummaryCard(truck)
                            orderControlsCard(truck)
                        case .truck:
                            truckSettingsCard(truck)
                        case .menu:
                            menuComposerCard(truck)
                            existingMenuCard(truck)
                        }

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
                applyEmptyMenuDefaultTabIfNeeded()
            }
            .onChange(of: ownerTruck?.id) {
                syncDrafts()
                hasAppliedEmptyMenuDefaultTab = false
                applyEmptyMenuDefaultTabIfNeeded()
            }
        }
    }

    private func applyEmptyMenuDefaultTabIfNeeded() {
        guard !hasAppliedEmptyMenuDefaultTab, let truck = ownerTruck else { return }
        if viewModel.getOwnerMenuItems(for: truck.id).isEmpty {
            truckWorkspaceTab = .menu
        }
        hasAppliedEmptyMenuDefaultTab = true
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

    private func orderControlsCard(_ truck: FoodTruck) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            workspaceSectionHeader(
                "Order controls",
                subtitle: "Open, pause, prep, intake, and payments",
                systemImage: "switch.2",
                accent: .orange
            )
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightBitesCard()
    }

    private func truckSettingsCard(_ truck: FoodTruck) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            workspaceSectionHeader(
                "Truck settings",
                subtitle: "Hours and published location",
                systemImage: "slider.horizontal.3",
                accent: .blue
            )
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightBitesCard()
    }

    private func menuComposerCard(_ truck: FoodTruck) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            workspaceSectionHeader(
                "Add to menu",
                subtitle: "Each item opens on its own page—name, photo, price, and add-ons like toppings or meat choice.",
                systemImage: "plus.square.on.square",
                accent: .green
            )
            NavigationLink {
                OwnerMenuItemFormView(truck: truck, editingItem: nil)
            } label: {
                Label("Add menu item", systemImage: "plus.circle.fill")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(NightBitesTheme.ember)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightBitesCard()
    }

    private func existingMenuCard(_ truck: FoodTruck) -> some View {
        let menuItems = viewModel.getOwnerMenuItems(for: truck.id)
        return VStack(alignment: .leading, spacing: 12) {
            workspaceSectionHeader(
                "Your menu",
                subtitle: "Tap an item to edit the full page—photo, price, category, and customizations.",
                systemImage: "fork.knife.circle",
                accent: NightBitesTheme.info
            )
            if menuItems.isEmpty {
                Text("No menu items yet. Add one above.")
                    .foregroundStyle(NightBitesTheme.labelSecondary)
            } else {
                ForEach(menuItems) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            ownerMenuItemThumb(item)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name)
                                            .font(.headline)
                                        Text(item.description)
                                            .font(.caption)
                                            .foregroundStyle(NightBitesTheme.labelSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(String(format: "$%.2f", item.price))
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(NightBitesTheme.saffron)
                                        Text(item.category)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(NightBitesTheme.labelSecondary)
                                    }
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            NavigationLink {
                                OwnerMenuItemFormView(truck: truck, editingItem: item)
                            } label: {
                                Label("Edit item", systemImage: "pencil")
                            }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                            .tint(NightBitesTheme.ember)

                            Button {
                                if item.isAvailable {
                                    viewModel.markMenuItemSoldOut(itemID: item.id)
                                } else {
                                    viewModel.setMenuItemAvailability(itemID: item.id, isAvailable: true)
                                }
                            } label: {
                                Text(item.isAvailable ? "Sold out" : "Back on")
                            }
                            .font(.subheadline.weight(.bold))
                            .buttonStyle(.bordered)
                            .tint(item.isAvailable ? .orange : .green)

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightBitesCard()
    }

    private func ownerMenuItemThumb(_ item: MenuItem) -> some View {
        Group {
            if let urlString = item.imageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    case .failure, .empty:
                        ownerMenuPlaceholderThumb
                    @unknown default:
                        ownerMenuPlaceholderThumb
                    }
                }
            } else {
                ownerMenuPlaceholderThumb
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(NightBitesTheme.border, lineWidth: 1)
        )
    }

    private var ownerMenuPlaceholderThumb: some View {
        ZStack {
            NightBitesTheme.mutedCard
            Image(systemName: "photo")
                .foregroundStyle(NightBitesTheme.labelSecondary)
        }
    }

    private func workspaceSectionHeader(_ title: String, subtitle: String, systemImage: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
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
            Spacer(minLength: 0)
        }
    }

    private func syncDrafts() {
        guard let truck = ownerTruck else { return }
        activeHoursDraft = truck.activeHours
        latitudeDraft = String(format: "%.5f", truck.liveLatitude)
        longitudeDraft = String(format: "%.5f", truck.liveLongitude)
        prepMinutesDraft = String(viewModel.prepMinutes(for: truck.id))
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

    private func activeOrderCount(for truck: FoodTruck) -> Int {
        guard let ownerID = authViewModel.currentUser?.id else { return 0 }
        return viewModel.ordersQueue(for: ownerID)
            .filter { $0.status != .completed && $0.status != .cancelled }
            .count
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
