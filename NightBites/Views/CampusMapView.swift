import MapKit
import SwiftUI

struct CampusMapView: View {
    @Environment(FoodTruckViewModel.self) private var viewModel
    @Environment(LocationAccessManager.self) private var locationAccessManager
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedTruck: FoodTruck?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                CampusSelectorView()
                    .padding(.horizontal)

                Map(position: $cameraPosition) {
                    UserAnnotation()
                    ForEach(viewModel.filteredFoodTrucks) { truck in
                        Annotation(truck.name, coordinate: truck.coordinate) {
                            Button {
                                selectedTruck = truck
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: truck.supportsOrdering ? "fork.knife.circle.fill" : "mappin.circle.fill")
                                        .font(.title)
                                        .foregroundColor(truck.supportsOrdering ? NightBitesTheme.ember : .gray)

                                    Text(truck.name)
                                        .font(.caption2)
                                        .padding(4)
                                        .background(NightBitesTheme.card)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
                .padding(.bottom)
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapUserLocationButton()
                }
            }
            .nightBitesScreenBackground()
            .navigationTitle("Campus Map")
            .onAppear {
                centerMapOnSelectedCampus()
                locationAccessManager.refreshLocation()
            }
            .onChange(of: viewModel.selectedCampusID) {
                centerMapOnSelectedCampus()
            }
            .sheet(item: $selectedTruck) { truck in
                NavigationStack {
                    FoodTruckDetailView(viewModel: viewModel, truck: truck)
                }
                .nightBitesStudentCheckoutDestination(viewModel: viewModel)
            }
        }
    }

    private func centerMapOnSelectedCampus() {
        guard let campus = viewModel.selectedCampus else { return }

        cameraPosition = .region(
            MKCoordinateRegion(
                center: campus.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
            )
        )
    }
}
