import Foundation
import Combine

class RideViewModel: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    
    private let socketService: WebSocketService

    init(webSocketService: WebSocketService) {
        self.socketService = webSocketService
    }

    var webSocketService: WebSocketService {
        socketService
    }
    
    /// Accepts a ride via HTTP and also emits the websocket accept signal for backends
    /// that rely on the socket event to notify the client app in real time.
    func acceptRide(rideId: String, authToken: String?) {
        print("CAPTAIN DEBUG: acceptRide started for ride \(rideId)")
        guard let url = ApiConstants.acceptRideUrl(id: rideId) else {
            sendAcceptRideSignal(rideId: rideId, source: "url_fallback")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeoutMs / 1000)

        if let token = authToken, !token.isEmpty {
            request.addValue("Bearer \(token)", forHTTPHeaderField: ApiConstants.authHeader)
        }

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error {
                print("Ride accept HTTP failed: \(error.localizedDescription). Sending WebSocket accept signal.")
                self?.sendAcceptRideSignal(rideId: rideId, source: "http_error")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("Ride accept HTTP failed: no HTTP response. Sending WebSocket accept signal.")
                self?.sendAcceptRideSignal(rideId: rideId, source: "missing_http_response")
                return
            }

            if (200...299).contains(httpResponse.statusCode) {
                print("CAPTAIN DEBUG: ride accepted via HTTP for \(rideId)")
                self?.updateRideStatus(rideId: rideId, status: "accepted", authToken: authToken)
                self?.sendAcceptRideSignal(rideId: rideId, source: "http_success")
            } else {
                print("CAPTAIN DEBUG: ride accept HTTP status \(httpResponse.statusCode) for \(rideId). Sending WebSocket accept signal.")
                self?.sendAcceptRideSignal(rideId: rideId, source: "http_status_\(httpResponse.statusCode)")
            }
        }.resume()
    }

    private func sendAcceptRideSignal(rideId: String, source: String) {
        let message: [String: Any] = [
            "event": "accept_ride",
            "data": ["ride_id": rideId]
        ]
        socketService.send(message)
        print("CAPTAIN DEBUG: accept_ride WebSocket signal sent (\(source)) for ride \(rideId)")
    }
    
    /// Rejects a ride (optional, if needed)
    func rejectRide(rideId: String) {
        let message: [String: Any] = [
            "event": "reject_ride",
            "data": ["ride_id": rideId]
        ]
        
        socketService.send(message)
        
        print("Ride rejected: \(rideId)")
    }

    func connectSocket(authToken: String) {
        socketService.connectIfNeeded(authToken: authToken)
    }

    func disconnectSocket() {
        socketService.disconnect()
    }

    func updateRideStatus(rideId: String, status: String, authToken: String?) {
        guard let url = ApiConstants.updateRideStatusUrl(id: rideId) else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeoutMs / 1000)
        request.addValue(ApiConstants.applicationJson, forHTTPHeaderField: ApiConstants.contentType)

        if let token = authToken, !token.isEmpty {
            request.addValue("Bearer \(token)", forHTTPHeaderField: ApiConstants.authHeader)
        }

        let payload: [String: Any] = ["status": status]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error {
                print("Update ride status HTTP failed: \(error.localizedDescription).")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("Update ride status HTTP failed: no HTTP response.")
                return
            }

            if (200...299).contains(httpResponse.statusCode) {
                print("CAPTAIN DEBUG: ride status updated via HTTP: \(rideId) -> \(status)")
            } else {
                print("CAPTAIN DEBUG: update ride status HTTP \(httpResponse.statusCode) for \(rideId) -> \(status)")
            }
        }.resume()
    }

    func addTripProgression(rideId: String, stage: String, authToken: String?) {
        guard let url = ApiConstants.addTripProgressionUrl(id: rideId) else {
            print("Trip progression URL invalid for ride \(rideId)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(ApiConstants.connectionTimeoutMs / 1000)
        request.addValue(ApiConstants.applicationJson, forHTTPHeaderField: ApiConstants.contentType)

        if let token = authToken, !token.isEmpty {
            request.addValue("Bearer \(token)", forHTTPHeaderField: ApiConstants.authHeader)
        }

        let payload: [String: Any] = ["stage": stage]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                print("Trip progression HTTP failed: \(error.localizedDescription)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("Trip progression HTTP failed: no HTTP response.")
                return
            }

            if (200...299).contains(httpResponse.statusCode) {
                print("Trip progression recorded via HTTP: \(rideId) -> \(stage)")
            } else {
                print("Trip progression HTTP \(httpResponse.statusCode) for \(rideId) -> \(stage)")
            }
        }.resume()
    }

}
