import Foundation

public enum AuthState: Equatable {
    case idle
    case loading
    case authenticated
    case error(String)
}
