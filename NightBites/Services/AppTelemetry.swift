 import Foundation
import os
#if canImport(FirebaseAnalytics)
    import FirebaseAnalytics
#endif
#if canImport(Sentry)
    import Sentry
#endif

enum AppTelemetry {
    private static let logger = Logger(subsystem: "xcode.NightBites", category: "telemetry")

    static func configure() {
        NSSetUncaughtExceptionHandler(appUnhandledExceptionHandler)
        configureSentryIfAvailable()
        track(event: "app_launch")
    }

    fileprivate static func recordUnhandledException(_ exception: NSException) {
        logger.fault("Uncaught exception: \(exception.name.rawValue, privacy: .public) - \(exception.reason ?? "n/a", privacy: .public)")
        #if canImport(Sentry)
            SentrySDK.capture(message: "Uncaught exception: \(exception.name.rawValue) \(exception.reason ?? "n/a")")
        #endif
    }

    static func track(event: String, metadata: [String: String] = [:]) {
        if metadata.isEmpty {
            logger.notice("event=\(event, privacy: .public)")
        } else {
            let compact = metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            logger.notice("event=\(event, privacy: .public) \(compact, privacy: .public)")
        }
        forwardEventToBackends(event: event, metadata: metadata)
    }

    static func track(error: String, metadata: [String: String] = [:]) {
        if metadata.isEmpty {
            logger.error("error=\(error, privacy: .public)")
        } else {
            let compact = metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            logger.error("error=\(error, privacy: .public) \(compact, privacy: .public)")
        }
        forwardErrorToBackends(error: error, metadata: metadata)
    }

    private static func forwardEventToBackends(event: String, metadata: [String: String]) {
        #if canImport(FirebaseAnalytics)
            if AppReleaseConfig.enableFirebaseAnalytics {
                Analytics.logEvent(normalizedEventName(event), parameters: metadata)
            }
        #endif
        #if canImport(Sentry)
            let breadcrumb = Breadcrumb(level: .info, category: "app.event")
            breadcrumb.message = event
            breadcrumb.data = metadata
            SentrySDK.addBreadcrumb(breadcrumb)
        #endif
    }

    private static func forwardErrorToBackends(error: String, metadata: [String: String]) {
        #if canImport(FirebaseAnalytics)
            if AppReleaseConfig.enableFirebaseAnalytics {
                var params = metadata
                params["error"] = error
                Analytics.logEvent("app_error", parameters: params)
            }
        #endif
        #if canImport(Sentry)
            var combined = metadata
            combined["error"] = error
            SentrySDK.capture(message: error) { scope in
                scope.setContext(value: combined, key: "telemetry")
            }
        #endif
    }

    private static func configureSentryIfAvailable() {
        #if canImport(Sentry)
            if let dsn = AppReleaseConfig.sentryDSN, !dsn.isEmpty {
                SentrySDK.start { options in
                    options.dsn = dsn
                    options.enableCrashHandler = true
                    options.attachStacktrace = true
                }
            }
        #endif
    }

    private static func normalizedEventName(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let filtered = lowered.map { char -> Character in
            if char.isLetter || char.isNumber || char == "_" {
                return char
            }
            return "_"
        }
        let result = String(filtered)
        return String(result.prefix(40))
    }
}

private func appUnhandledExceptionHandler(_ exception: NSException) {
    AppTelemetry.recordUnhandledException(exception)
}
