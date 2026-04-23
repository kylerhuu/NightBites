import Foundation

struct AppSeedData {
    let campuses: [Campus]
    let foodTrucks: [FoodTruck]
    let menuItems: [MenuItem]
    let orders: [Order]
    let reviews: [Review]
}

protocol BackendService {
    var isRemoteEnabled: Bool { get }
    func loadSeedData() -> AppSeedData
    func syncData() async -> AppSeedData?
    func submit(order: Order) async
    func update(orderID: UUID, status: OrderStatus) async
    func submit(application: TruckApplication) async
    func submit(review: Review) async
    func submit(truck: FoodTruck) async
    @discardableResult
    func submit(menuItem: MenuItem, truckName: String) async -> Bool
    func update(truck: FoodTruck) async
    @discardableResult
    func update(menuItem: MenuItem, truckName: String) async -> Bool
    /// Public URL to use as `MenuItem.imageURL` after a successful upload.
    func uploadMenuItemImage(truckID: UUID, itemID: UUID, imageData: Data, contentType: String) async throws -> String
}

protocol AuthService {
    var currentUser: AppUser? { get }
    var supportsGoogleSignIn: Bool { get }
    func signIn(email: String, password: String) async throws -> AppUser
    func signInWithGoogle() async throws -> AppUser
    func signUp(email: String, password: String, role: UserRole) async throws -> String
    func resendVerification(email: String) async throws -> String
    func setCurrentUser(_ user: AppUser?)
    func signOut()
}

private struct SupabaseSession: Codable {
    let accessToken: String
    let refreshToken: String?
}

private enum AuthSessionStore {
    static let currentUserKey = "nightbites.auth.currentUser.v1"
    static let sessionKey = "nightbites.auth.session.v1"

    static func loadCurrentUser() -> AppUser? {
        guard
            let data = UserDefaults.standard.data(forKey: currentUserKey),
            let user = try? JSONDecoder().decode(AppUser.self, from: data)
        else {
            return nil
        }
        return user
    }

    static func saveCurrentUser(_ user: AppUser?) {
        guard let user else {
            UserDefaults.standard.removeObject(forKey: currentUserKey)
            return
        }
        guard let data = try? JSONEncoder().encode(user) else { return }
        UserDefaults.standard.set(data, forKey: currentUserKey)
    }

    static func loadSession() -> SupabaseSession? {
        guard
            let data = UserDefaults.standard.data(forKey: sessionKey),
            let session = try? JSONDecoder().decode(SupabaseSession.self, from: data)
        else {
            return nil
        }
        return session
    }

    static func saveSession(_ session: SupabaseSession?) {
        guard let session else {
            UserDefaults.standard.removeObject(forKey: sessionKey)
            return
        }
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: sessionKey)
    }
}

/// Allows other app types to use the current Supabase JWT without exposing `AuthSessionStore`.
enum SupabaseSessionAccess {
    static var accessToken: String? { AuthSessionStore.loadSession()?.accessToken }
}

struct SupabaseConfig {
    let projectURL: URL
    let anonKey: String

    static func fromBundle() -> SupabaseConfig? {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: urlString),
            let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            !key.isEmpty
        else {
            return nil
        }

        return SupabaseConfig(projectURL: url, anonKey: key)
    }
}

enum AuthError: LocalizedError {
    case invalidCredentials
    case emailNotVerified
    case invalidResponse
    case signupFailed
    case googleSignInUnavailable
    case verificationEmailFailed

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password."
        case .emailNotVerified:
            return "Your email is not verified yet. Check your inbox and verify before signing in."
        case .invalidResponse:
            return "Unexpected auth response from server."
        case .signupFailed:
            return "We couldn't create your account."
        case .googleSignInUnavailable:
            return "Google sign-in is not configured for this build."
        case .verificationEmailFailed:
            return "We couldn't send a verification email right now."
        }
    }
}

final class InMemoryAuthService: AuthService {
    private(set) var currentUser: AppUser?
    var supportsGoogleSignIn: Bool { true }

    init() {
        currentUser = AuthSessionStore.loadCurrentUser()
    }

    func signIn(email: String, password _: String) async throws -> AppUser {
        let role: UserRole = email.localizedCaseInsensitiveContains("owner") ? .owner : .student
        let user = AppUser(id: UUID().uuidString, email: email, role: role)
        setCurrentUser(user)
        return user
    }

    func signUp(email _: String, password _: String, role _: UserRole) async throws -> String {
        "Account created. Check your email to verify before signing in."
    }

    func signInWithGoogle() async throws -> AppUser {
        let user = AppUser(id: UUID().uuidString, email: "google-student@nightbites.app", role: .student)
        setCurrentUser(user)
        return user
    }

    func resendVerification(email: String) async throws -> String {
        "Verification email sent to \(email)."
    }

    func setCurrentUser(_ user: AppUser?) {
        currentUser = user
        AuthSessionStore.saveCurrentUser(user)
    }

    func signOut() {
        setCurrentUser(nil)
    }
}

final class SupabaseAuthService: AuthService {
    private struct SupabaseUserPayload: Decodable {
        let id: String
        let email: String?
    }

    private struct SignInResponse: Decodable {
        let access_token: String?
        let refresh_token: String?
        let user: SupabaseUserPayload?
    }

    private(set) var currentUser: AppUser?
    var supportsGoogleSignIn: Bool {
        AppReleaseConfig.enableGoogleSignIn && AppReleaseConfig.googleOAuthRedirectURL != nil
    }

