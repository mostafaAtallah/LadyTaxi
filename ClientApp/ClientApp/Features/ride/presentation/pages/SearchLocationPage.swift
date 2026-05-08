import SwiftUI
import MapKit
import CoreLocation

struct SearchLocationView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = SearchLocationViewModel()
    @State private var searchText = ""
    @State private var selectedLocation: LocationResult?
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    
    let locationType: LocationType
    
    enum LocationType: String {
        case pickup = "pickup"
        case dropoff = "dropoff"
    }
    
    var body: some View {
        NavigationView {
            Group {
                if selectedLocation == nil {
                    searchView
                } else {
                    mapView
                }
            }
            .navigationTitle(locationType == .pickup ? L10n.t("search_location.set_pickup") : L10n.t("search_location.set_destination"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if selectedLocation != nil {
                            selectedLocation = nil
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "arrow.backward")
                    }
                }
            }
        }
        .onAppear {
            viewModel.locationType = locationType
        }
    }
    
    // MARK: - Search View
    private var searchView: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                TextField(L10n.t("search_location.placeholder"), text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocorrectionDisabled()
                    .padding(.leading)
                    .onChange(of: searchText) { newValue in
                        if newValue.isEmpty {
                            viewModel.searchResults = []
                        } else {
                            // Debounce search
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                if self.searchText == newValue {
                                    viewModel.searchLocations(query: newValue)
                                }
                            }
                        }
                    }
                
                Button {
                    viewModel.searchLocations(query: searchText)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .padding()
                }
                .disabled(searchText.isEmpty)
            }
            .padding()
            
            // Current Location Option
            Button {
                viewModel.useCurrentLocation()
                dismiss() // Dismiss after selecting current location
            } label: {
                HStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppColors.primary.opacity(0.1))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "location.fill")
                                .foregroundColor(AppColors.primary)
                        )
                    
                    VStack(alignment: .leading) {
                        Text(L10n.t("search_location.use_current"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppColors.textPrimary)
                        
                        Text(L10n.t("search_location.use_current_subtitle"))
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textSecondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            
            Divider()
            
            // Search Results or Empty State
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if viewModel.searchResults.isEmpty && !searchText.isEmpty {
                emptySearchView
            } else if viewModel.searchResults.isEmpty {
                emptyInitialView
            } else {
                searchResultsList
            }
        }
    }
    
    // MARK: - Map View
    private var mapView: some View {
        ZStack(alignment: .top) {
            // Map
            Map(
                coordinateRegion: $region,
                showsUserLocation: true,
                userTrackingMode: .constant(.none),
                annotationItems: [selectedLocation!]
            ) { location in
                MapMarker(
                    coordinate: location.coordinate,
                    tint: AppColors.primary
                )
            }
            .onAppear {
                if let location = selectedLocation {
                    region.center = location.coordinate
                }
            }
            
            // Location Info Card
            VStack {
                if let location = selectedLocation {
                    locationInfoCard(location: location)
                        .padding(.horizontal)
                        .padding(.top)
                }
                
                Spacer()
                
                // Confirm Button
                Button {
                    confirmSelection()
                } label: {
                    HStack {
                        Image(systemName: "checkmark")
                        Text(L10n.t("search_location.confirm"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(AppColors.primary)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()
                }
                
                // My Location Button
                HStack {
                    Spacer()
                    
                    Button {
                        viewModel.centerMapOnUserLocation { coordinate in
                            if let coordinate = coordinate {
                                region.center = coordinate
                            }
                        }
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 18))
                            .frame(width: 44, height: 44)
                            .background(AppColors.surface)
                            .foregroundColor(AppColors.primary)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 4)
                    }
                    .padding(.trailing)
                    .padding(.bottom, 80)
                }
            }
        }
    }
    
    // MARK: - Subviews
    private var emptySearchView: some View {
        VStack {
            Spacer()
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(AppColors.textSecondary.opacity(0.5))
            
            Text(L10n.t("search_location.no_results"))
                .font(.system(size: 16))
                .foregroundColor(AppColors.textSecondary.opacity(0.5))
                .padding(.top, 16)
            
            Spacer()
        }
    }
    
    private var emptyInitialView: some View {
        VStack {
            Spacer()
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(AppColors.textSecondary.opacity(0.5))
            
            Text(L10n.t("search_location.search_prompt"))
                .font(.system(size: 16))
                .foregroundColor(AppColors.textSecondary.opacity(0.5))
                .padding(.top, 16)
            
            Spacer()
        }
    }
    
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.searchResults) { location in
                    Button {
                        selectLocation(location)
                    } label: {
                        HStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppColors.inputFill)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Image(systemName: "mappin.circle")
                                        .foregroundColor(AppColors.textSecondary)
                                )
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(location.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(AppColors.textPrimary)
                                
                                Text(location.address)
                                    .font(.system(size: 12))
                                    .foregroundColor(AppColors.textSecondary)
                                    .lineLimit(2)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Divider()
                        .padding(.leading, 68)
                }
            }
        }
    }
    
    private func locationInfoCard(location: LocationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(location.name)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
            
            Text(location.address)
                .font(.system(size: 12))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8)
    }
    
    // MARK: - Actions
    private func selectLocation(_ location: LocationResult) {
        selectedLocation = location
        region.center = location.coordinate
    }
    
    private func confirmSelection() {
        guard let location = selectedLocation else { return }
        viewModel.confirmSelection(location: location)
        dismiss()
    }
}

