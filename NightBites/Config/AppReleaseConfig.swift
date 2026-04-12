import Foundation

enum AppReleaseConfig {
    // Override any of these via Info.plist keys for production builds:
    // SUPPORT_EMAIL, PRIVACY_POLICY_URL, TERMS_URL, SENTRY_DSN, ENABLE_FIREBASE_ANALYTICS
    static let supportEmail = stringFromInfoPlist("SUPPORT_EMAIL") ?? "support@nightbites.app"
    static let privacyPolicyURLString = stringFromInfoPlist("PRIVACY_POLICY_URL") ?? "https://nightbites.app/privacy"
    static let termsURLString = stringFromInfoPlist("TERMS_URL") ?? "https://nightbites.app/terms"

    // Keep false until a real payment processor is integrated and tested.
    static let enableDigitalPayments = boolFromInfoPlist("ENABLE_DIGITAL_PAYMENTS") ?? false

    static let enableFirebaseAnalytics = boolFromInfoPlist("ENABLE_FIREBASE_ANALYTICS") ?? true
    static let enableGoogleSignIn = boolFromInfoPlist("ENABLE_GOOGLE_SIGN_IN") ?? true

    static var googleOAuthRedirectURL: URL? {
        guard let value = stringFromInfoPlist("GOOGLE_OAUTH_REDIRECT_URL") else { return nil }
        return URL(string: value)
    }

    // Add your production Sentry DSN via Info.plist key SENTRY_DSN to enable Sentry.
    // Example: https://publicKey@o0.ingest.sentry.io/0
    static let sentryDSN: String? = stringFromInfoPlist("SENTRY_DSN")

    static let stripePublishableKey = stringFromInfoPlist("STRIPE_PUBLISHABLE_KEY")
    static let stripeMerchantIdentifier = stringFromInfoPlist("STRIPE_MERCHANT_IDENTIFIER")
    static let smsBackupWebhookURL: URL? = {
        guard let value = stringFromInfoPlist("SMS_BACKUP_WEBHOOK_URL") else { return nil }
        return URL(string: value)
    }()

    static let paymentsAPIBaseURL: URL? = {
        guard let value = stringFromInfoPlist("PAYMENTS_API_BASE_URL") else { return nil }
        return URL(string: value)
    }()

    static var supportEmailURL: URL? {
        URL(string: "mailto:\(supportEmail)")
    }

    static var privacyPolicyURL: URL? {
        URL(string: privacyPolicyURLString)
    }

    static var termsURL: URL? {
        URL(string: termsURLString)
    }

    static func runStartupChecks() {
        if supportEmailURL == nil {
            AppTelemetry.track(error: "release_config_invalid_support_email")
        }
        if privacyPolicyURL == nil {
            AppTelemetry.track(error: "release_config_invalid_privacy_url")
        }
        if termsURL == nil {
            AppTelemetry.track(error: "release_config_invalid_terms_url")
        }
        if enableGoogleSignIn && googleOAuthRedirectURL == nil {
            AppTelemetry.track(error: "release_config_missing_google_oauth_redirect_url")
        }
        if enableDigitalPayments {
            if stripePublishableKey == nil {
                AppTelemetry.track(error: "release_config_missing_stripe_publishable_key")
            }
            if stripeMerchantIdentifier == nil {
                AppTelemetry.track(error: "release_config_missing_stripe_merchant_identifier")
            }
            if paymentsAPIBaseURL == nil {
                AppTelemetry.track(error: "release_config_missing_payments_api_base_url")
            }
        }
        AppTelemetry.track(
            event: "release_config_loaded",
            metadata: ["digital_payments_enabled": String(enableDigitalPayments)]
        )
    }

    private static func stringFromInfoPlist(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func boolFromInfoPlist(_ key: String) -> Bool? {
        if let boolValue = Bundle.main.object(forInfoDictionaryKey: key) as? Bool {
            return boolValue
        }
        guard let stringValue = stringFromInfoPlist(key)?.lowercased() else {
            return nil
        }
        switch stringValue {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            return nil
        }
    }
}