    private let config: SupabaseConfig
    private let session: URLSession

    init(config: SupabaseConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
        let storedUser = AuthSessionStore.loadCurrentUser()
        let storedSession = AuthSessionStore.loadSession()

        if storedSession == nil, storedUser != nil {
            AuthSessionStore.saveCurrentUser(nil)
            currentUser = nil
        } else {
            currentUser = storedUser
        }
    }

    func signIn(email: String, password: String) async throws -> AppUser {
        struct SignInRequest: Encodable {
            let email: String
            let password: String
        }

        var components = URLComponents(url: config.projectURL.appending(path: "/auth/v1/token"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "password")]

        guard let url = components?.url else {
            throw AuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")

        request.httpBody = try JSONEncoder().encode(SignInRequest(email: email, password: password))

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let authIssue = Self.decodeAuthAPIError(data: data), authIssue.code == "email_not_confirmed" {
                throw AuthError.emailNotVerified
            }
            throw AuthError.invalidCredentials
        }

        let payload = try JSONDecoder().decode(SignInResponse.self, from: data)
        guard let userPayload = payload.user, let accessToken = payload.access_token else {
            throw AuthError.invalidResponse
        }

        let role = (try? await fetchRole(userID: userPayload.id, accessToken: accessToken)) ?? .student
        let user = AppUser(id: userPayload.id, email: userPayload.email ?? email, role: role)
        setAuthenticatedSession(
            user: user,
            accessToken: accessToken,
            refreshToken: payload.refresh_token
        )
        return user
    }

    func signInWithGoogle() async throws -> AppUser {
        guard
            supportsGoogleSignIn,
            let redirectURL = AppReleaseConfig.googleOAuthRedirectURL
        else {
            throw AuthError.googleSignInUnavailable
        }

        var components = URLComponents(url: config.projectURL.appending(path: "/auth/v1/authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: redirectURL.absoluteString)
        ]

        guard let authURL = components?.url else {
            throw AuthError.invalidResponse
        }

        let callbackURL = try await OAuthWebAuthenticationSession.start(
            url: authURL,
            callbackURLScheme: redirectURL.scheme
        )

        guard let oauthTokens = Self.extractTokensFromOAuthCallback(callbackURL) else {
            throw AuthError.invalidResponse
        }

        let userPayload = try await fetchAuthenticatedUser(accessToken: oauthTokens.accessToken)
        let role = (try? await fetchRole(userID: userPayload.id, accessToken: oauthTokens.accessToken)) ?? .student
        let user = AppUser(id: userPayload.id, email: userPayload.email ?? "google-user@nightbites.app", role: role)
        setAuthenticatedSession(
            user: user,
            accessToken: oauthTokens.accessToken,
            refreshToken: oauthTokens.refreshToken
        )
        return user
    }

    func signUp(email: String, password: String, role: UserRole) async throws -> String {
        struct SignUpRequest: Encodable {
            struct UserMetadata: Encodable {
                let role: String
            }

            let email: String
            let password: String
            let data: UserMetadata
        }

        struct SignUpResponse: Decodable {
            struct UserPayload: Decodable {
                let id: String
            }

            let user: UserPayload?
        }

        let url = config.projectURL.appending(path: "/auth/v1/signup")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(
            SignUpRequest(
                email: email,
                password: password,
                data: SignUpRequest.UserMetadata(role: role == .owner ? "owner" : "student")
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw AuthError.signupFailed
        }

        let payload = try JSONDecoder().decode(SignUpResponse.self, from: data)
        if let userID = payload.user?.id {
            try? await upsertProfileRole(userID: userID, role: role)
        }

        return "Account created. Check your email to verify your account, then sign in."
    }

    func resendVerification(email: String) async throws -> String {
        struct VerificationResendRequest: Encodable {
            let type: String
            let email: String
        }

        let url = config.projectURL.appending(path: "/auth/v1/resend")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(VerificationResendRequest(type: "signup", email: email))

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw AuthError.verificationEmailFailed
        }
        return "Verification email sent. Check your inbox and spam folder."
    }

    func setCurrentUser(_ user: AppUser?) {
        currentUser = user
        AuthSessionStore.saveCurrentUser(user)
    }

    func signOut() {
        AuthSessionStore.saveSession(nil)
        setCurrentUser(nil)
    }

    private func setAuthenticatedSession(user: AppUser, accessToken: String, refreshToken: String?) {
        AuthSessionStore.saveSession(
            SupabaseSession(
                accessToken: accessToken,
                refreshToken: refreshToken
            )
        )
        setCurrentUser(user)
    }

    private func fetchRole(userID: String, accessToken: String) async throws -> UserRole {
        struct ProfileRoleResponse: Decodable {
            let role: String?
        }

        var components = URLComponents(url: config.projectURL.appending(path: "/rest/v1/profiles"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "role"),
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components?.url else {
            throw AuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw AuthError.invalidResponse
        }

        let decoded = try JSONDecoder().decode([ProfileRoleResponse].self, from: data)
        let roleValue = decoded.first?.role?.lowercased()
        return roleValue == "owner" ? .owner : .student
    }

    private func fetchAuthenticatedUser(accessToken: String) async throws -> SupabaseUserPayload {
        let url = config.projectURL.appending(path: "/auth/v1/user")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw AuthError.invalidResponse
        }
        return try JSONDecoder().decode(SupabaseUserPayload.self, from: data)
    }

    private func upsertProfileRole(userID: String, role: UserRole) async throws {
        struct ProfileUpsert: Encodable {
            let user_id: String
            let role: String
        }

        let url = config.projectURL.appending(path: "/rest/v1/profiles")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(ProfileUpsert(user_id: userID, role: role == .owner ? "owner" : "student"))

        _ = try await session.data(for: request)
    }

    private struct AuthAPIError: Decodable {
        let code: String?
        let msg: String?
        let error_description: String?
    }

    private static func decodeAuthAPIError(data: Data) -> AuthAPIError? {
        try? JSONDecoder().decode(AuthAPIError.self, from: data)
    }

    private struct OAuthCallbackTokens {
        let accessToken: String
        let refreshToken: String?
    }

    private static func extractTokensFromOAuthCallback(_ url: URL) -> OAuthCallbackTokens? {
        let fragmentItems: [URLQueryItem]
        if let fragment = url.fragment {
            var components = URLComponents()
            components.query = fragment
            fragmentItems = components.queryItems ?? []
        } else {
            fragmentItems = []
        }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let items = fragmentItems + queryItems

        guard let accessToken = items.first(where: { $0.name == "access_token" })?.value, !accessToken.isEmpty else {
            return nil
        }

        let refreshToken = items.first(where: { $0.name == "refresh_token" })?.value
        return OAuthCallbackTokens(accessToken: accessToken, refreshToken: refreshToken)
    }
}

final class InMemoryBackendService: BackendService {
    var isRemoteEnabled: Bool { false }

