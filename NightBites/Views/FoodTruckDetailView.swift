import SwiftUI

struct FoodTruckDetailView: View {
    @Environment(FoodTruckViewModel.self) private var viewModel
    @Environment(AuthViewModel.self) private var authViewModel

    @State private var selectedCategory: String?
    @State private var detailMenuItem: MenuItem?
    @State private var orderToTrack: Order?
    @State private var reorderUnavailable = false
    @State private var showReviewsSheet = false
    @State private var reviewRating = 5
    @State private var reviewText = ""
    @State private var reviewMediaURL = ""

    let truck: FoodTruck

    private var menuItems: [MenuItem] {
        viewModel.getStudentMenuItems(for: truck.id)
    }

    private var categories: [String] {
        Array(Set(menuItems.map(\.category))).sorted()
    }

    private var visibleItems: [MenuItem] {
        guard let selectedCategory else { return menuItems }
        return menuItems.filter { $0.category == selectedCategory }
    }

    private var currentCustomerUserID: String? {
        authViewModel.currentUser?.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                cover

                StudentTruckMenuHeader(truck: truck)

                syncBanner

                if !truck.studentCanBrowseMenu {
                    ContentUnavailableView(
                        "Menu unavailable",
                        systemImage: "lock.fill",
                        description: Text("This truck isn’t set up for browsing yet.")
                    )
                } else if menuItems.isEmpty {
                    if case .syncing = viewModel.remoteSyncPhase {
                        ProgressView("Loading menu…")
                            .tint(NightBitesTheme.ember)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        ContentUnavailableView(
                            "Menu is empty",
                            systemImage: "tray",
                            description: Text("Check back after the truck adds items.")
                        )
                    }
                } else {
                    if truck.studentCanPlaceOrders,
                       let currentCustomerUserID,
                       viewModel.lastOrder(for: truck.id, customerUserID: currentCustomerUserID) != nil {
                        reorderButton(currentCustomerUserID)
                    }

                    if !truck.studentCanPlaceOrders, truck.studentCanBrowseMenu {
                        orderingBlockedCallout
                    }

                    StudentMenuCategoryChipsRow(categories: categories, selectedCategory: $selectedCategory)

                    LazyVStack(spacing: 12) {
                        ForEach(visibleItems) { item in
                            StudentMenuItemCard(
                                item: item,
                                inCartQuantity: viewModel.quantityInCart(for: item),
                                canOrder: truck.studentCanPlaceOrders,
                                onTap: { detailMenuItem = item },
                                onQuickAdd: {
                                    guard truck.studentCanPlaceOrders, item.isAvailable else { return }
                                    if item.hasModifiers {
                                        detailMenuItem = item
                                    } else {
                                        viewModel.quickAddToCart(item: item)
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 110)
        }
        .nightBitesScreenBackground()
        .navigationTitle(truck.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showReviewsSheet = true
                } label: {
                    Image(systemName: "star.bubble.fill")
                }
                .tint(NightBitesTheme.ember)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if truck.studentCanPlaceOrders,
               viewModel.cartTruckID == truck.id,
               viewModel.activeCartItemCount > 0 {
                StudentStickyCartBar(
                    itemCount: viewModel.activeCartItemCount,
                    subtotal: viewModel.activeCartSubtotal
                ) {
                    viewModel.presentStudentCheckout(for: truck)
                }
                .background(
                    LinearGradient(
                        colors: [NightBitesTheme.ink.opacity(0), NightBitesTheme.ink.opacity(0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                )
            }
        }
        .sheet(item: $detailMenuItem) { item in
            MenuItemDetailSheet(
                menuItem: item,
                truckSupportsOrdering: truck.studentCanPlaceOrders,
                onAdded: {}
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showReviewsSheet) {
            reviewsSheet
                .presentationDetents([.large])
        }
        .sheet(item: $orderToTrack) { order in
            NavigationStack {
                OrderTrackingView(orderID: order.id)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { orderToTrack = nil }
                        }
                    }
            }
        }
        .alert("Couldn’t Reorder", isPresented: $reorderUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Some items from your previous order are no longer available.")
        }
        .refreshable {
            await viewModel.refreshStudentCatalog()
        }
        .onChange(of: viewModel.lastStudentOrderReadyForTracking) { _, new in
            guard let new, new.truckID == truck.id else { return }
            orderToTrack = new
            viewModel.lastStudentOrderReadyForTracking = nil
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let urlString = truck.coverImageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                case .failure:
                    NightBitesTheme.mutedCard
                case .empty:
                    ZStack {
                        NightBitesTheme.mutedCard
                        ProgressView().tint(NightBitesTheme.ember)
                    }
                @unknown default:
                    NightBitesTheme.mutedCard
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(NightBitesTheme.border, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var syncBanner: some View {
        switch viewModel.remoteSyncPhase {
        case .idle:
            EmptyView()
        case .syncing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(NightBitesTheme.ember)
                Text("Syncing latest menu…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.red.opacity(0.9))
                Button("Try again") {
                    Task { await viewModel.refreshStudentCatalog() }
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.borderedProminent)
                .tint(NightBitesTheme.ember)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func reorderButton(_ userID: String) -> some View {
        Button {
            if viewModel.reorderLastOrder(for: truck.id, customerUserID: userID) {
                viewModel.presentStudentCheckout(for: truck)
            } else {
                reorderUnavailable = true
            }
        } label: {
            Label("Reorder last", systemImage: "arrow.clockwise.circle.fill")
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(NightBitesTheme.mutedCard)
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(NightBitesTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var orderingBlockedCallout: some View {
        Label(orderingDisabledReason, systemImage: "pause.circle.fill")
            .font(.subheadline.weight(.semibold))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NightBitesTheme.warning.opacity(0.12))
            .foregroundStyle(NightBitesTheme.warning)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var orderingDisabledReason: String {
        if !truck.canUseOrderAheadFeature {
            return "Ordering isn’t enabled for this truck yet."
        }
        if !truck.isOpen {
            return truck.closedEarly ? "This truck closed early tonight." : "This truck is closed right now."
        }
        if truck.ordersPaused {
            return "New orders are paused — check back soon."
        }
        return "Ordering isn’t available right now."
    }

    private var reviewsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ReviewComposerView(
                        rating: $reviewRating,
                        text: $reviewText,
                        mediaURL: $reviewMediaURL,
                        onSubmit: submitReview
                    )

                    let reviews = viewModel.reviews(for: truck.id)
                    if reviews.isEmpty {
                        Text("No reviews yet. Be the first.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(reviews) { review in
                            ReviewCardView(review: review)
                        }
                    }
                }
                .padding()
            }
            .nightBitesScreenBackground()
            .navigationTitle("Reviews")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showReviewsSheet = false }
                }
            }
        }
    }

    private func submitReview() {
        let displayName = authViewModel.currentUser?.email.components(separatedBy: "@").first ?? "Student"
        viewModel.addReview(
            truckID: truck.id,
            userName: displayName,
            rating: reviewRating,
            text: reviewText,
            mediaURL: reviewMediaURL
        )
        reviewText = ""
        reviewMediaURL = ""
        reviewRating = 5
    }
}

private struct ReviewComposerView: View {
    @Binding var rating: Int
    @Binding var text: String
    @Binding var mediaURL: String
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper("Rating: \(rating)/5", value: $rating, in: 1 ... 5)
            TextField("Write your review", text: $text, axis: .vertical)
                .lineLimit(3 ... 6)
                .textFieldStyle(.roundedBorder)
            TextField("Photo/video URL (optional)", text: $mediaURL)
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
            Button("Post Review", action: onSubmit)
                .buttonStyle(.borderedProminent)
                .tint(NightBitesTheme.ember)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .nightBitesCard()
    }
}

private struct ReviewCardView: View {
    let review: Review

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(review.userDisplayName)
                    .fontWeight(.semibold)
                Spacer()
                Text(String(repeating: "★", count: review.rating))
                    .foregroundColor(NightBitesTheme.saffron)
            }

            Text(review.text)

            if let mediaURL = review.mediaURL, let url = URL(string: mediaURL) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    NightBitesTheme.mutedCard
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .nightBitesCard()
    }
}
