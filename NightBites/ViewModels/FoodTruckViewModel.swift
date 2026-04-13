import Foundation
import Observation

struct OwnerAnalytics {
    let busiestTimeLabel: String
    let topItems: [(name: String, quantity: Int)]
    let repeatCustomerPercentage: Double
    let averageOrderValue: Double
}

struct OwnerPayoutSummary {
    let todaysEarnings: Double
    let weeklyEarnings: Double
    let pendingPayouts: Double
    let nextPayoutDateLabel: String
    let platformFees: Double
    let processingFees: Double
    let subscriptionFees: Double
    let netEarnings: Double
}

enum RemoteSyncPhase: Equatable {
    case idle
    case syncing
    case failed(String)
}

@MainActor
@Observable
final class FoodTruckViewModel {
    private static let persistedOrdersKey = "nightbites.orders.v1"
    private static let persistedAutoAcceptKey = "nightbites.orders.autoAccept.v1"
    private static let persistedPaymentSettingsKey = "nightbites.trucks.paymentSettings.v1"
    private let backendService: BackendService
    private var gpsUpdateTask: Task<Void, Never>?
    private var remoteSyncTask: Task<Void, Never>?

    var campuses: [Campus] = []
    var foodTrucks: [FoodTruck] = []
    var menuItems: [MenuItem] = []
    var orders: [Order] = []
    var truckApplications: [TruckApplication] = []
    var reviews: [Review] = []

    var selectedCampusID: UUID?
    var selectedCuisine: String = "All"
    var searchText: String = ""

    var remoteSyncPhase: RemoteSyncPhase = .idle

    /// Programmatic checkout push must target a `NavigationStack` root — not `FoodTruckDetailView` — or SwiftUI drops the destination.
    var studentCheckoutTruckID: UUID?
    /// Filled when checkout completes; `StudentRootView` presents order tracking globally.
    var studentOrderPendingTracking: Order?

    var cartLines: [CartLine] = []
    var nextStopByTruckID: [UUID: String] = [:]
    var recurringScheduleByTruckID: [UUID: String] = [:]
    var autoAcceptByTruckID: [UUID: Bool] = [:]
    var onlinePaymentsEnabledByTruckID: [UUID: Bool] = [:]
    var applePayEnabledByTruckID: [UUID: Bool] = [:]
    var payoutAccountStatusByTruckID: [UUID: OwnerPayoutAccountStatus] = [:]

    init(backendService: BackendService) {
        self.backendService = backendService
        loadData()
        selectedCampusID = campuses.first?.id
        if backendService.isRemoteEnabled {
            Task {
                await refreshFromRemote()
            }
            startRemoteSync()
        } else {
            loadPersistedOrders()
        }
        loadPersistedAutoAcceptSettings()
        loadPersistedPaymentSettings()
        startGPSUpdates()
    }

    var isRemoteEnabled: Bool {
        backendService.isRemoteEnabled
    }

    var selectedCampus: Campus? {
        campuses.first(where: { $0.id == selectedCampusID })
    }

    var availableCuisines: [String] {
        let cuisines = Set(foodTrucks.map(\.cuisineType))
        return ["All"] + cuisines.sorted()
    }

    var filteredFoodTrucks: [FoodTruck] {
        foodTrucks
            .filter(\.isDiscoverable)
            .filter { truck in
                guard let campus = selectedCampus else { return true }
                return truck.campusName == campus.name
            }
            .filter { truck in
                selectedCuisine == "All" || truck.cuisineType == selectedCuisine
            }
            .filter { truck in
                searchText.isEmpty ||
                truck.name.localizedCaseInsensitiveContains(searchText) ||
                truck.cuisineType.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.distance < $1.distance }
    }

    var cartTruckID: UUID? {
        cartLines.first?.menuItem.truckId
    }

    var activeCartItemCount: Int {
        cartLines.reduce(0) { $0 + $1.quantity }
    }

    var activeCartSubtotal: Double {
        cartLines.reduce(0) { $0 + $1.lineSubtotal() }
    }

    func getMenuItems(for truckId: UUID) -> [MenuItem] {
        menuItems
            .filter { $0.truckId == truckId && $0.isAvailable }
            .sorted { $0.name < $1.name }
    }

    /// Student menu: includes sold-out / unavailable rows for clear UI treatment.
    func getStudentMenuItems(for truckId: UUID) -> [MenuItem] {
        menuItems
            .filter { $0.truckId == truckId }
            .sorted { lhs, rhs in
                if lhs.isAvailable != rhs.isAvailable { return lhs.isAvailable && !rhs.isAvailable }
                if lhs.category != rhs.category { return lhs.category < rhs.category }
                return lhs.name < rhs.name
            }
    }

    func getOwnerMenuItems(for truckId: UUID) -> [MenuItem] {
        menuItems
            .filter { $0.truckId == truckId }
            .sorted {
                if $0.category == $1.category {
                    return $0.name < $1.name
                }
                return $0.category < $1.category
            }
    }

    func quantityInCart(for item: MenuItem) -> Int {
        cartLines.filter { $0.menuItem.id == item.id }.reduce(0) { $0 + $1.quantity }
    }

