//
//  RideTrackingPage.swift
//  ClientApp
//
//  Created by user on 08/02/2026.
//          

import SwiftUI
import MapKit
import Combine
import CoreLocation // Required for CLLocationManager
import UIKit
import ContactsUI

extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

// MARK: - Helper Structs for MapKit

struct CustomAnnotation: Identifiable, Equatable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let tint: Color
    var title: String? = nil
}

struct CustomPolyline: Identifiable, Equatable {

    
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let color: Color
    let width: CGFloat
}

// MARK: - Ride Tracking View Model

class RideTrackingViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var mapRegion: MKCoordinateRegion
    @Published var cameraPosition: MapCameraPosition
    @Published var annotations: [CustomAnnotation] = []
    @Published var polylines: [CustomPolyline] = []
    @Published var arrivalTimeSeconds: Int?
    @Published var currentRideStatus: String = ""
    @Published var isRideCompleted = false
    
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var driverLocation: CLLocationCoordinate2D?
    
    // Ride details
    let rideId: String
    let driverId: String?
    let pickupCoordinate: CLLocationCoordinate2D
    let dropoffCoordinate: CLLocationCoordinate2D
    let driverName: String
    let vehicleInfo: String
    
    private let locationManager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()
    private let socketService = WebSocketService.shared
    private var isInitialCameraAnimationDone = false
    private var lastCameraCenter: CLLocationCoordinate2D?
    private var routeCache: [String: [CLLocationCoordinate2D]] = [:]
    private var routeRequestSignature: [String: String] = [:]
    private var isRequestingRoute: [String: Bool] = [:]
    
    init(rideId: String, driverId: String?, pickupLat: Double, pickupLng: Double, dropoffLat: Double, dropoffLng: Double, driverName: String, vehicleInfo: String) {
        self.rideId = rideId
        self.driverId = driverId
        self.pickupCoordinate = Self.normalizedCoordinate(lat: pickupLat, lng: pickupLng)
        self.dropoffCoordinate = Self.normalizedCoordinate(lat: dropoffLat, lng: dropoffLng)
        self.driverName = driverName
        self.vehicleInfo = vehicleInfo
        
        let initialCenter = Self.preferredCenter(pickup: self.pickupCoordinate, dropoff: self.dropoffCoordinate)
        let initialRegion = MKCoordinateRegion(
            center: initialCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        _mapRegion = Published(initialValue: initialRegion)
        _cameraPosition = Published(initialValue: .region(initialRegion))
        
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()

        subscribeToDriverLocation()
        subscribeToRideStatus()
        startRideStatusPolling()
    }

    deinit {
        cancellables.removeAll()
    }
    
    func setupMap() {
        // Initial setup for markers
        updateMarkers()
        let staticPoints = [pickupCoordinate, dropoffCoordinate].filter { Self.isUsableCoordinate($0) }
        animateCamera(to: staticPoints)
    }
    
    func requestUserLocation() {
        locationManager.startUpdatingLocation()
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latestLocation = locations.first else { return }
        userLocation = latestLocation.coordinate
        updateMarkers()
        drawPolyline()
        
        let driverLoc = driverLocation ?? pickupCoordinate
        if !isInitialCameraAnimationDone {
            animateCamera(to: [userLocation!, driverLoc, dropoffCoordinate])
            isInitialCameraAnimationDone = true
            lastCameraCenter = userLocation
        } else {
            // Animate to user/driver if moved significantly (e.g. 50 meters)
            if let last = lastCameraCenter {
                let current = userLocation!
                let dist = calculateDistance(from: last, to: current)
                if dist > 0.05 { // 50m
                    animateCamera(to: [userLocation!, driverLoc])
                    lastCameraCenter = current
                }
            } else {
                animateCamera(to: [userLocation!, driverLoc])
                lastCameraCenter = userLocation
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Failed to get user location: \(error.localizedDescription)")
    }
    
    func updateMarkers() {
        var newAnnotations: [CustomAnnotation] = []
        
        // Pickup marker
        newAnnotations.append(CustomAnnotation(id: "pickup", coordinate: pickupCoordinate, tint: .green, title: L10n.t("ride_tracking.pickup")))
        
        // Dropoff marker
        newAnnotations.append(CustomAnnotation(id: "dropoff", coordinate: dropoffCoordinate, tint: .red, title: L10n.t("ride_tracking.dropoff")))
        
        // Current user location marker
        if let userLoc = userLocation {
            newAnnotations.append(CustomAnnotation(id: "user", coordinate: userLoc, tint: .blue, title: L10n.t("home.location.current")))
        }
        
        // Driver location marker
        if let driverLoc = driverLocation {
            newAnnotations.append(CustomAnnotation(id: "driver", coordinate: driverLoc, tint: .yellow, title: driverName))
        }
        
        annotations = newAnnotations
    }
    
    func drawPolyline() {
        var newPolylines: [CustomPolyline] = []

        if let driverLoc = driverLocation {
            // Priority 1: Driver to Client (Actual current location)
            if let clientLoc = userLocation, !Self.areCoordinatesClose(driverLoc, clientLoc, thresholdMeters: 30) {
                let routeId = "driverToClient"
                if let cached = routeCache[routeId], cached.count > 2 {
                    newPolylines.append(
                        CustomPolyline(id: routeId, coordinates: cached, color: .blue, width: 6)
                    )
                } else {
                    // Fallback is thin and gray to distinguish from road directions
                    newPolylines.append(
                        CustomPolyline(id: routeId + "_fallback", coordinates: [driverLoc, clientLoc], color: .gray.opacity(0.4), width: 2)
                    )
                }
                requestRouteIfNeeded(id: routeId, from: driverLoc, to: clientLoc)
            } 
            // Priority 2: Fallback Driver to Pickup point if client location unknown
            else if !Self.areCoordinatesClose(driverLoc, pickupCoordinate, thresholdMeters: 30) {
                let routeId = "driverToPickup"
                if let cached = routeCache[routeId], cached.count > 2 {
                    newPolylines.append(
                        CustomPolyline(id: routeId, coordinates: cached, color: .blue, width: 5)
                    )
                } else {
                    newPolylines.append(
                        CustomPolyline(id: routeId + "_fallback", coordinates: [driverLoc, pickupCoordinate], color: .gray.opacity(0.4), width: 2)
                    )
                }
                requestRouteIfNeeded(id: routeId, from: driverLoc, to: pickupCoordinate)
            }
        }

        if Self.isUsableCoordinate(pickupCoordinate) && Self.isUsableCoordinate(dropoffCoordinate) {
            let routeId = "pickupToDropoff"
            if let cached = routeCache[routeId], cached.count > 2 {
                newPolylines.append(
                    CustomPolyline(id: routeId, coordinates: cached, color: .purple, width: 5)
                )
            } else {
                newPolylines.append(
                    CustomPolyline(id: routeId + "_fallback", coordinates: [pickupCoordinate, dropoffCoordinate], color: .gray.opacity(0.3), width: 2)
                )
            }
            requestRouteIfNeeded(id: routeId, from: pickupCoordinate, to: dropoffCoordinate)
        }

        polylines = newPolylines
    }

    private func requestRouteIfNeeded(id: String, from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) {
        guard Self.isUsableCoordinate(from), Self.isUsableCoordinate(to) else { return }

        let signature = Self.routeSignature(from: from, to: to)
        // If we already have a successful route for this coordinate pair, skip
        if routeRequestSignature[id] == signature {
            return
        }
        
        // Prevent flooding/overlapping requests
        if isRequestingRoute[id] == true { return }
        isRequestingRoute[id] = true

        Task { [weak self] in
            guard let self = self else { return }
            let result = await self.fetchBackendRoute(from: from, to: to)
            
            await MainActor.run {
                self.isRequestingRoute[id] = false
                if result.points.count > 1 {
                    self.routeCache[id] = result.points
                    
                    // Update arrival time if this is the driver's route to client/pickup
                    if id == "driverToClient" || id == "driverToPickup" {
                        self.arrivalTimeSeconds = result.duration
                    }
                    
                    self.routeRequestSignature[id] = signature // Only set signature on success
                    self.drawPolyline()
                }
            }
        }
    }

    private func fetchBackendRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> (points: [CLLocationCoordinate2D], duration: Int?) {
        var baseUrl = ApiConstants.baseUrl
        if baseUrl.hasSuffix("/") { baseUrl.removeLast() }
        
        let urlString = "\(baseUrl)\(ApiConstants.getRoute)?startLat=\(from.latitude)&startLng=\(from.longitude)&endLat=\(to.latitude)&endLng=\(to.longitude)"
        
        guard let url = URL(string: urlString) else { return ([], nil) }
        
        do {
            var request = URLRequest(url: url)
            if let token = UserDefaults.standard.string(forKey: "auth_token") ?? UserDefaults.standard.string(forKey: "token") {
                request.addValue("Bearer \(token)", forHTTPHeaderField: ApiConstants.authHeader)
            }
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            struct RoutePoint: Codable {
                let lat: Double
                let lng: Double
            }
            struct RouteResponse: Codable {
                let points: [RoutePoint]
                let totalDuration: Int?
            }
            
            let decoder = JSONDecoder()
            let response = try decoder.decode(RouteResponse.self, from: data)
            
            return (response.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }, response.totalDuration)
        } catch {
            print("Backend Route Error: \(error.localizedDescription)")
            return await fetchBackendRouteLowercase(url: url)
        }
    }

    private func fetchBackendRouteLowercase(url: URL) async -> (points: [CLLocationCoordinate2D], duration: Int?) {
        do {
            var request = URLRequest(url: url)
            if let token = UserDefaults.standard.string(forKey: "auth_token") ?? UserDefaults.standard.string(forKey: "token") {
                request.addValue("Bearer \(token)", forHTTPHeaderField: ApiConstants.authHeader)
            }
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let pointsData = (json["Points"] as? [[String: Any]]) ?? (json["points"] as? [[String: Any]])
                let duration = (json["TotalDuration"] as? Int) ?? (json["totalDuration"] as? Int)
                
                let points = pointsData?.compactMap { p -> CLLocationCoordinate2D? in
                    let lat = (p["Lat"] as? Double) ?? (p["lat"] as? Double)
                    let lng = (p["Lng"] as? Double) ?? (p["lng"] as? Double)
                    if let lat, let lng { return CLLocationCoordinate2D(latitude: lat, longitude: lng) }
                    return nil
                } ?? []
                
                return (points, duration)
            }
        } catch {
            print("Backend Route Retry Error: \(error.localizedDescription)")
        }
        return ([], nil)
    }

    private func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        // ... (keep decodePolyline for local use if needed, though we now use backend points)
        var coordinates = [CLLocationCoordinate2D]()
        var index = encoded.startIndex
        var lat = 0
        var lng = 0

        while index < encoded.endIndex {
            func decodeComponent() -> Int {
                var result = 0
                var shift = 0
                var byte: Int
                repeat {
                    byte = Int(encoded[index].asciiValue! - 63)
                    index = encoded.index(after: index)
                    result |= (byte & 0x1F) << shift
                    shift += 5
                } while byte >= 0x20
                return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            }
            lat += decodeComponent()
            lng += decodeComponent()
            coordinates.append(CLLocationCoordinate2D(latitude: Double(lat) / 1E5, longitude: Double(lng) / 1E5))
        }
        return coordinates
    }
    
    func animateCamera(to coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return }
        
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLng = coordinates[0].longitude
        var maxLng = coordinates[0].longitude
        
        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLng = min(minLng, coord.longitude)
            maxLng = max(maxLng, coord.longitude)
        }
        
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let span = MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.5, longitudeDelta: (maxLng - minLng) * 1.5) // Add some padding
        let updatedRegion = MKCoordinateRegion(center: center, span: span)
        mapRegion = updatedRegion
        cameraPosition = .region(updatedRegion)
    }
    
    // MARK: - Distance Calculation (Haversine Formula)
    func calculateDistance(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let earthRadiusKm = 6371.0
        
        let lat1Rad = start.latitude * .pi / 180.0
        let lon1Rad = start.longitude * .pi / 180.0
        let lat2Rad = end.latitude * .pi / 180.0
        let lon2Rad = end.longitude * .pi / 180.0
        
        let dLon = lon2Rad - lon1Rad
        let dLat = lat2Rad - lat1Rad
        
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1Rad) * cos(lat2Rad) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        
        return earthRadiusKm * c
    }
    
    func subscribeToDriverLocation() {
        socketService.driverLocationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                guard let self else { return }

                // Robust ID matching - compare only digits to avoid string/int mismatches
                let eventDriverId = self.extractId(payload["driver_id"] ?? payload["id"])
                let expectedDriverId = self.extractId(self.driverId)

                if !expectedDriverId.isEmpty && !eventDriverId.isEmpty && eventDriverId != expectedDriverId {
                    return
                }

                let lat = Self.parseDouble(payload["latitude"]) ?? Self.parseDouble(payload["lat"])
                let lng = Self.parseDouble(payload["longitude"]) ?? Self.parseDouble(payload["lng"])

                guard let lat, let lng else { return }
                let coordinate = Self.normalizedCoordinate(lat: lat, lng: lng)
                guard Self.isUsableCoordinate(coordinate) else { return }

                self.driverLocation = coordinate
                print("DEBUG: Driver location updated to: \(coordinate.latitude), \(coordinate.longitude)")
                self.updateMarkers()
                self.drawPolyline()
                
                // Update camera
                let driverLoc = coordinate
                if let userLoc = self.userLocation {
                    self.animateCamera(to: [userLoc, driverLoc])
                } else {
                    self.animateCamera(to: [driverLoc, self.pickupCoordinate])
                }
            }
            .store(in: &cancellables)
    }

    private func subscribeToRideStatus() {
        socketService.rideStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                self?.handleRideStatusPayload(payload)
            }
            .store(in: &cancellables)
    }

    private func startRideStatusPolling() {
        Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchRideStatus()
            }
            .store(in: &cancellables)
    }

    private func fetchRideStatus() {
        guard !isRideCompleted else { return }
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

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self,
                  let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode),
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            let payload = (json["data"] as? [String: Any]) ?? json
            DispatchQueue.main.async {
                self.handleRideStatusPayload(payload)
            }
        }.resume()
    }

    private func handleRideStatusPayload(_ payload: [String: Any]) {
        let payloadRideId = String(describing: payload["ride_id"] ?? payload["rideId"] ?? payload["id"] ?? "")
        if !payloadRideId.isEmpty && payloadRideId != rideId {
            return
        }

        let status = Self.normalizedStatus(from: payload)
        guard !status.isEmpty else { return }

        currentRideStatus = status

        if Self.isCompletedStatus(status) {
            isRideCompleted = true
        }
    }

    private func extractId(_ value: Any?) -> String {
        guard let value = value else { return "" }
        let str = "\(value)"
        return str.filter { $0.isNumber }
    }

    private static func parseDouble(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func normalizedStatus(from payload: [String: Any]) -> String {
        String(describing: payload["status"] ?? payload["ride_status"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func isCompletedStatus(_ status: String) -> Bool {
        switch status {
        case "completed", "finished", "done":
            return true
        default:
            return false
        }
    }

    private static func normalizedCoordinate(lat: Double, lng: Double) -> CLLocationCoordinate2D {
        // Recover swapped coordinates when latitude is out of range but longitude is valid latitude.
        if abs(lat) > 90, abs(lng) <= 90 {
            return CLLocationCoordinate2D(latitude: lng, longitude: lat)
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private static func isUsableCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return false }
        // Prevent plotting null-island fallback.
        return abs(coordinate.latitude) > 0.0001 || abs(coordinate.longitude) > 0.0001
    }

    private static func preferredCenter(pickup: CLLocationCoordinate2D, dropoff: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        if isUsableCoordinate(pickup) { return pickup }
        if isUsableCoordinate(dropoff) { return dropoff }
        return CLLocationCoordinate2D(latitude: 24.7136, longitude: 46.6753)
    }

    private static func routeSignature(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> String {
        func rounded(_ value: Double) -> String {
            String(format: "%.4f", value)
        }
        return "\(rounded(from.latitude)),\(rounded(from.longitude))->\(rounded(to.latitude)),\(rounded(to.longitude))"
    }

    private static func areCoordinatesClose(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, thresholdMeters: CLLocationDistance) -> Bool {
        let first = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let second = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return first.distance(from: second) <= thresholdMeters
    }
}

// MARK: - Main View

struct RideTrackingPage: View {
    
            @StateObject private var viewModel: RideTrackingViewModel
        
            // Used for navigation
            @State private var navigateToHome = false
            @State private var navigateToCancellation = false
            @State private var navigateToChat = false
            @State private var showAddContact = false
        
            // Driver Info for Bottom Card
            let driverName: String
            let vehicleInfo: String
            let rideId:String
            let driverId: String?
            let driverPhone: String?
            init(rideId: String, pickupLat: Double, pickupLng: Double, dropoffLat: Double, dropoffLng: Double, driverId: String? = nil, driverName: String = L10n.t("ride_tracking.default_driver_name"), vehicleInfo: String = L10n.t("ride_tracking.default_vehicle_info"), driverPhone: String? = nil) {
                self.rideId = rideId
                self.driverId = driverId
                self.driverName = driverName
                self.vehicleInfo = vehicleInfo
                self.driverPhone = driverPhone
                _viewModel = StateObject(wrappedValue: RideTrackingViewModel(
                    rideId: rideId,
                    driverId: driverId,
                    pickupLat: pickupLat,
                    pickupLng: pickupLng,
                    dropoffLat: dropoffLat,
                    dropoffLng: dropoffLng,
                    driverName: driverName,
                    vehicleInfo: vehicleInfo
                ))
            }
        
            var body: some View {
                ZStack(alignment: .bottom) {
                    Map(position: $viewModel.cameraPosition, interactionModes: .all) {
                        ForEach(viewModel.polylines) { polyline in
                            MapPolyline(coordinates: polyline.coordinates)
                                .stroke(polyline.color, lineWidth: polyline.width)
                        }
    
                        ForEach(viewModel.annotations) { annotation in
                            if annotation.id == "driver" {
                                Annotation(annotation.title ?? "", coordinate: annotation.coordinate) {
                                    ZStack {
                                        // Backup circle
                                        Circle()
                                            .fill(Color.red.opacity(0.3))
                                            .frame(width: 44, height: 44)

                                        if let uiImage = UIImage(named: "driverCar") {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 40, height: 40)
                                        } else {
                                            // If you see this yellow car, the asset "driverCar" is missing from the bundle
                                            Image(systemName: "car.side.fill")
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 30, height: 30)
                                                .foregroundColor(.yellow)
                                                .onAppear {
                                                    print("DEBUG: driverCar asset NOT FOUND in bundle")
                                                }
                                        }
                                    }
                                    .shadow(radius: 2)
                                }
                            } else {
                                Marker(annotation.title ?? "", coordinate: annotation.coordinate)
                                    .tint(annotation.tint)
                            }
                        }
                    }
    
                    .edgesIgnoringSafeArea(.all)
                    .onAppear {
                        viewModel.requestUserLocation()
                        viewModel.setupMap()
                    }
    
                    // Driver Info Card
                    driverInfoCard
                }
                .navigationTitle(L10n.t("ride_tracking.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            navigateToCancellation = true
                        }) {
                            Image(systemName: "xmark")
                        }
                    }
                }
                .navigationDestination(isPresented: $navigateToCancellation) {
                    RideCancellationPage(rideId: rideId) {
                        // Delay ensuring the dismissal of CancellationPage is processed first
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            self.navigateToHome = true
                        }
                    }
                }
                .navigationDestination(isPresented: $navigateToHome) {
                    HomePage()
                }
                .navigationDestination(isPresented: $navigateToChat) {
                    ChatPage(rideId: rideId, driverId: driverId, driverName: driverName)
                }
                .onReceive(viewModel.$isRideCompleted.removeDuplicates()) { completed in
                    if completed {
                        navigateToHome = true
                    }
                }
            };   private var driverInfoCard: some View {
        VStack {
            driverDetailsSection
            .padding(.bottom, 10)
            locationInfoSection
            cancelTripButton
                .padding(.top, 12)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(radius: 10)
    }

    private var driverDetailsSection: some View {
        HStack {
            Image(systemName: "car.fill")
                .font(.title)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading) {
                Text(driverName)
                    .font(.headline)
                Text(vehicleInfo)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: {
                    navigateToChat = true
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "message.fill")
                            .font(.title3)
                        Text(L10n.t("chat.button"))
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(12)
                }

                Button(action: {
                    guard let phone = driverPhone?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !phone.isEmpty,
                          !driverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return
                    }
                    showAddContact = true
                }) {
                    Image(systemName: "phone.fill")
                        .font(.title3)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.green)
                    .cornerRadius(12)
                }
                .disabled((driverPhone ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity((driverPhone ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
        }
    }

    private var locationInfoSection: some View {

        VStack(alignment: .leading, spacing: 8) {

            HStack {

                Image(systemName: "location.fill")

                    .foregroundColor(.green)

                Text(L10n.t("ride_tracking.pickup"))

                    .font(.subheadline)

                    .foregroundColor(.gray)

                Spacer()

                if let driverLoc = viewModel.driverLocation {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(String(format: "%.1f", viewModel.calculateDistance(from: driverLoc, to: viewModel.pickupCoordinate))) \(L10n.t("ride_tracking.km_away"))")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        
                        if let seconds = viewModel.arrivalTimeSeconds {
                            Text("\(Int(ceil(Double(seconds) / 60.0))) \(L10n.t("ride_booking.time_unit_min"))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
            }
        }
        .sheet(isPresented: $showAddContact) {
            AddContactView(
                name: driverName,
                phone: driverPhone ?? ""
            )
        }
    }

            }

            HStack {

                Image(systemName: "flag.fill")

                    .foregroundColor(.red)

                Text(L10n.t("ride_tracking.dropoff"))

                    .font(.subheadline)

                    .foregroundColor(.gray)

                Spacer()

            }

        }

    }

    private var cancelTripButton: some View {
        Button {
            navigateToCancellation = true
        } label: {
            Text(L10n.t("ride_tracking.cancel_trip"))
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundColor(.white)
                .background(Color.red)
                .cornerRadius(10)
        }
    }
}




// MARK: - Custom Corner Radius Extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners) )
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}


// MARK: - Previews

struct RideTrackingPage_Previews: PreviewProvider {
    static var previews: some View {
        RideTrackingPage(rideId: UUID().uuidString, pickupLat: 34.0, pickupLng: -118.0, dropoffLat: 34.1, dropoffLng: -118.1)
    }
}

struct AddContactView: UIViewControllerRepresentable {
    let name: String
    let phone: String

    func makeUIViewController(context: Context) -> CNContactViewController {
        let contact = CNMutableContact()
        contact.givenName = name
        contact.phoneNumbers = [
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))
        ]

        let controller = CNContactViewController(forNewContact: contact)
        controller.contactStore = CNContactStore()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: CNContactViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            viewController.dismiss(animated: true)
        }
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var points = Array(
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: pointCount
        )
        getCoordinates(&points, range: NSRange(location: 0, length: pointCount))
        return points
    }
}
