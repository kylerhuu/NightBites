import SwiftUI

struct CheckoutView: View {
    @Bindable var viewModel: FoodTruckViewModel
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(PaymentManager.self) private var paymentManager
    @Environment(\.dismiss) private var dismiss

    let truck: FoodTruck
    var onOrderPlaced: ((Order) -> Void)?

    @State private var selectedPaymentMethod: PaymentMethod = .cash
    @State private var customerName = ""
    @State private var customizationNotes = ""
    @State private var pickupTiming: PickupTiming = .asap
    @State private var scheduledPickupDate = Date().addingTimeInterval(30 * 60)
    @State private var paymentStatusMessage: String?

    init(truck: FoodTruck, viewModel: FoodTruckViewModel, onOrderPlaced: ((Order) -> Void)? = nil) {
        self.truck = truck
        self.viewModel = viewModel
        self.onOrderPlaced = onOrderPlaced
    }

    private var resolvedTruck: FoodTruck {
        viewModel.foodTrucks.first(where: { $0.id == truck.id }) ?? truck
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Checkout")
                    .font(.largeTitle.weight(.heavy))

                CheckoutPickupMapSnippet(truck: resolvedTruck)

                pickupSection

                paymentSection

                cartSection

                instructionsSection

                placeOrderBlock
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 28)
        }
        .nightBitesScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") { dismiss() }
            }
        }
        .onAppear {
            if !availablePaymentMethods.contains(selectedPaymentMethod) {
                selectedPaymentMethod = availablePaymentMethods.first ?? .cash
            }
            if customerName.isEmpty {
                customerName = customerDisplayName
            }
            AppTelemetry.track(event: "checkout_opened", metadata: ["truck_id": truck.id.uuidString])
        }
    }

    private var pickupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Pickup time")
            Picker("When", selection: $pickupTiming) {
                ForEach(PickupTiming.allCases, id: \.rawValue) { timing in
                    Text(timing.rawValue).tag(timing)
                }
            }
            .pickerStyle(.segmented)
            .tint(NightBitesTheme.ember)

            if pickupTiming == .scheduled {
                DatePicker(
                    "Pickup time",
                    selection: $scheduledPickupDate,
                    in: Date().addingTimeInterval(5 * 60)...Date().addingTimeInterval(4 * 60 * 60),
                    displayedComponents: [.hourAndMinute]
                )
                .tint(NightBitesTheme.ember)
            }

            TextField("Pickup name", text: $customerName)
                .textFieldStyle(.plain)
                .padding(14)
                .background(NightBitesTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NightBitesTheme.border, lineWidth: 1)
                )

            Text("Est. prep window: \(resolvedTruck.formattedWait)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(NightBitesTheme.card.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(NightBitesTheme.border, lineWidth: 1)
        )
    }

    private var paymentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Payment")
            VStack(spacing: 8) {
                ForEach(availablePaymentMethods) { method in
                    Button {
                        selectedPaymentMethod = method
                    } label: {
                        HStack {
                            Text(method.rawValue)
                                .font(.body.weight(.semibold))
                            Spacer()
                            if selectedPaymentMethod == method {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(NightBitesTheme.ember)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selectedPaymentMethod == method ? NightBitesTheme.ember.opacity(0.14) : NightBitesTheme.mutedCard.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selectedPaymentMethod == method ? NightBitesTheme.ember.opacity(0.45) : NightBitesTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if !AppReleaseConfig.enableDigitalPayments {
                Text("Digital payments are off in this build — pay at pickup.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !viewModel.acceptsOnlinePayments(for: resolvedTruck.id) {
                Text("This truck only accepts pay at pickup right now.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if viewModel.payoutAccountStatus(for: resolvedTruck.id) != .connected {
                Text("Truck payout onboarding is not finished yet, so in-app payments stay hidden.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if selectedPaymentMethod == .card || selectedPaymentMethod == .applePay {
                Text("Card and Apple Pay are scaffolded here, but still need Stripe SDK + backend intent confirmation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("Service fee: 6% per order, capped at $2.99.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(NightBitesTheme.card.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(NightBitesTheme.border, lineWidth: 1)
        )
    }

    private var cartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Your bag")
            if viewModel.cartLines.isEmpty {
                Text("Your bag is empty.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.cartLines) { line in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.menuItem.name)
                                .font(.subheadline.weight(.bold))
                            if let detail = line.orderCustomizationText(), !detail.isEmpty {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(String(format: "$%.2f ea", line.unitPrice()))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(NightBitesTheme.saffron)
                        }
                        Spacer()
                        HStack(spacing: 10) {
                            Button {
                                viewModel.decrementCartLine(id: line.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title2)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .buttonStyle(.plain)
                            .tint(NightBitesTheme.ember)

                            Text("\(line.quantity)")
                                .font(.headline.monospacedDigit())
                                .frame(minWidth: 22)

                            Button {
                                viewModel.incrementCartLine(id: line.id)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .buttonStyle(.plain)
                            .tint(NightBitesTheme.ember)
                        }
                    }
                    .padding(.vertical, 6)
                    if line.id != viewModel.cartLines.last?.id {
                        Divider().opacity(0.35)
                    }
                }

                HStack {
                    Text("Subtotal")
                        .font(.headline.weight(.bold))
                    Spacer()
                    Text(String(format: "$%.2f", viewModel.activeCartSubtotal))
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(NightBitesTheme.saffron)
                }
                .padding(.top, 6)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Service fee")
                            .font(.subheadline.weight(.semibold))
                        Text("Supports NightBites operations and secure ordering")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "$%.2f", serviceFee))
                        .font(.subheadline.weight(.bold))
                }

                HStack {
                    Text("Total")
                        .font(.headline.weight(.bold))
                    Spacer()
                    Text(String(format: "$%.2f", checkoutTotal))
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(NightBitesTheme.label)
                }
            }
        }
        .padding(16)
        .background(NightBitesTheme.card.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(NightBitesTheme.border, lineWidth: 1)
        )
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Notes for the truck")
            TextField("Allergies, sauces, etc.", text: $customizationNotes, axis: .vertical)
                .lineLimit(2 ... 5)
                .textFieldStyle(.plain)
                .padding(14)
                .background(NightBitesTheme.mutedCard.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickNoteChip("No onions")
                    quickNoteChip("Extra spicy")
                    quickNoteChip("Sauce on side")
                }
            }
        }
        .padding(16)
        .background(NightBitesTheme.card.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(NightBitesTheme.border, lineWidth: 1)
        )
    }

    private var placeOrderBlock: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    paymentStatusMessage = nil
                    let orderReference = UUID().uuidString
                    let checkoutSession = await paymentManager.prepareCheckout(
                        method: selectedPaymentMethod,
                        subtotalAmount: viewModel.activeCartSubtotal,
                        serviceFeeAmount: serviceFee,
                        amount: checkoutTotal,
                        orderReference: orderReference,
                        truckID: resolvedTruck.id
                    )
                    guard checkoutSession != nil else {
                        paymentStatusMessage = paymentManager.lastErrorMessage ?? "Could not start checkout."
                        return
                    }

                    let confirmed = await paymentManager.confirmPreparedCheckout()
                    guard confirmed else {
                        paymentStatusMessage = paymentManager.lastErrorMessage ?? "Payment confirmation failed."
                        return
                    }
                    if let order = viewModel.placeOrder(
                        paymentMethod: selectedPaymentMethod,
                        paymentStatus: selectedPaymentMethod == .cash ? .payOnPickup : .authorized,
                        paymentTransactionID: paymentManager.lastTransactionID,
                        customerUserID: authViewModel.currentUser?.id,
                        customerName: resolvedCustomerName,
                        customization: customizationNotes,
                        pickupTiming: pickupTiming,
                        scheduledPickupDate: pickupTiming == .scheduled ? scheduledPickupDate : nil
                    ) {
                        customizationNotes = ""
                        onOrderPlaced?(order)
                        dismiss()
                    }
                }
            } label: {
                Text("Place order")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background {
                        if canPlaceOrder {
                            NightBitesTheme.heroGradient
                        } else {
                            Color.gray.opacity(0.35)
                        }
                    }
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(paymentManager.isProcessing || !canPlaceOrder)
            .nightBitesPrimaryGlow(radius: canPlaceOrder ? 16 : 0, y: canPlaceOrder ? 8 : 0)

            if paymentManager.isProcessing {
                ProgressView(selectedPaymentMethod == .cash ? "Preparing order…" : "Preparing payment…")
                    .tint(NightBitesTheme.ember)
            }

            if !canPlaceOrder {
                Text(checkoutDisabledMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let paymentStatusMessage {
                Text(paymentStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.red.opacity(0.9))
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.heavy))
            .foregroundStyle(.secondary)
    }

    private func quickNoteChip(_ text: String) -> some View {
        Button(text) {
            if customizationNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                customizationNotes = text
            } else if !customizationNotes.localizedCaseInsensitiveContains(text) {
                customizationNotes += ", \(text)"
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(NightBitesTheme.mutedCard)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(NightBitesTheme.border, lineWidth: 1))
        .buttonStyle(.plain)
    }

    private var customerDisplayName: String {
        let emailPrefix = authViewModel.currentUser?.email.components(separatedBy: "@").first
        let trimmed = emailPrefix?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Guest" : trimmed
    }

    private var resolvedCustomerName: String {
        let trimmed = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? customerDisplayName : trimmed
    }

    private var availablePaymentMethods: [PaymentMethod] {
        viewModel.availablePaymentMethods(for: resolvedTruck.id)
    }

    private var serviceFee: Double {
        viewModel.serviceFee(for: viewModel.activeCartSubtotal)
    }

    private var checkoutTotal: Double {
        viewModel.totalAtCheckout(for: viewModel.activeCartSubtotal)
    }

    private var canPlaceOrder: Bool {
        !viewModel.cartLines.isEmpty && canUseCurrentSessionForOrdering && resolvedTruck.supportsOrdering
    }

    private var canUseCurrentSessionForOrdering: Bool {
        guard let currentUser = authViewModel.currentUser else { return false }
        return !viewModel.isRemoteEnabled || !currentUser.isGuest
    }

    private var checkoutDisabledMessage: String {
        if viewModel.cartLines.isEmpty {
            return "Add at least one item to continue."
        }
        if selectedPaymentMethod != .cash && !viewModel.canAcceptDigitalPayments(for: resolvedTruck.id) {
            return "This truck is not set up for in-app payments yet."
        }
        if !resolvedTruck.supportsOrdering {
            return "This truck isn’t taking orders right now."
        }
        return "Sign in with a real account to place an order in this build."
    }
}

extension View {
    /// Attach to a `NavigationStack` root (Explore tab or map sheet) so checkout pushes reliably.
    func nightBitesStudentCheckoutDestination(viewModel: FoodTruckViewModel) -> some View {
        navigationDestination(
            isPresented: Binding(
                get: { viewModel.studentCheckoutTruckID != nil },
                set: { if !$0 { viewModel.studentCheckoutTruckID = nil } }
            )
        ) {
            if let id = viewModel.studentCheckoutTruckID,
               let truck = viewModel.foodTrucks.first(where: { $0.id == id }) {
                CheckoutView(truck: truck, viewModel: viewModel, onOrderPlaced: { order in
                    viewModel.lastStudentOrderReadyForTracking = order
                    viewModel.studentCheckoutTruckID = nil
                })
            } else {
                ProgressView()
                    .tint(NightBitesTheme.ember)
            }
        }
    }
}
