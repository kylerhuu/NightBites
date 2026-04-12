import Foundation

struct TruckApplication: Identifiable {
    let id = UUID()
    let truckName: String
    let ownerName: String
    let cuisineType: String
    let campusName: String
    let contactEmail: String
    let selectedPlan: TruckPlan
    let createdAt: Date
    let status: ApplicationStatus
}

enum ApplicationStatus: String {
    case submitted = "Submitted"
    case approved = "Approved"
    case rejected = "Rejected"
}
