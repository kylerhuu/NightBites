import SwiftUI

struct StudentMenuItemCard: View {
    let item: MenuItem
    let inCartQuantity: Int
    let canOrder: Bool
    let onTap: () -> Void
    let onQuickAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            menuImage
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(NightBitesTheme.border, lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture { onTap() }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(item.isAvailable ? NightBitesTheme.label : NightBitesTheme.labelSecondary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Text(item.formattedPrice)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(NightBitesTheme.saffron)
                }
                .contentShape(Rectangle())
                .onTapGesture { onTap() }

                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(NightBitesTheme.labelSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }

                if !item.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(item.tags, id: \.self) { tag in
                                Text(tag.uppercased())
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(NightBitesTheme.ember.opacity(0.16))
                                    .foregroundStyle(NightBitesTheme.ember)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }
                }

                HStack {
                    if !item.isAvailable {
                        Text("UNAVAILABLE")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.18))
                            .foregroundStyle(Color.red.opacity(0.95))
                            .clipShape(Capsule())
                    } else if canOrder {
                        Spacer(minLength: 0)
                        quickAddControl
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(NightBitesTheme.card.opacity(item.isAvailable ? 0.95 : 0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    item.isAvailable ? NightBitesTheme.border : Color.white.opacity(0.04),
                    lineWidth: 1
                )
        )
        .opacity(item.isAvailable ? 1 : 0.72)
    }

    @ViewBuilder
    private var menuImage: some View {
        if let imageURL = item.imageURL, let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    ZStack {
                        NightBitesTheme.mutedCard
                        ProgressView().tint(NightBitesTheme.ember)
                    }
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            NightBitesTheme.mutedCard
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var quickAddControl: some View {
        HStack(spacing: 10) {
            if inCartQuantity > 0 {
                Text("\(inCartQuantity) in bag")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NightBitesTheme.saffron)
            }
            if item.hasModifiers {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
            } else {
                Button {
                    onQuickAdd()
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(NightBitesTheme.ember))
                        .nightBitesPrimaryGlow(radius: 10, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
