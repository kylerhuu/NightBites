import SwiftUI

struct OrderTrackingView: View {
    @Environment(FoodTruckViewModel.self) private var viewModel
    let orderID: UUID

    private var order: Order? {
        viewModel.orders.first { $0.id == orderID }
    }

    var body: some View {
        Group {
            if let order {
                content(order: order)
            } else {
                ContentUnavailableView(
                    "Order not found",
                    systemImage: "tray",
                    description: Text("This order may have been removed from your device.")
                )
            }
        }
        .nightBitesScreenBackground()
        .navigationTitle("Order status")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.refreshStudentCatalog()
        }
    }

    private func content(order: Order) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(order.truckName)
                        .font(.title2.weight(.heavy))
                    Text("#\(order.shortOrderNumber) • \(order.campusName)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                timeline(for: order.status)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Pickup")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.secondary)
                    Text(order.formattedPickupTime)
                        .font(.title3.weight(.bold))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NightBitesTheme.card.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(NightBitesTheme.border, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Items")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.secondary)
                    ForEach(order.items) { line in
                        HStack(alignment: .top) {
                            Text("×\(line.quantity)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(NightBitesTheme.saffron)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.menuItem.name)
                                    .font(.subheadline.weight(.semibold))
                                if let c = line.customization, !c.isEmpty {
                                    Text(c)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(String(format: "$%.2f", line.subtotal))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .padding(16)
                .nightBitesCard()

                if let helpURL = orderHelpLink(order: order) {
                    Link(destination: helpURL) {
                        Label("Problem with this order? Email us", systemImage: "envelope.open")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(NightBitesTheme.ember)
                }
            }
            .padding(18)
        }
    }

    private func orderHelpLink(order: Order) -> URL? {
        let local = AppReleaseConfig.supportEmail
        let subject = "NightBites order #\(order.shortOrderNumber) — \(order.truckName)"
        let enc = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:\(local)?subject=\(enc)")
    }

    private func timeline(for status: OrderStatus) -> some View {
        let steps: [(title: String, subtitle: String, done: Bool)] = [
            ("Sent", "We notified the truck", isDone(status, min: 0)),
            ("Accepted", "They’re working on it", isDone(status, min: 1)),
            ("Ready", "Head to the window", isDone(status, min: 2))
        ]

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(step.done ? NightBitesTheme.ember : NightBitesTheme.mutedCard)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .stroke(step.done ? NightBitesTheme.saffron : NightBitesTheme.border, lineWidth: 2)
                            )
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(step.done ? NightBitesTheme.ember.opacity(0.35) : NightBitesTheme.border)
                                .frame(width: 2, height: 36)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title)
                            .font(.headline.weight(.bold))
                        Text(step.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, index < steps.count - 1 ? 12 : 0)
                }
            }
        }
        .padding(16)
        .background(NightBitesTheme.card.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(NightBitesTheme.border, lineWidth: 1)
        )
    }

    private func isDone(_ status: OrderStatus, min: Int) -> Bool {
        let rank: Int
        switch status {
        case .pending: rank = 0
        case .accepted, .preparing: rank = 1
        case .ready, .completed: rank = 2
        case .cancelled: rank = 0
        }
        return rank >= min
    }
}
