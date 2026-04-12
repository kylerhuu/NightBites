//
//  NightBitesApp.swift
//  NightBites
//
//  Created by Kyler Hu on 2/24/26.
//

import SwiftUI
#if canImport(FirebaseCore)
    import FirebaseCore
#endif

@main
struct NightBitesApp: App {
    @State private var foodTruckViewModel: FoodTruckViewModel
    @State private var authViewModel: AuthViewModel
    @State private var paymentManager: PaymentManager
    @State private var locationAccessManager: LocationAccessManager

    @MainActor
    init() {
        #if canImport(FirebaseCore)
            if AppReleaseConfig.enableFirebaseAnalytics {
                if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
                    FirebaseApp.configure()
                } else {
                    AppTelemetry.track(error: "firebase_config_missing_google_service_info")
                }
            }
        #endif
        AppTelemetry.configure()
        AppReleaseConfig.runStartupChecks()
        let backendService: BackendService
        let authService: AuthService
        let paymentService: PaymentService
        let allowsGuestStudentAccess: Bool

        if let supabaseConfig = SupabaseConfig.fromBundle() {
            backendService = SupabaseBackendService(config: supabaseConfig)
            authService = SupabaseAuthService(config: supabaseConfig)
            allowsGuestStudentAccess = false
        } else {
            backendService = InMemoryBackendService()
            authService = InMemoryAuthService()
            allowsGuestStudentAccess = true
        }

        if let paymentsBaseURL = AppReleaseConfig.paymentsAPIBaseURL {
            paymentService = RemotePaymentService(baseURL: paymentsBaseURL)
        } else {
            paymentService = InMemoryPaymentService()
        }

        _foodTruckViewModel = State(initialValue: FoodTruckViewModel(backendService: backendService))
        _authViewModel = State(initialValue: AuthViewModel(
            authService: authService,
            allowsGuestStudentAccess: allowsGuestStudentAccess
        ))
        _paymentManager = State(initialValue: PaymentManager(service: paymentService))
        _locationAccessManager = State(initialValue: LocationAccessManager())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(foodTruckViewModel)
                .environment(authViewModel)
                .environment(paymentManager)
                .environment(locationAccessManager)
                .controlSize(.large)
        }
    }
}