    func loadSeedData() -> AppSeedData {
        let ucla = Campus(name: "UCLA", latitude: 34.0689, longitude: -118.4452)
        let usc = Campus(name: "USC", latitude: 34.0224, longitude: -118.2851)
        let berkeley = Campus(name: "UC Berkeley", latitude: 37.8719, longitude: -122.2585)

        let campuses = [ucla, usc, berkeley]

        let trucks: [FoodTruck] = [
            FoodTruck(
                ownerUserID: nil,
                name: "Midnight Tacos",
                cuisineType: "Mexican",
                campusName: "UCLA",
                distance: 0.3,
                rating: 4.7,
                ratingCount: 128,
                estimatedWait: 12,
                isOpen: true,
                ordersPaused: false,
                closedEarly: false,
                activeHours: "10:00 AM - 3:00 PM",
                imageName: "taco-truck",
                coverImageURL: "https://images.unsplash.com/photo-1613514785940-daed07799d9b",
                profileImageURL: nil,
                galleryImageURLs: [],
                latitude: 34.0700,
                longitude: -118.4440,
                liveLatitude: 34.0700,
                liveLongitude: -118.4440,
                plan: .pro,
                hasLiveTracking: true,
                proSubscriptionActive: true,
                closingAt: Date().addingTimeInterval(28 * 60)
            ),
            FoodTruck(
                ownerUserID: nil,
                name: "Noodle Orbit",
                cuisineType: "Asian",
                campusName: "UCLA",
                distance: 0.6,
                rating: 4.6,
                ratingCount: 84,
                estimatedWait: 18,
                isOpen: true,
                ordersPaused: false,
                closedEarly: false,
                activeHours: "11:00 AM - 4:00 PM",
                imageName: "noodle-truck",
                coverImageURL: "https://images.unsplash.com/photo-1555126634-323283e090fa",
                profileImageURL: nil,
                galleryImageURLs: [],
                latitude: 34.0677,
                longitude: -118.4470,
                liveLatitude: 34.0677,
                liveLongitude: -118.4470,
                plan: .free,
                hasLiveTracking: false,
                proSubscriptionActive: false
            ),
            FoodTruck(
                ownerUserID: nil,
                name: "Burger Express",
                cuisineType: "American",
                campusName: "USC",
                distance: 0.5,
                rating: 4.5,
                ratingCount: 94,
                estimatedWait: 16,
                isOpen: true,
                ordersPaused: false,
                closedEarly: false,
                activeHours: "9:30 AM - 2:30 PM",
                imageName: "burger-truck",
                coverImageURL: "https://images.unsplash.com/photo-1550547660-d9450f859349",
                profileImageURL: nil,
                galleryImageURLs: [],
                latitude: 34.0230,
                longitude: -118.2872,
                liveLatitude: 34.0230,
                liveLongitude: -118.2872,
                plan: .pro,
                hasLiveTracking: true,
                proSubscriptionActive: true
            ),
            FoodTruck(
                ownerUserID: nil,
                name: "Slice Theory",
                cuisineType: "Pizza",
                campusName: "USC",
                distance: 0.8,
                rating: 4.4,
                ratingCount: 61,
                estimatedWait: 20,
                isOpen: false,
                ordersPaused: true,
                closedEarly: false,
                activeHours: "Closed today",
                imageName: "pizza-truck",
                coverImageURL: "https://images.unsplash.com/photo-1513104890138-7c749659a591",
                profileImageURL: nil,
                galleryImageURLs: [],
                latitude: 34.0211,
                longitude: -118.2832,
                liveLatitude: 34.0211,
                liveLongitude: -118.2832,
                plan: .free,
                hasLiveTracking: false,
                proSubscriptionActive: false
            ),
            FoodTruck(
                ownerUserID: nil,
                name: "Falafel Circuit",
                cuisineType: "Mediterranean",
                campusName: "UC Berkeley",
                distance: 0.4,
                rating: 4.8,
                ratingCount: 144,
                estimatedWait: 14,
                isOpen: true,
                ordersPaused: false,
                closedEarly: false,
                activeHours: "10:30 AM - 5:00 PM",
                imageName: "falafel-truck",
                coverImageURL: "https://images.unsplash.com/photo-1640960543409-dbe56ccc30e2",
                profileImageURL: nil,
                galleryImageURLs: [],
                latitude: 37.8726,
                longitude: -122.2601,
                liveLatitude: 37.8726,
                liveLongitude: -122.2601,
                plan: .pro,
                hasLiveTracking: true,
                proSubscriptionActive: true
            )
        ]

        guard
            let tacoTruck = trucks.first(where: { $0.name == "Midnight Tacos" }),
            let noodleTruck = trucks.first(where: { $0.name == "Noodle Orbit" }),
            let burgerTruck = trucks.first(where: { $0.name == "Burger Express" }),
            let falafelTruck = trucks.first(where: { $0.name == "Falafel Circuit" })
        else {
            return AppSeedData(campuses: campuses, foodTrucks: trucks, menuItems: [], orders: [], reviews: [])
        }

        let smashPattyGroup = MenuModifierGroup(
            name: "Patty",
            isRequired: true,
            minSelection: 1,
            maxSelection: 1,
            options: [
                MenuModifierOption(name: "Single", priceDelta: 0),
                MenuModifierOption(name: "Double", priceDelta: 3)
            ]
        )
        let smashAddOnGroup = MenuModifierGroup(
            name: "Add-ons",
            isRequired: false,
            minSelection: 0,
            maxSelection: 2,
            options: [
                MenuModifierOption(name: "Bacon", priceDelta: 2),
                MenuModifierOption(name: "Fried egg", priceDelta: 1.5)
            ]
        )

        let menuItems = [
            MenuItem(
                name: "Street Taco Trio",
                description: "Three tacos with salsa verde and onions.",
                price: 12.99,
                category: "Main",
                isAvailable: true,
                truckId: tacoTruck.id,
                imageURL: "https://images.unsplash.com/photo-1611250188496-e966043a0629",
                tags: ["Best Seller"]
            ),
            MenuItem(
                name: "Loaded Nachos",
                description: "House chips, queso, pico, jalapeño.",
                price: 10.49,
                category: "Main",
                isAvailable: true,
                truckId: tacoTruck.id,
                imageURL: "https://images.unsplash.com/photo-1582169296194-e4d644c48063",
                tags: ["Sells Out Fast"]
            ),
            MenuItem(
                name: "Midnight Churros",
                description: "Cinnamon sugar, dulce drizzle.",
                price: 5.49,
                category: "Dessert",
                isAvailable: false,
                truckId: tacoTruck.id,
                imageURL: "https://images.unsplash.com/photo-1626082927389-6cd097cdc6ec",
                tags: ["Sold Out"]
            ),
            MenuItem(name: "Garlic Dan Dan", description: "Spicy noodles with ground pork and bok choy.", price: 13.99, category: "Main", isAvailable: true, truckId: noodleTruck.id, imageURL: "https://images.unsplash.com/photo-1617093727343-374698b1b08d"),
            MenuItem(
                name: "Classic Smash",
                description: "Smashed patty, cheddar, pickles, Night aioli.",
                price: 14.99,
                category: "Main",
                isAvailable: true,
                truckId: burgerTruck.id,
                imageURL: "https://images.unsplash.com/photo-1568901346375-23c9450c58cd",
                modifierGroups: [smashPattyGroup, smashAddOnGroup],
                tags: ["Popular"]
            ),
            MenuItem(name: "Fries", description: "Sea salt fries with Night sauce.", price: 4.99, category: "Side", isAvailable: true, truckId: burgerTruck.id, imageURL: "https://images.unsplash.com/photo-1630384060421-cb20d0e0649d"),
            MenuItem(name: "Falafel Bowl", description: "Falafel, rice, cucumber, tahini and greens.", price: 13.49, category: "Main", isAvailable: true, truckId: falafelTruck.id, imageURL: "https://images.unsplash.com/photo-1512621776951-a57141f2eefd")
        ]

        let orders = [
            Order(
                truckID: tacoTruck.id,
                customerUserID: "seed-student-1",
                truckName: "Midnight Tacos",
                campusName: "UCLA",
                items: [OrderItem(menuItem: menuItems[0], quantity: 1)],
                subtotalAmount: menuItems[0].price,
                serviceFeeAmount: 0,
                chargedTotalAmount: menuItems[0].price,
                status: .ready,
                paymentMethod: .applePay,
                orderDate: Date().addingTimeInterval(-2_500),
                estimatedDelivery: Date().addingTimeInterval(600)
            )
        ]

        return AppSeedData(campuses: campuses, foodTrucks: trucks, menuItems: menuItems, orders: orders, reviews: [])
    }

