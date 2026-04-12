import Foundation

#if canImport(StripePaymentSheet)
import StripePaymentSheet

struct StripePaymentCheckoutPresenter: PaymentCheckoutPresenter {
    func presentCheckout(session: PaymentCheckoutSession) async throws -> PaymentConfirmationResult {
        guard session.paymentMethod != .cash else {
            return PaymentConfirmationResult(outcome: .succeeded, message: nil, transactionID: nil)
        }

        // This build does not yet wire a UIWindowScene / presenting controller into the payment flow.
        // Keep the integration seam compile-safe until Stripe SDK installation and UI hosting are configured.
        return PaymentConfirmationResult(
            outcome: .failed,
            message: "Stripe SDK is installed, but PaymentSheet presentation is not wired yet.",
            transactionID: nil
        )
    }
}
#else
typealias StripePaymentCheckoutPresenter = NoopPaymentCheckoutPresenter
#endif
