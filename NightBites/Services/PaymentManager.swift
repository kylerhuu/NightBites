import Foundation
import Observation

struct PaymentAuthorizationResult {
    let success: Bool
    let message: String?
    let transactionID: String?
}

enum PaymentError: LocalizedError {
    case digitalPaymentsDisabled
    case missingConfiguration
    case paymentBackendUnavailable
    case authorizationFailed

    var errorDescription: String? {
        switch self {
        case .digitalPaymentsDisabled:
            return "Digital payments are disabled for this build."
        case .missingConfiguration:
            return "Payment configuration is incomplete."
        case .paymentBackendUnavailable:
            return "Payment server is unavailable."
        case .authorizationFailed:
            return "Payment authorization failed. Try again."
        }
    }
}

protocol PaymentService {
    func authorizePayment(
        method: PaymentMethod,
        amount: Double,
        orderReference: String
    ) async throws -> PaymentAuthorizationResult
}

final class InMemoryPaymentService: PaymentService {
    func authorizePayment(
        method: PaymentMethod,
        amount _: Double,
        orderReference _: String
    ) async throws -> PaymentAuthorizationResult {
        if method == .cash {
            return PaymentAuthorizationResult(success: true, message: nil, transactionID: nil)
        }
        if !AppReleaseConfig.enableDigitalPayments {
            throw PaymentError.digitalPaymentsDisabled
        }
        if AppReleaseConfig.paymentsAPIBaseURL == nil || AppReleaseConfig.stripePublishableKey == nil {
            throw PaymentError.missingConfiguration
        }
        throw PaymentError.paymentBackendUnavailable
    }
}

final class RemotePaymentService: PaymentService {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func authorizePayment(
        method: PaymentMethod,
        amount: Double,
        orderReference: String
    ) async throws -> PaymentAuthorizationResult {
        struct PaymentRequest: Encodable {
            let method: String
            let amount_cents: Int
            let currency: String
            let order_reference: String
        }

        struct PaymentResponse: Decodable {
            let status: String
            let transaction_id: String?
            let message: String?
        }

        if method == .cash {
            return PaymentAuthorizationResult(success: true, message: nil, transactionID: nil)
        }
        guard AppReleaseConfig.enableDigitalPayments else {
            throw PaymentError.digitalPaymentsDisabled
        }
        guard AppReleaseConfig.stripePublishableKey != nil else {
            throw PaymentError.missingConfiguration
        }

        let endpoint = baseURL.appending(path: "/api/mobile/payments/authorize")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            PaymentRequest(
                method: method.rawValue,
                amount_cents: max(Int((amount * 100).rounded()), 0),
                currency: "USD",
                order_reference: orderReference
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw PaymentError.authorizationFailed
        }

        let payload = try JSONDecoder().decode(PaymentResponse.self, from: data)
        let success = payload.status.lowercased() == "authorized" || payload.status.lowercased() == "succeeded"
        return PaymentAuthorizationResult(
            success: success,
            message: payload.message,
            transactionID: payload.transaction_id
        )
    }
}

@Observable
final class PaymentManager {
    private let service: PaymentService

    var isProcessing = false
    var lastErrorMessage: String?
    var lastTransactionID: String?

    init(service: PaymentService) {
        self.service = service
    }

    func authorizeIfNeeded(
        method: PaymentMethod,
        amount: Double,
        orderReference: String
    ) async -> Bool {
        if method == .cash {
            lastErrorMessage = nil
            lastTransactionID = nil
            return true
        }

        isProcessing = true
        lastErrorMessage = nil
        lastTransactionID = nil
        defer { isProcessing = false }

        do {
            let result = try await service.authorizePayment(
                method: method,
                amount: amount,
                orderReference: orderReference
            )
            if result.success {
                lastTransactionID = result.transactionID
                AppTelemetry.track(event: "payment_authorized", metadata: ["method": method.rawValue])
                return true
            }
            let message = result.message ?? PaymentError.authorizationFailed.localizedDescription
            lastErrorMessage = message
            AppTelemetry.track(error: "payment_authorization_failed", metadata: ["message": message])
            return false
        } catch {
            lastErrorMessage = error.localizedDescription
            AppTelemetry.track(error: "payment_authorization_error", metadata: ["message": error.localizedDescription])
            return false
        }
    }
}
