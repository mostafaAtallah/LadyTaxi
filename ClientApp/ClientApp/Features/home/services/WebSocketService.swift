import Foundation
import Combine

final class WebSocketService {
    static let shared = WebSocketService()

    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private(set) var isConnected = false
    private var authToken: String?
    private var reconnectAttempt = 0
    private var isManuallyDisconnected = false
    private var pingTimer: Timer?

    let rideAcceptedPublisher = PassthroughSubject<[String: Any], Never>()
    let rideStatusPublisher = PassthroughSubject<[String: Any], Never>()
    let driverLocationPublisher = PassthroughSubject<[String: Any], Never>()
    let chatMessagePublisher = PassthroughSubject<[String: Any], Never>()

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = TimeInterval(ApiConstants.connectionTimeout / 1000)
        configuration.timeoutIntervalForResource = TimeInterval(ApiConstants.receiveTimeout / 1000)
        session = URLSession(configuration: configuration)
    }

    func connectIfNeeded(token: String? = nil) {
        guard !isConnected else { return }
        connect(token: token)
    }

    func connect(token: String? = nil) {
        let resolvedToken = token ?? currentAuthToken()
        guard let resolvedToken, !resolvedToken.isEmpty else {
            print("WebSocketService: missing auth token, cannot connect.")
            return
        }

        isManuallyDisconnected = false
        authToken = resolvedToken

        guard let wsURL = buildWebSocketURL(token: resolvedToken) else {
            print("WebSocketService: invalid socket URL.")
            return
        }

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = session.webSocketTask(with: wsURL)
        webSocketTask?.resume()
        isConnected = true
        reconnectAttempt = 0
        startPing()

        receive()
        print("WebSocketService: connected to \(wsURL.absoluteString)")
    }

    func disconnect() {
        isManuallyDisconnected = true
        authToken = nil
        reconnectAttempt = 0
        stopPing()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        print("WebSocketService: disconnected.")
    }

    func send(
        event: String,
        data: [String: Any],
        completion: ((Bool) -> Void)? = nil
    ) {
        guard isConnected, let webSocketTask else {
            print("WebSocketService: send skipped, socket is not connected.")
            completion?(false)
            return
        }

        let payload: [String: Any] = ["event": event, "data": data]
        guard let encoded = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: encoded, encoding: .utf8) else {
            print("WebSocketService: failed to encode event \(event).")
            completion?(false)
            return
        }

        webSocketTask.send(.string(json)) { [weak self] error in
            if let error {
                print("WebSocketService: send error for \(event): \(error.localizedDescription)")
                self?.isConnected = false
                self?.scheduleReconnectIfNeeded()
                completion?(false)
                return
            }
            completion?(true)
        }
    }

    func sendFindDriverRequest(rideId: String, tripLocationData: TripLocationData) {
        let userId = UserDefaults.standard.string(forKey: "user_id")
            ?? UserDefaults.standard.string(forKey: "userId")
            ?? "0"

        let payload: [String: Any] = [
            "ride_id": rideId,
            "user_id": userId,
            "pickup_lat": tripLocationData.pickupLocation?.latitude ?? 0,
            "pickup_lng": tripLocationData.pickupLocation?.longitude ?? 0,
            "dropoff_lat": tripLocationData.dropoffLocation?.latitude ?? 0,
            "dropoff_lng": tripLocationData.dropoffLocation?.longitude ?? 0,
            "pickup_address": tripLocationData.pickupAddress,
            "dropoff_address": tripLocationData.dropoffAddress
        ]

        connectIfNeeded()
        sendRideRequestWithRetry(payload: payload, attempt: 1, maxAttempts: 4)
    }

    private func sendRideRequestWithRetry(
        payload: [String: Any],
        attempt: Int,
        maxAttempts: Int
    ) {
        send(event: "request_ride", data: payload) { [weak self] sent in
            guard let self else { return }

            if sent {
                print("WebSocketService: request_ride sent successfully on attempt \(attempt).")
                return
            }

            guard attempt < maxAttempts else {
                print("WebSocketService: request_ride failed after \(attempt) attempts.")
                return
            }

            let delay = Double(attempt) * 0.8
            print("WebSocketService: retrying request_ride in \(delay)s (attempt \(attempt + 1)/\(maxAttempts)).")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.connectIfNeeded()
                self?.sendRideRequestWithRetry(payload: payload, attempt: attempt + 1, maxAttempts: maxAttempts)
            }
        }
    }

    private func receive() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                self.handle(message: message)
                self.receive()
            case .failure(let error):
                print("WebSocketService: receive error: \(error.localizedDescription)")
                self.isConnected = false
                self.stopPing()
                self.scheduleReconnectIfNeeded()
            }
        }
    }

    private func scheduleReconnectIfNeeded() {
        guard !isManuallyDisconnected else { return }
        guard let token = authToken else { return }

        let delay = min(20.0, pow(2.0, Double(reconnectAttempt)))
        reconnectAttempt += 1
        print("WebSocketService: reconnect scheduled in \(delay)s")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard !self.isConnected else { return }
            guard !self.isManuallyDisconnected else { return }
            self.connect(token: token)
        }
    }

    private func startPing() {
        stopPing()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.webSocketTask?.sendPing { error in
                if let error {
                    print("WebSocketService: ping failed: \(error.localizedDescription)")
                    self?.isConnected = false
                    self?.stopPing()
                    self?.scheduleReconnectIfNeeded()
                }
            }
        }
    }

    private func stopPing() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let string):
            text = string
        case .data(let data):
            text = String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            return
        }

        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("WebSocketService: invalid message payload.")
            return
        }

        let event = root["event"] as? String ?? root["@event"] as? String ?? ""
        var eventData = root["data"] as? [String: Any] ?? [:]

        // Some backends send event payload at root-level instead of under "data".
        if eventData.isEmpty {
            eventData = root
        }

        if !event.isEmpty {
            print("WebSocketService: received event \(event) with keys \(Array(eventData.keys).sorted())")
        }

        switch event {
        case "ride_accepted",
             "driver_assigned",
             "ride_assigned",
             "trip_accepted",
             "accept_ride":
            rideAcceptedPublisher.send(eventData)
        case "ride_status_updated",
             "trip_status_updated",
             "ride_completed",
             "trip_completed":
            rideStatusPublisher.send(eventData)
        case "driver_location_updated":
            driverLocationPublisher.send(eventData)
        case "chat_message",
             "chat_message_received",
             "receive_chat_message",
             "chatMessage",
             "message":
            chatMessagePublisher.send(eventData)
        default:
            break
        }
    }

    private func buildWebSocketURL(token: String) -> URL? {
        guard var components = URLComponents(string: ApiConstants.socketUrl) else {
            return nil
        }

        if components.scheme == "https" {
            components.scheme = "wss"
        } else if components.scheme == "http" {
            components.scheme = "ws"
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = "ws"
        if basePath.isEmpty {
            components.path = "/\(endpointPath)"
        } else {
            components.path = "/\(basePath)/\(endpointPath)"
        }

        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    private func currentAuthToken() -> String? {
        UserDefaults.standard.string(forKey: "auth_token")
        ?? UserDefaults.standard.string(forKey: "token")
        ?? UserDefaults.standard.string(forKey: "access_token")
    }
}
