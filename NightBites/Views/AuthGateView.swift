import SwiftUI

struct AuthGateView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var mode: AuthMode = .signIn
    @State private var signupRole: UserRole = .student

    var body: some View {
        NavigationStack {
            ZStack {
                NightBitesTheme.pageGradient
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    Text("NightBites")
                        .font(.largeTitle.weight(.bold))

                    Text("Students discover trucks. Owners manage listings, subscriptions, and analytics.")
                        .foregroundColor(.secondary)

                    Picker("Mode", selection: $mode) {
                        ForEach(AuthMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)

                        SecureField("Password", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)

                        #if DEBUG
                            HStack(spacing: 8) {
                                Button("Use Student Demo") {
                                    email = "student@nightbites.app"
                                    password = "demo1234"
                                    signupRole = .student
                                    mode = .signIn
                                }
                                .buttonStyle(.bordered)

                                Button("Use Owner Demo") {
                                    email = "owner@nightbites.app"
                                    password = "demo1234"
                                    signupRole = .owner
                                    mode = .signIn
                                }
                                .buttonStyle(.bordered)
                            }
                        #endif

                        if authViewModel.canContinueAsGuestStudent {
                            Button("Continue as Guest Student") {
                                authViewModel.continueAsGuestStudent()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(NightBitesTheme.ember)
                            .disabled(authViewModel.isLoading)
                        } else {
                            Text("Sign in is required in this build so orders can be tied to a real account.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        if mode == .signIn {
                            Button(authViewModel.isLoading ? "Opening Google..." : "Continue with Google") {
                                Task {
                                    await authViewModel.signInWithGoogle()
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(authViewModel.isLoading || !authViewModel.supportsGoogleSignIn)

                            if !authViewModel.supportsGoogleSignIn {
                                Text("Google sign-in is disabled until OAuth redirect settings are configured.")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if mode == .createAccount {
                            Picker("Account type", selection: $signupRole) {
                                ForEach(UserRole.allCases) { role in
                                    Text(role.rawValue).tag(role)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text("Create as Truck Owner to access the owner dashboard after verification.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        Button(authViewModel.isLoading ? "Working..." : mode.buttonTitle) {
                            Task {
                                if mode == .signIn {
                                    await authViewModel.signIn(email: email, password: password)
                                } else {
                                    await authViewModel.signUp(email: email, password: password, role: signupRole)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            authViewModel.isLoading ||
                            email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            password.isEmpty
                        )

                        if mode == .signIn {
                            Button("Resend Verification Email") {
                                Task {
                                    await authViewModel.resendVerification(email: email)
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(authViewModel.isLoading)
                        }

                        #if DEBUG
                            Button("Enter Truck Owner Demo (Skip Verification)") {
                                authViewModel.signInDemoOwner(email: email)
                            }
                            .buttonStyle(.bordered)
                            .disabled(authViewModel.isLoading)
                        #endif

                        if let info = authViewModel.infoMessage {
                            Text(info)
                                .font(.footnote)
                                .foregroundColor(.green)
                        }

                        if let error = authViewModel.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundColor(.red)
                        }
                    }
                    .nightBitesCard()

                    Text(mode == .signIn ? "If sign in fails, verify your email and use Resend Verification if needed." : "After sign-up, verify your email and then use Sign In.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding()
            }
            .navigationBarHidden(true)
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
