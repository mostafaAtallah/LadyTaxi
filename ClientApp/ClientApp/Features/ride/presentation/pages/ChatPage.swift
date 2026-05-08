import SwiftUI
import Combine

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let senderId: String
    let text: String
    let timestamp: Date
    let isMe: Bool
    let clientId: String?
}

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var messageText: String = ""
    
    private let rideId: String
    private let driverId: String?
    private let socketService = WebSocketService.shared
    private var cancellables = Set<AnyCancellable>()
    private var pendingClientMessageIds = Set<String>()
    
    init(rideId: String, driverId: String?) {
        self.rideId = rideId
        self.driverId = driverId
        let token = UserDefaults.standard.string(forKey: "auth_token")
            ?? UserDefaults.standard.string(forKey: "token")
            ?? UserDefaults.standard.string(forKey: "access_token")
        socketService.connectIfNeeded(token: token)
        subscribeToMessages()
    }
    
    func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        guard let userId = currentUserId() else {
            print("ChatViewModel: missing user id, cannot send message.")
            return
        }
        let token = UserDefaults.standard.string(forKey: "auth_token")
            ?? UserDefaults.standard.string(forKey: "token")
            ?? UserDefaults.standard.string(forKey: "access_token")
        guard let token, !token.isEmpty else {
            print("ChatViewModel: missing auth token, cannot send message.")
            return
        }
        let clientMessageId = UUID().uuidString
        let payload: [String: Any] = [
            "ride_id": rideId,
            "message": trimmed,
            "user_id": userId,
            "userId": userId,
            "sender_id": userId,
            "senderId": userId,
            "driver_id": driverId ?? "",
            "driverId": driverId ?? "",
            "receiver_id": driverId ?? "",
            "recipient_id": driverId ?? "",
            "client_message_id": clientMessageId,
            "clientMessageId": clientMessageId
        ]

        DispatchQueue.main.async {
            let newMessage = ChatMessage(
                id: UUID().uuidString,
                senderId: userId,
                text: trimmed,
                timestamp: Date(),
                isMe: true,
                clientId: clientMessageId
            )
            self.messages.append(newMessage)
            self.pendingClientMessageIds.insert(clientMessageId)
            self.messageText = ""
        }

        socketService.connectIfNeeded(token: token)
        sendChatPayload(payload, token: token, attempt: 1, maxAttempts: 3)
    }

    private func subscribeToMessages() {
        socketService.chatMessagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                guard let self = self else { return }
                
                let incomingRideId = String(describing: payload["ride_id"]
                    ?? payload["rideId"]
                    ?? payload["rideID"]
                    ?? payload["ride"]
                    ?? "")
                guard incomingRideId == self.rideId else { return }
                
                let senderId = String(describing: payload["sender_id"]
                    ?? payload["senderId"]
                    ?? payload["senderID"]
                    ?? payload["user_id"]
                    ?? payload["userId"]
                    ?? "")
                let userId = self.currentUserId() ?? ""
                
                let clientMessageId = String(describing: payload["client_message_id"]
                    ?? payload["clientMessageId"]
                    ?? payload["message_id"]
                    ?? payload["messageId"]
                    ?? "")
                if !clientMessageId.isEmpty, self.pendingClientMessageIds.contains(clientMessageId) {
                    self.pendingClientMessageIds.remove(clientMessageId)
                    return
                }
                
                // Avoid double-adding my own messages if they come back from server
                if !userId.isEmpty, senderId == userId { return }
                
                let text = payload["message"] as? String
                    ?? payload["text"] as? String
                    ?? payload["body"] as? String
                    ?? payload["content"] as? String
                    ?? ""
                let timestampStr = payload["timestamp"] as? String ?? ""
                let timestamp = ISO8601DateFormatter().date(from: timestampStr) ?? Date()
                
                let newMessage = ChatMessage(
                    id: UUID().uuidString,
                    senderId: senderId,
                    text: text,
                    timestamp: timestamp,
                    isMe: false,
                    clientId: clientMessageId.isEmpty ? nil : clientMessageId
                )
                self.messages.append(newMessage)
            }
            .store(in: &cancellables)
    }

    private func currentUserId() -> String? {
        let userId = UserDefaults.standard.string(forKey: "user_id")
            ?? UserDefaults.standard.string(forKey: "userId")
            ?? UserDefaults.standard.string(forKey: "auth_user_id")
            ?? UserDefaults.standard.string(forKey: "id")
        return (userId?.isEmpty == false) ? userId : nil
    }

    private func sendChatPayload(
        _ payload: [String: Any],
        token: String,
        attempt: Int,
        maxAttempts: Int
    ) {
        socketService.send(event: "send_chat_message", data: payload) { [weak self] success in
            guard let self else { return }
            if success { return }

            guard attempt < maxAttempts else {
                print("ChatViewModel: send_chat_message failed after \(attempt) attempts.")
                return
            }

            let delay = Double(attempt) * 0.6
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.socketService.connectIfNeeded(token: token)
                self.sendChatPayload(payload, token: token, attempt: attempt + 1, maxAttempts: maxAttempts)
            }
        }
    }
}

struct ChatPage: View {
    let driverName: String
    @StateObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(rideId: String, driverId: String?, driverName: String) {
        self.driverName = driverName
        _viewModel = StateObject(wrappedValue: ChatViewModel(rideId: rideId, driverId: driverId))
    }
    
    var body: some View {
        VStack {
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages) { _ in
                    if let lastId = viewModel.messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input Area
            HStack(spacing: 12) {
                TextField(L10n.t("chat.placeholder"), text: $viewModel.messageText)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(20)
                
                Button(action: viewModel.sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(viewModel.messageText.isEmpty ? Color.gray : Color.blue)
                        .clipShape(Circle())
                }
                .disabled(viewModel.messageText.isEmpty)
            }
            .padding()
            .background(Color(.systemBackground))
            .shadow(radius: 2)
        }
        .navigationTitle(driverName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isMe { Spacer() }
            
            Text(message.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(message.isMe ? Color.blue : Color(.systemGray5))
                .foregroundColor(message.isMe ? .white : .primary)
                .cornerRadius(18)
                .frame(maxWidth: 280, alignment: message.isMe ? .trailing : .leading)
            
            if !message.isMe { Spacer() }
        }
    }
}
