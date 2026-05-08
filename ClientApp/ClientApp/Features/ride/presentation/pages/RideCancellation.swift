//
//  RideCancellation.swift
//  ClientApp
//
//  Created by user on 21/02/2026.
//

import SwiftUI
    
struct CancellationReasonItem: Identifiable, Equatable {
    let id = UUID()
    let code: String
    let label: String
}

@MainActor
final class RideCancellationViewModel: ObservableObject {
    @Published var reasons: [CancellationReasonItem] = []
    @Published var selectedCode: String?
    @Published var note: String = ""
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    func loadReasons() {
        let storedLanguageCode = UserDefaults.standard.string(forKey: "app.language.code")
        // Follow app language setting; default to Arabic to match AppLocalizer behavior.
        let languageCode = (storedLanguageCode ?? "ar").lowercased()

        guard var components = URLComponents(string: ApiConstants.baseUrl + ApiConstants.cancellationReasons) else {
            errorMessage = L10n.t("ride_cancellation.error.invalid_reasons_url")
            return
        }
        let langParam = languageCode.hasPrefix("ar") ? "ar" : "en"
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "language", value: langParam)
        ]
        guard let url = components.url else {
            errorMessage = L10n.t("ride_cancellation.error.invalid_reasons_url")
            return
        }

        isLoading = true
        errorMessage = nil

        var request = URLRequest(url: url)
        request.addValue(langParam, forHTTPHeaderField: "Accept-Language")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false

                if let error {
                    self.errorMessage = "\(L10n.t("ride_cancellation.error.load_reasons_details")): \(error.localizedDescription)"
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let data else {
                    self.errorMessage = L10n.t("ride_cancellation.error.load_reasons")
                    return
                }

                guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    self.errorMessage = L10n.t("ride_cancellation.error.invalid_payload")
                    return
                }

                let mapped = self.mapCancellationReasons(raw: raw, languageCode: languageCode)
                self.reasons = mapped
                if self.selectedCode == nil {
                    self.selectedCode = mapped.first?.code
                }
            }
        }.resume()
    }

    private func mapCancellationReasons(
        raw: [[String: Any]],
        languageCode: String
    ) -> [CancellationReasonItem] {
        let isArabic = languageCode.hasPrefix("ar")
        return raw.compactMap { row in
            let code = extractString(from: row, keys: ["code", "Code"]) ?? ""
            guard !code.isEmpty else { return nil }

            let label = extractString(from: row, keys: ["label", "Label"]) ?? ""
            let arLabel = extractString(from: row, keys: [
                "arLabel",
                "ArLabel",
                "labelAr",
                "labelAR",
                "label_ar",
                "ar_label",
                "arabicLabel",
                "labelArabic",
                "name_ar",
                "ar_name",
                "title_ar",
                "ar_title"
            ])

            let serverLabel = (isArabic && !(arLabel ?? "").isEmpty) ? (arLabel ?? "") : label
            let localizedLabel = L10n.t("ride_cancellation.reason.\(code.lowercased())")
            let finalLabel = (localizedLabel == "ride_cancellation.reason.\(code.lowercased())")
                ? serverLabel
                : localizedLabel
            return CancellationReasonItem(code: code, label: finalLabel)
        }
    }

    private func extractString(from row: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = row[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    func submitCancellation(rideId: String, onSuccess: @escaping () -> Void) {
        guard let selectedCode, !selectedCode.isEmpty else {
            errorMessage = L10n.t("ride_cancellation.error.select_reason")
            return
        }

        guard let token = UserDefaults.standard.string(forKey: "auth_token")
                ?? UserDefaults.standard.string(forKey: "token"),
              !token.isEmpty else {
            errorMessage = L10n.t("ride_cancellation.error.login_again")
            return
        }

        let path = ApiConstants.cancelRide.replacingOccurrences(of: "{id}", with: rideId)
        guard let url = URL(string: ApiConstants.baseUrl + path) else {
            errorMessage = L10n.t("ride_cancellation.error.invalid_cancel_url")
            return
        }

        var body: [String: Any] = ["reasonCode": selectedCode]
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            body["note"] = trimmedNote
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            errorMessage = L10n.t("ride_cancellation.error.prepare_request")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeout / 1000)
        request.addValue(ApiConstants.applicationJson, forHTTPHeaderField: ApiConstants.contentType)
        request.addValue("Bearer \(token)", forHTTPHeaderField: ApiConstants.authHeader)

        isSubmitting = true
        errorMessage = nil
        successMessage = nil

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSubmitting = false

                if let error {
                    self.errorMessage = "\(L10n.t("ride_cancellation.error.cancel_failed_details")): \(error.localizedDescription)"
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.errorMessage = L10n.t("ride_cancellation.error.invalid_server_response")
                    return
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    let serverMessage = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    self.errorMessage = serverMessage.isEmpty ? "\(L10n.t("ride_cancellation.error.cancel_failed_status")) (\(httpResponse.statusCode))." : serverMessage
                    return
                }

                let socket = WebSocketService.shared
                socket.connectIfNeeded(token: token)
                socket.send(event: "cancel_ride", data: ["ride_id": rideId]) { sent in
                    if !sent {
                        print("RideCancellation: cancel_ride websocket send failed for ride \(rideId)")
                    }
                }

                self.successMessage = L10n.t("ride_cancellation.success")
                onSuccess()
            }
        }.resume()
    }
}

struct RideCancellationPage: View {
    let rideId: String
    var onCancelled: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = RideCancellationViewModel()

    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.t("ride_cancellation.title"))
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(L10n.t("ride_cancellation.subtitle"))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.isLoading {
                ProgressView(L10n.t("ride_cancellation.loading"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(viewModel.reasons) { reason in
                            Button {
                                viewModel.selectedCode = reason.code
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(reason.label)
                                            .foregroundColor(.primary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    Image(systemName: viewModel.selectedCode == reason.code ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(viewModel.selectedCode == reason.code ? .blue : .gray)
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(10)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("ride_cancellation.optional_note"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField(L10n.t("ride_cancellation.note_placeholder"), text: $viewModel.note)
                    .textFieldStyle(.roundedBorder)
            }

            if let error = viewModel.errorMessage, !error.isEmpty {
                Text(error)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button(L10n.t("ride_cancellation.back")) {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)

                Button(viewModel.isSubmitting ? L10n.t("ride_cancellation.submitting") : L10n.t("ride_cancellation.confirm")) {
                    viewModel.submitCancellation(rideId: rideId) {
                        dismiss()
                        onCancelled()
                    }
                }
                .disabled(viewModel.isSubmitting || viewModel.selectedCode == nil)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadReasons()
        }
    }
}
