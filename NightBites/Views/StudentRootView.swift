import SwiftUI

struct StudentRootView: View {
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
    }
}