// MARK: - View Model
class SearchLocationViewModel: ObservableObject {
    @Published var searchResults: [LocationResult] = []
    @Published var isLoading = false
    @Published var currentLocation: CLLocation?
    var locationType: SearchLocationView.LocationType = .pickup
    
    private let locationManager = CLLocationManager()
    private let apiService = LocationAPIService()
    
    init() {
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func searchLocations(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isLoading = true
        apiService.searchLocations(query: query) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let locations):
                    self?.searchResults = locations
                case .failure(let error):
                    print("Search error: \(error)")
                    self?.searchResults = []
                }
            }
        }
    }
    
    func useCurrentLocation() {
        isLoading = true
        
        locationManager.requestLocation { [weak self] location in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let location = location {
                    // Reverse geocode to get address
                    self?.getAddressFromLocation(location) { address in
                        let locationResult = LocationResult(
                            name: L10n.t("search_location.current_location"),
                            address: address ?? L10n.t("search_location.current_location"),
                            coordinate: location.coordinate
                        )
                        self?.confirmSelection(location: locationResult)
                    }
                }
            }
        }
    }
    
    func confirmSelection(location: LocationResult) {
        // Save to shared state or UserDefaults
        // This would typically connect to your HomeViewModel
        
        let locationData: [String: Any] = [
            "name": location.name,
            "address": location.address,
            "lat": location.coordinate.latitude,
            "lng": location.coordinate.longitude
        ]
        
        if locationType == .pickup {
            // Save pickup location
            UserDefaults.standard.set(locationData, forKey: "pickupLocation")
            // Notify home view model
            NotificationCenter.default.post(
                name: .pickupLocationUpdated,
                object: locationData
            )
        } else {
            // Save dropoff location
            UserDefaults.standard.set(locationData, forKey: "dropoffLocation")
            // Notify home view model
            NotificationCenter.default.post(
                name: .dropoffLocationUpdated,
                object: locationData
            )
        }
    }
    
    func centerMapOnUserLocation(completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        locationManager.requestLocation { location in
            completion(location?.coordinate)
        }
    }
    
    private func getAddressFromLocation(_ location: CLLocation, completion: @escaping (String?) -> Void) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let placemark = placemarks?.first {
                let address = [
                    placemark.thoroughfare,
                    placemark.locality,
                    placemark.administrativeArea,
                    placemark.country
                ].compactMap { $0 }.joined(separator: ", ")
                completion(address)
            } else {
                completion(nil)
            }
        }
    }
}

// MARK: - Models
struct LocationResult: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Services
class LocationAPIService {
    func searchLocations(query: String, completion: @escaping (Result<[LocationResult], Error>) -> Void) {
        var components = URLComponents(string: ApiConstants.baseUrl + ApiConstants.searchLocations)
        components?.queryItems = [URLQueryItem(name: "query", value: query)]

        guard let url = components?.url else {
            completion(.failure(URLError(.badURL)))
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }

            do {
                guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    completion(.success([]))
                    return
                }

                let locations = jsonArray.compactMap { dict -> LocationResult? in
                    let name = (dict["name"] as? String) ?? (dict["Name"] as? String) ?? ""
                    let address = (dict["address"] as? String) ?? (dict["Address"] as? String) ?? name
                    let lat = (dict["lat"] as? Double) ?? (dict["Lat"] as? Double)
                    let lng = (dict["lng"] as? Double) ?? (dict["Lng"] as? Double)

                    guard !name.isEmpty, let lat, let lng else { return nil }
                    return LocationResult(
                        name: name,
                        address: address,
                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)
                    )
                }

                completion(.success(locations))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

// MARK: - Location Manager Extension
extension CLLocationManager {
    func requestLocation(completion: @escaping (CLLocation?) -> Void) {
        self.delegate = LocationManagerDelegate(completion: completion)
        requestLocation()
    }
}

private class LocationManagerDelegate: NSObject, CLLocationManagerDelegate {
    private let completion: (CLLocation?) -> Void
    
    init(completion: @escaping (CLLocation?) -> Void) {
        self.completion = completion
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        completion(locations.first)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
        completion(nil)
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let pickupLocationUpdated = Notification.Name("pickupLocationUpdated")
    static let dropoffLocationUpdated = Notification.Name("dropoffLocationUpdated")
}

// MARK: - Preview
struct SearchLocationView_Previews: PreviewProvider {
    static var previews: some View {
        SearchLocationView(locationType: .pickup)
    }
}
