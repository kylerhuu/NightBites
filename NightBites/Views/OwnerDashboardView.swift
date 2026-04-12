import SwiftUI

struct OwnerDashboardView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(FoodTruckViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Payouts & Analytics")
                        .font(.largeTitle.weight(.bold))
                    Text("Business health lives here so orders and truck setup can stay operational.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .nightBitesHeroCard()

                let payouts = payoutSummary
                let analytics = ownerAnalytics

                VStack(alignment: .leading, spacing: 10) {
                    Text("Payouts")
                        .font(.headline)

                    HStack(spacing: 12) {
                        metricCard(title: "Today", value: currency(payouts.todaysEarnings), color: NightBitesTheme.success)
                        metricCard(title: "Weekly", value: currency(payouts.weeklyEarnings), color: NightBitesTheme.info)
                    }

                    HStack(spacing: 12) {
                        metricCard(title: "Pending", value: currency(payouts.pendingPayouts), color: NightBitesTheme.saffron)
                        metricCard(title: "Net Earnings", value: currency(payouts.netEarnings), color: NightBitesTheme.ember)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Next payout: \(payouts.nextPayoutDateLabel)")
                            .font(.subheadline)
                        Text("Fees: Platform \(currency(payouts.platformFees)) + Processing \(currency(payouts.processingFees))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .nightBitesCard()
                }
                .nightBitesCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Actionable Analytics")
                        .font(.headline)

                    metricCard(title: "Busiest Time", value: analytics.busiestTimeLabel, color: NightBitesTheme.info)
                    metricCard(title: "Repeat Customers", value: String(format: "%.1f%%", analytics.repeatCustomerPercentage), color: NightBitesTheme.ember)
                    metricCard(title: "Average Order Value", value: currency(analytics.averageOrderValue), color: NightBitesTheme.saffron)

                    Text("Top-Selling Items")
                        .font(.subheadline)

                    if analytics.topItems.isEmpty {
                        Text("No order history yet.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(analytics.topItems.enumerated()), id: \.offset) { entry in
                            HStack {
                                Text(entry.element.name)
                                Spacer()
                                Text("x\(entry.element.quantity)")
                                    .foregroundColor(.secondary)
                            }
                            Divider()
                        }
                    }
                }
                .nightBitesCard()
            }
            .padding()
        }
        .nightBitesScreenBackground()
        .navigationTitle("Dashboard")
    }

    private var ownerAnalytics: OwnerAnalytics {
        guard let userID = authViewModel.currentUser?.id else {
            return OwnerAnalytics(
                busiestTimeLabel: "No data yet",
                topItems: [],
                repeatCustomerPercentage: 0,
                averageOrderValue: 0
            )
        }

        return viewModel.analytics(for: userID)
    }

    private var payoutSummary: OwnerPayoutSummary {
        guard let userID = authViewModel.currentUser?.id else {
            return OwnerPayoutSummary(
                todaysEarnings: 0,
                weeklyEarnings: 0,
                pendingPayouts: 0,
                nextPayoutDateLabel: "-",
                platformFees: 0,
                processingFees: 0,
                netEarnings: 0
            )
        }
        return viewModel.payoutSummary(for: userID)
    }

    private func metricCard(title: String, value: String, color: Color) -> some View {
        NightBitesMetricTile(title: title, value: value, tint: color)
    }

    private func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}
