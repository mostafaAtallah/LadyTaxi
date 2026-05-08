import SwiftUI
import UIKit

struct AppColors {
    // Primary Colors
    static let primary = Color(hex: 0x6C63FF)
    static let primaryLight = Color(hex: 0x9D97FF)
    static let primaryDark = Color(hex: 0x4A42DB)
    
    // Secondary Colors
    static let secondary = Color(hex: 0xFF6B6B)
    static let secondaryLight = Color(hex: 0xFF9999)
    
    // Status Colors
    static let success = Color(hex: 0x4CAF50)
    static let warning = Color(hex: 0xFFC107)
    static let error = Color(hex: 0xE53935)
    static let info = Color(hex: 0x2196F3)
    
    // Background Colors
    static let background = Color(hex: 0xF5F5F5)
    static let surface = Color(hex: 0xFFFFFF)
    static let inputFill = Color(hex: 0xF0F0F0)
    
    // Dark Theme Colors
    static let darkBackground = Color(hex: 0x121212)
    static let darkSurface = Color(hex: 0x1E1E1E)
    
    // Text Colors
    static let textPrimary = Color(hex: 0x1A1A1A)
    static let textSecondary = Color(hex: 0x757575)
    static let textHint = Color(hex: 0xBDBDBD)
    static let textOnPrimary = Color(hex: 0xFFFFFF)
    
    // Ride Status Colors
    static let rideSearching = Color(hex: 0x2196F3)
    static let rideAccepted = Color(hex: 0x4CAF50)
    static let rideArriving = Color(hex: 0xFF9800)
    static let rideInProgress = Color(hex: 0x6C63FF)
    static let rideCompleted = Color(hex: 0x4CAF50)
    static let rideCancelled = Color(hex: 0xE53935)
    
    // Map Colors
    static let pickupMarker = Color(hex: 0x4CAF50)
    static let dropoffMarker = Color(hex: 0xE53935)
    static let routeLine = Color(hex: 0x6C63FF)
    static let driverMarker = Color(hex: 0x2196F3)
    
    // UIKit compatibility
    static var uiPrimary: UIColor { UIColor(primary) }
    static var uiPrimaryLight: UIColor { UIColor(primaryLight) }
    static var uiPrimaryDark: UIColor { UIColor(primaryDark) }
    static var uiSecondary: UIColor { UIColor(secondary) }
    static var uiSecondaryLight: UIColor { UIColor(secondaryLight) }
    static var uiSuccess: UIColor { UIColor(success) }
    static var uiWarning: UIColor { UIColor(warning) }
    static var uiError: UIColor { UIColor(error) }
    static var uiInfo: UIColor { UIColor(info) }
    static var uiBackground: UIColor { UIColor(background) }
    static var uiSurface: UIColor { UIColor(surface) }
    static var uiInputFill: UIColor { UIColor(inputFill) }
    static var uiDarkBackground: UIColor { UIColor(darkBackground) }
    static var uiDarkSurface: UIColor { UIColor(darkSurface) }
    static var uiTextPrimary: UIColor { UIColor(textPrimary) }
    static var uiTextSecondary: UIColor { UIColor(textSecondary) }
    static var uiTextHint: UIColor { UIColor(textHint) }
    static var uiTextOnPrimary: UIColor { UIColor(textOnPrimary) }
}

// Extension for Color to support hex initialization
extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

// Extension for UIColor to support hex initialization (for UIKit)
extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
    
    convenience init(_ color: Color) {
        self.init(cgColor: color.cgColor!)
    }
}
