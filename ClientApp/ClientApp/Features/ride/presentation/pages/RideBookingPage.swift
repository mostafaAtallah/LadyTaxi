//
//  RideBookingPage.swift
//  ClientApp
//
//  Created by user on 07/02/2026.
//

import SwiftUI
import Combine
// Import the new shared models

// MARK: - Data Models

struct FareEstimate: Codable, Equatable {
    let baseFare: Double
    let distanceKm: Double
    let distanceCost: Double
    let durationMinutes: Int
    let timeCost: Double
    let trafficMultiplier: Double
    let economyFare: Double
    let comfortFare: Double
    let premiumFare: Double
}

struct Vehicle: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let iconName: String
    
    static let vehicleTypes = [ 
        Vehicle(id: "economy", name: L10n.t("ride_booking.vehicle.economy.name"), description: L10n.t("ride_booking.vehicle.economy.description"), iconName: "car.fill"),
        Vehicle(id: "comfort", name: L10n.t("ride_booking.vehicle.comfort.name"), description: L10n.t("ride_booking.vehicle.comfort.description"), iconName: "figure.seated.seatbelt"),
        Vehicle(id: "premium", name: L10n.t("ride_booking.vehicle.premium.name"), description: L10n.t("ride_booking.vehicle.premium.description"), iconName: "star.fill")
    ]
}

struct DriverGender: Identifiable, Equatable {
    let id: String
    let name: String
    let iconName: String
    
    static let genderOptions = [
        DriverGender(id: "any", name: L10n.t("ride_booking.gender.any"), iconName: "person.fill"),
        DriverGender(id: "male", name: L10n.t("ride_booking.gender.male"), iconName: "person.fill"),
        DriverGender(id: "female", name: L10n.t("ride_booking.gender.female"), iconName: "person.fill")
    ]
}

// MARK: - View Model

@MainActor
class RideBookingViewModel: ObservableObject {
    @Published var fareEstimate: FareEstimate?
    @Published var isLoadingFare = false
    @Published var rideState: RideState = .idle
    
    private var cancellables = Set<AnyCancellable>()
    
    // Dependency on TripLocationData
    private let tripLocationData: TripLocationData

    init(tripLocationData: TripLocationData) {
        self.tripLocationData = tripLocationData
    }

    func fetchFareEstimate(vehicleType: String) {
        isLoadingFare = true
        
        var components = URLComponents(string: ApiConstants.baseUrl + ApiConstants.estimateFare)!
        components.queryItems = [
            URLQueryItem(name: "pickupLat", value: "\(tripLocationData.pickupLocation?.latitude ?? 0)"),
            URLQueryItem(name: "pickupLng", value: "\(tripLocationData.pickupLocation?.longitude ?? 0)"),
            URLQueryItem(name: "dropoffLat", value: "\(tripLocationData.dropoffLocation?.latitude ?? 0)"),
            URLQueryItem(name: "dropoffLng", value: "\(tripLocationData.dropoffLocation?.longitude ?? 0)"),
            URLQueryItem(name: "vehicleType", value: vehicleType)
        ]
        
        guard let url = components.url else {
            // Handle invalid URL
            isLoadingFare = false
            return
        }

        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: FareEstimate.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                self?.isLoadingFare = false
                if case .failure(let error) = completion {
                    self?.rideState = .error(error.localizedDescription)
                }
            }, receiveValue: { [weak self] estimate in
                self?.fareEstimate = estimate
            })
            .store(in: &cancellables)
    }
    
    func requestRide(vehicleType: String, driverGender: String) {
        rideState = .loading

        guard let pickup = tripLocationData.pickupLocation,
              let dropoff = tripLocationData.dropoffLocation else {
            rideState = .error(L10n.t("ride_booking.error.missing_locations"))
            return
        }

        guard let url = URL(string: ApiConstants.baseUrl + ApiConstants.requestRide) else {
            rideState = .error(L10n.t("ride_booking.error.invalid_api_url"))
            return
        }

        guard let token = UserDefaults.standard.string(forKey: "auth_token")
                ?? UserDefaults.standard.string(forKey: "token"),
              !token.isEmpty else {
            rideState = .error(L10n.t("ride_booking.error.login_required"))
            return
        }

        let requestBody: [String: Any] = [
            "fromLocation": tripLocationData.pickupAddress,
            "fromLatitude": pickup.latitude,
            "fromLongitude": pickup.longitude,
            "toLocation": tripLocationData.dropoffAddress,
            "toLatitude": dropoff.latitude,
            "toLongitude": dropoff.longitude,
            "price": fareEstimate?.economyFare ?? 0,
            "driverGenderPreference": driverGender
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            rideState = .error(L10n.t("ride_booking.error.request_body"))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeout / 1000)
        request.addValue(ApiConstants.applicationJson, forHTTPHeaderField: ApiConstants.contentType)
        request.addValue("Bearer \(token)", forHTTPHeaderField: ApiConstants.authHeader)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let error {
                    self.rideState = .error("\(L10n.t("ride_booking.error.request_failed")): \(error.localizedDescription)")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.rideState = .error(L10n.t("ride_booking.error.invalid_server_response"))
                    return
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    let message = (data.flatMap { String(data: $0, encoding: .utf8) } ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    self.rideState = .error(message.isEmpty ? "\(L10n.t("ride_booking.error.request_failed_status")) (\(httpResponse.statusCode))." : message)
                    return
                }

                let rideId = Self.extractRideId(from: data) ?? UUID().uuidString
                self.rideState = .searchingForDriver(rideId: rideId)
            }
        }.resume()
    }

    private static func extractRideId(from data: Data?) -> String? {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let rideId = extractRideId(from: json) {
            return rideId
        }

        if let nested = json["data"] as? [String: Any] {
            return extractRideId(from: nested)
        }

        return nil
    }

    private static func extractRideId(from payload: [String: Any]) -> String? {
        let candidateKeys = ["id", "ride_id", "rideId", "RideId", "trip_id", "tripId"]

        for key in candidateKeys {
            if let value = payload[key] {
                let rideId = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !rideId.isEmpty {
                    return rideId
                }
            }
        }

        return nil
    }
}