    func addCartLine(menuItem: MenuItem, selections: [UUID: Set<UUID>], quantity: Int) {
        guard menuItem.isAvailable else { return }
        if cartTruckID != nil, cartTruckID != menuItem.truckId {
            clearCart()
        }
        let normalized = CartLine.normalizedSelections(menuItem: menuItem, raw: selections)
        if let index = cartLines.firstIndex(where: { $0.matchesConfiguration(menuItem: menuItem, selections: normalized) }) {
            cartLines[index].quantity += quantity
        } else {
            cartLines.append(
                CartLine(menuItem: menuItem, quantity: quantity, selectionsByGroupID: normalized, lineNotes: nil)
            )
        }
    }

    /// One-tap add when the item has no modifier groups.
    func quickAddToCart(item: MenuItem) {
        guard !item.hasModifiers else { return }
        addCartLine(menuItem: item, selections: [:], quantity: 1)
    }

    func incrementCartLine(id: UUID) {
        guard let index = cartLines.firstIndex(where: { $0.id == id }) else { return }
        cartLines[index].quantity += 1
    }

    func decrementCartLine(id: UUID) {
        guard let index = cartLines.firstIndex(where: { $0.id == id }) else { return }
        if cartLines[index].quantity <= 1 {
            cartLines.remove(at: index)
        } else {
            cartLines[index].quantity -= 1
        }
    }

    func removeCartLine(id: UUID) {
        cartLines.removeAll { $0.id == id }
    }

    func clearCart() {
        cartLines.removeAll()
    }

    @discardableResult
    func placeOrder(
        paymentMethod: PaymentMethod,
        paymentStatus: PaymentStatus? = nil,
        paymentTransactionID: String? = nil,
        customerUserID: String?,
        customerName: String,
        customization: String?,
        pickupTiming: PickupTiming,
        scheduledPickupDate: Date?
    ) -> Order? {
        guard
            let truckID = cartTruckID,
            let truck = foodTrucks.first(where: { $0.id == truckID }),
            truck.supportsOrdering,
            !cartLines.isEmpty
        else {
            AppTelemetry.track(error: "order_place_blocked_validation")
            return nil
        }

        let trimmedCustomization = customization?.trimmed
        let resolvedCustomization = trimmedCustomization?.isEmpty == false ? trimmedCustomization : nil

        let items = cartLines.map { line in
            OrderItem(
                menuItem: line.pricedMenuItemSnapshot(),
                quantity: line.quantity,
                customization: line.orderCustomizationText()
            )
        }
        .sorted { $0.menuItem.name < $1.menuItem.name }

        let computedSubtotal = items.reduce(0) { $0 + $1.subtotal }
        let computedServiceFee = serviceFee(for: computedSubtotal)
        let computedChargedTotal = computedSubtotal + computedServiceFee

        let isAutoAcceptEnabled = autoAcceptByTruckID[truckID] ?? false
        let resolvedPickupDate: Date?
        switch pickupTiming {
        case .asap:
            resolvedPickupDate = Date().addingTimeInterval(TimeInterval(prepMinutes(for: truckID) * 60))
        case .scheduled:
            if let scheduledPickupDate {
                resolvedPickupDate = max(scheduledPickupDate, Date().addingTimeInterval(5 * 60))
            } else {
                resolvedPickupDate = Date().addingTimeInterval(TimeInterval(prepMinutes(for: truckID) * 60))
            }
        }

        let order = Order(
            truckID: truck.id,
            customerUserID: customerUserID,
            truckName: truck.name,
            campusName: truck.campusName,
            items: items,
            subtotalAmount: computedSubtotal,
            serviceFeeAmount: computedServiceFee,
            chargedTotalAmount: computedChargedTotal,
            status: isAutoAcceptEnabled ? .accepted : .pending,
            paymentMethod: paymentMethod,
            paymentStatus: paymentStatus,
            paymentTransactionID: paymentTransactionID,
            pickupTiming: pickupTiming,
            orderDate: Date(),
            estimatedDelivery: resolvedPickupDate,
            customerName: customerName.trimmed.isEmpty ? "Guest" : customerName.trimmed,
            specialInstructions: resolvedCustomization
        )

        orders.insert(order, at: 0)
        persistOrders()
        AppTelemetry.track(
            event: "order_place_success",
            metadata: [
                "truck_id": truck.id.uuidString,
                "item_count": String(items.count),
                "payment_method": paymentMethod.rawValue,
                "pickup_timing": pickupTiming.rawValue
            ]
        )
        Task {
            await backendService.submit(order: order)
            await refreshFromRemote()
        }
        clearCart()
        return order
    }

    func submitTruckApplication(
        truckName: String,
        ownerName: String,
        cuisineType: String,
        campusName: String,
        contactEmail: String,
        selectedPlan: TruckPlan
    ) {
        let application = TruckApplication(
            truckName: truckName,
            ownerName: ownerName,
            cuisineType: cuisineType,
            campusName: campusName,
            contactEmail: contactEmail,
            selectedPlan: selectedPlan,
            createdAt: Date(),
            status: .submitted
        )

        truckApplications.insert(application, at: 0)
        Task {
            await backendService.submit(application: application)
        }
    }

