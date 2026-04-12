import Foundation

enum PaymentMethod: String, CaseIterable, Identifiable, Codable {
    case card = "Card"
    case applePay = "Apple Pay"
    case cash = "Pay at Pickup"

    var id: String { rawValue }
}

enum PickupTiming: String, CaseIterable, Codable {
    case asap = "ASAP"
    case scheduled = "Scheduled"
}

struct Order: Identifiable, Hashable {
    let id: UUID
    let truckID: UUID?
    let customerUserID: String?
    let truckName: String
    let campusName: String
    let items: [OrderItem]
    let totalAmount: Double
    var status: OrderStatus
    let paymentMethod: PaymentMethod
    let pickupTiming: PickupTiming
    let orderDate: Date
    let estimatedDelivery: Date?
    let customerName: String
    let specialInstructions: String?

    init(
        id: UUID = UUID(),
        truckID: UUID? = nil,
        customerUserID: String? = nil,
        truckName: String,
        campusName: String,
        items: [OrderItem],
        totalAmount: Double,
        status: OrderStatus,
        paymentMethod: PaymentMethod,
        pickupTiming: PickupTiming = .asap,
        orderDate: Date,
        estimatedDelivery: Date?,
        customerName: String = "Guest",
        specialInstructions: String? = nil
    ) {
        self.id = id
        self.truckID = truckID
        self.customerUserID = customerUserID
        self.truckName = truckName
        self.campusName = campusName
        self.items = items
        self.totalAmount = totalAmount
        self.status = status
        self.paymentMethod = paymentMethod
        self.pickupTiming = pickupTiming
        self.orderDate = orderDate
        self.estimatedDelivery = estimatedDelivery
        self.customerName = customerName
        self.specialInstructions = specialInstructions
    }

    var formattedTotal: String {
        String(format: "$%.2f", totalAmount)
    }

    var formattedDate: String {
        Self.orderDateFormatter.string(from: orderDate)
    }

    var formattedPickupTime: String {
        guard let estimatedDelivery else { return "ASAP" }
        return Self.pickupTimeFormatter.string(from: estimatedDelivery)
    }

    var shortOrderNumber: String {
        String(id.uuidString.prefix(6)).uppercased()
    }

    private static let orderDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let pickupTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Order, rhs: Order) -> Bool {
        lhs.id == rhs.id
    }
}

struct OrderItem: Identifiable, Hashable {
    let id: UUID
    let menuItem: MenuItem
    let quantity: Int
    let customization: String?

    init(
        id: UUID = UUID(),
        menuItem: MenuItem,
        quantity: Int,
        customization: String? = nil
    ) {
        self.id = id
        self.menuItem = menuItem
        self.quantity = quantity
        self.customization = customization
    }

    var subtotal: Double {
        menuItem.price * Double(quantity)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: OrderItem, rhs: OrderItem) -> Bool {
        lhs.id == rhs.id
    }
}

enum OrderStatus: String, CaseIterable, Codable {
    case pending = "Pending Acceptance"
    case accepted = "Accepted"
    case preparing = "Preparing"
    case ready = "Ready for Pickup"
    case completed = "Completed"
    case cancelled = "Cancelled"

    var colorName: String {
        switch self {
        case .pending: return "gray"
        case .accepted: return "indigo"
        case .preparing: return "blue"
        case .ready: return "orange"
        case .completed: return "green"
        case .cancelled: return "red"
        }
    }
}
