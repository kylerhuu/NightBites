import SwiftUI

struct StudentStickyCartBar: View {
    let itemCount: Int
    let subtotal: Double
    /// When false (e.g. truck paused), the bar still shows the bag but checkout tap is disabled.
    var isActionable: Bool = true
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
                        .foregroundStyle(NightBitesTheme.label.opacity(0.85))
                    Text("\(itemCount) items")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(NightBitesTheme.label)
                }

                Spacer()

                Text(String(format: "$%.2f", subtotal))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(NightBitesTheme.label)

                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(NightBitesTheme.label.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .background {
                Group {
                    if isActionable {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(NightBitesTheme.heroGradient)
                    } else {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(NightBitesTheme.mutedCard)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(NightBitesTheme.border, lineWidth: 1)
            )
            .nightBitesPrimaryGlow(radius: isActionable ? 16 : 0, y: isActionable ? 8 : 0)
        }
        .buttonStyle(.plain)
        .disabled(!isActionable)
        .opacity(isActionable ? 1 : 0.9)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}
