import Foundation
import SwiftUI

/// Snackpass-style operational headline for the student menu header.
enum StudentTruckOperationalState: Equatable {
    case openNow
    case closingSoon
    case ordersPaused
    case closedEarly
    case closed
    case orderingNotAvailable

    var title: String {
        switch self {
        case .openNow: return "Open Now"
        case .closingSoon: return "Closing Soon"
        case .ordersPaused: return "Orders Paused"
        case .closedEarly: return "Closed Early"
        case .closed: return "Closed"
        case .orderingNotAvailable: return "Ordering Unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .openNow: return "flame.fill"
        case .closingSoon: return "hourglass.circle.fill"
        case .ordersPaused: return "pause.circle.fill"
        case .closedEarly: return "moon.zzz.fill"
        case .closed: return "xmark.circle.fill"
        case .orderingNotAvailable: return "lock.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .openNow: return NightBitesTheme.success
        case .closingSoon: return NightBitesTheme.warning
        case .ordersPaused: return NightBitesTheme.warning
        case .closedEarly: return Color.orange.opacity(0.85)
        case .closed: return Color.gray
        case .orderingNotAvailable: return Color.gray
        }
    }
}

extension FoodTruck {
    /// True when the truck is still accepting orders but is within the “closing soon” window.
    var isApproachingClosingDeadline: Bool {
        guard isOpen, !ordersPaused, let closingAt else { return false }
        let now = Date()
        guard closingAt > now else { return false }
        return closingAt.timeIntervalSince(now) <= 45 * 60
    }

    var closingTimeShortFormatted: String? {
        guard let closingAt else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: closingAt)
    }

    var studentHoursCaption: String {
        if isApproachingClosingDeadline, let t = closingTimeShortFormatted {
            return "Stops taking orders around \(t) • Hours: \(activeHours)"
        }
        return "Until \(activeHours)"
    }

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
        if isApproachingClosingDeadline {
            return .closingSoon
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
