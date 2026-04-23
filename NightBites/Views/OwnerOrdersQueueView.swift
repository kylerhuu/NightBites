import AudioToolbox
import SwiftUI
import UIKit
import UserNotifications

struct OwnerOrdersQueueView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(FoodTruckViewModel.self) private var viewModel

    @State private var seenOrderIDs: Set<UUID> = []
    @State private var expandedOrderIDs: Set<UUID> = []
    @State private var latestAlertOrder: Order?
    @State private var showAlertBanner = false

    @State private var enableLoudInAppAlerts = true
    @State private var enableLocalNotifications = true
    @State private var keepScreenAwakeForOrders = true
    @State private var enableSMSBackup = false
    @State private var orderRefreshPoll: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let primaryTruck {
                        truckHeader(primaryTruck)
                    }

                    if !queueOrders.isEmpty {
                        queueOverview
                    }

                    if queueOrders.isEmpty {
                        ContentUnavailableView(
                            "No active orders",
                            systemImage: "tray",
                            description: Text("New orders will show up here as a simple running list.")
                        )
                    } else {
                        ForEach(queueOrders) { order in
                            orderRow(order)
                        }
                    }
                }
                .padding()
            }
            .nightBitesScreenBackground()
            .navigationTitle("Orders")
            .overlay(alignment: .top) {
                if showAlertBanner, let order = latestAlertOrder {
                    newOrderAlertBanner(order: order)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .refreshable {
                await viewModel.refreshStudentCatalog()
            }
            .onAppear {
                loadOperatorPreferences()
                requestNotificationPermissionIfNeeded()
                seedSeenOrdersIfNeeded()
                applyIdleTimerPolicy()
                startOrderListPolling()
            }
            .onChange(of: queueOrders.map(\.id)) {
                processQueueChanges()
                applyIdleTimerPolicy()
            }
            .onChange(of: keepScreenAwakeForOrders) {
                saveOperatorPreferences()
                applyIdleTimerPolicy()
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                orderRefreshPoll?.cancel()
                orderRefreshPoll = nil
            }
        }
    }

    private func startOrderListPolling() {
        guard viewModel.isRemoteEnabled else { return }
        orderRefreshPoll?.cancel()
        orderRefreshPoll = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                if Task.isCancelled { break }
                await viewModel.refreshStudentCatalog()
            }
        }
    }

    private var ownerID: String? {
        authViewModel.currentUser?.id
    }

    private var primaryTruck: FoodTruck? {
        guard let ownerID else { return nil }
        return viewModel.trucksOwned(by: ownerID).first
    }

    private var queueOrders: [Order] {
        guard let ownerID else { return [] }
        return viewModel.ordersQueue(for: ownerID)
            .filter { $0.status != .completed && $0.status != .cancelled }
            .sorted { pickupDate(for: $0) < pickupDate(for: $1) }
    }

    private func truckHeader(_ truck: FoodTruck) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(truck.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(NightBitesTheme.label)
                    Text("New orders: the big button on each card. To edit the menu, open the My Truck tab.")
                        .font(.subheadline)
                        .foregroundStyle(NightBitesTheme.labelSecondary)
                }

                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(NightBitesTheme.ink.opacity(0.45))
                        .frame(width: 52, height: 52)
                    Image(systemName: "list.bullet.clipboard.fill")
                        .font(.title2)
                        .foregroundColor(NightBitesTheme.saffron)
                }
            }

            HStack(spacing: 8) {
                statusChip(truck.liveStatusLabel, tint: NightBitesTheme.ember)
                Text("\(queueOrders.count) active")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NightBitesTheme.labelSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightBitesCard()
    }

    private var queueOverview: some View {
        HStack(spacing: 10) {
            overviewTile(title: "New", value: queueOrders.filter { $0.status == .pending }.count, tint: .gray)
            overviewTile(
                title: "Cooking",
                value: queueOrders.filter { $0.status == .accepted || $0.status == .preparing }.count,
                tint: .orange
            )
            overviewTile(title: "Ready", value: queueOrders.filter { $0.status == .ready }.count, tint: .green)
        }
    }

    private func overviewTile(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(NightBitesTheme.labelSecondary)
            Text("\(value)")
                .font(.title3.bold())
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            LinearGradient(
                colors: [NightBitesTheme.card, tint.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }

    private func orderRow(_ order: Order) -> some View {
        let isExpanded = expandedOrderIDs.contains(order.id)
        let tint = timingTint(for: order)
        let step = primaryStep(for: order)

        return VStack(alignment: .leading, spacing: 12) {
            Button {
                toggleExpansion(for: order.id)
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(order.customerName)
                                .font(.headline)
                                .foregroundStyle(NightBitesTheme.label)
                            priorityDot(for: order)
                        }
                        Text("Pickup \(order.formattedPickupTime)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NightBitesTheme.label)
                        Text("Ordered \(order.formattedDate)")
                            .font(.caption)
                            .foregroundStyle(NightBitesTheme.labelSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NightBitesTheme.labelSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let step {
                Button {
                    viewModel.transitionOrder(order.id, to: step.status)
                } label: {
                    Text(step.title)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(step.tint)
            } else {
                HStack {
                    statusChip(QueueStatusLabel.chip(order.status), tint: statusColor(for: order.status))
                    Spacer()
                    Text(order.formattedTotal)
                        .font(.subheadline.weight(.semibold))
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if step != nil {
                        HStack {
                            statusChip(QueueStatusLabel.chip(order.status), tint: statusColor(for: order.status))
                            Spacer()
                            Text(order.formattedTotal)
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(order.items) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("x\(item.quantity) \(item.menuItem.name)")
                                    .font(.subheadline)
                                    .foregroundStyle(NightBitesTheme.label)
                                if let customization = item.customization, !customization.isEmpty {
                                    Text(customization)
                                        .font(.caption)
                                        .foregroundStyle(NightBitesTheme.labelSecondary)
                                }
                            }
                        }
                    }

                    if let instructions = order.specialInstructions, !instructions.isEmpty {
                        Text("Notes: \(instructions)")
                            .font(.caption)
                            .foregroundStyle(NightBitesTheme.labelSecondary)
                    }
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [NightBitesTheme.card, NightBitesTheme.mutedCard.opacity(0.9), tint],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderTint(for: order).opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.035), radius: 10, y: 4)
    }

    /// One obvious action per order in sequence.
    private func primaryStep(for order: Order) -> (title: String, status: OrderStatus, tint: Color)? {
        switch order.status {
        case .pending:
            return ("Accept order", .accepted, .blue)
        case .accepted:
            return ("Start cooking", .preparing, .orange)
        case .preparing:
            return ("Ready for pickup", .ready, .green)
        case .ready:
            return ("Picked up", .completed, .gray)
        case .completed, .cancelled:
            return nil
        }
    }

    private enum QueueStatusLabel {
        static func chip(_ status: OrderStatus) -> String {
            switch status {
            case .pending: return "New"
            case .accepted, .preparing: return "Cooking"
            case .ready: return "At window"
            case .completed: return "Done"
            case .cancelled: return "Cancelled"
            }
        }
    }

    private func toggleExpansion(for orderID: UUID) {
        if expandedOrderIDs.contains(orderID) {
            expandedOrderIDs.remove(orderID)
        } else {
            expandedOrderIDs.insert(orderID)
        }
    }

    private func pickupDate(for order: Order) -> Date {
        order.estimatedDelivery ?? order.orderDate
    }

    private func timingTint(for order: Order) -> Color {
        let interval = pickupDate(for: order).timeIntervalSinceNow
        if interval <= 300, order.status != .ready {
            return Color.red.opacity(0.12)
        }
        if interval <= 900, order.status != .ready {
            return Color.orange.opacity(0.12)
        }
        return Color(.secondarySystemBackground)
    }

    private func borderTint(for order: Order) -> Color {
        let interval = pickupDate(for: order).timeIntervalSinceNow
        if interval <= 300, order.status != .ready {
            return .red
        }
        if interval <= 900, order.status != .ready {
            return .orange
        }
        return statusColor(for: order.status)
    }

    private func priorityDot(for order: Order) -> some View {
        Circle()
            .fill(borderTint(for: order))
            .frame(width: 8, height: 8)
    }

    private func statusChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.15))
            .foregroundColor(tint)
            .clipShape(Capsule())
    }

    private func newOrderAlertBanner(order: Order) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("New Order \(order.shortOrderNumber)")
                .font(.headline)
            Text("\(order.customerName) • Pickup \(order.formattedPickupTime)")
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            LinearGradient(
                colors: [Color.red.opacity(0.96), Color.orange.opacity(0.94)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.red.opacity(0.25), radius: 10, y: 4)
    }

    private func processQueueChanges() {
        let activeIDs = Set(queueOrders.map(\.id))
        guard !seenOrderIDs.isEmpty else {
            seenOrderIDs = activeIDs
            persistSeenOrders()
            return
        }

        let newOrders = queueOrders.filter { !seenOrderIDs.contains($0.id) && ($0.status == .pending || $0.status == .accepted) }
        seenOrderIDs.formUnion(activeIDs)
        persistSeenOrders()

        guard !newOrders.isEmpty else { return }
        for order in newOrders {
            triggerNewOrderAlert(order)
        }
    }

    private func triggerNewOrderAlert(_ order: Order) {
        latestAlertOrder = order
        withAnimation(.spring(duration: 0.25)) {
            showAlertBanner = true
        }

        if enableLoudInAppAlerts {
            AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
            AudioServicesPlaySystemSound(1005)
            AudioServicesPlaySystemSound(1315)
        }
        if enableLocalNotifications {
            postLocalNotification(for: order)
        }
        if enableSMSBackup {
            postSMSBackupWebhook(for: order)
        }

        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    showAlertBanner = false
                }
            }
        }
    }

    private func postLocalNotification(for order: Order) {
        let content = UNMutableNotificationContent()
        content.title = "New order #\(order.shortOrderNumber)"
        content.body = "\(order.customerName) pickup \(order.formattedPickupTime)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "owner-order-\(order.id.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func postSMSBackupWebhook(for order: Order) {
        guard let webhookURL = AppReleaseConfig.smsBackupWebhookURL else { return }

        struct Payload: Encodable {
            let order_id: String
            let order_number: String
            let truck_name: String
            let customer_name: String
            let pickup_time: String
            let total: String
        }

        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(
            Payload(
                order_id: order.id.uuidString,
                order_number: order.shortOrderNumber,
                truck_name: order.truckName,
                customer_name: order.customerName,
                pickup_time: order.formattedPickupTime,
                total: order.formattedTotal
            )
        )
        Task {
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        guard enableLocalNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func applyIdleTimerPolicy() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwakeForOrders && !queueOrders.isEmpty
    }

    private func seedSeenOrdersIfNeeded() {
        let saved = loadSeenOrdersFromStorage()
        if saved.isEmpty {
            seenOrderIDs = Set(queueOrders.map(\.id))
            persistSeenOrders()
        } else {
            seenOrderIDs = saved
        }
    }

    private func preferenceKey(_ suffix: String) -> String {
        "owner.queue.\(ownerID ?? "unknown").\(suffix)"
    }

    private func seenOrdersKey() -> String {
        preferenceKey("seenOrderIDs")
    }

    private func loadOperatorPreferences() {
        let defaults = UserDefaults.standard
        enableLoudInAppAlerts = defaults.object(forKey: preferenceKey("loudAlerts")) as? Bool ?? true
        enableLocalNotifications = defaults.object(forKey: preferenceKey("localNotifications")) as? Bool ?? true
        keepScreenAwakeForOrders = defaults.object(forKey: preferenceKey("keepAwake")) as? Bool ?? true
        enableSMSBackup = defaults.object(forKey: preferenceKey("smsBackup")) as? Bool ?? false
    }

    private func saveOperatorPreferences() {
        let defaults = UserDefaults.standard
        defaults.set(enableLoudInAppAlerts, forKey: preferenceKey("loudAlerts"))
        defaults.set(enableLocalNotifications, forKey: preferenceKey("localNotifications"))
        defaults.set(keepScreenAwakeForOrders, forKey: preferenceKey("keepAwake"))
        defaults.set(enableSMSBackup, forKey: preferenceKey("smsBackup"))
    }

    private func persistSeenOrders() {
        let ids = seenOrderIDs.map(\.uuidString)
        UserDefaults.standard.set(ids, forKey: seenOrdersKey())
    }

    private func loadSeenOrdersFromStorage() -> Set<UUID> {
        let values = UserDefaults.standard.stringArray(forKey: seenOrdersKey()) ?? []
        return Set(values.compactMap(UUID.init(uuidString:)))
    }

    private func statusColor(for status: OrderStatus) -> Color {
        switch status {
        case .pending:
            return .gray
        case .accepted:
            return .blue
        case .preparing:
            return .orange
        case .ready:
            return .green
        case .completed:
            return .gray
        case .cancelled:
            return .red
        }
    }
}
