struct ApiConstants {
  // Local development server
  static let baseUrl = "https://ladytaxi20251225225008-chhmhgf4e8h4fbdn.canadacentral-01.azurewebsites.net/"
    //"http://192.168.1.105:5001"
  static let socketUrl = "https://ladytaxi20251225225008-chhmhgf4e8h4fbdn.canadacentral-01.azurewebsites.net/"
   //"http://192.168.1.105:5001"
  //static let socketUrl = "http://192.168.1.105:5001"
  static let login = "/api/auth/login"
  static let registerUser = "/api/auth/register/user"

  // Customer Endpoints
  static let customerProfile = "/api/customer/profile"
  static let rideHistory = "/api/rides/history"
  static let paymentMethods = "/api/customer/payment-methods"

  // Ride Endpoints (using Trips controller)
  static let requestRide = "/api/trips"
  static let cancelRide = "/api/trips/{id}/cancel"
  static let cancellationReasons = "/api/trips/cancellation-reasons/client"
  static let rideDetails = "/api/trips/{id}"
  static let rateRide = "/api/ratings"
  static let estimateFare = "/api/trips/estimate"

  // Location Endpoints
  static let searchLocations = "/api/location/search"
  static let nearbyDrivers = "/api/location/nearby-drivers"
  static let geocode = "/api/location/geocode"
  static let reverseGeocode = "/api/location/reverse-geocode"
  static let getRoute = "/api/location/route"

  // Headers
  static let authHeader = "Authorization"
  static let contentType = "Content-Type"
  static let applicationJson = "application/json"

  // Timeouts
  static let connectionTimeout = 30000  // 30 seconds
  static let receiveTimeout = 30000     // 30 seconds
}
