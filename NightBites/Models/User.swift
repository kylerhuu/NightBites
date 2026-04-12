import Foundation

enum UserRole: String, CaseIterable, Identifiable, Codable {
    case student = "Student"
    case owner = "Truck Owner"

    var id: String { rawValue }
}

struct AppUser: Identifiable, Codable {
    let id: String
    let email: String
    let role: UserRole

    var isGuest: Bool {
        id.hasPrefix("guest-student-")
    }
}
