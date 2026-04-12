import Foundation
import Observation

@Observable
final class AuthViewModel {
    private let authService: AuthService
    private let allowsGuestStudentAccess: Bool

    var currentUser: AppUser?
    var isLoading = false
    var errorMessage: String?
    var infoMessage: String?

    init(authService: AuthService, allowsGuestStudentAccess: Bool = true) {
        self.authService = authService
        self.allowsGuestStudentAccess = allowsGuestStudentAccess
        self.currentUser = authService.currentUser

        if !allowsGuestStudentAccess, currentUser?.isGuest == true {
            authService.signOut()
            self.currentUser = nil
        }
    }

    var isSignedIn: Bool {
        currentUser != nil
    }

    var supportsGoogleSignIn: Bool {
        authService.supportsGoogleSignIn
    }

    var canContinueAsGuestStudent: Bool {
        allowsGuestStudentAccess
    }

    func signIn(email: String, password: String) async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty, !password.isEmpty else { return }
        AppTelemetry.track(event: "auth_sign_in_attempt")

        isLoading = true
        errorMessage = nil
        infoMessage = nil

        do {
            currentUser = try await authService.signIn(email: normalizedEmail, password: password)
            AppTelemetry.track(
                event: "auth_sign_in_success",
                metadata: ["role": currentUser?.role.rawValue ?? "unknown"]
            )
        } catch {
            errorMessage = error.localizedDescription
            AppTelemetry.track(error: "auth_sign_in_failed", metadata: ["message": error.localizedDescription])
        }

        isLoading = false
    }

    func signUp(email: String, password: String, role: UserRole) async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty, !password.isEmpty else { return }
        AppTelemetry.track(event: "auth_sign_up_attempt", metadata: ["role": role.rawValue])

        isLoading = true
        errorMessage = nil
        infoMessage = nil

        do {
            infoMessage = try await authService.signUp(email: normalizedEmail, password: password, role: role)
            AppTelemetry.track(event: "auth_sign_up_success", metadata: ["role": role.rawValue])
        } catch {
            errorMessage = error.localizedDescription
            AppTelemetry.track(error: "auth_sign_up_failed", metadata: ["message": error.localizedDescription])
        }

        isLoading = false
    }

    func signInWithGoogle() async {
        guard supportsGoogleSignIn else {
            errorMessage = "Google sign-in is not configured for this build."
            infoMessage = nil
            return
        }

        AppTelemetry.track(event: "auth_google_sign_in_attempt")
        isLoading = true
        errorMessage = nil
        infoMessage = nil

        do {
            currentUser = try await authService.signInWithGoogle()
            AppTelemetry.track(
                event: "auth_google_sign_in_success",
                metadata: ["role": currentUser?.role.rawValue ?? "unknown"]
            )
        } catch {
            errorMessage = error.localizedDescription
            AppTelemetry.track(error: "auth_google_sign_in_failed", metadata: ["message": error.localizedDescription])
        }
        isLoading = false
    }

    func resendVerification(email: String) async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty else {
            errorMessage = "Enter your email first."
            return
        }

        isLoading = true
        errorMessage = nil
        infoMessage = nil
        AppTelemetry.track(event: "auth_resend_verification_attempt")
        do {
            infoMessage = try await authService.resendVerification(email: normalizedEmail)
            AppTelemetry.track(event: "auth_resend_verification_success")
        } catch {
            errorMessage = error.localizedDescription
            AppTelemetry.track(error: "auth_resend_verification_failed", metadata: ["message": error.localizedDescription])
        }
        isLoading = false
    }

    func signOut() {
        authService.signOut()
        currentUser = nil
        AppTelemetry.track(event: "auth_sign_out")
    }

    func signInDemoOwner(email: String) {
#if !DEBUG
        errorMessage = "Demo owner access is unavailable in production."
        infoMessage = nil
        AppTelemetry.track(error: "auth_demo_owner_blocked_release")
        return
#endif
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackEmail = "demo-owner@nightbites.app"
        let user = AppUser(
            id: "demo-owner-\(UUID().uuidString)",
            email: normalizedEmail.isEmpty ? fallbackEmail : normalizedEmail,
            role: .owner
        )
        authService.setCurrentUser(user)
        currentUser = user
        errorMessage = nil
        infoMessage = "Demo owner access enabled. Verification is temporarily bypassed."
        AppTelemetry.track(event: "auth_demo_owner_sign_in")
    }

    func continueAsGuestStudent() {
        guard allowsGuestStudentAccess else {
            errorMessage = "Guest browsing is disabled in this build. Sign in to place real orders."
            infoMessage = nil
            return
        }

        let user = AppUser(
            id: "guest-student-\(UUID().uuidString)",
            email: "guest@nightbites.app",
            role: .student
        )
        authService.setCurrentUser(user)
        currentUser = user
        errorMessage = nil
        infoMessage = "Continuing as guest. You can sign in later from Profile."
        AppTelemetry.track(event: "auth_guest_continue")
    }
}