    func reviews(for truckID: UUID) -> [Review] {
        reviews
            .filter { $0.truckId == truckID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func addReview(truckID: UUID, userName: String, rating: Int, text: String, mediaURL: String?) {
        let trimmedText = text.trimmed
        guard !trimmedText.isEmpty else { return }
        let trimmedMediaURL = mediaURL?.trimmed

        let review = Review(
            truckId: truckID,
            userDisplayName: userName,
            rating: min(max(rating, 1), 5),
            text: trimmedText,
            mediaURL: trimmedMediaURL?.isEmpty == false ? trimmedMediaURL : nil,
            createdAt: Date()
        )
        reviews.insert(review, at: 0)
        Task {
            await backendService.submit(review: review)
        }
    }

    func trucksOwned(by ownerUserID: String) -> [FoodTruck] {
        foodTrucks.filter { $0.ownerUserID == ownerUserID }
    }

    func createTruck(
        name: String,
        cuisineType: String,
        campusName: String,
        ownerUserID: String,
        plan: TruckPlan,
        coverImageURL: String?,
        profileImageURL: String?
    ) {
        let trimmedName = name.trimmed
        let trimmedCuisine = cuisineType.trimmed
        guard !trimmedName.isEmpty, !trimmedCuisine.isEmpty else { return }

        let campus = campuses.first(where: { $0.name == campusName }) ?? campuses.first
        guard let campus else { return }

        let truck = FoodTruck(
            ownerUserID: ownerUserID,
            name: trimmedName,
            cuisineType: trimmedCuisine,
            campusName: campus.name,
            distance: 0.2,
            rating: 0.0,
            ratingCount: 0,
            estimatedWait: 15,
            isOpen: true,
            ordersPaused: false,
            closedEarly: false,
            activeHours: "10:00 AM - 3:00 PM",
            imageName: "food-truck",
            coverImageURL: coverImageURL,
            profileImageURL: profileImageURL,
            galleryImageURLs: [],
            latitude: campus.latitude,
            longitude: campus.longitude,
            liveLatitude: campus.latitude,
            liveLongitude: campus.longitude,
            plan: plan,
            hasLiveTracking: true,
            proSubscriptionActive: false,
            closingAt: nil
        )

        foodTrucks.insert(truck, at: 0)
        Task {
            await backendService.submit(truck: truck)
            await refreshFromRemote()
        }
    }

    func addMenuItem(
        to truckID: UUID,
        name: String,
        description: String,
        price: Double,
        category: String,
        imageURL: String?
    ) {
        let trimmedName = name.trimmed
        let trimmedDescription = description.trimmed
        guard !trimmedName.isEmpty, !trimmedDescription.isEmpty, price > 0 else { return }

        let item = MenuItem(
            name: trimmedName,
            description: trimmedDescription,
            price: price,
            category: category,
            isAvailable: true,
            truckId: truckID,
            imageURL: imageURL,
            tags: []
        )
        menuItems.insert(item, at: 0)
        let truckName = foodTrucks.first(where: { $0.id == truckID })?.name ?? ""
        Task {
            await backendService.submit(menuItem: item, truckName: truckName)
            await refreshFromRemote()
        }
    }

    func setMenuItemAvailability(itemID: UUID, isAvailable: Bool) {
        guard let index = menuItems.firstIndex(where: { $0.id == itemID }) else { return }
        menuItems[index].isAvailable = isAvailable
        persistMenuItemChange(itemID: itemID)
    }

    func markMenuItemSoldOut(itemID: UUID) {
        setMenuItemAvailability(itemID: itemID, isAvailable: false)
    }

    func updateMenuItemPrice(itemID: UUID, price: Double) {
        guard let index = menuItems.firstIndex(where: { $0.id == itemID }), price >= 0 else { return }
        menuItems[index].price = price
        persistMenuItemChange(itemID: itemID)
    }

    func updateMenuItemCategory(itemID: UUID, category: String) {
        let trimmedCategory = category.trimmed
        guard let index = menuItems.firstIndex(where: { $0.id == itemID }), !trimmedCategory.isEmpty else { return }
        menuItems[index].category = trimmedCategory
        persistMenuItemChange(itemID: itemID)
    }

    func addModifierGroup(
        to itemID: UUID,
        name: String,
        isRequired: Bool,
        maxSelection: Int
    ) {
        let trimmedName = name.trimmed
        guard let index = menuItems.firstIndex(where: { $0.id == itemID }), !trimmedName.isEmpty else { return }
        if menuItems[index].modifierGroups.contains(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            return
        }
        let minSelection = isRequired ? 1 : 0
        let normalizedMax = max(maxSelection, minSelection)
        menuItems[index].modifierGroups.append(
            MenuModifierGroup(
                name: trimmedName,
                isRequired: isRequired,
                minSelection: minSelection,
                maxSelection: normalizedMax
            )
        )
    }

    func addModifierOption(
        to itemID: UUID,
        groupName: String,
        optionName: String,
        priceDelta: Double
    ) {
        let trimmedGroup = groupName.trimmed
        let trimmedOption = optionName.trimmed
        guard
            let itemIndex = menuItems.firstIndex(where: { $0.id == itemID }),
            !trimmedGroup.isEmpty,
            !trimmedOption.isEmpty
        else {
            return
        }

        guard let groupIndex = menuItems[itemIndex].modifierGroups.firstIndex(
            where: { $0.name.caseInsensitiveCompare(trimmedGroup) == .orderedSame }
        ) else {
            return
        }

        menuItems[itemIndex].modifierGroups[groupIndex].options.append(
            MenuModifierOption(name: trimmedOption, priceDelta: priceDelta)
        )
    }

    func activateProSubscription(truckID: UUID) {
        guard let index = foodTrucks.firstIndex(where: { $0.id == truckID }) else { return }
        foodTrucks[index].plan = .pro
        foodTrucks[index].hasLiveTracking = true
        foodTrucks[index].proSubscriptionActive = true
    }

    func goLive(truckID: UUID) {
        guard let index = foodTrucks.firstIndex(where: { $0.id == truckID }) else { return }
        foodTrucks[index].isOpen = true
        foodTrucks[index].ordersPaused = false
        foodTrucks[index].closedEarly = false
        foodTrucks[index].hasLiveTracking = true
        #if DEBUG
            refreshBroadcastLocation(for: index)
        #endif
        persistTruckChange(truckID: truckID)
    }

    func goDark(truckID: UUID) {
        guard let index = foodTrucks.firstIndex(where: { $0.id == truckID }) else { return }
        foodTrucks[index].isOpen = false
        foodTrucks[index].ordersPaused = true
        foodTrucks[index].hasLiveTracking = false
        persistTruckChange(truckID: truckID)
    }

    func setOrdersPaused(truckID: UUID, paused: Bool) {
        guard let index = foodTrucks.firstIndex(where: { $0.id == truckID }) else { return }
        foodTrucks[index].ordersPaused = paused
        #if DEBUG
            if foodTrucks[index].isOpen {
                refreshBroadcastLocation(for: index)
            }
        #endif
        persistTruckChange(truckID: truckID)
    }

    func prepMinutes(for truckID: UUID) -> Int {
        guard let index = foodTrucks.firstIndex(where: { $0.id == truckID }) else { return 15 }
        return foodTrucks[index].prepMinutesOverride ?? foodTrucks[index].estimatedWait
    }

    func setPrepMinutes(truckID: UUID, minutes: Int) {
        guard let index = foodTrucks.firstIndex(where: { $0.id == truckID }) else { return }
        foodTrucks[index].prepMinutesOverride = max(5, minutes)
        persistTruckChange(truckID: truckID)
    }

    func resetPrepMinutes(truckID: UUID) {
        guard let index = foodTrucks.firstIndex(where: { $0.id == truckID }) else { return }
        foodTrucks[index].prepMinutesOverride = nil
    }

    func isBusyModeEnabled(for truckID: UUID) -> Bool {
        guard let index = foodTrucks.firstIndex(where: { $0.id == truckID }) else { return false }
        return foodTrucks[index].prepLoadMultiplier > 1.01
    }

    func setBusyMode(truckID: UUID, enabled: Bool) {
        guard let index = foodTrucks.firstIndex(where: { $0.id == truckID }) else { return }
        foodTrucks[index].prepLoadMultiplier = enabled ? 1.35 : 1.0
        persistTruckChange(truckID: truckID)
    }

    func closeEarly(truckID: UUID) {
        guard let index = foodTrucks.firstIndex(where: { $0.id == truckID }) else { return }
        foodTrucks[index].isOpen = false
        foodTrucks[index].closedEarly = true
        foodTrucks[index].ordersPaused = true
        foodTrucks[index].hasLiveTracking = false
        persistTruckChange(truckID: truckID)
    }

    func updateActiveHours(truckID: UUID, activeHours: String) {
        let trimmed = activeHours.trimmed
        guard let index = foodTrucks.firstIndex(where: { $0.id == truckID }) else { return }
        foodTrucks[index].activeHours = trimmed.isEmpty ? "Not set" : trimmed
        persistTruckChange(truckID: truckID)
    }

    func updateLiveLocation(truckID: UUID, latitude: Double, longitude: Double) {
        guard let index = foodTrucks.firstIndex(where: { $0.id == truckID }) else { return }
        foodTrucks[index].liveLatitude = latitude
        foodTrucks[index].liveLongitude = longitude
        foodTrucks[index].hasLiveTracking = true
        persistTruckChange(truckID: truckID)
    }

    func updateRouteInfo(truckID: UUID, nextStop: String, recurringSchedule: String) {
        let trimmedNextStop = nextStop.trimmed
        let trimmedSchedule = recurringSchedule.trimmed
        nextStopByTruckID[truckID] = trimmedNextStop.isEmpty ? nil : trimmedNextStop
        recurringScheduleByTruckID[truckID] = trimmedSchedule.isEmpty ? nil : trimmedSchedule
    }

    func ordersQueue(for ownerUserID: String) -> [Order] {
        let ownedTrucks = trucksOwned(by: ownerUserID)
        let ownedTruckIDs = Set(ownedTrucks.map(\.id))
        return orders
            .filter { order in
                guard let truckID = order.truckID else { return false }
                return ownedTruckIDs.contains(truckID)
            }
            .sorted { $0.orderDate > $1.orderDate }
    }

    func orders(for customerUserID: String) -> [Order] {
        orders
            .filter { $0.customerUserID == customerUserID }
            .sorted { $0.orderDate > $1.orderDate }
    }

    func lastOrder(for truckID: UUID, customerUserID: String) -> Order? {
        return orders
            .filter { order in
                order.customerUserID == customerUserID && order.truckID == truckID
            }
            .sorted { $0.orderDate > $1.orderDate }
            .first
    }

    @discardableResult
    func reorderLastOrder(for truckID: UUID, customerUserID: String) -> Bool {
        guard
            let truck = foodTrucks.first(where: { $0.id == truckID }),
            truck.supportsOrdering,
            let recentOrder = lastOrder(for: truckID, customerUserID: customerUserID)
        else {
            AppTelemetry.track(
                error: "order_reorder_blocked",
                metadata: ["truck_id": truckID.uuidString]
            )
            return false
        }

        if cartTruckID != nil, cartTruckID != truckID {
            clearCart()
        }

        let catalogByID = Dictionary(uniqueKeysWithValues: getStudentMenuItems(for: truckID).map { ($0.id, $0) })
        let catalogByName = Dictionary(uniqueKeysWithValues: getStudentMenuItems(for: truckID).map { ($0.name.lowercased(), $0) })
        var rebuiltLines: [CartLine] = []
        for item in recentOrder.items {
            guard
                let currentMenuItem = catalogByID[item.menuItem.id]
                    ?? catalogByName[item.menuItem.name.lowercased()],
                currentMenuItem.isAvailable
            else {
                continue
            }
            rebuiltLines.append(
                CartLine(
                    menuItem: currentMenuItem,
                    quantity: item.quantity,
                    selectionsByGroupID: [:],
                    lineNotes: item.customization
                )
            )
        }

        guard !rebuiltLines.isEmpty else {
            AppTelemetry.track(
                error: "order_reorder_no_available_items",
                metadata: ["truck_id": truckID.uuidString]
            )
            return false
        }
        cartLines = rebuiltLines
        AppTelemetry.track(
            event: "order_reorder_success",
            metadata: ["truck_id": truckID.uuidString, "item_count": String(rebuiltLines.count)]
        )
        return true
    }

    func setAutoAcceptEnabled(_ enabled: Bool, for truckID: UUID) {
        autoAcceptByTruckID[truckID] = enabled
        if enabled {
            for index in orders.indices where
                orders[index].truckID == truckID &&
                orders[index].status == .pending {
                orders[index].status = .accepted
            }
            persistOrders()
        }
        persistAutoAcceptSettings()
    }

    func isAutoAcceptEnabled(for truckID: UUID) -> Bool {
        autoAcceptByTruckID[truckID] ?? false
    }

    func acceptsOnlinePayments(for truckID: UUID) -> Bool {
        onlinePaymentsEnabledByTruckID[truckID] ?? false
    }

    func acceptsApplePay(for truckID: UUID) -> Bool {
        applePayEnabledByTruckID[truckID] ?? false
    }

    func payoutAccountStatus(for truckID: UUID) -> OwnerPayoutAccountStatus {
        payoutAccountStatusByTruckID[truckID] ?? .notStarted
    }

    func canAcceptDigitalPayments(for truckID: UUID) -> Bool {
        AppReleaseConfig.enableDigitalPayments &&
            acceptsOnlinePayments(for: truckID) &&
            payoutAccountStatus(for: truckID) == .connected
    }

    func availablePaymentMethods(for truckID: UUID) -> [PaymentMethod] {
        guard canAcceptDigitalPayments(for: truckID) else { return [.cash] }
        var methods: [PaymentMethod] = []
        if acceptsApplePay(for: truckID) {
            methods.append(.applePay)
        }
        methods.append(.card)
        methods.append(.cash)
        return methods
    }

    func setAcceptsOnlinePayments(_ enabled: Bool, for truckID: UUID) {
        onlinePaymentsEnabledByTruckID[truckID] = enabled
        if !enabled {
            applePayEnabledByTruckID[truckID] = false
        }
        persistPaymentSettings()
    }

    func setAcceptsApplePay(_ enabled: Bool, for truckID: UUID) {
        applePayEnabledByTruckID[truckID] = enabled
        if enabled {
            onlinePaymentsEnabledByTruckID[truckID] = true
        }
        persistPaymentSettings()
    }

    func setPayoutAccountStatus(_ status: OwnerPayoutAccountStatus, for truckID: UUID) {
        payoutAccountStatusByTruckID[truckID] = status
        persistPaymentSettings()
    }

    func serviceFee(for subtotal: Double) -> Double {
        guard subtotal > 0 else { return 0 }
        return min(max(subtotal * 0.06, 0.50), 2.99)
    }

    func totalAtCheckout(for subtotal: Double) -> Double {
        subtotal + serviceFee(for: subtotal)
    }

    func setAutoAcceptEnabled(_ enabled: Bool, forOwner ownerUserID: String) {
        for truck in trucksOwned(by: ownerUserID) {
            setAutoAcceptEnabled(enabled, for: truck.id)
        }
    }

    func isAutoAcceptEnabledForAllOwnedTrucks(ownerUserID: String) -> Bool {
        let trucks = trucksOwned(by: ownerUserID)
        guard !trucks.isEmpty else { return false }
        return trucks.allSatisfy { isAutoAcceptEnabled(for: $0.id) }
    }

    func transitionOrder(_ orderID: UUID, to status: OrderStatus) {
        guard let index = orders.firstIndex(where: { $0.id == orderID }) else { return }
        let previous = orders[index].status
        orders[index].status = status
        persistOrders()
        AppTelemetry.track(
            event: "order_status_transition",
            metadata: [
                "order_id": orderID.uuidString,
                "from": previous.rawValue,
                "to": status.rawValue
            ]
        )
        Task {
            await backendService.update(orderID: orderID, status: status)
            await refreshFromRemote()
        }
    }

    func analytics(for ownerUserID: String) -> OwnerAnalytics {
        let ownedTrucks = trucksOwned(by: ownerUserID)
        let ownedTruckIDs = Set(ownedTrucks.map(\.id))
        let ownerOrders = orders
            .filter { order in
                guard let truckID = order.truckID else { return false }
                return ownedTruckIDs.contains(truckID) && order.status != .cancelled
            }

        let topItems = Dictionary(grouping: ownerOrders.flatMap(\.items), by: { $0.menuItem.name })
            .map { key, grouped in
                (name: key, quantity: grouped.reduce(0) { $0 + $1.quantity })
            }
            .sorted { $0.quantity > $1.quantity }
            .prefix(3)
            .map { $0 }

        let hourCounts = Dictionary(grouping: ownerOrders, by: { Calendar.current.component(.hour, from: $0.orderDate) })
            .mapValues(\.count)
        let peakHour = hourCounts.max(by: { $0.value < $1.value })?.key
        let busiestTimeLabel = peakHour.map { formatHour($0) } ?? "No data yet"

        let ordersByCustomer = Dictionary(grouping: ownerOrders, by: \.customerName)
        let repeatCustomers = ordersByCustomer.values.filter { $0.count > 1 }.count
        let repeatCustomerPercentage = ordersByCustomer.isEmpty ? 0 : (Double(repeatCustomers) / Double(ordersByCustomer.count)) * 100
        let averageOrderValue = ownerOrders.isEmpty ? 0 : ownerOrders.reduce(0) { $0 + $1.chargedTotalAmount } / Double(ownerOrders.count)

        return OwnerAnalytics(
            busiestTimeLabel: busiestTimeLabel,
            topItems: topItems,
            repeatCustomerPercentage: repeatCustomerPercentage,
            averageOrderValue: averageOrderValue
        )
    }

    func payoutSummary(for ownerUserID: String) -> OwnerPayoutSummary {
        let ownedTruckIDs = Set(trucksOwned(by: ownerUserID).map(\.id))
        let ownerOrders = orders
            .filter { order in
                guard let truckID = order.truckID else { return false }
                return ownedTruckIDs.contains(truckID) && order.status != .cancelled
            }

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now

        let todaysOrders = ownerOrders.filter { $0.orderDate >= todayStart }
        let weeklyOrders = ownerOrders.filter { $0.orderDate >= weekAgo }
        let unsettledOrders = ownerOrders.filter { $0.status != .completed }

        let todaysEarnings = todaysOrders.reduce(0) { $0 + $1.subtotalAmount }
        let weeklyEarnings = weeklyOrders.reduce(0) { $0 + $1.subtotalAmount }
        let pendingPayouts = unsettledOrders.reduce(0) { $0 + $1.subtotalAmount }

        let gross = ownerOrders.reduce(0) { $0 + $1.subtotalAmount }
        let platformFees = ownerOrders.reduce(0) { $0 + $1.serviceFeeAmount }
        let processingFees = ownerOrders.reduce(0) { $0 + (0.029 * $1.chargedTotalAmount) + 0.30 }
        let subscriptionFees = Double(trucksOwned(by: ownerUserID).filter { $0.plan == .pro }.count) * 19.99
        let netEarnings = max(0, gross - processingFees)

        return OwnerPayoutSummary(
            todaysEarnings: todaysEarnings,
            weeklyEarnings: weeklyEarnings,
            pendingPayouts: pendingPayouts,
            nextPayoutDateLabel: Self.dateFormatter.string(from: nextPayoutDate(from: now)),
            platformFees: platformFees,
            processingFees: processingFees,
            subscriptionFees: subscriptionFees,
            netEarnings: netEarnings
        )
    }

    private func loadData() {
        let data = backendService.loadSeedData()
        campuses = data.campuses
        foodTrucks = data.foodTrucks
        menuItems = data.menuItems
        orders = data.orders
        reviews = data.reviews
    }

    private func persistOrders() {
        guard !backendService.isRemoteEnabled else { return }
        let stored = orders.map(StoredOrder.init)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: Self.persistedOrdersKey)
    }

    private func loadPersistedOrders() {
        guard !backendService.isRemoteEnabled else { return }
        guard
            let data = UserDefaults.standard.data(forKey: Self.persistedOrdersKey),
            let stored = try? JSONDecoder().decode([StoredOrder].self, from: data)
        else {
            return
        }
        orders = stored.map(\.order)
    }

    private func persistAutoAcceptSettings() {
        let compact = autoAcceptByTruckID.map { ($0.key.uuidString, $0.value) }
        let map = Dictionary(uniqueKeysWithValues: compact)
        UserDefaults.standard.set(map, forKey: Self.persistedAutoAcceptKey)
    }

    private func loadPersistedAutoAcceptSettings() {
        guard let map = UserDefaults.standard.dictionary(forKey: Self.persistedAutoAcceptKey) else { return }
        var rebuilt: [UUID: Bool] = [:]
        for (key, value) in map {
            guard let uuid = UUID(uuidString: key), let boolValue = value as? Bool else { continue }
            rebuilt[uuid] = boolValue
        }
        autoAcceptByTruckID = rebuilt
    }

    private func persistPaymentSettings() {
        let stored = StoredTruckPaymentSettings(
            onlinePaymentsEnabledByTruckID: Dictionary(
                uniqueKeysWithValues: onlinePaymentsEnabledByTruckID.map { ($0.key.uuidString, $0.value) }
            ),
            applePayEnabledByTruckID: Dictionary(
                uniqueKeysWithValues: applePayEnabledByTruckID.map { ($0.key.uuidString, $0.value) }
            ),
            payoutAccountStatusByTruckID: Dictionary(
                uniqueKeysWithValues: payoutAccountStatusByTruckID.map { ($0.key.uuidString, $0.value) }
            )
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: Self.persistedPaymentSettingsKey)
    }

    private func loadPersistedPaymentSettings() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.persistedPaymentSettingsKey),
            let stored = try? JSONDecoder().decode(StoredTruckPaymentSettings.self, from: data)
        else {
            return
        }

