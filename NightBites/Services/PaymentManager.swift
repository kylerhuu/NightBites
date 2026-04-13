import Foundation
import Observation

enum PaymentProcessor: String, Codable {
    case stripe
}

enum PaymentConfirmationOutcome: String, Codable {
    case authorized
    case succeeded
    case failed
    case requiresAction
}

struct PaymentCheckoutSession {
    let checkoutID: String
    let processor: PaymentProcessor
    let paymentMethod: PaymentMethod
    let amount: Double
    let currencyCode: String
    let orderReference: String
    let clientSecret: String?
    let customerEphemeralKey: String?
    let customerID: String?
    let merchantDisplayName: String?
    let merchantCountryCode: String?
    let applePayMerchantIdentifier: String?
}

struct PaymentConfirmationResult {
    let outcome: PaymentConfirmationOutcome
    let message: String?
    let transactionID: String?

    var isSuccess: Bool {
        outcome == .authorized || outcome == .succeeded
    }
}

enum PaymentError: LocalizedError {
    case digitalPaymentsDisabled
    case missingConfiguration
    case paymentBackendUnavailable
    case checkoutInitializationFailed
    case paymentConfirmationFailed
    case paymentUIPresentationUnavailable

    var errorDescription: String? {
        switch self {
        case .digitalPaymentsDisabled:
            return "Digital payments are disabled for this build."
        case .missingConfiguration:
            return "Payment configuration is incomplete."
        case .paymentBackendUnavailable:
            return "Payment server is unavailable."
        case .checkoutInitializationFailed:
            return "Could not start checkout. Try again."
        case .paymentConfirmationFailed:
            return "Payment confirmation failed. Try again."
        case .paymentUIPresentationUnavailable:
            return "Payment UI is not available yet in this build."
        }
    }
}

protocol PaymentCheckoutPresenter {
    func presentCheckout(session: PaymentCheckoutSession) async throws -> PaymentConfirmationResult
}

protocol PaymentService {
    func createCheckoutSession(
        method: PaymentMethod,
        subtotalAmount: Double,
        serviceFeeAmount: Double,
        amount: Double,
        orderReference: String,
        truckID: UUID
    ) async throws -> PaymentCheckoutSession

    func confirmCheckout(session: PaymentCheckoutSession) async throws -> PaymentConfirmationResult
}

final class InMemoryPaymentService: PaymentService {
    func createCheckoutSession(
        method: PaymentMethod,
        subtotalAmount _: Double,
        serviceFeeAmount _: Double,
        amount: Double,
        orderReference: String,
        truckID _: UUID
    ) async throws -> PaymentCheckoutSession {
        if method == .cash {
            return PaymentCheckoutSession(
                checkoutID: orderReference,
                processor: .stripe,
                paymentMethod: method,
                amount: amount,
                currencyCode: "USD",
                orderReference: orderReference,
                clientSecret: nil,
                customerEphemeralKey: nil,
                customerID: nil,
                merchantDisplayName: "NightBites",
                merchantCountryCode: "US",
                applePayMerchantIdentifier: AppReleaseConfig.stripeMerchantIdentifier
            )
        }
        if !AppReleaseConfig.enableDigitalPayments {
            throw PaymentError.digitalPaymentsDisabled
        }
        if AppReleaseConfig.paymentsAPIBaseURL == nil || AppReleaseConfig.stripePublishableKey == nil {
            throw PaymentError.missingConfiguration
        }
        throw PaymentError.paymentBackendUnavailable
    }

