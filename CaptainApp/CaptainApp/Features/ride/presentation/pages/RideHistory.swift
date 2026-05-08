import SwiftUI
import Foundation

struct CaptainRideHistoryItem: Identifiable {
    let id: String
    let pickupAddress: String
    let dropoffAddress: String
    let fareText: String
    let statusText: String
    let dateText: String
}

@MainActor
final class CaptainRideHistoryViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var rides: [CaptainRideHistoryItem] = []

    func load(authToken: String?, captainId: Int?) {
        guard let token = authToken, !token.isEmpty else {
            errorMessage = L10n.t("ride_history.error.missing_auth")
            return
        }
        guard let captainId else {
            errorMessage = L10n.t("ride_history.error.missing_captain")
            return
        }
        guard let url = ApiConstants.captainRideHistoryUrl(captainId: captainId) else {
            errorMessage = L10n.t("ride_history.error.invalid_endpoint")
            return
        }

        isLoading = true
        errorMessage = nil
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeoutMs / 1000)
        request.addValue("Bearer \(token)", forHTTPHeaderField: ApiConstants.authHeader)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let error {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let data else {
                    self.isLoading = false
                    self.errorMessage = L10n.t("ride_history.error.empty_response")
                    return
                }

                if let http = response as? HTTPURLResponse {
                    guard (200...299).contains(http.statusCode) else {
                        self.isLoading = false
                        let body = String(data: data, encoding: .utf8) ?? ""
                        self.errorMessage = "HTTP \(http.statusCode): \(body.prefix(180))"
                        return
                    }
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) else {
                    self.isLoading = false
                    self.errorMessage = L10n.t("ride_history.error.non_json")
                    return
                }

                let rows = Self.extractRows(from: json)
                self.rides = rows.compactMap(Self.parseRide)
                self.isLoading = false
                self.errorMessage = rows.isEmpty ? L10n.t("ride_history.error.no_rides") : nil
            }
        }.resume()
    }

    private static func extractRows(from json: Any) -> [[String: Any]] {
        if let array = json as? [[String: Any]] { return array }
        guard let dict = json as? [String: Any] else { return [] }

        if let dataArray = dict["data"] as? [[String: Any]] { return dataArray }
        if let ridesArray = dict["rides"] as? [[String: Any]] { return ridesArray }

        if let dataDict = dict["data"] as? [String: Any] {
            if let items = dataDict["items"] as? [[String: Any]] { return items }
            if let rides = dataDict["rides"] as? [[String: Any]] { return rides }
            if let rows = dataDict["history"] as? [[String: Any]] { return rows }
        }

        if let history = dict["history"] as? [[String: Any]] { return history }

        return []
    }

    private static func parseRide(_ row: [String: Any]) -> CaptainRideHistoryItem? {
        let id = toString(row["id"]) ?? toString(row["rideId"]) ?? toString(row["ride_id"]) ?? UUID().uuidString
        let pickup = toString(row["pickupAddress"]) ?? toString(row["pickup_address"]) ?? toString(row["pickup"]) ?? L10n.t("ride_history.pickup")
        let dropoff = toString(row["dropoffAddress"]) ?? toString(row["dropoff_address"]) ?? toString(row["dropoff"]) ?? L10n.t("ride_history.dropoff")

        var fareText = "-"
        if let fare = toDouble(row["fare"]) ?? toDouble(row["totalFare"]) ?? toDouble(row["total_fare"]) {
            fareText = String(format: "$%.2f", fare)
        }

        let statusText = (toString(row["status"]) ?? L10n.t("ride_history.unknown_status")).capitalized

        let rawDate = toString(row["createdAt"]) ?? toString(row["created_at"]) ?? toString(row["date"]) ?? ""
        let dateText = formatDate(rawDate)

        return CaptainRideHistoryItem(
            id: id,
            pickupAddress: pickup,
            dropoffAddress: dropoff,
            fareText: fareText,
            statusText: statusText,
            dateText: dateText
        )
    }
}

struct RideHistoryPage: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var viewModel = CaptainRideHistoryViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("ride_history.title"))
                    .font(.title3.bold())
                Spacer()
                Button(L10n.t("ride_history.refresh")) {
                    viewModel.load(authToken: authViewModel.authToken, captainId: authViewModel.captainId)
                }
                .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppColors.surface)

            ZStack {
                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        ProgressView(L10n.t("ride_history.loading"))
                        Spacer()
                    }
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Spacer()
                        Text(L10n.t("ride_history.failed"))
                            .font(.headline)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(AppColors.error)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Button(L10n.t("ride_history.retry")) {
                            viewModel.load(authToken: authViewModel.authToken, captainId: authViewModel.captainId)
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                } else if viewModel.rides.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Text(L10n.t("ride_history.empty.title"))
                            .font(.headline)
                        Text(L10n.t("ride_history.empty.subtitle"))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.rides) { ride in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(ride.statusText)
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(AppColors.primary)
                                        Spacer()
                                        Text(ride.fareText)
                                            .font(.subheadline.weight(.bold))
                                    }

                                    Text("\(L10n.t("ride_history.pickup")): \(ride.pickupAddress)")
                                        .font(.caption)
                                        .foregroundColor(AppColors.textSecondary)
                                        .lineLimit(1)

                                    Text("\(L10n.t("ride_history.dropoff")): \(ride.dropoffAddress)")
                                        .font(.caption)
                                        .foregroundColor(AppColors.textSecondary)
                                        .lineLimit(1)

                                    if !ride.dateText.isEmpty {
                                        Text(ride.dateText)
                                            .font(.caption2)
                                            .foregroundColor(AppColors.textSecondary)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppColors.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppColors.background)
        .task {
            viewModel.load(authToken: authViewModel.authToken, captainId: authViewModel.captainId)
        }
    }
}

private func toString(_ value: Any?) -> String? {
    if let text = value as? String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    if let number = value as? NSNumber {
        return number.stringValue
    }
    return nil
}

private func toDouble(_ value: Any?) -> Double? {
    if let number = value as? Double { return number }
    if let number = value as? NSNumber { return number.doubleValue }
    if let text = value as? String { return Double(text) }
    return nil
}

private func formatDate(_ raw: String) -> String {
    guard !raw.isEmpty else { return "" }

    let iso = ISO8601DateFormatter()
    if let date = iso.date(from: raw) {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    return raw
}
