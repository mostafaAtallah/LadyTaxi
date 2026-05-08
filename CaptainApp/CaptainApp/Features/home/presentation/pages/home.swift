import SwiftUI
import MapKit
import CoreLocation
import Combine
import UIKit

// MARK: - 2. Main Page View
enum TripStage: Int, CaseIterable {
    case none
    case reachedPickup
    case clientInCar
    case completed
}

struct TripStageRecord: Identifiable {
    let id = UUID()
    let stage: TripStage
    let coordinate: CLLocationCoordinate2D?
    let timestamp: Date
}

struct HomePage: View {
    private enum BottomTab {
        case home
        case rideHistory
        case profile
    }

    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var rideViewModel: RideViewModel
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var currentPendingRideRequest: PendingRideRequest?
    @State private var activePickupRide: PendingRideRequest?
    @State private var routeToPickup: MKRoute?
    @State private var fallbackRouteLine: MKPolyline?
    @State private var resolvedPickupCoordinate: CLLocationCoordinate2D?
    @State private var lastCaptainCoordinate: CLLocationCoordinate2D?
    @State private var pickupLineSourceCoordinate: CLLocationCoordinate2D?
    @State private var lineDebugText: String = "line: idle"
    @State private var selectedTab: BottomTab = .home
    @State private var showRideCancelledAlert = false
    @State private var cancelledRideMessage = ""
    @State private var tripStageRecords: [TripStageRecord] = []
    @State private var currentTripStage: TripStage = .none
    @State private var showNavigationOptions = false
    @StateObject private var locationProvider = LocationProvider()
    private let minLineDistanceMeters: CLLocationDistance = 2
    private let maxLineDistanceMeters: CLLocationDistance = 200_000