    func syncData() async -> AppSeedData? {
        nil
    }

    func submit(order _: Order) async {}

    func update(orderID _: UUID, status _: OrderStatus) async {}

    func submit(application _: TruckApplication) async {}

    func submit(review _: Review) async {}

    func submit(truck _: FoodTruck) async {}

    func submit(menuItem _: MenuItem, truckName _: String) async -> Bool { true }

    func update(truck _: FoodTruck) async {}

    func update(menuItem _: MenuItem, truckName _: String) async -> Bool { true }

    func uploadMenuItemImage(truckID: UUID, itemID: UUID, imageData: Data, contentType: String) async throws -> String {
        // Offline catalog: use an inline data URL so AsyncImage can show the pick without a server.
        let b64 = imageData.base64EncodedString()
        return "data:\(contentType);base64,\(b64)"
    }
}

final class SupabaseBackendService: BackendService {
    private let config: SupabaseConfig
    private let session: URLSession
    private let fallback: InMemoryBackendService
    private static let menuAssetsBucket = "menu-assets"
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(config: SupabaseConfig, session: URLSession = .shared, fallback: InMemoryBackendService = InMemoryBackendService()) {
        self.config = config
        self.session = session
        self.fallback = fallback
    }

    var isRemoteEnabled: Bool { true }

