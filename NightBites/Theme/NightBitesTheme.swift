import SwiftUI

enum NightBitesTheme {
    static let ember = Color(red: 1.00, green: 0.54, blue: 0.16)
    static let saffron = Color(red: 1.00, green: 0.78, blue: 0.27)
    static let cream = Color(red: 0.96, green: 0.92, blue: 0.84)
    static let ink = Color(red: 0.05, green: 0.06, blue: 0.08)
    static let midnight = Color(red: 0.08, green: 0.09, blue: 0.12)
    /// Surfaces sit clearly above the page (higher luminance than `midnight`).
    static let card = Color(red: 0.17, green: 0.18, blue: 0.23)
    static let mutedCard = Color(red: 0.22, green: 0.23, blue: 0.30)
    static let success = Color(red: 0.32, green: 0.88, blue: 0.54)
    static let info = Color(red: 0.42, green: 0.72, blue: 1.00)
    static let warning = Color(red: 1.00, green: 0.67, blue: 0.22)
    static let border = Color.white.opacity(0.16)

    /// Page wash: keep depth without muddying foreground cards (ember is very subtle).
    static let pageGradient = LinearGradient(
        colors: [ink, midnight, ember.opacity(0.07)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradient = LinearGradient(
        colors: [Color(red: 0.98, green: 0.50, blue: 0.14), Color(red: 0.69, green: 0.23, blue: 0.08)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let surfaceGradient = LinearGradient(
        colors: [card, mutedCard],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Explicit labels for custom dark panels when not relying on environment alone.
    static let label = Color(red: 0.96, green: 0.96, blue: 0.98)
    static let labelSecondary = Color(red: 0.72, green: 0.74, blue: 0.80)
}

struct NightBitesScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(NightBitesTheme.pageGradient.ignoresSafeArea())
    }
}

struct NightBitesCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(NightBitesTheme.surfaceGradient)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(NightBitesTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 12, y: 6)
    }
}

struct NightBitesHeroCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(NightBitesTheme.heroGradient)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: NightBitesTheme.ember.opacity(0.22), radius: 16, y: 8)
    }
}

extension View {
    func nightBitesScreenBackground() -> some View {
        modifier(NightBitesScreenBackground())
    }

    func nightBitesCard() -> some View {
        modifier(NightBitesCard())
    }

    func nightBitesHeroCard() -> some View {
        modifier(NightBitesHeroCard())
    }

    /// Ember glow for primary CTAs and active controls (use sparingly).
    func nightBitesPrimaryGlow(radius: CGFloat = 14, y: CGFloat = 6) -> some View {
        shadow(color: NightBitesTheme.ember.opacity(0.42), radius: radius, y: y)
    }
}

struct NightBitesChip: View {
    let text: String
    let tint: Color
    var foreground: Color? = nil

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14))
            .foregroundColor(foreground ?? tint)
            .clipShape(Capsule())
    }
}

struct NightBitesMetricTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            LinearGradient(
                colors: [NightBitesTheme.card, tint.opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        )
    }
}
