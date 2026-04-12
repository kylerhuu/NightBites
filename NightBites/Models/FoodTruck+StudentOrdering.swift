import SwiftUI

/// Snackpass-style operational headline for the student menu header.
enum StudentTruckOperationalState: Equatable {
    case openNow
    case ordersPaused
    case closedEarly
    case closed
    case orderingNotAvailable

    var title: String {
        switch self {
        case .openNow: return "Open Now"
        case .ordersPaused: return "Orders Paused"
        case .closedEarly: return "Closed Early"
        case .closed: return "Closed"
        case .orderingNotAvailable: return "Ordering Unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .openNow: return "flame.fill"
        case .ordersPaused: return "pause.circle.fill"
        case .closedEarly: return "moon.zzz.fill"
        case .closed: return "xmark.circle.fill"
        case .orderingNotAvailable: return "lock.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .openNow: return NightBitesTheme.success
        case .ordersPaused: return NightBitesTheme.warning
        case .closedEarly: return Color.orange.opacity(0.85)
        case .closed: return Color.gray
        case .orderingNotAvailable: return Color.gray
        }
    }
}

extension FoodTruck {
    var studentOperationalState: StudentTruckOperationalState {
        if !canUseOrderAheadFeature {
            return .orderingNotAvailable
        }
        if !isOpen, closedEarly {
            return .closedEarly
        }
        if !isOpen {
            return .closed
        }
        if ordersPaused {
            return .ordersPaused
        }
        return .openNow
    }

    var studentCanBrowseMenu: Bool {
        canUseOrderAheadFeature
    }

    var studentCanPlaceOrders: Bool {
        supportsOrdering
    }
}