    func loadSeedData() -> AppSeedData {
        fallback.loadSeedData()
    }

    func syncData() async -> AppSeedData? {
        do {
            let campuses: [CampusRow] = try await fetchRows(table: "campuses")
            let trucks: [FoodTruckRow] = try await fetchRows(table: "food_trucks")
            let menuItems: [MenuItemRow] = try await fetchRows(table: "menu_items")
            let orders: [OrderRow] = try await fetchRows(table: "orders")
            let reviews: [ReviewRow] = try await fetchRows(table: "reviews")

            let campusMap = Dictionary(uniqueKeysWithValues: campuses.map { ($0.name, $0) })

            let mappedCampuses = campuses.map { row in
                Campus(id: row.id, name: row.name, latitude: row.latitude, longitude: row.longitude)
            }

            let mappedTrucks: [FoodTruck] = trucks.map { row in
                FoodTruck(
                    id: row.id,
                    ownerUserID: row.owner_user_id,
                    name: row.name,
                    cuisineType: row.cuisine_type,
                    campusName: row.campus_name,
                    distance: row.distance ?? 0.0,
                    rating: row.rating ?? 4.5,
                    ratingCount: row.rating_count ?? 0,
                    estimatedWait: row.estimated_wait ?? 15,
                    isOpen: row.is_open ?? true,
                    ordersPaused: row.orders_paused ?? false,
                    closedEarly: row.closed_early ?? false,
                    activeHours: row.active_hours ?? "Not set",
                    imageName: row.image_name ?? "food-truck",
                    coverImageURL: row.cover_image_url,
                    profileImageURL: row.profile_image_url,
                    galleryImageURLs: row.gallery_image_urls ?? [],
                    latitude: row.latitude,
                    longitude: row.longitude,
                    liveLatitude: row.live_latitude ?? row.latitude,
                    liveLongitude: row.live_longitude ?? row.longitude,
                    plan: row.plan == "pro" ? .pro : .free,
                    hasLiveTracking: row.has_live_tracking ?? false,
                    proSubscriptionActive: row.pro_subscription_active ?? (row.plan == "pro"),
                    closingAt: row.closing_at.flatMap { Self.iso8601Formatter.date(from: $0) }
                )
            }

            let mappedMenuItems: [MenuItem] = menuItems.compactMap { row in
                let resolvedTruckID = row.truck_id.flatMap(UUID.init(uuidString:))
                    ?? mappedTrucks.first(where: { $0.name == row.truck_name })?.id
                guard let truckId = resolvedTruckID else { return nil }
                return MenuItem(
                    id: row.id,
                    name: row.name,
                    description: row.description,
                    price: row.price,
                    category: row.category,
                    isAvailable: row.is_available,
                    truckId: truckId,
                    imageURL: row.image_url,
                    modifierGroups: row.modifier_groups ?? [],
                    tags: row.tags ?? []
                )
            }

            let mappedOrders: [Order] = orders.compactMap { row in
                let status = OrderStatus(rawValue: row.status) ?? .pending
                let paymentMethod = PaymentMethod(rawValue: row.payment_method) ?? .cash
                let pickupTiming = PickupTiming(rawValue: row.pickup_timing ?? PickupTiming.asap.rawValue) ?? .asap
                let orderItems = (row.items ?? []).map { item in
                    let menuItem = MenuItem(
                        id: item.menu_item_id.flatMap(UUID.init(uuidString:)) ?? UUID(),
                        name: item.name,
                        description: item.description,
                        price: item.price,
                        category: item.category,
                        isAvailable: true,
                        truckId: item.truck_id.flatMap(UUID.init(uuidString:)) ?? UUID(),
                        imageURL: item.image_url,
                        tags: []
                    )
                    return OrderItem(
                        id: item.id.flatMap(UUID.init(uuidString:)) ?? UUID(),
                        menuItem: menuItem,
                        quantity: item.quantity,
                        customization: item.customization
                    )
                }

                return Order(
                    id: row.id,
                    truckID: row.truck_id.flatMap(UUID.init(uuidString:)),
                    customerUserID: row.customer_user_id,
                    truckName: row.truck_name,
                    campusName: row.campus_name,
                    items: orderItems,
                    subtotalAmount: row.subtotal_amount ?? row.total_amount,
                    serviceFeeAmount: row.service_fee_amount ?? 0,
                    chargedTotalAmount: row.charged_total_amount ?? row.total_amount,
                    status: status,
                    paymentMethod: paymentMethod,
                    pickupTiming: pickupTiming,
                    orderDate: row.order_date,
                    estimatedDelivery: row.estimated_delivery,
                    customerName: row.customer_name ?? "Guest",
                    specialInstructions: row.special_instructions
                )
            }
            .sorted { $0.orderDate > $1.orderDate }

            let mappedReviews: [Review] = reviews.compactMap { row in
                guard let truckID = UUID(uuidString: row.truck_id) else { return nil }
                return Review(
                    id: row.id,
                    truckId: truckID,
                    userDisplayName: row.user_display_name,
                    rating: row.rating,
                    text: row.text,
                    mediaURL: row.media_url,
                    createdAt: row.created_at
                )
            }
            .sorted { $0.createdAt > $1.createdAt }

            if mappedCampuses.isEmpty || mappedTrucks.isEmpty || campusMap.isEmpty {
                return nil
            }

            return AppSeedData(
                campuses: mappedCampuses,
                foodTrucks: mappedTrucks,
                menuItems: mappedMenuItems,
                orders: mappedOrders,
                reviews: mappedReviews
            )
        } catch {
            return nil
        }
    }

