import SwiftUI

// MARK: - Data Models

struct LocationCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double
}

struct TripLocationData {
    var pickupLocation: LocationCoordinate?
    var dropoffLocation: LocationCoordinate?
    var pickupAddress: String
    var dropoffAddress: String
}
