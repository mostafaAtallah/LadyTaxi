import SwiftUI
import MapKit // Added import
import CoreLocation

private enum HomeTab {
    case home
    case history
    case profile
}

struct HomePage: View {
    @State private var
    goToRide = false;
    @EnvironmentObject var authManager: AuthManager // Inject AuthManager
    @Environment(\.homeBottomInset) private var homeBottomInset
    @StateObject private var viewModel = HomeViewModel()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var isSelectingPickup = true
    @State private var isSelectingDestination = false
    @State private var showingSearchLocation = false
    @State private var selectedTab: HomeTab = .home

    var body: some View {
        GeometryReader { proxy in
            let bottomInset = proxy.safeAreaInsets.bottom
            ZStack(alignment: .bottom) {
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomTabBar
            }
            .environment(\.homeBottomInset, bottomInset)
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            homeMapContent
        case .history:
            RideHistoryTabView()
        case .profile:
            ProfileTabView()
        }
    }

    private var homeMapContent: some View {
        GeometryReader { proxy in
            ZStack {
                Map(coordinateRegion: $region,
                    showsUserLocation: true,
                    userTrackingMode: .constant(.none),
                    annotationItems: viewModel.annotations
                ) { annotation in
                    MapMarker(coordinate: annotation.coordinate, tint: annotation.tint)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()

                if isSelectingPickup || isSelectingDestination {
                    CenterPointerView(isPickup: isSelectingPickup)
                }

                VStack {
                    Spacer()

                    BottomLocationCard(
                        viewModel: viewModel,
                        isSelectingPickup: $isSelectingPickup,
                        isSelectingDestination: $isSelectingDestination,
                        onSearchPickup: {
                            isSelectingPickup = true
                            isSelectingDestination = false
                            showingSearchLocation = true
                        },
                        onSearchDestination: {
                            isSelectingPickup = false
                            isSelectingDestination = true
                            showingSearchLocation = true
                        },
                        onConfirmPickup: {
                            viewModel.confirmPickup(from: region.center)
                            isSelectingPickup = false
                            isSelectingDestination = true
                        },
                        onConfirmDestination: {
                            viewModel.confirmDestination(from: region.center)
                            isSelectingDestination = false
                        },
                        onProceedToBooking: {
                            goToRide = true
                        }
                    )
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 10, y: -5)
                    .padding(.bottom, 72 + homeBottomInset)
                }
                VStack {
                    Spacer()

                    HStack {
                        Spacer()

                        VStack(spacing: 10) {
                            if viewModel.pickupLocation != nil && (isSelectingDestination || viewModel.dropoffLocation != nil) {
                                FloatingActionButton(
                                    icon: "arrow.uturn.backward",
                                    color: AppColors.surface,
                                    iconColor: AppColors.primary,
                                    action: {
                                        stepBackToLaunchPoint()
                                    }
                                )
                            }

                            FloatingActionButton(
                                icon: "location.fill",
                                color: AppColors.surface,
                                iconColor: AppColors.primary,
                                action: {
                                    if let location = viewModel.currentLocation {
                                        region.center = location.coordinate
                                    }
                                }
                            )
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, (viewModel.canRequestRide ? 290 : 230) + homeBottomInset)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.requestLocation()
            // Removed syncSelectionMode() from here
        }
        .onChange(of: viewModel.pickupAddress) { _ in
            syncSelectionMode()
        }
        .onChange(of: viewModel.dropoffAddress) { _ in
            syncSelectionMode()
        }
        .onChange(of: viewModel.pickupLocation) { pickup in
            guard let pickup else { return }
            focusMap(on: pickup)
        }
        .onChange(of: viewModel.dropoffLocation) { dropoff in
            guard let dropoff else { return }
            focusMap(on: dropoff)
        }
        .sheet(isPresented: $showingSearchLocation, onDismiss: {
            viewModel.reloadLocationsFromStorage()
            syncSelectionMode()
        }) {
            SearchLocationView(locationType: resolvedSearchLocationType())
        }
        .fullScreenCover(isPresented: $goToRide) {
            if let pickupLoc = viewModel.pickupLocation, let dropoffLoc = viewModel.dropoffLocation,
               let pickupAddr = viewModel.pickupAddress, let dropoffAddr = viewModel.dropoffAddress {
                NavigationStack {
                    RideBookingPage(tripLocationData: TripLocationData(
                        pickupLocation: pickupLoc,
                        dropoffLocation: dropoffLoc,
                        pickupAddress: pickupAddr,
                        dropoffAddress: dropoffAddr
                    ))
                }
            } else {
                Text(L10n.t("home.error.missing_locations"))
            }
        }
    }

    private func resolvedSearchLocationType() -> SearchLocationView.LocationType {
        if isSelectingDestination {
            return .dropoff
        }
        if isSelectingPickup {
            return .pickup
        }
        return viewModel.pickupAddress == nil ? .pickup : .dropoff
    }

    private func syncSelectionMode() {
        if viewModel.pickupAddress == nil {
            isSelectingPickup = true
            isSelectingDestination = false
            return
        }

        if viewModel.dropoffAddress == nil {
            isSelectingPickup = false
            isSelectingDestination = true
        } else {
            isSelectingPickup = false
            isSelectingDestination = false
        }
    }

    private func focusMap(on coordinate: LocationCoordinate) {
        withAnimation(.easeInOut(duration: 0.25)) {
            region.center = CLLocationCoordinate2D(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
    }

    private func stepBackToLaunchPoint() {
        viewModel.clearDropoff()
        isSelectingPickup = true
        isSelectingDestination = false
        if let pickup = viewModel.pickupLocation {
            focusMap(on: pickup)
        }
    }

    private var bottomTabBar: some View {
        HStack(spacing: 0) {
            tabButton(icon: "house.fill", title: L10n.t("home.tab.home"), tab: .home)
            tabButton(icon: "clock.fill", title: L10n.t("home.tab.ride_history"), tab: .history)
            tabButton(icon: "person.fill", title: L10n.t("home.tab.profile"), tab: .profile)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .background(.ultraThinMaterial)
    }

    private func tabButton(icon: String, title: String, tab: HomeTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isSelected ? AppColors.primary : AppColors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

struct RideHistoryTabView: View {
    var body: some View {
        HistoryPage()
    }
}

struct ProfileTabView: View {
    var body: some View {
        ProfilePage()
    }
}

private struct HomeBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private extension EnvironmentValues {
    var homeBottomInset: CGFloat {
        get { self[HomeBottomInsetKey.self] }
        set { self[HomeBottomInsetKey.self] = newValue }
    }
}

// MARK: - Center Pointer View
struct CenterPointerView: View {
    let isPickup: Bool

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(isPickup ? Color.green : Color.red)
                .frame(width: 12, height: 12)
                .shadow(color: .black.opacity(0.3), radius: 4)

            Rectangle()
                .fill(isPickup ? Color.green : Color.red)
                .frame(width: 2, height: 30)
        }
    }
}

// MARK: - Top Menu Bar
struct TopMenuBar: View {
    @Binding var showingSearchLocation: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Menu Button
            Button(action: {}) {
                Image(systemName: "line.horizontal.3")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 8)
            }

            // Search Bar
            Button(action: {
                showingSearchLocation = true
            }) {
                HStack {
                    Image(systemName: "location.fill")
                        .font(.system(size: 18))
                        .foregroundColor(AppColors.primary)

                    Text(L10n.t("home.brand"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.1), radius: 8)
            }
        }
    }
}
// MARK: - Bottom Location Card
struct BottomLocationCard: View {
    @ObservedObject var viewModel: HomeViewModel
    @Binding var isSelectingPickup: Bool
    @Binding var isSelectingDestination: Bool
    let onSearchPickup: () -> Void
    let onSearchDestination: () -> Void
    let onConfirmPickup: () -> Void
    let onConfirmDestination: () -> Void
    let onProceedToBooking: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isSelectingPickup || viewModel.pickupAddress == nil {
                // Step 1: Pickup Selection
                pickupSection
                confirmPickupButton
            } else {
                // Step 2: Destination Selection
                destinationSection

                if viewModel.dropoffAddress != nil {
                    proceedToBookingButton
                } else {
                    confirmDestinationButton
                }
            }
        }
        .padding(24)
    }

    // MARK: - Pickup Section
    private var pickupSection: some View {
        Button(action: onSearchPickup) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(AppColors.primary)

                Text(viewModel.pickupSearchDisplayText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.32), lineWidth: 1)
            )
        }
    }

    // MARK: - Destination Section
    private var destinationSection: some View {
        Button(action: onSearchDestination) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(AppColors.secondary)

                Text(viewModel.dropoffAddress ?? "Search destination point")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(viewModel.dropoffAddress == nil ? AppColors.textSecondary : AppColors.textPrimary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.32), lineWidth: 1)
            )
        }
    }

    // MARK: - Buttons
    private var confirmPickupButton: some View {
        Button(action: onConfirmPickup) {
            HStack {
                Image(systemName: "checkmark")
                Text(L10n.t("home.confirm_pickup"))
            }
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.green)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var confirmDestinationButton: some View {
        Button(action: onConfirmDestination) {
            HStack {
                Image(systemName: "checkmark")
                Text(L10n.t("home.confirm_destination"))
            }
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.red)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var proceedToBookingButton: some View {
        Button(action: onProceedToBooking) {
            HStack {
                Image(systemName: "car.fill")
                Text(L10n.t("home.proceed_booking"))
            }
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(AppColors.primary)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Floating Action Button
struct FloatingActionButton: View {
    let icon: String
    let color: Color
    var iconColor: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .frame(width: 44, height: 44)
                .background(color)
                .foregroundColor(iconColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 4)
        }
    }
}

// MARK: - Supporting View Models/Models
class HomeViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentLocation: CLLocation?
    @Published var currentLocationName: String?
    @Published var pickupAddress: String?
    @Published var dropoffAddress: String?
    @Published var pickupLocation: LocationCoordinate?
    @Published var dropoffLocation: LocationCoordinate?
    @Published var annotations: [MapPoint] = [] // Changed to MapPoint
    private var observers: [NSObjectProtocol] = []
    private let locationManager = CLLocationManager()
    private let geocodingService = HomeGeocodingService()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        registerLocationObservers()
        loadPersistedLocations()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    var canRequestRide: Bool {
        pickupAddress != nil && dropoffAddress != nil
    }

    var pickupSearchDisplayText: String {
        if let pickupAddress, !pickupAddress.isEmpty {
            return pickupAddress
        }

        if let currentLocationName, !currentLocationName.isEmpty {
            return currentLocationName
        }


        return L10n.t("search_location.placeholder")
    }

    func requestLocation() {
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .restricted, .denied:
            currentLocationName = L10n.t("search_location.use_current")
        @unknown default:
            break
        }
    }

    func confirmPickup(from coordinate: CLLocationCoordinate2D? = nil) {
        if pickupLocation == nil {
            if let coordinate, CLLocationCoordinate2DIsValid(coordinate) {
                pickupLocation = LocationCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
                pickupAddress = pickupAddress ?? "\(L10n.t("home.pickup.coordinate_prefix")) (\(String(format: "%.5f", coordinate.latitude)), \(String(format: "%.5f", coordinate.longitude)))"
            } else if let current = currentLocation?.coordinate {
                pickupAddress = pickupAddress ?? currentLocationName ?? "\(L10n.t("home.pickup.coordinate_prefix")) (\(String(format: "%.5f", current.latitude)), \(String(format: "%.5f", current.longitude)))"
                pickupLocation = LocationCoordinate(latitude: current.latitude, longitude: current.longitude)
            }
        }
        refreshAnnotations()
    }

    func confirmDestination(from coordinate: CLLocationCoordinate2D? = nil) {
        if dropoffLocation == nil, let coordinate, CLLocationCoordinate2DIsValid(coordinate) {
            dropoffLocation = LocationCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            dropoffAddress = dropoffAddress ?? "\(L10n.t("home.dropoff.coordinate_prefix")) (\(String(format: "%.5f", coordinate.latitude)), \(String(format: "%.5f", coordinate.longitude)))"
        }
        refreshAnnotations()
    }

    func clearLocations() {
        pickupAddress = nil
        dropoffAddress = nil
        pickupLocation = nil
        dropoffLocation = nil
        annotations.removeAll()
        UserDefaults.standard.removeObject(forKey: "pickupLocation")
        UserDefaults.standard.removeObject(forKey: "dropoffLocation")
    }

    func clearDropoff() {
        dropoffAddress = nil
        dropoffLocation = nil
        UserDefaults.standard.removeObject(forKey: "dropoffLocation")
        refreshAnnotations()
    }

    private func registerLocationObservers() {
        let center = NotificationCenter.default
        let pickupObserver = center.addObserver(
            forName: .pickupLocationUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.applyLocationUpdate(notification.object, type: .pickup)
        }
        let dropoffObserver = center.addObserver(
            forName: .dropoffLocationUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.applyLocationUpdate(notification.object, type: .dropoff)
        }
        observers.append(pickupObserver)
        observers.append(dropoffObserver)
    }

    private enum StoredLocationType {
        case pickup
        case dropoff
    }

    private func applyLocationUpdate(_ object: Any?, type: StoredLocationType) {
        guard let dict = object as? [String: Any] else { return }
        guard let coordinate = parseCoordinate(from: dict) else { return }
        let address = (dict["address"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = dict["name"] as? String
        let resolvedAddress = (address?.isEmpty == false) ? address! : (fallbackName ?? L10n.t("home.location.selected"))

        switch type {
        case .pickup:
            pickupLocation = LocationCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            pickupAddress = resolvedAddress
        case .dropoff:
            dropoffLocation = LocationCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            dropoffAddress = resolvedAddress
        }

        refreshAnnotations()
    }

    private func loadPersistedLocations() {
        if let pickup = UserDefaults.standard.dictionary(forKey: "pickupLocation") {
            applyLocationUpdate(pickup, type: .pickup)
        }
        if let dropoff = UserDefaults.standard.dictionary(forKey: "dropoffLocation") {
            applyLocationUpdate(dropoff, type: .dropoff)
        }
    }

    func reloadLocationsFromStorage() {
        loadPersistedLocations()
    }

    private func parseCoordinate(from dict: [String: Any]) -> CLLocationCoordinate2D? {
        let lat = parseDouble(dict["lat"]) ?? parseDouble(dict["latitude"])
        let lng = parseDouble(dict["lng"]) ?? parseDouble(dict["longitude"])

        guard let rawLat = lat, let rawLng = lng else { return nil }
        let normalized = normalizeCoordinate(rawLat: rawLat, rawLng: rawLng)
        guard CLLocationCoordinate2DIsValid(normalized) else { return nil }
        guard abs(normalized.latitude) > 0.0001 || abs(normalized.longitude) > 0.0001 else {
            return nil
        }
        return normalized
    }

    private func parseDouble(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func normalizeCoordinate(rawLat: Double, rawLng: Double) -> CLLocationCoordinate2D {
        // If coordinates appear swapped, recover by swapping.
        if abs(rawLat) > 90, abs(rawLng) <= 90 {
            return CLLocationCoordinate2D(latitude: rawLng, longitude: rawLat)
        }
        return CLLocationCoordinate2D(latitude: rawLat, longitude: rawLng)
    }

    private func refreshAnnotations() {
        var updated: [MapPoint] = []
        if let pickup = pickupLocation {
            updated.append(MapPoint(
                coordinate: CLLocationCoordinate2D(latitude: pickup.latitude, longitude: pickup.longitude),
                tint: .green
            ))
        }
        if let dropoff = dropoffLocation {
            updated.append(MapPoint(
                coordinate: CLLocationCoordinate2D(latitude: dropoff.latitude, longitude: dropoff.longitude),
                tint: .red
            ))
        }
        annotations = updated
    }

    private func resolveCurrentLocationName(from location: CLLocation) {
        geocodingService.reverseGeocode(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude) { [weak self] resolvedName in
            guard let self, let resolvedName, !resolvedName.isEmpty else { return }
            DispatchQueue.main.async {
                self.currentLocationName = resolvedName
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.currentLocationName = L10n.t("search_location.use_current")
            }
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        DispatchQueue.main.async {
            self.currentLocation = location
        }
        resolveCurrentLocationName(from: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Failed to get current location: \(error.localizedDescription)")
    }
}

private final class HomeGeocodingService {
    func reverseGeocode(latitude: Double, longitude: Double, completion: @escaping (String?) -> Void) {
        var components = URLComponents(string: ApiConstants.baseUrl + ApiConstants.reverseGeocode)
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lng", value: String(longitude))
        ]

        guard let url = components?.url else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if error != nil {
                completion(nil)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let data else {
                completion(nil)
                return
            }

            do {
                let jsonObject = try JSONSerialization.jsonObject(with: data)
                completion(Self.parseDisplayName(from: jsonObject))
            } catch {
                completion(nil)
            }
        }.resume()
    }

    private static func parseDisplayName(from jsonObject: Any) -> String? {
        if let dict = jsonObject as? [String: Any] {
            let candidateKeys = [
                "address",
                "formattedAddress",
                "formatted_address",
                "name",
                "displayName",
                "display_name"
            ]

            for key in candidateKeys {
                if let value = dict[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }

            if let result = dict["result"] {
                return parseDisplayName(from: result)
            }

            if let results = dict["results"] {
                return parseDisplayName(from: results)
            }
        }

        if let array = jsonObject as? [Any] {
            for item in array {
                if let parsed = parseDisplayName(from: item) {
                    return parsed
                }
            }
        }

        return nil
    }
}

// Define a local struct for map annotations
struct MapPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let tint: Color
}

// MARK: - Preview
struct HomePage_Previews: PreviewProvider {
    static var previews: some View {
        HomePage()
    }
}