        onlinePaymentsEnabledByTruckID = stored.onlinePaymentsEnabledByTruckID.reduce(into: [:]) { result, entry in
            guard let uuid = UUID(uuidString: entry.key) else { return }
            result[uuid] = entry.value
        }
        applePayEnabledByTruckID = stored.applePayEnabledByTruckID.reduce(into: [:]) { result, entry in
            guard let uuid = UUID(uuidString: entry.key) else { return }
            result[uuid] = entry.value
        }
        payoutAccountStatusByTruckID = stored.payoutAccountStatusByTruckID.reduce(into: [:]) { result, entry in
            guard let uuid = UUID(uuidString: entry.key) else { return }
            result[uuid] = entry.value
        }
    }

    private func formatHour(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return Self.hourFormatter.string(from: date)
    }

    private func nextPayoutDate(from date: Date) -> Date {
        var components = DateComponents()
        components.weekday = 6
        components.hour = 9
        components.minute = 0
        components.second = 0
        return Calendar.current.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .nextTimePreservingSmallerComponents
        ) ?? date
    }

    private func refreshBroadcastLocation(for index: Int) {
        guard foodTrucks.indices.contains(index) else { return }
        let truck = foodTrucks[index]
        let jitterLat = Double.random(in: -0.0006 ... 0.0006)
        let jitterLon = Double.random(in: -0.0006 ... 0.0006)
        foodTrucks[index].liveLatitude = truck.latitude + jitterLat
        foodTrucks[index].liveLongitude = truck.longitude + jitterLon
    }

    private func startGPSUpdates() {
        #if !DEBUG
            return
        #endif
        gpsUpdateTask?.cancel()
        gpsUpdateTask = Task { [weak self] in
            while !(Task.isCancelled) {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self else { return }
                guard !(Task.isCancelled) else { return }
                self.updateLiveTruckLocations()
            }
        }
    }

    private func startRemoteSync() {
        remoteSyncTask?.cancel()
        remoteSyncTask = Task { [weak self] in
            while !(Task.isCancelled) {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard let self else { return }
                guard !(Task.isCancelled) else { return }
                await self.refreshFromRemote()
            }
        }
    }

    private func updateLiveTruckLocations() {
        #if !DEBUG
            return
        #endif
        for index in foodTrucks.indices {
            let truck = foodTrucks[index]
            guard truck.isOpen, truck.hasLiveTracking, !truck.closedEarly else { continue }
            let jitterLat = Double.random(in: -0.0002 ... 0.0002)
            let jitterLon = Double.random(in: -0.0002 ... 0.0002)
            let nextLat = truck.liveLatitude + jitterLat
            let nextLon = truck.liveLongitude + jitterLon
            foodTrucks[index].liveLatitude = nextLat.clamped(
                min: truck.latitude - 0.0035,
                max: truck.latitude + 0.0035
            )
            foodTrucks[index].liveLongitude = nextLon.clamped(
                min: truck.longitude - 0.0035,
                max: truck.longitude + 0.0035
            )
        }
    }

    private func refreshFromRemote() async {
        guard backendService.isRemoteEnabled else { return }
        remoteSyncPhase = .syncing
        guard let data = await backendService.syncData() else {
            remoteSyncPhase = .failed("Couldn’t refresh. Check your connection and try again.")
            return
        }
        campuses = data.campuses
        foodTrucks = data.foodTrucks
        menuItems = data.menuItems
        orders = data.orders
        reviews = data.reviews
        remoteSyncPhase = .idle
    }

    func refreshStudentCatalog() async {
        await refreshFromRemote()
    }

    func presentStudentCheckout(for truck: FoodTruck) {
        studentCheckoutTruckID = truck.id
    }

    private func persistTruckChange(truckID: UUID) {
        guard backendService.isRemoteEnabled,
              let truck = foodTrucks.first(where: { $0.id == truckID })
        else { return }

        Task {
            await backendService.update(truck: truck)
            await refreshFromRemote()
        }
    }

    private func persistMenuItemChange(itemID: UUID) {
        guard backendService.isRemoteEnabled,
              let item = menuItems.first(where: { $0.id == itemID })
        else { return }

        let truckName = foodTrucks.first(where: { $0.id == item.truckId })?.name ?? ""
        Task {
            await backendService.update(menuItem: item, truckName: truckName)
            await refreshFromRemote()
        }
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}

