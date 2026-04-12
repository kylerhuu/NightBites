import MapKit
import SwiftUI

struct CheckoutPickupMapSnippet: View {
    let truck: FoodTruck

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: truck.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pickup location")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.secondary)

            Map(initialPosition: .region(region), interactionModes: []) {
                Annotation(truck.name, coordinate: truck.coordinate) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title)
                        .foregroundStyle(NightBitesTheme.ember)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(NightBitesTheme.border, lineWidth: 1)
            )

            Text("\(truck.name) • \(truck.campusName)")
                .font(.footnote.weight(.semibold))
        }
    }
}
