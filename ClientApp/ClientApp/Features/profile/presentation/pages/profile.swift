import SwiftUI

struct ClientProfile {
    let id: Int?
    let firstName: String
    let familyName: String
    let fullName: String
    let email: String
    let phoneNumber: String
    let gender: String

    static let empty = ClientProfile(
        id: nil,
        firstName: "",
        familyName: "",
        fullName: L10n.t("profile.default_client"),
        email: "",
        phoneNumber: "",
        gender: ""
    )
}

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profile: ClientProfile = .empty
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadProfile(authManager: AuthManager) {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        Task {
            let token = authManager.getToken()
            let userId = UserDefaults.standard.string(forKey: "auth_user_id")

            do {
                // Try the configured endpoint first.
                if let profile = try await fetchCustomerProfile(token: token) {
                    self.profile = profile
                    self.isLoading = false
                    return
                }

                // Fallback to users endpoint if customer profile endpoint is unavailable.
                if let userId, !userId.isEmpty, let profile = try await fetchUserById(userId: userId, token: token) {
                    self.profile = profile
                    self.isLoading = false
                    return
                }

                self.errorMessage = L10n.t("profile.error.unable_load")
                self.isLoading = false
            } catch {
                self.errorMessage = "\(L10n.t("profile.error.load_details")): \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private func fetchCustomerProfile(token: String?) async throws -> ClientProfile? {
        guard let url = URL(string: ApiConstants.baseUrl + ApiConstants.customerProfile) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeout / 1000)
        if let token, !token.isEmpty {
            request.addValue("Bearer \(token)", forHTTPHeaderField: ApiConstants.authHeader)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        guard (200...299).contains(http.statusCode) else { return nil }
        return parseProfile(from: data)
    }

    private func fetchUserById(userId: String, token: String?) async throws -> ClientProfile? {
        guard let url = URL(string: ApiConstants.baseUrl + "/api/users/\(userId)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeout / 1000)
        if let token, !token.isEmpty {
            request.addValue("Bearer \(token)", forHTTPHeaderField: ApiConstants.authHeader)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        guard (200...299).contains(http.statusCode) else { return nil }
        return parseProfile(from: data)
    }

    private func parseProfile(from data: Data) -> ClientProfile? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Support direct object and wrapped { data: {...} } response styles.
        let source = (json["data"] as? [String: Any]) ?? json

        let firstName = source["firstName"] as? String ?? ""
        let familyName = source["familyName"] as? String ?? ""
        let fullNameFromApi = source["fullName"] as? String ?? ""
        let fullName = fullNameFromApi.isEmpty
            ? [firstName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
            : fullNameFromApi

        let email = source["email"] as? String ?? ""
        let phoneNumber = source["phoneNumber"] as? String ?? ""
        let gender = source["gender"] as? String ?? ""

        let id: Int?
        if let intId = source["id"] as? Int {
            id = intId
        } else if let stringId = source["id"] as? String {
            id = Int(stringId)
        } else {
            id = nil
        }

        return ClientProfile(
            id: id,
            firstName: firstName,
            familyName: familyName,
            fullName: fullName.isEmpty ? L10n.t("profile.default_client") : fullName,
            email: email,
            phoneNumber: phoneNumber,
            gender: gender
        )
    }
}

struct ProfilePage: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showingLogoutAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    profileHeader
                    menuList
                    logoutSection
                    Text(L10n.t("profile.version"))
                        .font(.footnote)
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle(L10n.t("profile.title"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {}) {
                        Image(systemName: "pencil")
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView(L10n.t("profile.loading"))
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .onAppear {
                viewModel.loadProfile(authManager: authManager)
            }
            .alert(L10n.t("profile.logout"), isPresented: $showingLogoutAlert) {
                Button(L10n.t("profile.cancel"), role: .cancel) {}
                Button(L10n.t("profile.logout"), role: .destructive) {
                    authManager.logout()
                }
            } message: {
                Text(L10n.t("profile.logout.confirm"))
            }
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(AppColors.inputFill)
                .frame(width: 100, height: 100)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 44))
                        .foregroundColor(AppColors.textSecondary)
                )

            Text(viewModel.profile.fullName)
                .font(.title2.bold())

            if !viewModel.profile.phoneNumber.isEmpty {
                Text(viewModel.profile.phoneNumber)
                    .foregroundColor(AppColors.textSecondary)
            } else if !viewModel.profile.email.isEmpty {
                Text(viewModel.profile.email)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(AppColors.surface)
    }

    private var menuList: some View {
        VStack(spacing: 2) {
            profileMenuItem(icon: "mappin.and.ellipse", title: L10n.t("profile.menu.saved_places"), subtitle: L10n.t("profile.menu.saved_places.subtitle"))
            profileMenuItem(icon: "creditcard", title: L10n.t("profile.menu.payment_methods"), subtitle: L10n.t("profile.menu.payment_methods.subtitle"))
            profileMenuItem(icon: "tag", title: L10n.t("profile.menu.promotions"), subtitle: L10n.t("profile.menu.promotions.subtitle"))
            profileMenuItem(icon: "bell", title: L10n.t("profile.menu.notifications"), subtitle: L10n.t("profile.menu.notifications.subtitle"))
            profileMenuItem(icon: "shield", title: L10n.t("profile.menu.safety"), subtitle: L10n.t("profile.menu.safety.subtitle"))
            profileMenuItem(icon: "questionmark.circle", title: L10n.t("profile.menu.help_support"), subtitle: L10n.t("profile.menu.help_support.subtitle"))
            profileMenuItem(icon: "info.circle", title: L10n.t("profile.menu.about"), subtitle: L10n.t("profile.menu.about.subtitle"))
        }
        .background(AppColors.surface)
    }

    private var logoutSection: some View {
        VStack(spacing: 8) {
            if let error = viewModel.errorMessage, !error.isEmpty {
                Text(error)
                    .foregroundColor(AppColors.error)
                    .font(.footnote)
            }

            Button {
                showingLogoutAlert = true
            } label: {
                Text(L10n.t("profile.logout"))
                    .foregroundColor(AppColors.error)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppColors.error, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func profileMenuItem(icon: String, title: String, subtitle: String) -> some View {
        Button(action: {}) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppColors.inputFill)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: icon)
                            .foregroundColor(AppColors.primary)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundColor(AppColors.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
    }
}

struct ProfilePage_Previews: PreviewProvider {
    static var previews: some View {
        ProfilePage()
            .environmentObject(AuthManager())
    }
}
