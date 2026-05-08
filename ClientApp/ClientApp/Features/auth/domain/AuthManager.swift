import Foundation
import Combine
import SwiftUI // For @MainActor

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var isAuthenticated: Bool = false {
        didSet {
            // Potentially publish a notification or log state changes
            if isAuthenticated {
                print("AuthManager: User is now authenticated.")
            } else {
                print("AuthManager: User is now unauthenticated.")
            }
        }
    }

    private var authTokenKey: String = "auth_token"
    private var userIdKey: String = "user_id"
    private var authUserIdKey: String = "auth_user_id"
    private var userStorageKey: String = "auth_user"

    init() {
        checkAuthStatus()
    }

    func checkAuthStatus() {
        if let token = UserDefaults.standard.string(forKey: authTokenKey), !token.isEmpty {
            isAuthenticated = true
        } else {
            isAuthenticated = false
        }
    }

    func login(token: String, userId: String?) {
        UserDefaults.standard.set(token, forKey: authTokenKey)
        if let userId {
            UserDefaults.standard.set(userId, forKey: userIdKey)
            UserDefaults.standard.set(userId, forKey: authUserIdKey)
        }
        isAuthenticated = true
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: authTokenKey)
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: authUserIdKey)
        UserDefaults.standard.removeObject(forKey: userStorageKey)
        isAuthenticated = false
    }

    func getToken() -> String? {
        UserDefaults.standard.string(forKey: authTokenKey)
            ?? UserDefaults.standard.string(forKey: "token")
            ?? UserDefaults.standard.string(forKey: "access_token")
    }

    func saveUser(_ user: User) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userStorageKey)
        }
        UserDefaults.standard.set(String(user.id), forKey: authUserIdKey)
        UserDefaults.standard.set(String(user.id), forKey: userIdKey)
    }

    // You might add methods here to handle API calls that return 401,
    // and automatically call logout() when that happens.
    // This would typically involve a custom URLSessionDelegate or network layer.
}
