import SwiftUI

struct StudentStickyCartBar: View {
    let itemCount: Int
    let subtotal: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(NightBitesTheme.ink.opacity(0.55))
                        .frame(width: 44, height: 44)
                    Image(systemName: "bag.fill")
                        .foregroundStyle(NightBitesTheme.saffron)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Your order")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(itemCount) items")
                        .font(.headline.weight(.bold))
                }

                Spacer()

                Text(String(format: "$%.2f", subtotal))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.white)

                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(NightBitesTheme.heroGradient)
            )
            .nightBitesPrimaryGlow(radius: 16, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial.opacity(0.001))
    }
}
