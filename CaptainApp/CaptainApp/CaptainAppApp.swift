//
//  CaptainAppApp.swift
//  CaptainApp
//
//  Created by user on 09/02/2026.
//

import SwiftUI

@main
struct CaptainAppApp: App {
    @StateObject private var languageSettings = AppLanguageSettings()
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var homeViewModel = HomeViewModel()
    @StateObject private var rideViewModel = RideViewModel(webSocketService: WebSocketService())

    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.state == .authenticated {
                    HomePage()
                        .environmentObject(homeViewModel)
                        .environmentObject(authViewModel)
                        .environmentObject(rideViewModel)
                } else {
                    LoginScreen()
                        .environmentObject(authViewModel)
                        .environmentObject(homeViewModel)
                        .environmentObject(rideViewModel)
                }
            }
                .environmentObject(languageSettings)
                .environment(\.locale, languageSettings.locale)
                .environment(\.layoutDirection, languageSettings.layoutDirection)
        }
    }
}
