//
//  ClientAppApp.swift
//  ClientApp
//
//  Created by user on 02/02/2026.
//

import SwiftUI
import MapKit // Added import
import CoreLocation // Added import
import Combine // Added import

// Import AuthManager


@main
struct ClientAppApp: App {
    @StateObject private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            // Conditionally display LoginPage or HomePage based on authentication status
            ZStack {
                if authManager.isAuthenticated {
                    HomePage()
                } else {
                    LoginPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .environmentObject(authManager) // Provide AuthManager to the environment
        }
    }
}
