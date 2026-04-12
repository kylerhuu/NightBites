import SwiftUI
import CoreLocation

struct ProfileView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(FoodTruckViewModel.self) private var viewModel
    @Environment(LocationAccessManager.self) private var locationAccessManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Account")
                            .font(.headline)
                        Text(authViewModel.currentUser?.email ?? "-")
                        Text(authViewModel.currentUser?.role.rawValue ?? "-")
                            .foregroundColor(.secondary)
                    }
                    .nightBitesCard()

                    if authViewModel.currentUser?.role == .owner {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Owner Tools")
                                .font(.headline)

                            NavigationLink {
                                OwnerDashboardView()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Dashboard")
                                            .fontWeight(.semibold)
                                        Text("Analytics, payouts, and business overview")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                            }

                            if let truck = ownerTrucks.first {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Primary Truck")
                                        .font(.subheadline.weight(.semibold))
                                    Text(truck.name)
                                    Text("\(truck.cuisineType) • \(truck.campusName)")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 6)
                            } else {
                                Text("No truck created yet.")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .nightBitesCard()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Location")
                            .font(.headline)
                        Text("Permission: \(locationAccessManager.statusDescription)")
                            .foregroundColor(.secondary)

                        if locationAccessManager.isAuthorized {
                            if let coordinate = locationAccessManager.latestCoordinate {
                                Text(String(format: "Current: %.4f, %.4f", coordinate.latitude, coordinate.longitude))
                                    .font(.footnote)
                            }
                            Button("Refresh Location") {
                                locationAccessManager.refreshLocation()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Enable Location Access") {
                                locationAccessManager.requestPermission()
                            }
                            .buttonStyle(.borderedProminent)

                            if locationAccessManager.authorizationStatus == .denied {
                                Button("Open iOS Settings") {
                                    locationAccessManager.openSystemSettings()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .nightBitesCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Support & Legal")
                            .font(.headline)
                        if let supportURL = AppReleaseConfig.supportEmailURL {
                            Link("Contact Support", destination: supportURL)
                        } else {
                            Text("Contact Support: not configured")
                                .foregroundColor(.red)
                        }
                        if let privacyURL = AppReleaseConfig.privacyPolicyURL {
                            Link("Privacy Policy", destination: privacyURL)
                        } else {
                            Text("Privacy Policy URL missing")
                                .foregroundColor(.red)
                        }
                        if let termsURL = AppReleaseConfig.termsURL {
                            Link("Terms of Service", destination: termsURL)
                        } else {
                            Text("Terms URL missing")
                                .foregroundColor(.red)
                        }
                    }
                    .nightBitesCard()

                    Button("Sign Out", role: .destructive) {
                        authViewModel.signOut()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .nightBitesScreenBackground()
            .navigationTitle("Profile")
        }
    }

    private var ownerTrucks: [FoodTruck] {
        guard let userID = authViewModel.currentUser?.id else { return [] }
        return viewModel.trucksOwned(by: userID)
    }
}
