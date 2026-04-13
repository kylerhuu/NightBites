//
//  FoodTruckListView.swift
//  NightBites
//
//  Created by Kyler Hu on 2/24/26.
//

import SwiftUI

struct FoodTruckListView: View {
    @Environment(FoodTruckViewModel.self) private var viewModel

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        NavigationStack {
            VStack(spacing: 12) {
                CampusSelectorView()

                Picker("Cuisine", selection: $bindableViewModel.selectedCuisine) {
                    ForEach(bindableViewModel.availableCuisines, id: \.self) { cuisine in
                        Text(cuisine).tag(cuisine)
                    }
                }
                .pickerStyle(.segmented)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(bindableViewModel.filteredFoodTrucks) { truck in
                            NavigationLink {
                                FoodTruckDetailView(viewModel: viewModel, truck: truck)
                            } label: {
                                FoodTruckRowView(truck: truck)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.visible)
            }
            .padding(.horizontal)
            .nightBitesScreenBackground()
            .navigationTitle("Campus Trucks")
            .searchable(text: $bindableViewModel.searchText, prompt: "Search truck or cuisine")
        }
    }
}

struct CampusSelectorView: View {
    @Environment(FoodTruckViewModel.self) private var viewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.campuses) { campus in
                    Button {
                        viewModel.selectedCampusID = campus.id
                    } label: {
                        Text(campus.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(viewModel.selectedCampusID == campus.id ? NightBitesTheme.ember : NightBitesTheme.mutedCard)
                            .foregroundColor(
                                viewModel.selectedCampusID == campus.id ? .white : .primary
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct FoodTruckRowView: View {
    let truck: FoodTruck

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let imageURL = truck.coverImageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    NightBitesTheme.ember.opacity(0.15)
                }
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(truck.name)
                        .font(.headline)

                    Text("\(truck.cuisineType) • \(truck.campusName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .foregroundColor(NightBitesTheme.saffron)
                            .font(.caption)

                        Text(String(format: "%.1f", truck.rating))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    Text(truck.formattedDistance)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Label(truck.formattedWait, systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(NightBitesTheme.info)

                if truck.hasLiveTracking {
                    Label("Location", systemImage: "location.fill")
                        .font(.caption)
                        .foregroundColor(NightBitesTheme.success)
                }

                Text(truck.liveStatusLabel)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((truck.ordersPaused ? NightBitesTheme.ember : NightBitesTheme.success).opacity(0.14))
                    .clipShape(Capsule())

                Spacer()

                Text(truck.supportsOrdering ? "ORDER AHEAD" : "MENU ONLY")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(truck.supportsOrdering ? NightBitesTheme.success.opacity(0.15) : NightBitesTheme.mutedCard)
                    .clipShape(Capsule())
            }

            Text("Hours: \(truck.activeHours)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .nightBitesCard()
        .padding(.vertical, 4)
    }
}