    func confirmCheckout(session: PaymentCheckoutSession) async throws -> PaymentConfirmationResult {
        if session.paymentMethod == .cash {
            return PaymentConfirmationResult(outcome: .succeeded, message: nil, transactionID: nil)
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

    func createCheckoutSession(
        method: PaymentMethod,
        subtotalAmount: Double,
        serviceFeeAmount: Double,
        amount: Double,
        orderReference: String,
        truckID: UUID
    ) async throws -> PaymentCheckoutSession {
        struct CheckoutRequest: Encodable {
            let method: String
            let subtotal_amount_cents: Int
            let service_fee_amount_cents: Int
            let amount_cents: Int
            let currency: String
            let order_reference: String
            let truck_id: String
            let merchant_identifier: String?
        }

        struct CheckoutResponse: Decodable {
            let checkout_id: String
            let processor: String?
            let payment_method: String?
            let amount_cents: Int?
            let currency: String?
            let order_reference: String?
            let client_secret: String?
            let customer_ephemeral_key: String?
            let customer_id: String?
            let merchant_display_name: String?
            let merchant_country_code: String?
            let apple_pay_merchant_identifier: String?
        }

        if method == .cash {
            return PaymentCheckoutSession(
                checkoutID: orderReference,
                processor: .stripe,
                paymentMethod: method,
                amount: amount,
                currencyCode: "USD",
                orderReference: orderReference,
                clientSecret: nil,
                customerEphemeralKey: nil,
                customerID: nil,
                merchantDisplayName: "NightBites",
                merchantCountryCode: "US",
                applePayMerchantIdentifier: AppReleaseConfig.stripeMerchantIdentifier
            )
        }
        guard AppReleaseConfig.enableDigitalPayments else {
            throw PaymentError.digitalPaymentsDisabled
        }
        guard AppReleaseConfig.stripePublishableKey != nil else {
            throw PaymentError.missingConfiguration
        }

        let endpoint = baseURL.appending(path: "/api/mobile/payments/create-intent")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            CheckoutRequest(
                method: method.rawValue,
                subtotal_amount_cents: max(Int((subtotalAmount * 100).rounded()), 0),
                service_fee_amount_cents: max(Int((serviceFeeAmount * 100).rounded()), 0),
                amount_cents: max(Int((amount * 100).rounded()), 0),
                currency: "USD",
                order_reference: orderReference,
                truck_id: truckID.uuidString,
                merchant_identifier: AppReleaseConfig.stripeMerchantIdentifier
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw PaymentError.checkoutInitializationFailed
        }

        let payload = try JSONDecoder().decode(CheckoutResponse.self, from: data)
        let processor = PaymentProcessor(rawValue: payload.processor ?? "stripe") ?? .stripe
        let resolvedMethod = PaymentMethod(rawValue: payload.payment_method ?? method.rawValue) ?? method

        return PaymentCheckoutSession(
            checkoutID: payload.checkout_id,
            processor: processor,
            paymentMethod: resolvedMethod,
            amount: Double(payload.amount_cents ?? max(Int((amount * 100).rounded()), 0)) / 100,
            currencyCode: payload.currency ?? "USD",
            orderReference: payload.order_reference ?? orderReference,
            clientSecret: payload.client_secret,
            customerEphemeralKey: payload.customer_ephemeral_key,
            customerID: payload.customer_id,
            merchantDisplayName: payload.merchant_display_name,
            merchantCountryCode: payload.merchant_country_code,
            applePayMerchantIdentifier: payload.apple_pay_merchant_identifier ?? AppReleaseConfig.stripeMerchantIdentifier
        )
    }

    func confirmCheckout(session checkoutSession: PaymentCheckoutSession) async throws -> PaymentConfirmationResult {
        struct ConfirmRequest: Encodable {
            let checkout_id: String
            let order_reference: String
        }

        struct ConfirmResponse: Decodable {
            let status: String
            let transaction_id: String?
            let message: String?
        }

        if checkoutSession.paymentMethod == .cash {
            return PaymentConfirmationResult(outcome: .succeeded, message: nil, transactionID: nil)
        }

        let endpoint = baseURL.appending(path: "/api/mobile/payments/confirm")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ConfirmRequest(
                checkout_id: checkoutSession.checkoutID,
                order_reference: checkoutSession.orderReference
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw PaymentError.paymentConfirmationFailed
        }

        let payload = try JSONDecoder().decode(ConfirmResponse.self, from: data)
        let normalizedStatus = payload.status.lowercased()
        let outcome: PaymentConfirmationOutcome
        switch normalizedStatus {
        case "authorized":
            outcome = .authorized
        case "succeeded", "paid":
            outcome = .succeeded
        case "requires_action":
            outcome = .requiresAction
        default:
            outcome = .failed
        }

        return PaymentConfirmationResult(
            outcome: outcome,
            message: payload.message,
            transactionID: payload.transaction_id
        )
    }
}

@Observable
final class PaymentManager {
    private let service: PaymentService
    private let presenter: PaymentCheckoutPresenter

    var isProcessing = false
    var lastErrorMessage: String?
    var lastTransactionID: String?
    var lastCheckoutSession: PaymentCheckoutSession?

    init(service: PaymentService, presenter: PaymentCheckoutPresenter) {
        self.service = service
        self.presenter = presenter
    }

    func prepareCheckout(
        method: PaymentMethod,
        subtotalAmount: Double,
        serviceFeeAmount: Double,
        amount: Double,
        orderReference: String,
        truckID: UUID
    ) async -> PaymentCheckoutSession? {
        if method == .cash {
            lastErrorMessage = nil
            lastTransactionID = nil
            let session = PaymentCheckoutSession(
                checkoutID: orderReference,
                processor: .stripe,
                paymentMethod: method,
                amount: amount,
                currencyCode: "USD",
                orderReference: orderReference,
                clientSecret: nil,
                customerEphemeralKey: nil,
                customerID: nil,
                merchantDisplayName: "NightBites",
                merchantCountryCode: "US",
                applePayMerchantIdentifier: AppReleaseConfig.stripeMerchantIdentifier
            )
            // `confirmPreparedCheckout` reads `lastCheckoutSession`; cash must not leave it nil.
            lastCheckoutSession = session
            return session
        }

        isProcessing = true
        lastErrorMessage = nil
        lastTransactionID = nil
        defer { isProcessing = false }

        do {
            let checkoutSession = try await service.createCheckoutSession(
                method: method,
                subtotalAmount: subtotalAmount,
                serviceFeeAmount: serviceFeeAmount,
                amount: amount,
                orderReference: orderReference,
                truckID: truckID
            )
            lastCheckoutSession = checkoutSession
            AppTelemetry.track(
                event: "payment_checkout_created",
                metadata: ["method": method.rawValue, "checkout_id": checkoutSession.checkoutID]
            )
            return checkoutSession
        } catch {
            lastCheckoutSession = nil
            lastErrorMessage = error.localizedDescription
            AppTelemetry.track(error: "payment_checkout_create_error", metadata: ["message": error.localizedDescription])
            return nil
        }
    }

    func confirmPreparedCheckout() async -> Bool {
        guard let checkoutSession = lastCheckoutSession else {
            lastErrorMessage = PaymentError.checkoutInitializationFailed.localizedDescription
            return false
        }
        if checkoutSession.paymentMethod == .cash {
            lastErrorMessage = nil
            lastTransactionID = nil
            return true
        }

        isProcessing = true
        lastErrorMessage = nil
        lastTransactionID = nil
        defer { isProcessing = false }

        do {
            let presentedResult = try await presenter.presentCheckout(session: checkoutSession)
            guard presentedResult.isSuccess else {
                let message = presentedResult.message ?? PaymentError.paymentUIPresentationUnavailable.localizedDescription
                lastErrorMessage = message
                AppTelemetry.track(error: "payment_checkout_presentation_failed", metadata: ["message": message])
                return false
            }

            let result = try await service.confirmCheckout(session: checkoutSession)
            if result.isSuccess {
                lastTransactionID = result.transactionID
                AppTelemetry.track(
                    event: "payment_checkout_confirmed",
                    metadata: ["method": checkoutSession.paymentMethod.rawValue, "outcome": result.outcome.rawValue]
                )
                return true
            }
            let message = result.message ?? PaymentError.paymentConfirmationFailed.localizedDescription
            lastErrorMessage = message
            AppTelemetry.track(error: "payment_checkout_confirmation_failed", metadata: ["message": message])
            return false
        } catch {
            lastErrorMessage = error.localizedDescription
            AppTelemetry.track(error: "payment_checkout_confirmation_error", metadata: ["message": error.localizedDescription])
            return false
        }
    }
}

struct NoopPaymentCheckoutPresenter: PaymentCheckoutPresenter {
    func presentCheckout(session: PaymentCheckoutSession) async throws -> PaymentConfirmationResult {
        if session.paymentMethod == .cash {
            return PaymentConfirmationResult(outcome: .succeeded, message: nil, transactionID: nil)
        }
        return PaymentConfirmationResult(
            outcome: .failed,
            message: "Stripe PaymentSheet / Apple Pay SDK is not installed yet.",
            transactionID: nil
        )
    }
}
