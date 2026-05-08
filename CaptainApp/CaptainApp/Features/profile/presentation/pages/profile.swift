import SwiftUI
import Foundation

struct CaptainProfileData {
    var fullName: String = L10n.t("profile.default_captain")
    var rating: Double = 0
    var isVerified: Bool = false
    var totalTrips: Int = 0
    var experienceText: String = "-"
    var acceptanceRateText: String = "-"
    var vehicleInfo: String = L10n.t("profile.not_available")
}

@MainActor
final class CaptainProfileViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var profile = CaptainProfileData()

    func load(authToken: String?, captainId: Int?) {
        guard let captainId else {
            errorMessage = L10n.t("profile.error.missing_captain_id")
            return
        }
        guard let url = ApiConstants.captainProfileUrl(captainId: captainId) else {
            errorMessage = L10n.t("profile.error.invalid_endpoint")
            return
        }

        isLoading = true
        errorMessage = nil

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeoutMs / 1000)
        if let token = authToken, !token.isEmpty {
            request.addValue("Bearer \(token)", forHTTPHeaderField: ApiConstants.authHeader)
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false

                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.errorMessage = L10n.t("profile.error.invalid_response")
                    return
                }

                let payload = Self.extractPayload(from: json)
                self.profile = Self.parseProfile(payload)
            }
        }.resume()
    }

    private static func extractPayload(from json: [String: Any]) -> [String: Any] {
        if let data = json["data"] as? [String: Any] { return data }
        if let profile = json["profile"] as? [String: Any] { return profile }
        if let driver = json["driver"] as? [String: Any] { return driver }
        return json
    }

    private static func parseProfile(_ payload: [String: Any]) -> CaptainProfileData {
        var result = CaptainProfileData()

        let firstName = asString(payload["firstName"]) ?? asString(payload["FirstName"]) ?? asString(payload["first_name"]) ?? ""
        let familyName = asString(payload["familyName"]) ?? asString(payload["FamilyName"]) ?? asString(payload["family_name"]) ?? ""
        let combined = "\(firstName) \(familyName)".trimmingCharacters(in: .whitespaces)
        result.fullName = combined.isEmpty ? (asString(payload["UserName"]) ?? asString(payload["name"]) ?? asString(payload["fullName"]) ?? L10n.t("profile.default_captain")) : combined

        result.rating = asDouble(payload["Rating"]) ?? asDouble(payload["rating"]) ?? asDouble(payload["averageRating"]) ?? asDouble(payload["average_rating"]) ?? 0
        result.isVerified = asBool(payload["IsVerified"]) ?? asBool(payload["isVerified"]) ?? asBool(payload["verified"]) ?? false

        result.totalTrips = asInt(payload["TotalRides"]) ?? asInt(payload["totalTrips"]) ?? asInt(payload["total_trips"]) ?? asInt(payload["completedTrips"]) ?? 0

        if let experienceYears = asDouble(payload["experienceYears"]) ?? asDouble(payload["experience_years"]) {
            result.experienceText = "\(String(format: "%.1f", experienceYears)) \(L10n.t("profile.year_unit"))"
        } else {
            result.experienceText = asString(payload["experience"]) ?? "-"
        }

        if let acceptance = asDouble(payload["acceptanceRate"]) ?? asDouble(payload["acceptance_rate"]) {
            result.acceptanceRateText = "\(Int(acceptance.rounded()))%"
        } else {
            result.acceptanceRateText = asString(payload["acceptance"]) ?? "-"
        }

        if let vehicle = payload["vehicle"] as? [String: Any] {
            let make = asString(vehicle["make"]) ?? ""
            let model = asString(vehicle["model"]) ?? ""
            let plate = asString(vehicle["plateNumber"]) ?? asString(vehicle["plate_number"]) ?? ""
            let vehicleTitle = "\(make) \(model)".trimmingCharacters(in: .whitespaces)
            let text = [vehicleTitle, plate].filter { !$0.isEmpty }.joined(separator: " • ")
            result.vehicleInfo = text.isEmpty ? L10n.t("profile.not_available") : text
        } else {
            let make = asString(payload["VehicleMake"]) ?? asString(payload["vehicleMake"]) ?? ""
            let model = asString(payload["VehicleModel"]) ?? asString(payload["vehicleModel"]) ?? ""
            let plate = asString(payload["PlateNumber"]) ?? asString(payload["plateNumber"]) ?? asString(payload["plate_number"]) ?? ""
            let vehicleTitle = "\(make) \(model)".trimmingCharacters(in: .whitespaces)
            let text = [vehicleTitle, plate].filter { !$0.isEmpty }.joined(separator: " • ")
            result.vehicleInfo = text.isEmpty ? (asString(payload["vehicleInfo"]) ?? asString(payload["vehicle_info"]) ?? L10n.t("profile.not_available")) : text
        }

        return result
    }
}