// MARK: - Ride State Enum

enum RideState: Equatable {
    case idle
    case loading
    case searchingForDriver(rideId: String)
    case error(String)
}

private struct ActiveFindingRide: Identifiable {
    let id: String
}


// MARK: - Main View

struct RideBookingPage: View {
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RideBookingViewModel
    
    // Trip location data
    let tripLocationData: TripLocationData

    init(tripLocationData: TripLocationData) {
        self.tripLocationData = tripLocationData
        _viewModel = StateObject(wrappedValue: RideBookingViewModel(tripLocationData: tripLocationData))
    }
    
    @State private var selectedVehicleType = "economy"
    @State private var selectedPaymentMethod = "cash"
    @State private var selectedDriverGender = "any"
    
    @State private var activeFindingRide: ActiveFindingRide?
    
    var body: some View {
        VStack(spacing: 0) {
            pageHeader

            if viewModel.isLoadingFare && viewModel.fareEstimate == nil {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                content
            }
            
            bottomBar
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            viewModel.fetchFareEstimate(vehicleType: selectedVehicleType)
        }
        .onChange(of: selectedVehicleType) { newType in
            viewModel.fetchFareEstimate(vehicleType: newType)
        }
        .onChange(of: viewModel.rideState) { newState in
            if case .searchingForDriver(let rideId) = newState {
                let trimmedRideId = rideId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedRideId.isEmpty else {
                    print("CLIENT DEBUG: blocked FindingDriverPage presentation because rideId is empty")
                    return
                }
                activeFindingRide = ActiveFindingRide(id: trimmedRideId)
            }
        }
        .fullScreenCover(item: $activeFindingRide) { findingRide in
            NavigationStack {
                FindingDriverPage(
                    rideId: findingRide.id,
                    tripLocationData: tripLocationData,
                    onCancelRequest: {
                        activeFindingRide = nil
                        viewModel.rideState = .idle
                    }
                )
            }
        }
    }

