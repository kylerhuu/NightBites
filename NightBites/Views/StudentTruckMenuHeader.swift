import SwiftUI

struct StudentTruckMenuHeader: View {
    let truck: FoodTruck

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: truck.studentOperationalState.systemImage)
                    .font(.title3)
                    .foregroundStyle(truck.studentOperationalState.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(truck.studentOperationalState.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(NightBitesTheme.label)
                    Text("Until \(truck.activeHours)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(NightBitesTheme.labelSecondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(truck.formattedWait)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(NightBitesTheme.saffron)
                    Text("wait")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(NightBitesTheme.labelSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(NightBitesTheme.mutedCard.opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(NightBitesTheme.border, lineWidth: 1)
                )
            }

            HStack(spacing: 10) {
                Label(truck.campusName, systemImage: "building.columns.fill")
                Label(truck.formattedDistance, systemImage: "location.fill")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(NightBitesTheme.labelSecondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NightBitesTheme.card.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(NightBitesTheme.border, lineWidth: 1)
        )
    }
}
