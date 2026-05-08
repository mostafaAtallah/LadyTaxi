import SwiftUI

struct RideHistoryItem: Identifiable, Decodable {
    let id: Int
    let fromLocation: String
    let toLocation: String
    let price: Double
    let status: String
    let createdAt: String
    let completedAt: String?
    let captainName: String?
    let vehicleMake: String?
    let vehicleModel: String?
    let vehiclePlate: String?

    var formattedPrice: String {
        String(format: "$%.2f", price)
    }

    var vehicleSummary: String {
        [vehicleMake, vehicleModel, vehiclePlate]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    var rideDateText: String {
        Self.formatBackendDate(createdAt)
    }

    private static func formatBackendDate(_ raw: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: raw) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }

        return raw
    }
}

@MainActor
final class RideHistoryViewModel: ObservableObject {
    @Published var rides: [RideHistoryItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func fetchHistory() {
        guard !isLoading else { return }

        guard let token = UserDefaults.standard.string(forKey: "auth_token")
            ?? UserDefaults.standard.string(forKey: "token"),
              !token.isEmpty else {
            errorMessage = L10n.t("ride_history.error.missing_auth")
            return
        }

        guard let url = URL(string: ApiConstants.baseUrl + ApiConstants.rideHistory) else {
            errorMessage = L10n.t("ride_history.error.invalid_endpoint")
            return
        }

        isLoading = true
        errorMessage = nil

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeout / 1000)
        request.addValue("Bearer \(token)", forHTTPHeaderField: ApiConstants.authHeader)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false

                if let error {
                    self.errorMessage = "\(L10n.t("ride_history.error.load_details")): \(error.localizedDescription)"
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.errorMessage = L10n.t("ride_history.error.invalid_response")
                    return
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    let message = (data.flatMap { String(data: $0, encoding: .utf8) } ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    self.errorMessage = message.isEmpty
                        ? "\(L10n.t("ride_history.error.load_status")) (\(httpResponse.statusCode))."
                        : message
                    return
                }

                guard let data else {
                    self.errorMessage = L10n.t("ride_history.error.empty_response")
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    let items = try decoder.decode([RideHistoryItem].self, from: data)
                    self.rides = items.sorted { $0.id > $1.id }
                } catch {
                    self.errorMessage = L10n.t("ride_history.error.invalid_format")
                }
            }
        }.resume()
    }
}

struct HistoryPage: View {
    @StateObject private var viewModel = RideHistoryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView(L10n.t("ride_history.loading"))
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .foregroundColor(AppColors.error)
                            .multilineTextAlignment(.center)
                        Button(L10n.t("ride_history.retry")) {
                            viewModel.fetchHistory()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if viewModel.rides.isEmpty {
                    Text(L10n.t("ride_history.empty"))
                        .foregroundColor(AppColors.textSecondary)
                } else {
                    List(viewModel.rides) { ride in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(ride.status.capitalized)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                  .padding(.vertical, 4)
                                    .background(statusColor(ride.status).opacity(0.15))
                                    .foregroundColor(statusColor(ride.status))
                                    .clipShape(Capsule())

                                Spacer()

                    Text(ride.formattedPrice)
                                    .font(.headline)
                            }

                            Text(ride.fromLocation)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            Text("\(L10n.t("ride_history.to")) \(ride.toLocation)")
                                .font(.subheadline)
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(1)

                            Text(ride.rideDateText)
                                .font(.footnote)
                                .foregroundColor(AppColors.textSecondary)

                            if let captain = ride.captainName, !captain.isEmpty {
                                Text("\(L10n.t("ride_history.captain")): \(captain)")
                                    .font(.footnote)
                            }

                            if !ride.vehicleSummary.isEmpty {
                                Text(ride.vehicleSummary)
                                    .font(.footnote)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(L10n.t("ride_history.title"))
            .onAppear {
                viewModel.fetchHistory()
            }
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "completed": return AppColors.rideCompleted
        case "cancelled": return AppColors.rideCancelled
        case "accepted", "arriving": return AppColors.rideAccepted
        case "in_progress", "inprogress": return AppColors.rideInProgress
        default: return AppColors.rideSearching
        }
    }
}