    func submit(order: Order) async {
        struct OrderInsert: Encodable {
            struct OrderItemInsert: Encodable {
                let id: String
                let menu_item_id: String
                let truck_id: String
                let name: String
                let description: String
                let price: Double
                let category: String
                let image_url: String?
                let quantity: Int
                let customization: String?
            }

            let id: String
            let truck_id: String?
            let customer_user_id: String?
            let truck_name: String
            let campus_name: String
            let customer_name: String
            let subtotal_amount: Double
            let service_fee_amount: Double
            let charged_total_amount: Double
            let total_amount: Double
            let status: String
            let payment_method: String
            let pickup_timing: String
            let order_date: String
            let estimated_delivery: String?
            let special_instructions: String?
            let items: [OrderItemInsert]
        }

        let payload = OrderInsert(
            id: order.id.uuidString,
            truck_id: order.truckID?.uuidString,
            customer_user_id: order.customerUserID,
            truck_name: order.truckName,
            campus_name: order.campusName,
            customer_name: order.customerName,
            subtotal_amount: order.subtotalAmount,
            service_fee_amount: order.serviceFeeAmount,
            charged_total_amount: order.chargedTotalAmount,
            total_amount: order.chargedTotalAmount,
            status: order.status.rawValue,
            payment_method: order.paymentMethod.rawValue,
            pickup_timing: order.pickupTiming.rawValue,
            order_date: Self.iso8601Formatter.string(from: order.orderDate),
            estimated_delivery: order.estimatedDelivery.map(Self.iso8601Formatter.string),
            special_instructions: order.specialInstructions,
            items: order.items.map { item in
                OrderInsert.OrderItemInsert(
                    id: item.id.uuidString,
                    menu_item_id: item.menuItem.id.uuidString,
                    truck_id: item.menuItem.truckId.uuidString,
                    name: item.menuItem.name,
                    description: item.menuItem.description,
                    price: item.menuItem.price,
                    category: item.menuItem.category,
                    image_url: item.menuItem.imageURL,
                    quantity: item.quantity,
                    customization: item.customization
                )
            }
        )

        _ = try? await insertRow(table: "orders", payload: payload)
    }

    func update(orderID: UUID, status: OrderStatus) async {
        struct OrderStatusPatch: Encodable {
            let status: String
        }

        _ = try? await patchRows(
            table: "orders",
            filters: [URLQueryItem(name: "id", value: "eq.\(orderID.uuidString)")],
            payload: OrderStatusPatch(status: status.rawValue)
        )
    }

    func submit(application: TruckApplication) async {
        struct ApplicationInsert: Encodable {
            let truck_name: String
            let owner_name: String
            let cuisine_type: String
            let campus_name: String
            let contact_email: String
            let selected_plan: String
            let created_at: String
            let status: String
        }

        let payload = ApplicationInsert(
            truck_name: application.truckName,
            owner_name: application.ownerName,
            cuisine_type: application.cuisineType,
            campus_name: application.campusName,
            contact_email: application.contactEmail,
            selected_plan: application.selectedPlan.rawValue.lowercased(),
            created_at: Self.iso8601Formatter.string(from: application.createdAt),
            status: application.status.rawValue.lowercased()
        )

        _ = try? await insertRow(table: "truck_applications", payload: payload)
    }

    func submit(review: Review) async {
        struct ReviewInsert: Encodable {
            let id: String
            let truck_id: String
            let user_display_name: String
            let rating: Int
            let text: String
            let media_url: String?
            let created_at: String
        }

        let payload = ReviewInsert(
            id: review.id.uuidString,
            truck_id: review.truckId.uuidString,
            user_display_name: review.userDisplayName,
            rating: review.rating,
            text: review.text,
            media_url: review.mediaURL,
            created_at: Self.iso8601Formatter.string(from: review.createdAt)
        )

        _ = try? await insertRow(table: "reviews", payload: payload)
    }

