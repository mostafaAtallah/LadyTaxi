import Foundation
import SwiftUI

enum AuthState: Equatable {
    case idle
    case loading
    case authenticated
    case error(String)
}

@MainActor
class AuthViewModel: ObservableObject {
    @Published var state: AuthState = .idle
    @Published var authToken: String?
    @Published var captainId: Int?
    @Published var isCaptainVerified: Bool = false
    private let authTokenKey = "captain_auth_token"
    private let captainIdKey = "captain_id"
    private let captainVerifiedKey = "captain_is_verified"

    init() {
        restoreSession()
    }

    func restoreSession() {
        let token = UserDefaults.standard.string(forKey: authTokenKey)
        let storedCaptainId = UserDefaults.standard.integer(forKey: captainIdKey)
        let hasCaptainId = UserDefaults.standard.object(forKey: captainIdKey) != nil
        let storedVerified = UserDefaults.standard.bool(forKey: captainVerifiedKey)

        if let token, !token.isEmpty {
            authToken = token
            captainId = hasCaptainId ? storedCaptainId : nil
            isCaptainVerified = storedVerified
            state = .authenticated
        } else {
            state = .idle
        }
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: authTokenKey)
        UserDefaults.standard.removeObject(forKey: captainIdKey)
        UserDefaults.standard.removeObject(forKey: captainVerifiedKey)
        authToken = nil
        captainId = nil
        isCaptainVerified = false
        state = .idle
    }
    public func registerCaptain(
        firstName: String,
        familyName: String,
        phone: String,
        email: String,
        gender: String,
        birthDate: Date,
        password: String,
        licenseNumber: String,
        licenseExpiryDate: Date,
        vehicleMake: String,
        vehicleModel: String,
        vehicleYear: Int,
        vehicleColor: String,
        plateNumber: String,
        licenseFrontDocumentURL: URL,
        licenseBackDocumentURL: URL,
        nationalityIdDocumentURL: URL,
        residentCardFrontDocumentURL: URL,
        residentCardBackDocumentURL: URL,
        passportDocumentURL: URL?,
        otherDocumentURLs: [URL]
    ) {
        state = .loading
        authToken = nil
        captainId = nil
        isCaptainVerified = false
        
        guard let url = URL(string: ApiConstants.baseUrl + ApiConstants.registerCaptainPath) else {
            state = .error("Invalid API URL.")
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let body: [String: String] = [
            "firstName": firstName,
            "FamilyName": familyName,
            "phoneNumber": phone,
            "email": email,
            "password": password,
            "gender": gender,
            "dateOfBirth": dateFormatter.string(from: birthDate),
            "licenseNumber": licenseNumber,
            "licenseExpiryDate": dateFormatter.string(from: licenseExpiryDate),
            "vehicleMake": vehicleMake,
            "vehicleModel": vehicleModel,
            "vehicleYear": String(vehicleYear),
            "vehicleColor": vehicleColor,
            "plateNumber": plateNumber
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
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeoutMs / 1000)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { [weak self] in
                // DEBUG: Print response details
                print("DEBUG: Registration Response: \(response.debugDescription)")
                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("DEBUG: Registration Response Data: \(responseString)")
                }
                
                if let error = error {
                    if let urlError = error as? URLError, urlError.code == .timedOut {
                        self?.state = .error("The request timed out. Please check your network connection and try again.")
                    } else {
                        self?.state = .error("Registration failed: \(error.localizedDescription)")
                    }
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    if let httpResponse = response as? HTTPURLResponse {
                        self?.state = .error("Registration failed with status code: \(httpResponse.statusCode). Please check your details and try again.")
                    } else {
                        self?.state = .error("Registration failed. Please check your details and try again.")
                    }
                    return
                }
                if let data {
                    self?.extractAuthData(from: data)
                }

                guard let self = self else { return }
                guard let token = self.authToken, let captainId = self.captainId else {
                    self.state = .error("Registration succeeded, but failed to get auth data for document upload.")
                    return
                }

                // Mark authenticated immediately after registration; uploads continue in background.
                self.state = .authenticated

                self.uploadRegistrationDocuments(
                    captainId: captainId,
                    authToken: token,
                    licenseFrontDocumentURL: licenseFrontDocumentURL,
                    licenseBackDocumentURL: licenseBackDocumentURL,
                    nationalityIdDocumentURL: nationalityIdDocumentURL,
                    residentCardFrontDocumentURL: residentCardFrontDocumentURL,
                    residentCardBackDocumentURL: residentCardBackDocumentURL,
                    passportDocumentURL: passportDocumentURL,
                    otherDocumentURLs: otherDocumentURLs
                ) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            break
                        case .failure(let error):
                            print("Registration succeeded, but file upload failed: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }.resume()
    }

    public func login(email: String, password: String, loginAs: String) {
        state = .loading
        authToken = nil
        captainId = nil
        isCaptainVerified = false
        
        guard let url = URL(string: ApiConstants.baseUrl + ApiConstants.loginPath) else {
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
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeoutMs / 1000)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { [weak self] in
                if let error = error {
                    if let urlError = error as? URLError, urlError.code == .timedOut {
                        self?.state = .error("The request timed out. Please check your network connection and try again.")
                    } else {
                        self?.state = .error("Login failed: \(error.localizedDescription)")
                    }
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    print("Login HTTP status: \(httpResponse.statusCode)")
                }
                if let data, let raw = String(data: data, encoding: .utf8) {
                    print("Login raw response: \(raw)")
                }

                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    self?.state = .error("Invalid credentials.")
                    return
                }
                
                if let data {
                    self?.extractAuthData(from: data)
                }
                self?.state = .authenticated
            }
        }.resume()
    }

    private func extractAuthData(from data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return
        }

        if let token = (json["token"] as? String), !token.isEmpty {
            authToken = token
        }

        if let nested = json["data"] as? [String: Any], let token = (nested["token"] as? String), !token.isEmpty {
            authToken = token
        }

        if let id = extractCaptainId(from: json) {
            captainId = id
        } else if let nested = json["data"] as? [String: Any], let id = extractCaptainId(from: nested) {
            captainId = id
        }

        if let isVerified = extractCaptainVerified(from: json) {
            isCaptainVerified = isVerified
        } else if let nested = json["data"] as? [String: Any], let isVerified = extractCaptainVerified(from: nested) {
            isCaptainVerified = isVerified
        }

        if let token = authToken, !token.isEmpty {
            UserDefaults.standard.set(token, forKey: authTokenKey)
        }
        if let captainId {
            UserDefaults.standard.set(captainId, forKey: captainIdKey)
        }
        UserDefaults.standard.set(isCaptainVerified, forKey: captainVerifiedKey)
    }

    private func extractCaptainId(from json: [String: Any]) -> Int? {
        if let user = json["user"] as? [String: Any] {
            if let id = user["captainId"] as? Int { return id }
            if let id = user["captain_id"] as? Int { return id }
        }
        if let captain = json["captain"] as? [String: Any] {
            if let id = captain["id"] as? Int { return id }
            if let id = captain["captainId"] as? Int { return id }
            if let id = captain["captain_id"] as? Int { return id }
        }
        if let id = json["captainId"] as? Int { return id }
        if let id = json["captain_id"] as? Int { return id }
        return nil
    }

    private func extractCaptainVerified(from json: [String: Any]) -> Bool? {
        if let user = json["user"] as? [String: Any] {
            if let value = user["isCaptainVerified"] as? Bool { return value }
            if let value = user["is_captain_verified"] as? Bool { return value }
            if let value = user["isVerified"] as? Bool { return value }
        }
        if let captain = json["captain"] as? [String: Any] {
            if let value = captain["isVerified"] as? Bool { return value }
            if let value = captain["IsVerified"] as? Bool { return value }
        }
        if let value = json["isCaptainVerified"] as? Bool { return value }
        if let value = json["is_captain_verified"] as? Bool { return value }
        return nil
    }

    private func uploadRegistrationDocuments(
        captainId: Int,
        authToken: String,
        licenseFrontDocumentURL: URL,
        licenseBackDocumentURL: URL,
        nationalityIdDocumentURL: URL,
        residentCardFrontDocumentURL: URL,
        residentCardBackDocumentURL: URL,
        passportDocumentURL: URL?,
        otherDocumentURLs: [URL],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var uploads: [(String, URL)] = [
            ("license_front", licenseFrontDocumentURL),
            ("license_back", licenseBackDocumentURL),
            ("nationality_id", nationalityIdDocumentURL),
            ("resident_card_front", residentCardFrontDocumentURL),
            ("resident_card_back", residentCardBackDocumentURL)
        ]

        if let passportDocumentURL = passportDocumentURL {
            uploads.append(("passport", passportDocumentURL))
        }

        for (index, fileURL) in otherDocumentURLs.enumerated() {
            uploads.append(("other_file_\(index + 1)", fileURL))
        }

        uploadNextDocument(
            uploads: uploads,
            currentIndex: 0,
            captainId: captainId,
            authToken: authToken,
            completion: completion
        )
    }

    private func uploadNextDocument(
        uploads: [(String, URL)],
        currentIndex: Int,
        captainId: Int,
        authToken: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if currentIndex >= uploads.count {
            completion(.success(()))
            return
        }

        let (documentType, fileURL) = uploads[currentIndex]
        uploadCaptainDocument(
            captainId: captainId,
            authToken: authToken,
            documentType: documentType,
            fileURL: fileURL
        ) { result in
            switch result {
            case .success:
                self.uploadNextDocument(
                    uploads: uploads,
                    currentIndex: currentIndex + 1,
                    captainId: captainId,
                    authToken: authToken,
                    completion: completion
                )
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func uploadCaptainDocument(
        captainId: Int,
        authToken: String,
        documentType: String,
        fileURL: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: "\(ApiConstants.baseUrl)/api/captains/\(captainId)/verification/documents") else {
            completion(.failure(NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid document upload URL."])))
            return
        }

        guard let fileData = readFileData(fileURL: fileURL) else {
            completion(.failure(NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not read selected file."])))
            return
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: ApiConstants.authHeader)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: ApiConstants.contentType)

        let fileName = fileURL.lastPathComponent
        let mimeType = mimeType(for: fileURL)
        var body = Data()

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"DocumentType\"\r\n\r\n")
        body.append("\(documentType)\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"File\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        URLSession.shared.uploadTask(with: request, from: body) { _, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid upload response."])))
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(NSError(domain: "Upload", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Upload failed with status code \(httpResponse.statusCode)."])))
                return
            }

            completion(.success(()))
        }.resume()
    }

    private func readFileData(fileURL: URL) -> Data? {
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        return try? Data(contentsOf: fileURL)
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "pdf":
            return "application/pdf"
        default:
            return "application/octet-stream"
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
