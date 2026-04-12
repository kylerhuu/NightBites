import CoreLocation
import Foundation

enum TruckPlan: String, CaseIterable, Identifiable {
    case free = "Free"
    case pro = "Pro"

    var id: String { rawValue }

    var monthlyPriceText: String {
        switch self {
        case .free:
            return "$0/mo"
        case .pro:
            return "$19.99/mo"
        }
    }

    var orderingEnabled: Bool {
        true
    }
}

struct Campus: Identifiable, Hashable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double

    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct FoodTruck: Identifiable {
    let id: UUID
    let ownerUserID: String?
    let name: String
    let cuisineType: String
    let campusName: String
    let distance: Double
    let rating: Double
    let ratingCount: Int
    let estimatedWait: Int
    var prepMinutesOverride: Int? = nil
    var prepLoadMultiplier: Double = 1.0
    var isOpen: Bool
    var ordersPaused: Bool
    var closedEarly: Bool
    var activeHours: String
    let imageName: String
    let coverImageURL: String?
    let profileImageURL: String?
    let galleryImageURLs: [String]
    let latitude: Double
    let longitude: Double
    var liveLatitude: Double
    var liveLongitude: Double
    var plan: TruckPlan
    var hasLiveTracking: Bool
    var proSubscriptionActive: Bool

    init(
        id: UUID = UUID(),
        ownerUserID: String?,
        name: String,
        cuisineType: String,
        campusName: String,
        distance: Double,
        rating: Double,
        ratingCount: Int,
        estimatedWait: Int,
        prepMinutesOverride: Int? = nil,
        prepLoadMultiplier: Double = 1.0,
        isOpen: Bool,
        ordersPaused: Bool,
        closedEarly: Bool,
        activeHours: String,
        imageName: String,
        coverImageURL: String?,
        profileImageURL: String?,
        galleryImageURLs: [String],
        latitude: Double,
        longitude: Double,
        liveLatitude: Double,
        liveLongitude: Double,
        plan: TruckPlan,
        hasLiveTracking: Bool,
        proSubscriptionActive: Bool
    ) {
        self.id = id
        self.ownerUserID = ownerUserID
        self.name = name
        self.cuisineType = cuisineType
        self.campusName = campusName
        self.distance = distance
        self.rating = rating
        self.ratingCount = ratingCount
        self.estimatedWait = estimatedWait
        self.prepMinutesOverride = prepMinutesOverride
        self.prepLoadMultiplier = prepLoadMultiplier
        self.isOpen = isOpen
        self.ordersPaused = ordersPaused
        self.closedEarly = closedEarly
        self.activeHours = activeHours
        self.imageName = imageName
        self.coverImageURL = coverImageURL
        self.profileImageURL = profileImageURL
        self.galleryImageURLs = galleryImageURLs
        self.latitude = latitude
        self.longitude = longitude
        self.liveLatitude = liveLatitude
        self.liveLongitude = liveLongitude
        self.plan = plan
        self.hasLiveTracking = hasLiveTracking
        self.proSubscriptionActive = proSubscriptionActive
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: liveLatitude, longitude: liveLongitude)
    }

    var isDiscoverable: Bool {
        isOpen
    }

    var canUseOrderAheadFeature: Bool {
        plan.orderingEnabled
    }

    var supportsOrdering: Bool {
        canUseOrderAheadFeature && isOpen && !ordersPaused
    }

    var liveStatusLabel: String {
        if !isOpen {
            return closedEarly ? "Closed Early" : "Offline"
        }
        if ordersPaused {
            return "Live • Orders Paused"
        }
        return "Live"
    }

    var formattedDistance: String {
        String(format: "%.1f mi", distance)
    }

    var formattedWait: String {
        let effectiveWait = max(
            1,
            Int((Double(prepMinutesOverride ?? estimatedWait) * prepLoadMultiplier).rounded())
        )
        return "\(effectiveWait)-\(effectiveWait + 10) min"
    }
}