    func submit(truck: FoodTruck) async {
        struct TruckInsert: Encodable {
            let id: String
            let owner_user_id: String?
            let name: String
            let cuisine_type: String
            let campus_name: String
            let latitude: Double
            let longitude: Double
            let plan: String
            let estimated_wait: Int
            let is_open: Bool
            let orders_paused: Bool
            let closed_early: Bool
            let active_hours: String
            let image_name: String
            let cover_image_url: String?
            let profile_image_url: String?
            let gallery_image_urls: [String]
            let live_latitude: Double
            let live_longitude: Double
            let has_live_tracking: Bool
            let pro_subscription_active: Bool
            let closing_at: String?
        }

        let payload = TruckInsert(
            id: truck.id.uuidString,
            owner_user_id: truck.ownerUserID,
            name: truck.name,
            cuisine_type: truck.cuisineType,
            campus_name: truck.campusName,
            latitude: truck.latitude,
            longitude: truck.longitude,
            plan: truck.plan.rawValue.lowercased(),
            estimated_wait: truck.prepMinutesOverride ?? truck.estimatedWait,
            is_open: truck.isOpen,
            orders_paused: truck.ordersPaused,
            closed_early: truck.closedEarly,
            active_hours: truck.activeHours,
            image_name: truck.imageName,
            cover_image_url: truck.coverImageURL,
            profile_image_url: truck.profileImageURL,
            gallery_image_urls: truck.galleryImageURLs,
            live_latitude: truck.liveLatitude,
            live_longitude: truck.liveLongitude,
            has_live_tracking: truck.hasLiveTracking,
            pro_subscription_active: truck.proSubscriptionActive,
            closing_at: truck.closingAt.map { Self.iso8601Formatter.string(from: $0) }
        )

        _ = try? await insertRow(table: "food_trucks", payload: payload)
    }

    func submit(menuItem: MenuItem, truckName: String) async -> Bool {
        struct MenuItemInsert: Encodable {
            let id: String
            let truck_id: String
            let truck_name: String
            let name: String
            let description: String
            let price: Double
            let category: String
            let is_available: Bool
            let image_url: String?
            let tags: [String]
            let modifier_groups: [MenuModifierGroup]
        }
        let payload = MenuItemInsert(
            id: menuItem.id.uuidString,
            truck_id: menuItem.truckId.uuidString,
            truck_name: truckName,
            name: menuItem.name,
            description: menuItem.description,
            price: menuItem.price,
            category: menuItem.category,
            is_available: menuItem.isAvailable,
            image_url: menuItem.imageURL,
            tags: menuItem.tags,
            modifier_groups: menuItem.modifierGroups
        )
        do {
            _ = try await insertRow(table: "menu_items", payload: payload)
            return true
        } catch {
            AppTelemetry.track(error: "menu_item_submit_failed")
            return false
        }
    }

    func update(truck: FoodTruck) async {
        struct TruckPatch: Encodable {
            let active_hours: String
            let is_open: Bool
            let orders_paused: Bool
            let closed_early: Bool
            let estimated_wait: Int
            let live_latitude: Double
            let live_longitude: Double
            let has_live_tracking: Bool
            let closing_at: String?
        }

        let payload = TruckPatch(
            active_hours: truck.activeHours,
            is_open: truck.isOpen,
            orders_paused: truck.ordersPaused,
            closed_early: truck.closedEarly,
            estimated_wait: truck.prepMinutesOverride ?? truck.estimatedWait,
            live_latitude: truck.liveLatitude,
            live_longitude: truck.liveLongitude,
            has_live_tracking: truck.hasLiveTracking,
            closing_at: truck.closingAt.map { Self.iso8601Formatter.string(from: $0) }
        )

        _ = try? await patchRows(
            table: "food_trucks",
            filters: [URLQueryItem(name: "id", value: "eq.\(truck.id.uuidString)")],
            payload: payload
        )
    }

    func update(menuItem: MenuItem, truckName: String) async -> Bool {
        struct MenuItemPatch: Encodable {
            let truck_id: String
            let truck_name: String
            let name: String
            let description: String
            let price: Double
            let category: String
            let is_available: Bool
            let image_url: String?
            let tags: [String]
            let modifier_groups: [MenuModifierGroup]
        }
        let payload = MenuItemPatch(
            truck_id: menuItem.truckId.uuidString,
            truck_name: truckName,
            name: menuItem.name,
            description: menuItem.description,
            price: menuItem.price,
            category: menuItem.category,
            is_available: menuItem.isAvailable,
            image_url: menuItem.imageURL,
            tags: menuItem.tags,
            modifier_groups: menuItem.modifierGroups
        )

        do {
            _ = try await patchRows(
                table: "menu_items",
                filters: [URLQueryItem(name: "id", value: "eq.\(menuItem.id.uuidString)")],
                payload: payload
            )
            return true
        } catch {
            AppTelemetry.track(error: "menu_item_update_failed")
            return false
        }
    }

    func uploadMenuItemImage(truckID: UUID, itemID: UUID, imageData: Data, contentType: String) async throws -> String {
        let ext: String
        if contentType.contains("png") { ext = "png" } else if contentType.contains("webp") { ext = "webp" } else { ext = "jpg" }
        let uploadUrl = config.projectURL
            .appendingPathComponent("storage/v1/object")
            .appendingPathComponent(Self.menuAssetsBucket)
            .appendingPathComponent(truckID.uuidString)
            .appendingPathComponent("\(itemID.uuidString).\(ext)")

        var request = URLRequest(url: uploadUrl)
        request.httpMethod = "POST"
        request.httpBody = imageData
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")

        _ = try await performAuthorizedRequest(request)
        return publicMenuAssetURL(truckID: truckID, itemID: itemID, fileExtension: ext)
    }

