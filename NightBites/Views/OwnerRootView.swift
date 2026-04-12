import SwiftUI

struct OwnerRootView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(FoodTruckViewModel.self) private var viewModel

    var body: some View {
        TabView {
            OwnerOrdersQueueView()
                .tabItem {
                    Label("Orders", systemImage: "list.bullet.clipboard")
                }
                .badge(ordersBadgeLabel)

            OwnerTruckManagementView()
                .tabItem {
                    Label("My Truck", systemImage: "truck.box")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
                }
        }
        .tint(NightBitesTheme.ember)
        .preferredColorScheme(.dark)
    }

    private var ownerID: String? {
        authViewModel.currentUser?.id
    }

    private var activeOwnerOrders: [Order] {
        guard let ownerID else { return [] }
        return viewModel.ordersQueue(for: ownerID)
            .filter { $0.status != .completed && $0.status != .cancelled }
    }

    private var ordersBadgeCount: Int {
        activeOwnerOrders.filter { $0.status == .pending || $0.status == .ready }.count
    }

    private var ordersBadgeLabel: String? {
        ordersBadgeCount == 0 ? nil : String(ordersBadgeCount)
    }
}
