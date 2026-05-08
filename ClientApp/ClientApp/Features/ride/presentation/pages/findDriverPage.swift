import SwiftUI
import Combine

struct FindingDriverPage: View {
    @Environment(\.dismiss) private var dismiss

    let rideId: String
    let tripLocationData: TripLocationData
    var onCancelRequest: (() -> Void)? = nil

    @State private var animationProgress: CGFloat = 0.0
    @State private var navigateToRideTracking = false
    @State private var showingCancelAlert = false
    @State private var cancelSent = false

    @State private var driverName = L10n.t("ride_finding.default_driver")
    @State private var vehicleInfo = L10n.t("ride_finding.default_vehicle")
    @State private var driverId: String?
    @State private var acceptSocketSubscription: AnyCancellable?
    @State private var statusSocketSubscription: AnyCancellable?
    @State private var statusPollSubscription: AnyCancellable?

    private let socketService = WebSocketService.shared

    var body: some View {
        VStack {
            HStack {
                Button {
                    showingCancelAlert = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.title2)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)

            Spacer()

            TimelineView(.animation(minimumInterval: 0.05, paused: false)) { timeline in
                Canvas { context, size in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    animationProgress = fmod(now, 2.0) / 2.0

                    let center = CGPoint(x: size.width / 2, y: size.height / 2)

                    for i in 0..<3 {
                        let delay = CGFloat(i) * 0.3
                        let progress = fmod(animationProgress + delay, 1.0)

                        let currentWidth = 100 + (progress * 100)
                        let currentHeight = 100 + (progress * 100)
                        let opacity = 1.0 - progress

                        let rect = CGRect(
                            x: center.x - currentWidth / 2,
                            y: center.y - currentHeight / 2,
                            width: currentWidth,
                            height: currentHeight
                        )

                        context.stroke(
                            Path(ellipseIn: rect),
                            with: .color(AppColors.primary.opacity(opacity * 0.3)),
                            lineWidth: 2
                        )
                    }

                    let carSize: CGFloat = 80
                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - carSize / 2, y: center.y - carSize / 2, width: carSize, height: carSize)),
                        with: .color(AppColors.primary)
                    )

                    let carSymbol = context.resolve(
                        Text(Image(systemName: "car.fill"))
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    )
                    context.draw(carSymbol, at: center)
                }
                .frame(width: 200, height: 200)
            }

            Spacer().frame(height: 48)

            Text(L10n.t("ride_finding.title"))
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer().frame(height: 8)

            Text(L10n.t("ride_finding.subtitle"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
                .foregroundColor(AppColors.textSecondary)

            Spacer()

            Button {
                showingCancelAlert = true
            } label: {
                Text(L10n.t("ride_finding.cancel_request"))
                    .font(.headline)
                    .foregroundColor(AppColors.error)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppColors.error, lineWidth: 1)
                    )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            print("CLIENT DEBUG: FindingDriverPage appeared for ride \(rideId)")
            subscribeToSocketEvents()
            connectAndSendFindDriver()
            startStatusPolling()
        }
        .onDisappear {
            if !navigateToRideTracking && !cancelSent {
                cancelCurrentRideRequest()
            }
            acceptSocketSubscription?.cancel()
            acceptSocketSubscription = nil
            statusSocketSubscription?.cancel()
            statusSocketSubscription = nil
            statusPollSubscription?.cancel()
            statusPollSubscription = nil
        }
        .alert(L10n.t("ride_finding.cancel_alert_title"), isPresented: $showingCancelAlert) {
            Button(L10n.t("ride_finding.cancel_keep"), role: .cancel) {}
            Button(L10n.t("ride_finding.cancel_confirm"), role: .destructive) {
                cancelCurrentRideRequest()
                onCancelRequest?()
                dismiss()
            }
        } message: {
            Text(L10n.t("ride_finding.cancel_alert_message"))
        }
        .navigationDestination(isPresented: $navigateToRideTracking) {
            RideTrackingPage(
                rideId: rideId,
                pickupLat: tripLocationData.pickupLocation?.latitude ?? 0,
                pickupLng: tripLocationData.pickupLocation?.longitude ?? 0,
                dropoffLat: tripLocationData.dropoffLocation?.latitude ?? 0,
                dropoffLng: tripLocationData.dropoffLocation?.longitude ?? 0,
                driverId: driverId,
                driverName: driverName,
                vehicleInfo: vehicleInfo
            )
        }
    }

    private func subscribeToSocketEvents() {
        print("CLIENT DEBUG: subscribing to ride accept/status events for ride \(rideId)")
        acceptSocketSubscription = socketService.rideAcceptedPublisher
            .receive(on: DispatchQueue.main)
            .sink { payload in
                print("CLIENT DEBUG: rideAcceptedPublisher payload for ride \(rideId): \(payload)")
                handleAcceptedRidePayload(payload)
            }

        statusSocketSubscription = socketService.rideStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { payload in
                print("CLIENT DEBUG: rideStatusPublisher payload for ride \(rideId): \(payload)")
                handleRideStatusPayload(payload)
            }
    }

    private func connectAndSendFindDriver() {
        print("CLIENT DEBUG: connectAndSendFindDriver for ride \(rideId)")
        socketService.connectIfNeeded()
        socketService.sendFindDriverRequest(rideId: rideId, tripLocationData: tripLocationData)
    }

    private func cancelCurrentRideRequest() {
        guard !navigateToRideTracking else { return }
        guard !cancelSent else { return }
        cancelSent = true
        socketService.send(
            event: "cancel_ride",
            data: ["ride_id": rideId]
        )
    }

    private func startStatusPolling() {
        statusPollSubscription = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                fetchTripStatus()
            }
    }

    private func fetchTripStatus() {
        guard !navigateToRideTracking else { return }

        guard let token = UserDefaults.standard.string(forKey: "auth_token")
                ?? UserDefaults.standard.string(forKey: "token"),
              !token.isEmpty else {
            return
        }

        let path = ApiConstants.rideDetails.replacingOccurrences(of: "{id}", with: rideId)
        guard let url = URL(string: ApiConstants.baseUrl + path) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: ApiConstants.authHeader)
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeout / 1000)

        let completion: (Data?, URLResponse?, Error?) -> Void = { data, response, _ in
            guard let httpResponse = response as? HTTPURLResponse else { return }
            guard (200...299).contains(httpResponse.statusCode) else { return }
            guard let responseData = data else { return }
            guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else { return }

            let payload = (json["data"] as? [String: Any]) ?? json
            let status = normalizedStatus(from: payload)
            print("CLIENT DEBUG: polled trip payload for ride \(rideId) status=\(status) payload=\(payload)")
            guard isDriverAssignedPayload(payload, status: status) else { return }

            let captainName = resolvedCaptainName(from: payload)
            let captainIdValue = resolvedCaptainId(from: payload)
            let make = resolvedString(from: payload, keys: ["vehicleMake", "VehicleMake", "vehicle_make"])
            let model = resolvedString(from: payload, keys: ["vehicleModel", "VehicleModel", "vehicle_model"])
            let plate = resolvedString(from: payload, keys: ["vehiclePlate", "VehiclePlate", "vehicle_plate"])
            let builtVehicleInfo = [make, model, plate].filter { !$0.isEmpty }.joined(separator: " • ")

            DispatchQueue.main.async {
                self.driverName = captainName.isEmpty ? L10n.t("ride_finding.default_driver") : captainName
                if let captainIdValue {
                    self.driverId = String(captainIdValue)
                }
                self.vehicleInfo = builtVehicleInfo.isEmpty ? L10n.t("ride_finding.default_vehicle") : builtVehicleInfo
                self.navigateToRideTracking = true
            }
        }

        URLSession.shared.dataTask(with: request, completionHandler: completion).resume()
    }

    private func handleAcceptedRidePayload(_ payload: [String: Any]) {
        let acceptedRideId = String(describing: payload["ride_id"] ?? payload["rideId"] ?? "")
        print("CLIENT DEBUG: handleAcceptedRidePayload acceptedRideId=\(acceptedRideId) expected=\(rideId)")
        guard acceptedRideId == rideId else { return }
        applyAssignedDriverPayload(payload)
    }

    private func handleRideStatusPayload(_ payload: [String: Any]) {
        let statusRideId = String(describing: payload["ride_id"] ?? payload["rideId"] ?? "")
        print("CLIENT DEBUG: handleRideStatusPayload statusRideId=\(statusRideId) expected=\(rideId)")
        guard statusRideId == rideId else { return }

        let status = normalizedStatus(from: payload)
        guard isDriverAssignedPayload(payload, status: status) else { return }
        applyAssignedDriverPayload(payload)
    }

    private func applyAssignedDriverPayload(_ payload: [String: Any]) {
        print("CLIENT DEBUG: applyAssignedDriverPayload for ride \(rideId) payload=\(payload)")
        let acceptedDriverName = (payload["driver_name"] as? String)
            ?? (payload["captainName"] as? String)
            ?? (payload["CaptainName"] as? String)
        let acceptedDriverId = payload["driver_id"] ?? payload["captainId"] ?? payload["CaptainId"]
        let make = (payload["vehicle_make"] as? String) ?? (payload["vehicleMake"] as? String) ?? (payload["VehicleMake"] as? String) ?? ""
        let model = (payload["vehicle_model"] as? String) ?? (payload["vehicleModel"] as? String) ?? (payload["VehicleModel"] as? String) ?? ""
        let plate = (payload["vehicle_plate"] as? String) ?? (payload["vehiclePlate"] as? String) ?? (payload["VehiclePlate"] as? String) ?? ""

        driverName = (acceptedDriverName?.isEmpty == false) ? (acceptedDriverName ?? L10n.t("ride_finding.default_driver")) : L10n.t("ride_finding.default_driver")
        if let acceptedDriverId {
            driverId = String(describing: acceptedDriverId)
        }
        vehicleInfo = [make, model, plate]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")

        if vehicleInfo.isEmpty {
            vehicleInfo = L10n.t("ride_finding.default_vehicle")
        }

        if !navigateToRideTracking {
            print("CLIENT DEBUG: navigating to RideTrackingPage for ride \(rideId)")
            navigateToRideTracking = true
        }
    }

    private func normalizedStatus(from payload: [String: Any]) -> String {
        String(describing: payload["status"] ?? payload["ride_status"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func resolvedCaptainName(from payload: [String: Any]) -> String {
        resolvedString(from: payload, keys: ["captainName", "CaptainName", "driver_name"], fallback: L10n.t("ride_finding.default_driver"))
    }

    private func resolvedCaptainId(from payload: [String: Any]) -> Int? {
        if let intValue = payload["captainId"] as? Int { return intValue }
        if let stringValue = payload["captainId"] as? String, let intValue = Int(stringValue) { return intValue }
        if let intValue = payload["CaptainId"] as? Int { return intValue }
        if let stringValue = payload["CaptainId"] as? String, let intValue = Int(stringValue) { return intValue }
        if let intValue = payload["driver_id"] as? Int { return intValue }
        if let stringValue = payload["driver_id"] as? String, let intValue = Int(stringValue) { return intValue }
        return nil
    }

    private func resolvedString(from payload: [String: Any], keys: [String], fallback: String = "") -> String {
        for key in keys {
            if let value = payload[key] as? String, !value.isEmpty {
                return value
            }
        }
        return fallback
    }

    private func isDriverAssignedStatus(_ status: String) -> Bool {
        switch status {
        case "accepted", "inprogress", "arriving", "reached_pickup", "client_in_car":
            return true
        default:
            return false
        }
    }

    private func isDriverAssignedPayload(_ payload: [String: Any], status: String) -> Bool {
        if isDriverAssignedStatus(status) {
            return true
        }

        let hasCaptainId = resolvedCaptainId(from: payload) != nil
        return hasCaptainId
    }
}

struct FindingDriverPage_Previews: PreviewProvider {
    static var previews: some View {
        let sampleTripLocationData = TripLocationData(
            pickupLocation: LocationCoordinate(latitude: 34.0522, longitude: -118.2437),
            dropoffLocation: LocationCoordinate(latitude: 34.1522, longitude: -118.3437),
            pickupAddress: "123 Main St, Anytown",
            dropoffAddress: "456 Oak Ave, Anytown"
        )
        FindingDriverPage(
            rideId: UUID().uuidString,
            tripLocationData: sampleTripLocationData
        )
    }
}