    var body: some View {
        NavigationStack {
            content
        }
        .onAppear {
            let captainId = authViewModel.captainId
            homeViewModel.initializeHome(captainId: captainId)
            homeViewModel.bindWebSocket(rideViewModel.webSocketService)
            if let token = authViewModel.authToken, !token.isEmpty {
                rideViewModel.connectSocket(authToken: token)
            } else {
                print("HomePage: missing auth token, websocket connection skipped")
            }
            locationProvider.start()
        }
        .onDisappear {
            rideViewModel.disconnectSocket()
        }
        .alert(L10n.t("ride_tracking.cancel_trip"), isPresented: $showRideCancelledAlert) {
            Button(L10n.t("home.alert.ok"), role: .cancel) {
                showRideCancelledAlert = false
            }
        } message: {
            Text(cancelledRideMessage)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch homeViewModel.state {
        case .loading:
            ProgressView(L10n.t("home.loading"))
        case .error(let message):
            Text(message)
        case .ready(
            isOnline: let isOnline,
            currentPosition: let pos,
            pendingRide: let pending,
            someOtherData: _
        ):
            VStack(spacing: 0) {
                Group {
                    switch selectedTab {
                    case .home:
                        homeTabContent(isOnline: isOnline, pos: pos, pending: pending)
                    case .rideHistory:
                        RideHistoryPage()
                    case .profile:
                        ProfilePage()
                    }
                }
                bottomTabBar
            }
        }
    }

    private func homeTabContent(
        isOnline: Bool,
        pos: CLLocation?,
        pending: PendingRideRequest?
    ) -> some View {
        ZStack {
            homeMapLayer(pos: pos)
            homeOverlayLayer(isOnline: isOnline)
        }
        .overlay(alignment: .bottom) {
            pickupBottomSheet
        }
        .overlay(alignment: .bottomTrailing) {
            wazeFloatingButton
        }
        .confirmationDialog("Open with", isPresented: $showNavigationOptions) {
            Button("Waze") {
                openWazeFromHome()
            }
            Button("Maps") {
                openMapsFromHome()
            }
        }
        .onAppear {
            if let coordinate = captainDisplayCoordinate ?? pos?.coordinate {
                lastCaptainCoordinate = coordinate
                cameraPosition = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000))
            }
        }
        .onChange(of: pos) { _, newPos in
            if let coordinate = captainDisplayCoordinate ?? newPos?.coordinate {
                let hadNoCaptainLocation = (lastCaptainCoordinate == nil)
                lastCaptainCoordinate = coordinate

                if hadNoCaptainLocation && activePickupRide == nil {
                    withAnimation {
                        cameraPosition = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000))
                    }
                }
            }
        }
        .onReceive(locationProvider.$currentLocation) { _ in
            if let coordinate = captainDisplayCoordinate {
                lastCaptainCoordinate = coordinate
                if activePickupRide != nil {
                    pickupLineSourceCoordinate = coordinate
                }
                sendDriverLocationUpdate(coordinate)
            }
            refreshRouteToPickup()
        }
        .onChange(of: activePickupRide?.id) { _, _ in
            if activePickupRide == nil {
                pickupLineSourceCoordinate = nil
                fallbackRouteLine = nil
                routeToPickup = nil
            }
            resolvePickupCoordinateIfNeeded()
            refreshRouteToPickup()
        }
        .onChange(of: pending) { _, newValue in
            if let request = newValue {
                self.currentPendingRideRequest = request
            }
        }
        .onChange(of: homeViewModel.lastCancelledRideId) { _, newValue in
            guard let rideId = newValue, !rideId.isEmpty else { return }
            handleRideCancelled(rideId: rideId)
        }
        .sheet(item: $currentPendingRideRequest) { ride in
            RideRequestBottomSheet(
                rideRequest: ride,
                onAccept: {
                    resetTripStageTracking()
                    pickupLineSourceCoordinate = captainDisplayCoordinate ?? pos?.coordinate ?? lastCaptainCoordinate
                    rideViewModel.acceptRide(rideId: ride.rideId, authToken: authViewModel.authToken)
                    activePickupRide = ride
                    resolvePickupCoordinateIfNeeded()
                    refreshRouteToPickup()
                    focusOnPickup()
                    homeViewModel.rideRequestDismissed()
                    currentPendingRideRequest = nil
                },
                onReject: {
                    homeViewModel.rideRequestDismissed()
                    currentPendingRideRequest = nil
                }
            )
            .presentationDetents([.fraction(0.6)])
        }
    }

    private func homeMapLayer(pos: CLLocation?) -> some View {
        Map(position: $cameraPosition) {
            homeMapContent(pos: pos)
        }
        .ignoresSafeArea()
    }

    @MapContentBuilder
    private func homeMapContent(pos: CLLocation?) -> some MapContent {
        if let coordinate = captainDisplayCoordinate ?? pos?.coordinate {
            Marker(L10n.t("home.marker.your_location"), coordinate: coordinate)
        }
        if let pickup = pickupCoordinate {
            Marker(L10n.t("home.marker.pickup"), coordinate: pickup)
                .tint(AppColors.pickupMarker)
        }
        if let fallbackRouteLine {
            MapPolyline(fallbackRouteLine)
                .stroke(AppColors.routeLine, lineWidth: 6)
        } else if let routeToPickup {
            MapPolyline(routeToPickup.polyline)
                .stroke(AppColors.routeLine, lineWidth: 5)
        }
    }

    private func homeOverlayLayer(isOnline: Bool) -> some View {
        VStack {
            TopBarView(isOnline: isOnline)
            #if DEBUG
            Text(lineDebugText)
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12)
            #endif
            if let activePickupRide {
                pickupGuidanceCard(for: activePickupRide)
            }
            Spacer()
            OnlineStatusControlView(
                isOnline: isOnline,
                isCaptainVerified: authViewModel.isCaptainVerified
            )
        }
    }

    private func handleRideCancelled(rideId: String) {
        if let active = activePickupRide, active.rideId == rideId {
            activePickupRide = nil
        }
        if let pending = currentPendingRideRequest, pending.rideId == rideId {
            currentPendingRideRequest = nil
        }
        homeViewModel.rideRequestDismissed()
        resetTripStageTracking()
        pickupLineSourceCoordinate = nil
        fallbackRouteLine = nil
        routeToPickup = nil
        cancelledRideMessage = L10n.t("ride_history.cancelled") 
        showRideCancelledAlert = true
    }

    private var bottomTabBar: some View {
        HStack {
            tabButton(tab: .home, title: L10n.t("home.tab.home"), systemImage: "house.fill")
            tabButton(tab: .rideHistory, title: L10n.t("home.tab.ride_history"), systemImage: "clock.fill")
            tabButton(tab: .profile, title: L10n.t("home.tab.profile"), systemImage: "person.crop.circle.fill")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(AppColors.surface)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func tabButton(tab: BottomTab, title: String, systemImage: String) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.caption)
            }
            .foregroundStyle(isSelected ? AppColors.primary : AppColors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    private func placeholderTabContent(title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }

    private var pickupCoordinate: CLLocationCoordinate2D? {
        if let lat = activePickupRide?.pickupLat, let lng = activePickupRide?.pickupLng {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return resolvedPickupCoordinate
    }

    private func resolvePickupCoordinateIfNeeded() {
        guard let ride = activePickupRide else {
            resolvedPickupCoordinate = nil
            return
        }

        if let lat = ride.pickupLat, let lng = ride.pickupLng {
            resolvedPickupCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            focusOnPickup()
            return
        }

        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(ride.pickupLocation) { placemarks, error in
            guard error == nil, let coordinate = placemarks?.first?.location?.coordinate else { return }
            DispatchQueue.main.async {
                resolvedPickupCoordinate = coordinate
                focusOnPickup()
                refreshRouteToPickup()
            }
        }
    }

    private func refreshRouteToPickup() {
        let sourceForDebug = pickupLineSourceCoordinate ?? captainDisplayCoordinate ?? lineSourceCoordinate
        let destinationForDebug = pickupCoordinate
        lineDebugText = "line: src=\(coordText(sourceForDebug)) dst=\(coordText(destinationForDebug))"

        guard let destination = pickupCoordinate else {
            routeToPickup = nil
            fallbackRouteLine = nil
            lineDebugText = ""
            return
        }
        guard let sourceCoordinate = pickupLineSourceCoordinate ?? captainDisplayCoordinate ?? lineSourceCoordinate else {
            routeToPickup = nil
            fallbackRouteLine = nil
            lineDebugText = "line: no source"
            return
        }
        guard sourceCoordinate.isValidCoordinate, destination.isValidCoordinate else {
            routeToPickup = nil
            fallbackRouteLine = nil
            lineDebugText = "line: invalid coords"
            return
        }
        guard sourceCoordinate.latitude != destination.latitude || sourceCoordinate.longitude != destination.longitude else {
            fallbackRouteLine = nil
            routeToPickup = nil
            lineDebugText = "line: same point"
            return
        }

        let sourcePoint = MKMapPoint(sourceCoordinate)
        let destinationPoint = MKMapPoint(destination)
        let straightLineDistanceMeters = sourcePoint.distance(to: destinationPoint)
        guard straightLineDistanceMeters.isFinite,
              straightLineDistanceMeters > minLineDistanceMeters else {
            // Defensive guard against broken coordinates creating off-map/infinite-looking lines.
            routeToPickup = nil
            fallbackRouteLine = nil
            lineDebugText = "line: distance invalid \(Int(straightLineDistanceMeters))m"
            return
        }
        guard straightLineDistanceMeters <= maxLineDistanceMeters else {
            routeToPickup = nil
            fallbackRouteLine = nil
            lineDebugText = "line: source too far \(Int(straightLineDistanceMeters))m"
            return
        }

        // Always draw a direct straight line between captain and pickup.
        fallbackRouteLine = MKPolyline(
            coordinates: [sourceCoordinate, destination],
            count: 2
        )
        lineDebugText = "line: drawn \(Int(straightLineDistanceMeters))m"

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: sourceCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile

        MKDirections(request: request).calculate { response, error in
            guard error == nil, let route = response?.routes.first else { return }
            DispatchQueue.main.async {
                routeToPickup = route
            }
        }
    }

    private func focusOnPickup() {
        guard let pickup = pickupCoordinate else { return }
        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: pickup,
                    latitudinalMeters: 900,
                    longitudinalMeters: 900
                )
            )
        }
    }

    private var preferredCaptainCoordinate: CLLocationCoordinate2D? {
        if let currentLocation = locationProvider.currentLocation {
            let coordinate = currentLocation.coordinate
            if coordinate.isUsableForRouting {
                return coordinate
            }
        }

        if let lastCaptainCoordinate, lastCaptainCoordinate.isUsableForRouting {
            return lastCaptainCoordinate
        }

        return nil
    }

    private var lineSourceCoordinate: CLLocationCoordinate2D? {
        if let preferredCaptainCoordinate {
            return preferredCaptainCoordinate
        }

        if let fallbackFromState = homeCurrentPositionCoordinate, fallbackFromState.isValidCoordinate {
            return fallbackFromState
        }

        return nil
    }

    private var captainDisplayCoordinate: CLLocationCoordinate2D? {
        if let preferredCaptainCoordinate {
            return preferredCaptainCoordinate
        }
        if let fromState = homeCurrentPositionCoordinate, fromState.isUsableForRouting {
            return fromState
        }
        return nil
    }

    private var homeCurrentPositionCoordinate: CLLocationCoordinate2D? {
        switch homeViewModel.state {
        case .ready(_, let currentPosition, _, _):
            return currentPosition?.coordinate
        default:
            return nil
        }
    }

    private func coordText(_ coordinate: CLLocationCoordinate2D?) -> String {
        guard let coordinate else { return "nil" }
        return String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
    }

    @ViewBuilder
    private var pickupBottomSheet: some View {
        if let activePickupRide {
            RidePickupBottomSheet(
                ride: activePickupRide,
                route: routeToPickup,
                pickupCoordinate: pickupCoordinate,
                stageRecords: tripStageRecords,
                currentStage: currentTripStage,
                onReachedPickup: { handleReachedPickup(rideId: activePickupRide.rideId) },
                onClientInCar: { handleClientInCar(rideId: activePickupRide.rideId) },
                onCompleteRide: { handleCompleteRide(rideId: activePickupRide.rideId) }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var wazeFloatingButton: some View {
        if activePickupRide != nil, pickupCoordinate != nil {
            Button {
                showNavigationOptions = true
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(AppColors.primary)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            }
            .padding(.trailing, 16)
            .padding(.bottom, 220)
        } else {
            EmptyView()
        }
    }

    private func openWazeFromHome() {
        guard let pickupCoordinate else { return }
        let urlString = "waze://?ll=\(pickupCoordinate.latitude),\(pickupCoordinate.longitude)&navigate=yes"
        guard let url = URL(string: urlString) else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    private func openMapsFromHome() {
        guard let pickupCoordinate else { return }
        let placemark = MKPlacemark(coordinate: pickupCoordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = activePickupRide?.pickupLocation ?? ""
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func handleReachedPickup(rideId: String) {
        recordTripStage(.reachedPickup)
        rideViewModel.updateRideStatus(
            rideId: rideId,
            status: "reached_pickup",
            authToken: authViewModel.authToken
        )
    }

    private func handleClientInCar(rideId: String) {
        recordTripStage(.clientInCar)
        rideViewModel.updateRideStatus(
            rideId: rideId,
            status: "client_in_car",
            authToken: authViewModel.authToken
        )
    }

    private func handleCompleteRide(rideId: String) {
        recordTripStage(.completed)
        rideViewModel.updateRideStatus(
            rideId: rideId,
            status: "completed",
            authToken: authViewModel.authToken
        )
        activePickupRide = nil
        resetTripStageTracking()
        pickupLineSourceCoordinate = nil
        fallbackRouteLine = nil
        routeToPickup = nil
    }

    private func resetTripStageTracking() {
        tripStageRecords = []
        currentTripStage = .none
    }

    private func recordTripStage(_ stage: TripStage) {
        let coordinate = preferredCaptainCoordinate ?? captainDisplayCoordinate ?? lastCaptainCoordinate
        let record = TripStageRecord(
            stage: stage,
            coordinate: coordinate,
            timestamp: Date()
        )
        tripStageRecords.append(record)
        currentTripStage = stage
    }

    private func sendDriverLocationUpdate(_ coordinate: CLLocationCoordinate2D) {
        guard rideViewModel.webSocketService.isConnected else { return }

        let message: [String: Any] = [
            "event": "update_location",
            "data": [
                "lat": coordinate.latitude,
                "lng": coordinate.longitude
            ]
        ]
        rideViewModel.webSocketService.send(message)
    }

    @ViewBuilder
    private func pickupGuidanceCard(for ride: PendingRideRequest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("home.heading_to_pickup"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
            Text(ride.pickupLocation)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
            if let routeToPickup {
                Text("\(Int(routeToPickup.expectedTravelTime / 60)) \(L10n.t("home.unit.minute")) • \(String(format: "%.1f", routeToPickup.distance / 1000)) \(L10n.t("home.unit.km"))")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .padding(.horizontal, 16)
    }
}

private extension CLLocationCoordinate2D {
    var isValidCoordinate: Bool {
        CLLocationCoordinate2DIsValid(self)
            && latitude >= -90
            && latitude <= 90
            && longitude >= -180
            && longitude <= 180
    }

    var isUsableForRouting: Bool {
        guard isValidCoordinate else { return false }
        // Reject the common invalid origin coordinate.
        if abs(latitude) < 0.0001 && abs(longitude) < 0.0001 {
            return false
        }
        return true
    }
}

// MARK: - 3. Subviews (Fixes "Cannot find TopBarView in scope")

struct TopBarView: View {
    let isOnline: Bool
    var body: some View {
        HStack {
            Text(isOnline ? L10n.t("home.status.online") : L10n.t("home.status.offline"))
                .font(.caption.bold())
                .padding()
                .background(isOnline ? Color.green : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
        }.padding()
    }
}

struct OnlineStatusControlView: View {
    @EnvironmentObject var homeViewModel: HomeViewModel
    let isOnline: Bool
    let isCaptainVerified: Bool

    private func onToggleTapped() {
        guard isCaptainVerified else { return }
        homeViewModel.toggleOnlineStatus(isCaptainVerified: isCaptainVerified)
    }

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onToggleTapped) {
                Circle()
                    .fill(isCaptainVerified ? (isOnline ? Color.red : Color.blue) : Color.gray)
                    .frame(width: 60, height: 60)
                    .overlay(Image(systemName: "power").foregroundColor(.white))
            }
            .disabled(!isCaptainVerified)

            if !isCaptainVerified {
                Text(L10n.t("home.verification_required"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.error)
            }
        }
        .padding(.bottom, 40)
    }
}

struct RideRequestBottomSheet: View {
    let rideRequest: PendingRideRequest
    var onAccept: () -> Void
    var onReject: () -> Void

    @State private var countdown: Int = 30
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(countdown), total: 30)
                .tint(countdown > 10 ? AppColors.primary : AppColors.error)
                .background(AppColors.inputFill)

            VStack(spacing: 0) {
                HStack {
                    Text(L10n.t("home.incoming_request"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColors.info)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppColors.info.opacity(0.1))
                        .clipShape(Capsule())

                    Spacer()

                    Text("\(countdown)\(L10n.t("home.unit.second_suffix"))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(countdown > 10 ? AppColors.primary : AppColors.error)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background((countdown > 10 ? AppColors.primary : AppColors.error).opacity(0.1))
                        .clipShape(Capsule())
                }

                HStack(spacing: 12) {
                    Circle()
                        .fill(AppColors.inputFill)
                        .frame(width: 50, height: 50)
                        .overlay(
                            Text(String((rideRequest.customerName ?? "C").prefix(1)).uppercased())
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(AppColors.textPrimary)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(rideRequest.customerName ?? L10n.t("home.customer.default"))
                            .font(.system(size: 18, weight: .bold))

                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .font(.system(size: 12))
                            Text(String(format: "%.1f", rideRequest.customerRating ?? 4.8))
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("$\(String(format: "%.2f", rideRequest.fare))")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppColors.success)
                        Text("\(String(format: "%.1f", rideRequest.distanceKm ?? 0.0)) \(L10n.t("home.unit.km"))")
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .padding(.top, 16)

                locationInfo(
                    icon: "smallcircle.filled.circle",
                    color: AppColors.pickupMarker,
                    label: L10n.t("home.label.pickup"),
                    address: rideRequest.pickupLocation
                )
                .padding(.top, 16)

                locationInfo(
                    icon: "mappin.circle.fill",
                    color: AppColors.dropoffMarker,
                    label: L10n.t("home.label.dropoff"),
                    address: rideRequest.dropoffLocation
                )
                .padding(.top, 12)

                Button(action: onAccept) {
                    Text(L10n.t("home.accept"))
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .foregroundStyle(.white)
                        .background(AppColors.success)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 24)
            }
            .padding(24)
        }
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onReceive(timer) { _ in
            guard countdown > 0 else { return }
            countdown -= 1
            if countdown == 0 {
                onReject()
            }
        }
    }

    @ViewBuilder
    private func locationInfo(icon: String, color: Color, label: String, address: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
                Text(address)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
        }
    }
}

struct RidePickupBottomSheet: View {
    let ride: PendingRideRequest
    let route: MKRoute?
    let pickupCoordinate: CLLocationCoordinate2D?
    let stageRecords: [TripStageRecord]
    let currentStage: TripStage
    var onReachedPickup: () -> Void
    var onClientInCar: () -> Void
    var onCompleteRide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.t("home.heading_to_pickup"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                if let route {
                    Text("\(Int(route.expectedTravelTime / 60)) \(L10n.t("home.unit.minute")) • \(String(format: "%.1f", route.distance / 1000)) \(L10n.t("home.unit.km"))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            locationRow(
                icon: "smallcircle.filled.circle",
                color: AppColors.pickupMarker,
                label: L10n.t("home.label.pickup"),
                address: nil
            )

            locationRow(
                icon: "mappin.circle.fill",
                color: AppColors.dropoffMarker,
                label: L10n.t("home.label.dropoff"),
                address: nil
            )

            stageActionButton
        }
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }

    @ViewBuilder
    private func locationRow(icon: String, color: Color, label: String, address: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                if let address, !address.isEmpty {
                    Text(address)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func stageTitle(for stage: TripStage) -> String {
        switch stage {
        case .reachedPickup:
            return L10n.t("home.reached_pickup")
        case .clientInCar:
            return L10n.t("home.client_in_car")
        case .completed:
            return L10n.t("home.complete_ride")
        case .none:
            return L10n.t("home.trip_progress")
        }
    }

    private func formattedCoordinate(_ coordinate: CLLocationCoordinate2D?) -> String {
        guard let coordinate else { return L10n.t("home.location_unknown") }
        return String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }


    @ViewBuilder
    private var stageActionButton: some View {
        switch currentStage {
        case .none:
            Button(action: onReachedPickup) {
                Text(L10n.t("home.reached_pickup"))
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(.white)
                    .background(AppColors.info)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case .reachedPickup:
            Button(action: onClientInCar) {
                Text(L10n.t("home.client_in_car"))
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(.white)
                    .background(AppColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case .clientInCar:
            Button(action: onCompleteRide) {
                Text(L10n.t("home.complete_ride"))
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(.white)
                    .background(AppColors.success)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case .completed:
            EmptyView()
        }
    }
}

final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentLocation: CLLocation?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
}
