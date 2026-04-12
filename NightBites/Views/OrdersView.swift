import SwiftUI

struct OrdersView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(FoodTruckViewModel.self) private var viewModel

    var body: some View {
        NavigationStack {
            Group {
                if studentOrders.isEmpty {
                    ContentUnavailableView(
                        "No orders yet",
                        systemImage: "bag",
                        description: Text("Your pickup orders will appear here.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(studentOrders) { order in
                                NavigationLink {
                                    OrderTrackingView(orderID: order.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text("#\(order.shortOrderNumber) • \(order.truckName)")
                                                .font(.headline)

                                            Spacer()

                                            NightBitesChip(
                                                text: order.status.rawValue,
                                                tint: statusBackground(for: order.status),
                                                foreground: statusTint(for: order.status)
                                            )
                                        }

                                        Text("Pickup: \(order.formattedPickupTime) • \(order.campusName)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)

                                        VStack(alignment: .leading, spacing: 4) {
                                            ForEach(order.items) { item in
                                                Text("x\(item.quantity) \(item.menuItem.name)")
                                                    .font(.caption)
                                                Text("Modifiers: \(item.customization ?? "None")")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }

                                        HStack {
                                            Text(order.paymentMethod.rawValue)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("• \(order.paymentStatus.rawValue)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(order.formattedTotal)
                                                .font(.headline)
                                        }
                                    }
                                    .nightBitesCard()
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .nightBitesScreenBackground()
            .navigationTitle("Orders")
        }
    }

    private func statusBackground(for status: OrderStatus) -> Color {
        switch status {
        case .pending:
            return Color.gray.opacity(0.14)
        case .accepted:
            return Color.indigo.opacity(0.14)
        case .preparing:
            return Color.blue.opacity(0.14)
        case .ready:
            return NightBitesTheme.saffron.opacity(0.2)
        case .completed:
            return NightBitesTheme.success.opacity(0.14)
        case .cancelled:
            return Color.red.opacity(0.14)
        }
    }

    private func statusTint(for status: OrderStatus) -> Color {
        switch status {
        case .pending:
            return .gray
        case .accepted:
            return .indigo
        case .preparing:
            return .blue
        case .ready:
            return NightBitesTheme.ember
        case .completed:
            return NightBitesTheme.success
        case .cancelled:
            return .red
        }
    }

    private var studentOrders: [Order] {
        guard let userID = authViewModel.currentUser?.id else { return [] }
        return viewModel.orders(for: userID)
    }
}
