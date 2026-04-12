import SwiftUI

struct TruckOnboardingView: View {
    @Environment(FoodTruckViewModel.self) private var viewModel

    @State private var truckName = ""
    @State private var ownerName = ""
    @State private var cuisineType = ""
    @State private var contactEmail = ""
    @State private var selectedCampusID: UUID?
    @State private var selectedPlan: TruckPlan = .free
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Business Info") {
                    TextField("Truck name", text: $truckName)
                    TextField("Owner name", text: $ownerName)
                    TextField("Cuisine", text: $cuisineType)
                    TextField("Contact email", text: $contactEmail)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Picker("Campus", selection: $selectedCampusID) {
                        ForEach(viewModel.campuses) { campus in
                            Text(campus.name).tag(Optional(campus.id))
                        }
                    }
                }

                Section("Choose a Plan") {
                    Picker("Plan", selection: $selectedPlan) {
                        ForEach(TruckPlan.allCases) { plan in
                            Text(plan.rawValue).tag(plan)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(selectedPlan == .free ? "Free Plan" : "Pro Plan")
                            .font(.headline)

                        Text("Price: \(selectedPlan.monthlyPriceText)")
                        Text(selectedPlan == .free ? "Included: map listing, menu, and hours" : "Included: map listing, live GPS, order ahead, analytics, and promotions")
                        Text(selectedPlan == .free ? "Ordering: included for MVP" : "Ordering: included")
                        if selectedPlan == .pro {
                            Text("Customers pay a 6% service fee capped at $2.99 per order.")
                        }
                    }
                    .font(.subheadline)
                }

                Section {
                    Button("Submit Application") {
                        submit()
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("Truck Signup")
            .onAppear {
                if selectedCampusID == nil {
                    selectedCampusID = viewModel.campuses.first?.id
                }
            }
            .alert("Application Submitted", isPresented: $didSubmit) {
                Button("Done", role: .cancel) {}
            } message: {
                Text("We received your \(selectedPlan.rawValue) plan request and will follow up by email.")
            }
        }
    }

    private var canSubmit: Bool {
        !truckName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !ownerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !cuisineType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !contactEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedCampusID != nil
    }

    private func submit() {
        guard
            let campusID = selectedCampusID,
            let campus = viewModel.campuses.first(where: { $0.id == campusID })
        else {
            return
        }

        viewModel.submitTruckApplication(
            truckName: truckName,
            ownerName: ownerName,
            cuisineType: cuisineType,
            campusName: campus.name,
            contactEmail: contactEmail,
            selectedPlan: selectedPlan
        )

        truckName = ""
        ownerName = ""
        cuisineType = ""
        contactEmail = ""
        selectedPlan = .free
        didSubmit = true
    }
}