    private func publicMenuAssetURL(truckID: UUID, itemID: UUID, fileExtension: String) -> String {
        var base = config.projectURL.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        return "\(base)/storage/v1/object/public/\(Self.menuAssetsBucket)/\(truckID.uuidString)/\(itemID.uuidString).\(fileExtension)"
    }

    private func fetchRows<T: Decodable>(table: String) async throws -> [T] {
        var components = URLComponents(url: config.projectURL.appending(path: "/rest/v1/\(table)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "select", value: "*")]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, _) = try await performAuthorizedRequest(request)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Self.iso8601Formatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(value)")
        }

        return try decoder.decode([T].self, from: data)
    }

    private func insertRow<T: Encodable>(table: String, payload: T) async throws -> Data {
        let url = config.projectURL.appending(path: "/rest/v1/\(table)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        let (data, _) = try await performAuthorizedRequest(request)

        return data
    }

    private func patchRows<T: Encodable>(table: String, filters: [URLQueryItem], payload: T) async throws -> Data {
        var components = URLComponents(url: config.projectURL.appending(path: "/rest/v1/\(table)"), resolvingAgainstBaseURL: false)
        components?.queryItems = filters

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        let (data, _) = try await performAuthorizedRequest(request)

        return data
    }

    private func performAuthorizedRequest(_ baseRequest: URLRequest, allowRefresh: Bool = true) async throws -> (Data, HTTPURLResponse) {
        let activeSession = AuthSessionStore.loadSession()
        let (data, response) = try await session.data(for: authorizedRequest(baseRequest, accessToken: activeSession?.accessToken))

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if allowRefresh,
           [401, 403].contains(httpResponse.statusCode),
           let refreshedSession = try await refreshSessionIfNeeded() {
            let (retryData, retryResponse) = try await session.data(for: authorizedRequest(baseRequest, accessToken: refreshedSession.accessToken))
            guard let retryHTTPResponse = retryResponse as? HTTPURLResponse, (200 ... 299).contains(retryHTTPResponse.statusCode) else {
                throw URLError(.userAuthenticationRequired)
            }
            return (retryData, retryHTTPResponse)
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return (data, httpResponse)
    }

    private func authorizedRequest(_ baseRequest: URLRequest, accessToken: String?) -> URLRequest {
        var request = baseRequest
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? config.anonKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func refreshSessionIfNeeded() async throws -> SupabaseSession? {
        guard let storedSession = AuthSessionStore.loadSession(),
              let refreshToken = storedSession.refreshToken,
              !refreshToken.isEmpty
        else {
            return nil
        }

        struct RefreshRequest: Encodable {
            let refresh_token: String
        }

        var components = URLComponents(url: config.projectURL.appending(path: "/auth/v1/token"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]

        guard let refreshURL = components?.url else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(RefreshRequest(refresh_token: refreshToken))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            AuthSessionStore.saveSession(nil)
            AuthSessionStore.saveCurrentUser(nil)
            return nil
        }

        struct RefreshResponse: Decodable {
            let access_token: String?
            let refresh_token: String?
        }

        let payload = try JSONDecoder().decode(RefreshResponse.self, from: data)
        guard let accessToken = payload.access_token else {
            throw AuthError.invalidResponse
        }

        let refreshedSession = SupabaseSession(
            accessToken: accessToken,
            refreshToken: payload.refresh_token ?? refreshToken
        )
        AuthSessionStore.saveSession(refreshedSession)
        return refreshedSession
    }
}

private struct CampusRow: Decodable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
}

private struct FoodTruckRow: Decodable {
    let id: UUID
    let owner_user_id: String?
    let name: String
    let cuisine_type: String
    let campus_name: String
    let latitude: Double
    let longitude: Double
    let plan: String
    let distance: Double?
    let rating: Double?
    let rating_count: Int?
    let estimated_wait: Int?
    let is_open: Bool?
    let orders_paused: Bool?
    let closed_early: Bool?
    let active_hours: String?
    let image_name: String?
    let cover_image_url: String?
    let profile_image_url: String?
    let gallery_image_urls: [String]?
    let live_latitude: Double?
    let live_longitude: Double?
    let has_live_tracking: Bool?
    let pro_subscription_active: Bool?
    let closing_at: String?
}

private struct MenuItemRow: Decodable {
    let id: UUID
    let truck_id: String?
    let truck_name: String
    let name: String
    let description: String
    let price: Double
    let category: String
    let is_available: Bool
    let image_url: String?
    let tags: [String]?
    let modifier_groups: [MenuModifierGroup]?
}

private struct OrderRow: Decodable {
    struct ItemRow: Decodable {
        let id: String?
        let menu_item_id: String?
        let truck_id: String?
        let name: String
        let description: String
        let price: Double
        let category: String
        let image_url: String?
        let quantity: Int
        let customization: String?
    }

    let id: UUID
    let truck_id: String?
    let customer_user_id: String?
    let truck_name: String
    let campus_name: String
    let customer_name: String?
    let subtotal_amount: Double?
    let service_fee_amount: Double?
    let charged_total_amount: Double?
    let total_amount: Double
    let status: String
    let payment_method: String
    let pickup_timing: String?
    let order_date: Date
    let estimated_delivery: Date?
    let special_instructions: String?
    let items: [ItemRow]?
}

private struct ReviewRow: Decodable {
    let id: UUID
    let truck_id: String
    let user_display_name: String
    let rating: Int
    let text: String
    let media_url: String?
    let created_at: Date
}
