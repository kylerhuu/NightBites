import SwiftUI

struct AuthGateView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var mode: AuthMode = .signIn
    @State private var signupRole: UserRole = .student

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection

                    Picker("Mode", selection: $mode) {
                        ForEach(AuthMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(NightBitesTheme.ember)

                    VStack(alignment: .leading, spacing: 16) {
                        AuthLabeledField(title: "Email") {
                            TextField("", text: $email, prompt: Text("you@campus.edu").foregroundStyle(NightBitesTheme.labelSecondary.opacity(0.5)))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                        }

                        AuthLabeledField(title: "Password") {
                            SecureField("", text: $password, prompt: Text("Password").foregroundStyle(NightBitesTheme.labelSecondary.opacity(0.5)))
                                .textContentType(mode == .signIn ? .password : .newPassword)
                        }

                        #if DEBUG
                            demoAccountRow
                        #endif

                        if authViewModel.canContinueAsGuestStudent {
                            Button {
                                authViewModel.continueAsGuestStudent()
                            } label: {
                                Label("Continue as Guest Student", systemImage: "person.fill.questionmark")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(NightBitesTheme.mutedCard)
                                    .foregroundStyle(NightBitesTheme.label)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(NightBitesTheme.border, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(authViewModel.isLoading)

                            Text("Guest mode is great for exploring menus; use a real account when you are ready for synced orders and payments.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(NightBitesTheme.labelSecondary)
                        } else {
                            Text("Sign in is required in this build so orders can be tied to a real account.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(NightBitesTheme.labelSecondary)
                        }

                        if mode == .signIn {
                            googleSection
                        }

                        if mode == .createAccount {
                            Picker("Account type", selection: $signupRole) {
                                ForEach(UserRole.allCases) { role in
                                    Text(role.rawValue).tag(role)
                                }
                            }
                            .pickerStyle(.segmented)
                            .tint(NightBitesTheme.ember)

                            Text("Create as Truck Owner to access the owner dashboard after verification.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(NightBitesTheme.labelSecondary)
                        }

                        primaryAuthButton

                        if mode == .signIn {
                            Button("Resend Verification Email") {
                                Task {
                                    await authViewModel.resendVerification(email: email)
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NightBitesTheme.info)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .disabled(authViewModel.isLoading)
                        }

                        #if DEBUG
                            Button("Enter Truck Owner Demo (Skip Verification)") {
                                authViewModel.signInDemoOwner(email: email)
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(NightBitesTheme.mutedCard.opacity(0.8))
                            .foregroundStyle(NightBitesTheme.label)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(NightBitesTheme.border, lineWidth: 1)
                            )
                            .buttonStyle(.plain)
                            .disabled(authViewModel.isLoading)
                        #endif

                        messageBlock
                    }
                    .nightBitesCard()

                    Text(mode == .signIn ? "If sign in fails, verify your email and use Resend Verification if needed." : "After sign-up, verify your email and then use Sign In.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(NightBitesTheme.labelSecondary)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
            .nightBitesScreenBackground()
            .navigationTitle("NightBites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .tint(NightBitesTheme.ember)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(NightBitesTheme.heroGradient)
                        .frame(width: 52, height: 52)
                        .nightBitesPrimaryGlow(radius: 12, y: 4)
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Campus food, late night")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NightBitesTheme.saffron)
                    Text("Students find trucks. Owners run menus, orders, and payouts.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(NightBitesTheme.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var demoAccountRow: some View {
        HStack(spacing: 10) {
            Button("Student demo") {
                email = "student@nightbites.app"
                password = "demo1234"
                signupRole = .student
                mode = .signIn
            }
            .font(.caption.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(NightBitesTheme.ember.opacity(0.16))
            .foregroundStyle(NightBitesTheme.ember)
            .clipShape(Capsule())
            .buttonStyle(.plain)

            Button("Owner demo") {
                email = "owner@nightbites.app"
                password = "demo1234"
                signupRole = .owner
                mode = .signIn
            }
            .font(.caption.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(NightBitesTheme.ember.opacity(0.16))
            .foregroundStyle(NightBitesTheme.ember)
            .clipShape(Capsule())
            .buttonStyle(.plain)
        }
    }

    private var googleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task {
                    await authViewModel.signInWithGoogle()
                }
            } label: {
                Label(authViewModel.isLoading ? "Opening Google…" : "Continue with Google", systemImage: "globe.americas.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(NightBitesTheme.mutedCard)
                    .foregroundStyle(NightBitesTheme.label)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(NightBitesTheme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(authViewModel.isLoading || !authViewModel.supportsGoogleSignIn)

            if !authViewModel.supportsGoogleSignIn {
                Text("Google sign-in is disabled until OAuth redirect settings are configured.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(NightBitesTheme.labelSecondary)
            }
        }
    }

    private var primaryAuthButton: some View {
        let disabled = authViewModel.isLoading ||
            email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            password.isEmpty

        return Button {
            Task {
                if mode == .signIn {
                    await authViewModel.signIn(email: email, password: password)
                } else {
                    await authViewModel.signUp(email: email, password: password, role: signupRole)
                }
            }
        } label: {
            Text(authViewModel.isLoading ? "Working…" : mode.buttonTitle)
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    if disabled && !authViewModel.isLoading {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.gray.opacity(0.35))
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(NightBitesTheme.heroGradient)
                    }
                }
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .nightBitesPrimaryGlow(radius: (disabled && !authViewModel.isLoading) ? 0 : 14, y: (disabled && !authViewModel.isLoading) ? 0 : 6)
    }

    @ViewBuilder
    private var messageBlock: some View {
        if let info = authViewModel.infoMessage {
            Text(info)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(NightBitesTheme.success)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NightBitesTheme.success.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }

        if let error = authViewModel.errorMessage {
            Text(error)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.red.opacity(0.95))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct AuthLabeledField<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.heavy))
                .foregroundStyle(NightBitesTheme.labelSecondary)

            content()
                .font(.body.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(NightBitesTheme.ink.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NightBitesTheme.border, lineWidth: 1)
                )
                .foregroundStyle(NightBitesTheme.label)
        }
    }
}

private enum AuthMode: String, CaseIterable, Identifiable {
    case signIn
    case createAccount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signIn: return "Sign In"
        case .createAccount: return "Create Account"
        }
    }

    var buttonTitle: String {
        switch self {
        case .signIn: return "Sign In"
        case .createAccount: return "Create & Send Verification"
        }
    }
}