    private var pageHeader: some View {
        HStack {
            Button(action: {
                dismiss()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 16, weight: .semibold))
            }

            Spacer()

            Text(L10n.t("ride_booking.title"))
                .font(.headline)

            Spacer()

            Color.clear
                .frame(width: 60, height: 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }
    
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                routeSummary
                vehicleSelection
                driverGenderPreference
                paymentMethod
            }
            .padding()
        }
    }
    
    private var routeSummary: some View {
        VStack(alignment: .leading) {
            RouteRow(iconName: "circle.fill", color: .green, text: tripLocationData.pickupAddress)
            
            Rectangle()
                .fill(Color.gray)
                .frame(width: 2, height: 30)
                .padding(.leading, 7)

            RouteRow(iconName: "mappin.and.ellipse", color: .red, text: tripLocationData.dropoffAddress)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.0), radius: 10)
    }

    @ViewBuilder
    private var fareBreakdown: some View {
        if let estimate = viewModel.fareEstimate {
            VStack(alignment: .leading) {
                Text(L10n.t("ride_booking.fare_breakdown"))
                    .font(.headline)
                    .fontWeight(.bold)
                
                Divider().padding(.vertical, 4)

                FareBreakdownRow(label: L10n.t("ride_booking.base_fare"), value: formatIQD(estimate.baseFare))
                FareBreakdownRow(label: "\(L10n.t("ride_booking.distance")) (\(String(format: "%.1f", estimate.distanceKm)) \(L10n.t("ride_booking.distance_unit_km")))", value: formatIQD(estimate.distanceCost))
                FareBreakdownRow(label: "\(L10n.t("ride_booking.time")) (\(estimate.durationMinutes) \(L10n.t("ride_booking.time_unit_min")))", value: formatIQD(estimate.timeCost))
                FareBreakdownRow(label: L10n.t("ride_booking.traffic_multiplier"), value: "\(String(format: "%.2f", estimate.trafficMultiplier))x")
            }
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    private var vehicleSelection: some View {
        VStack(alignment: .leading) {
            Text(L10n.t("ride_booking.choose_vehicle"))
                .font(.title2)
                .fontWeight(.bold)
            
            ForEach(Vehicle.vehicleTypes) { vehicle in
                VehicleRow(
                    vehicle: vehicle,
                    price: priceForVehicle(vehicle.id),
                    isSelected: selectedVehicleType == vehicle.id
                )
                .onTapGesture {
                    selectedVehicleType = vehicle.id
                }
            }
        }
    }
    
    private var driverGenderPreference: some View {
        VStack(alignment: .leading) {
            Text(L10n.t("ride_booking.driver_gender_preference"))
                .font(.title2)
                .fontWeight(.bold)
            
            HStack(spacing: 12) {
                ForEach(DriverGender.genderOptions) { gender in
                    GenderOption(
                        gender: gender,
                        isSelected: selectedDriverGender == gender.id
                    )
                    .onTapGesture {
                        selectedDriverGender = gender.id
                    }
                }
            }
        }
    }
    
    private var paymentMethod: some View {
        VStack(alignment: .leading) {
            Text(L10n.t("ride_booking.payment_method"))
                .font(.title2)
                .fontWeight(.bold)
            
            HStack {
                Image(systemName: "creditcard")
                Text(L10n.t("ride_booking.payment.cash"))
                    .fontWeight(.medium)
                Spacer()
                Button(L10n.t("ride_booking.change")) {
                    // Action to change payment method
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 8)
        }
    }
    
    private var bottomBar: some View {
        VStack {
            Divider()
            HStack {
                VStack(alignment: .leading) {
                    Text(L10n.t("ride_booking.total_fare"))
                        .foregroundColor(.secondary)
                    Text(formatIQD(totalFare))
                        .font(.title)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                Button(action: {
                    viewModel.requestRide(
                        vehicleType: selectedVehicleType,
                        driverGender: selectedDriverGender
                    )
                }) {
                    if case .loading = viewModel.rideState {
                        ProgressView()
                    } else {
                        Text(L10n.t("ride_booking.request_ride"))
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                }
                .disabled(viewModel.rideState == .loading)
                .frame(width: 200)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 30) // For safe area
        }
        .background(Color(.systemBackground))
        .shadow(radius: 5)
    }
    
    private var totalFare: Double {
        guard let estimate = viewModel.fareEstimate else { return 0.0 }
        switch selectedVehicleType {
        case "economy": return estimate.economyFare
        case "comfort": return estimate.comfortFare
        case "premium": return estimate.premiumFare
        default: return 0.0
        }
    }
    
    private func priceForVehicle(_ type: String) -> Double {
        guard let estimate = viewModel.fareEstimate else { return 0.0 }
        switch type {
        case "economy": return estimate.economyFare
        case "comfort": return estimate.comfortFare
        case "premium": return estimate.premiumFare
        default: return 0.0
        }
    }

    private func formatIQD(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "IQD"
        formatter.currencySymbol = "IQD "
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "IQD 0"
    }
}


// MARK: - Subviews

struct RouteRow: View {
    let iconName: String
    let color: Color
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundColor(color)
                .font(.system(size: 16))
                .frame(width: 20)
            
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

struct FareBreakdownRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
        .padding(.vertical, 2)
    }
}

struct VehicleRow: View {
    let vehicle: Vehicle
    let price: Double
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Image(systemName: vehicle.iconName)
                .font(.title2)
                .frame(width: 48, height: 48)
                .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray5))
                .cornerRadius(12)
                .foregroundColor(isSelected ? .blue : .secondary)

            VStack(alignment: .leading) {
                Text(vehicle.name).fontWeight(.semibold)
                Text(vehicle.description).font(.caption).foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(formatIQD(price))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(isSelected ? .blue : .primary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.05), radius: 8)
        .padding(.vertical, 4)
    }

    private func formatIQD(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "IQD"
        formatter.currencySymbol = "IQD "
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "IQD 0"
    }
}

struct GenderOption: View {
    let gender: DriverGender
    let isSelected: Bool
    
    var body: some View {
        VStack {
            Image(systemName: gender.iconName)
                .font(.system(size: 28))
            Text(gender.name)
                .fontWeight(.semibold)
                .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.05), radius: 8)
        .foregroundColor(isSelected ? .blue : .primary)
    }
}

// MARK: - Previews

struct RideBookingPage_Previews: PreviewProvider {
    static var previews: some View {
        // Sample TripLocationData for preview purposes
        let sampleTripLocationData = TripLocationData(
            pickupLocation: LocationCoordinate(latitude: 34.0522, longitude: -118.2437),
            dropoffLocation: LocationCoordinate(latitude: 34.1522, longitude: -118.3437),
            pickupAddress: "123 Main St, Anytown",
            dropoffAddress: "456 Oak Ave, Anytown"
        )
        RideBookingPage(tripLocationData: sampleTripLocationData)
    }
}