private struct StoredOrder: Codable {
    struct StoredOrderItem: Codable {
        let id: UUID
        let menuItemID: UUID
        let menuItemName: String
        let menuItemDescription: String
        let menuItemPrice: Double
        let menuItemCategory: String
        let menuItemTruckID: UUID
        let menuItemImageURL: String?
        let quantity: Int
        let customization: String?

        nonisolated init(item: OrderItem) {
            id = item.id
            menuItemID = item.menuItem.id
            menuItemName = item.menuItem.name
            menuItemDescription = item.menuItem.description
            menuItemPrice = item.menuItem.price
            menuItemCategory = item.menuItem.category
            menuItemTruckID = item.menuItem.truckId
            menuItemImageURL = item.menuItem.imageURL
            quantity = item.quantity
            customization = item.customization
        }

        var orderItem: OrderItem {
            let menuItem = MenuItem(
                id: menuItemID,
                name: menuItemName,
                description: menuItemDescription,
                price: menuItemPrice,
                category: menuItemCategory,
                isAvailable: true,
                truckId: menuItemTruckID,
                imageURL: menuItemImageURL,
                tags: []
            )
            return OrderItem(id: id, menuItem: menuItem, quantity: quantity, customization: customization)
        }
    }

    let id: UUID
    let truckID: String?
    let customerUserID: String?
    let truckName: String
    let campusName: String
    let items: [StoredOrderItem]
    let subtotalAmount: Double?
    let serviceFeeAmount: Double?
    let chargedTotalAmount: Double?
    let status: OrderStatus
    let paymentMethod: PaymentMethod
    let paymentStatus: PaymentStatus?
    let paymentTransactionID: String?
    let pickupTiming: PickupTiming
    let orderDate: Date
    let estimatedDelivery: Date?
    let customerName: String
    let specialInstructions: String?