struct ProfilePage: View {
    enum ProfileDestination {
        case vehicleInfo
        case documents
        case paymentMethods
        case rideHistory
        case notifications
        case support
        case settings
    }

    enum PassengerPreference: String, CaseIterable, Identifiable {
        case any
        case female
        case male

        var id: String { rawValue }

        var title: String {
            switch self {
            case .any: return L10n.t("profile.preference.any")
            case .female: return L10n.t("profile.preference.female")
            case .male: return L10n.t("profile.preference.male")
            }
        }

        var icon: String {
            switch self {
            case .any: return "person.fill"
            case .female: return "figure.stand.dress.line.vertical.figure"
            case .male: return "figure.stand"
            }
        }
    }

    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CaptainProfileViewModel()

    @State private var currentPassengerPreference: PassengerPreference = .any
    @State private var selectedPassengerPreference: PassengerPreference = .any
    @State private var showPassengerPreferenceSheet = false
    @State private var showLanguageSheet = false
    @State private var showLogoutDialog = false
    @State private var isLoggingOut = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(spacing: 0) {
                    profileHeader
                    Color.clear.frame(height: 16)

                    menuNavigationItem(
                        icon: "car.fill",
                        title: L10n.t("profile.vehicle_info"),
                        subtitle: viewModel.profile.vehicleInfo,
                        destination: .vehicleInfo
                    )
                    menuNavigationItem(
                        icon: "doc.text.fill",
                        title: L10n.t("profile.documents"),
                        subtitle: L10n.t("profile.documents.subtitle"),
                        destination: .documents
                    )
                    menuNavigationItem(
                        icon: "wallet.pass.fill",
                        title: L10n.t("profile.payment_methods"),
                        subtitle: L10n.t("profile.payment_methods.subtitle"),
                        destination: .paymentMethods
                    )
                    menuNavigationItem(
                        icon: "clock.fill",
                        title: L10n.t("profile.ride_history"),
                        subtitle: L10n.t("profile.ride_history.subtitle"),
                        destination: .rideHistory
                    )
                    menuNavigationItem(
                        icon: "bell.fill",
                        title: L10n.t("profile.notifications"),
                        subtitle: L10n.t("profile.notifications.subtitle"),
                        destination: .notifications
                    )
                    menuItem(icon: "figure.2", title: L10n.t("profile.passenger_preferences"), subtitle: L10n.t("profile.passenger_preferences.subtitle")) {
                        selectedPassengerPreference = currentPassengerPreference
                        showPassengerPreferenceSheet = true
                    }
                    menuNavigationItem(
                        icon: "questionmark.circle.fill",
                        title: L10n.t("profile.help_support"),
                        subtitle: L10n.t("profile.help_support.subtitle"),
                        destination: .support
                    )
                    menuNavigationItem(
                        icon: "gearshape.fill",
                        title: L10n.t("profile.settings"),
                        subtitle: L10n.t("profile.settings.subtitle"),
                        destination: .settings
                    )
                    menuItem(
                        icon: "globe",
                        title: L10n.t("profile.language"),
                        subtitle: L10n.t("profile.language.subtitle")
                    ) {
                        showLanguageSheet = true
                    }

                    VStack(spacing: 16) {
                        Button(L10n.t("profile.logout")) {
                            showLogoutDialog = true
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundColor(AppColors.error)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.error, lineWidth: 1)
                        )
                        .disabled(isLoggingOut)

                        Text("\(L10n.t("profile.version")) 1.0.0")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(16)
                    Color.clear.frame(height: 24)
                }
            }
        }
        .background(AppColors.background)
        .sheet(isPresented: $showPassengerPreferenceSheet) {
            passengerPreferenceSheet
        }
        .sheet(isPresented: $showLanguageSheet) {
            languageSheet
        }
        .alert(L10n.t("profile.logout.confirm_title"), isPresented: $showLogoutDialog) {
            Button(L10n.t("profile.cancel"), role: .cancel) {}
            Button(L10n.t("profile.logout"), role: .destructive) {
                performLogout()
            }
        } message: {
            Text(L10n.t("profile.logout.confirm_message"))
        }
        .task {
            viewModel.load(authToken: authViewModel.authToken, captainId: authViewModel.captainId)
        }
        .onChange(of: viewModel.profile.isVerified) { _, isVerified in
            authViewModel.isCaptainVerified = isVerified
        }
    }

    private func performLogout() {
        isLoggingOut = true

        guard let url = ApiConstants.logoutUrl else {
            finalizeLogout()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeoutMs / 1000)
        if let token = authViewModel.authToken, !token.isEmpty {
            request.addValue("Bearer \(token)", forHTTPHeaderField: ApiConstants.authHeader)
        }

        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                finalizeLogout()
            }
        }.resume()
    }

    private func finalizeLogout() {
        authViewModel.authToken = nil
        authViewModel.captainId = nil
        authViewModel.isCaptainVerified = false
        authViewModel.state = .idle
        isLoggingOut = false
        dismiss()
    }

    private var topBar: some View {
        HStack {
            Text(L10n.t("profile.title"))
                .font(.title3.bold())
            Spacer()
            Button(action: {}) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.surface)
    }

    private var profileHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppColors.inputFill)
                    .frame(width: 100, height: 100)
                Image(systemName: "person.fill")
                    .font(.system(size: 48))
                    .foregroundColor(AppColors.textSecondary)
            }

            if viewModel.isLoading {
                ProgressView()
            }

            Text(viewModel.profile.fullName)
                .font(.system(size: 24, weight: .bold))

            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                Text(String(format: "%.2f", viewModel.profile.rating))
                    .font(.system(size: 16, weight: .medium))
                Text(viewModel.profile.isVerified ? L10n.t("profile.verified") : L10n.t("profile.unverified"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(viewModel.profile.isVerified ? AppColors.success : AppColors.error)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((viewModel.profile.isVerified ? AppColors.success : AppColors.error).opacity(0.1))
                    .clipShape(Capsule())
            }

            HStack {
                statColumn(value: "\(viewModel.profile.totalTrips)", label: L10n.t("profile.trips"))
                Spacer()
                statColumn(value: viewModel.profile.experienceText, label: L10n.t("profile.experience"))
                Spacer()
                statColumn(value: viewModel.profile.acceptanceRateText, label: L10n.t("profile.acceptance"))
            }
            .padding(.top, 8)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(AppColors.error)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(AppColors.surface)
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
            Text(label)
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func destinationView(for destination: ProfileDestination) -> some View {
        switch destination {
        case .vehicleInfo:
            profilePlaceholderPage(
                title: L10n.t("profile.vehicle_info"),
                subtitle: viewModel.profile.vehicleInfo
            )
        case .documents:
            profilePlaceholderPage(
                title: L10n.t("profile.documents"),
                subtitle: L10n.t("profile.documents.placeholder")
            )
        case .paymentMethods:
            profilePlaceholderPage(
                title: L10n.t("profile.payment_methods"),
                subtitle: L10n.t("profile.payment_methods.placeholder")
            )
        case .rideHistory:
            RideHistoryPage()
        case .notifications:
            profilePlaceholderPage(
                title: L10n.t("profile.notifications"),
                subtitle: L10n.t("profile.notifications.placeholder")
            )
        case .support:
            profilePlaceholderPage(
                title: L10n.t("profile.help_support"),
                subtitle: L10n.t("profile.help_support.placeholder")
            )
        case .settings:
            profilePlaceholderPage(
                title: L10n.t("profile.settings"),
                subtitle: L10n.t("profile.settings.placeholder")
            )
        }
    }

    private func profilePlaceholderPage(title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func menuNavigationItem(
        icon: String,
        title: String,
        subtitle: String,
        destination: ProfileDestination
    ) -> some View {
        NavigationLink {
            destinationView(for: destination)
        } label: {
            menuRow(icon: icon, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }

    private func menuItem(
        icon: String,
        title: String,
        subtitle: String,
        onTap: (() -> Void)? = nil
    ) -> some View {
        Button(action: { onTap?() }) {
            menuRow(icon: icon, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }

    private func menuRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColors.inputFill)
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .foregroundColor(AppColors.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
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
        .padding(.vertical, 10)
        .background(AppColors.surface)
    }

    private var passengerPreferenceSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.t("profile.passenger_preference.description"))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)

                ForEach(PassengerPreference.allCases) { option in
                    Button {
                        selectedPassengerPreference = option
                    } label: {
                        HStack {
                            Image(systemName: option.icon)
                                .frame(width: 22)
                            Text(option.title)
                            Spacer()
                            Image(systemName: selectedPassengerPreference == option ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(selectedPassengerPreference == option ? AppColors.primary : AppColors.textSecondary)
                        }
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.vertical, 4)
                    }
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle(L10n.t("profile.passenger_preference.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("profile.cancel")) {
                        showPassengerPreferenceSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("profile.save")) {
                        currentPassengerPreference = selectedPassengerPreference
                        showPassengerPreferenceSheet = false
                    }
                }
            }
        }
    }

    private var languageSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.t("profile.language.description"))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)

                languageOption(title: L10n.t("profile.language.arabic"), language: .arabic)
                languageOption(title: L10n.t("profile.language.english"), language: .english)

                Spacer()
            }
            .padding(20)
            .navigationTitle(L10n.t("profile.language"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("profile.cancel")) {
                        showLanguageSheet = false
                    }
                }
            }
        }
    }

    private func languageOption(title: String, language: AppLanguage) -> some View {
        Button {
            languageSettings.setLanguage(language)
            showLanguageSheet = false
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: languageSettings.language == language ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(languageSettings.language == language ? AppColors.primary : AppColors.textSecondary)
            }
            .foregroundColor(AppColors.textPrimary)
            .padding(.vertical, 4)
        }
    }
}

private func asString(_ value: Any?) -> String? {
    if let text = value as? String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    if let number = value as? NSNumber {
        return number.stringValue
    }
    return nil
}

private func asDouble(_ value: Any?) -> Double? {
    if let number = value as? Double { return number }
    if let number = value as? NSNumber { return number.doubleValue }
    if let text = value as? String { return Double(text) }
    return nil
}

private func asInt(_ value: Any?) -> Int? {
    if let number = value as? Int { return number }
    if let number = value as? NSNumber { return number.intValue }
    if let text = value as? String { return Int(text) }
    return nil
}

private func asBool(_ value: Any?) -> Bool? {
    if let value = value as? Bool { return value }
    if let number = value as? NSNumber { return number.intValue != 0 }
    if let text = value as? String {
        switch text.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }
    return nil
}
