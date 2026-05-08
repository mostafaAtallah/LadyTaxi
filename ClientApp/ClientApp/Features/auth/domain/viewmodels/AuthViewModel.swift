import Foundation

@MainActor
class AuthViewModel: ObservableObject {
    @Published var state: AuthState = .idle

    public func register(firstName: String, familyName: String, phone: String, email: String, gender: String, birthDate: Date, password: String, authManager: AuthManager) {
        state = .loading
        
        guard let url = URL(string: ApiConstants.baseUrl + ApiConstants.registerUser) else {
            state = .error("Invalid API URL.")
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let body: [String: String] = [
            "firstName": firstName,
            "familyName": familyName,
            "phoneNumber": phone,
            "email": email,
            "password": password,
            "gender": gender,
            "dateOfBirth": dateFormatter.string(from: birthDate)
        ]

        guard let finalBody = try? JSONSerialization.data(withJSONObject: body) else {
            state = .error("Failed to create request body.")
            return
        }
        
        // DEBUG: Print the request body
        if let jsonString = String(data: finalBody, encoding: .utf8) {
            print("DEBUG: Registration Request Body: \(jsonString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = finalBody
        request.addValue(ApiConstants.applicationJson, forHTTPHeaderField: ApiConstants.contentType)
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeout / 1000)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                // DEBUG: Print response details
                print("DEBUG: Registration Response: \(response.debugDescription)")
                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("DEBUG: Registration Response Data: \(responseString)")
                }
                
                if let error = error {
                    self?.state = .error("Registration failed: \(error.localizedDescription)")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    if let httpResponse = response as? HTTPURLResponse {
                        let message = (data.flatMap { String(data: $0, encoding: .utf8) } ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if message.isEmpty {
                            self?.state = .error("Registration failed with status code: \(httpResponse.statusCode). Please check your details and try again.")
                        } else {
                            self?.state = .error("Registration failed (\(httpResponse.statusCode)): \(message)")
                        }
                    } else {
                        self?.state = .error("Registration failed. Please check your details and try again.")
                    }
                    return
                }
                
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let token = (json["token"] as? String) ?? (json["Token"] as? String)
                    let userDict = json["user"] as? [String: Any] ?? json["User"] as? [String: Any]
                    let userIdValue = userDict?["id"] ?? userDict?["Id"]
                    let userId = (userIdValue as? Int).map(String.init) ?? (userIdValue as? String)
                    if let token {
                        authManager.login(token: token, userId: userId)
                    }
                }
                self?.state = .authenticated
            }
        }.resume()
    }

    public func login(email: String, password: String, loginAs: String, authManager: AuthManager) {
        state = .loading
        
        guard let url = URL(string: ApiConstants.baseUrl + ApiConstants.login) else {
            state = .error("Invalid API URL.")
            return
        }

        let body: [String: String] = [
            "email": email,
            "password": password,
            "loginAs": loginAs
        ]
        
        guard let finalBody = try? JSONSerialization.data(withJSONObject: body) else {
            state = .error("Failed to create request body.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = finalBody
        request.addValue(ApiConstants.applicationJson, forHTTPHeaderField: ApiConstants.contentType)
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeout / 1000)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.state = .error("Login failed: \(error.localizedDescription)")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    let message = (data.flatMap { String(data: $0, encoding: .utf8) } ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.state = .error(message.isEmpty ? "Invalid credentials." : message)
                    return
                }
                
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let token = (json["token"] as? String) ?? (json["Token"] as? String)
                    let userDict = json["user"] as? [String: Any] ?? json["User"] as? [String: Any]
                    let userIdValue = userDict?["id"] ?? userDict?["Id"]
                    let userId = (userIdValue as? Int).map(String.init) ?? (userIdValue as? String)
                    if let token {
                        authManager.login(token: token, userId: userId)
                    }
                }

                self?.state = .authenticated
            }
        }.resume()
    }
}