    init(order: Order) {
        id = order.id
        truckID = order.truckID?.uuidString
        customerUserID = order.customerUserID
        truckName = order.truckName
        campusName = order.campusName
        items = order.items.map(StoredOrderItem.init)
        subtotalAmount = order.subtotalAmount
        serviceFeeAmount = order.serviceFeeAmount
        chargedTotalAmount = order.chargedTotalAmount
        status = order.status
        paymentMethod = order.paymentMethod
        paymentStatus = order.paymentStatus
        paymentTransactionID = order.paymentTransactionID
        pickupTiming = order.pickupTiming
        orderDate = order.orderDate
        estimatedDelivery = order.estimatedDelivery
        customerName = order.customerName
        specialInstructions = order.specialInstructions
    }

    var order: Order {
        Order(
            id: id,
            truckID: truckID.flatMap(UUID.init(uuidString:)),
            customerUserID: customerUserID,
            truckName: truckName,
            campusName: campusName,
            items: items.map(\.orderItem),
            subtotalAmount: subtotalAmount ?? chargedTotalAmount ?? 0,
            serviceFeeAmount: serviceFeeAmount ?? 0,
            chargedTotalAmount: chargedTotalAmount ?? subtotalAmount ?? 0,
            status: status,
            paymentMethod: paymentMethod,
            paymentStatus: paymentStatus,
            paymentTransactionID: paymentTransactionID,
            pickupTiming: pickupTiming,
            orderDate: orderDate,
            estimatedDelivery: estimatedDelivery,
            customerName: customerName,
            specialInstructions: specialInstructions
        )
    }
}

enum OwnerPayoutAccountStatus: String, CaseIterable, Identifiable, Codable {
    case notStarted = "Not Connected"
    case pending = "Setup Pending"
    case connected = "Connected"

    var id: String { rawValue }
}

private struct StoredTruckPaymentSettings: Codable {
    let onlinePaymentsEnabledByTruckID: [String: Bool]
    let applePayEnabledByTruckID: [String: Bool]
    let payoutAccountStatusByTruckID: [String: OwnerPayoutAccountStatus]
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Double {
    func clamped(min lowerBound: Double, max upperBound: Double) -> Double {
        Swift.min(Swift.max(self, lowerBound), upperBound)
    }
}
