//
//  LoginPage.swift
//  ClientApp
//
//  Created by user on 02/02/2026.
//

import SwiftUI

struct LoginPage: View {
    @EnvironmentObject var authManager: AuthManager // Inject AuthManager
    @StateObject private var authVM = AuthViewModel()
    
    @State private var email = ""
    @State private var password = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                
                Text("Welcome Back!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 20)
                
                TextField("Email", text: $email)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                SecureField("Password", text: $password)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                
                if authVM.state == .loading {
                    ProgressView()
                        .padding()
                } else {
                    Button(action: {
                        authVM.login(email: email, password: password, loginAs: "client", authManager: authManager)
                    }) {
                        Text("Log in")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .padding(.top, 10)
                }
                
                Spacer()
                
                NavigationLink("Don't have an account? Sign Up", destination: RegisterView())
                    .foregroundColor(.blue)
            }
            .padding()
            .navigationTitle("Lady Taxi")
            .onChange(of: authVM.state) { state in
                if case .error(let message) = state {
                    alertMessage = message
                    showingAlert = true
                }
            }
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("Authentication"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
}
