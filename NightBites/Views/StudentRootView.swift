import SwiftUI

struct StudentRootView: View {
    @Environment(FoodTruckViewModel.self) private var viewModel

    var body: some View {
        TabView {
            FoodTruckListView()
                .tabItem {
                    Label("Explore", systemImage: "fork.knife.circle")
                }

            CampusMapView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }

            OrdersView()
                .tabItem {
                    Label("Orders", systemImage: "list.bullet.clipboard")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
                }
        }
        .tint(NightBitesTheme.ember)
        .sheet(isPresented: Binding(
            get: { viewModel.studentOrderPendingTracking != nil },
            set: { if !$0 { viewModel.studentOrderPendingTracking = nil } }
        )) {
            if let order = viewModel.studentOrderPendingTracking {
                NavigationStack {
                    OrderTrackingView(orderID: order.id)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    viewModel.studentOrderPendingTracking = nil
                                }
                            }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}
