import Foundation

struct Review: Identifiable {
    let id: UUID
    let truckId: UUID
    let userDisplayName: String
    let rating: Int
    let text: String
    let mediaURL: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        truckId: UUID,
        userDisplayName: String,
        rating: Int,
        text: String,
        mediaURL: String?,
        createdAt: Date
    ) {
        self.id = id
        self.truckId = truckId
        self.userDisplayName = userDisplayName
        self.rating = rating
        self.text = text
        self.mediaURL = mediaURL
        self.createdAt = createdAt
    }
}
