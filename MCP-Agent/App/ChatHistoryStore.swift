import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String
    var content: String
}

@MainActor
final class ChatHistoryStore: ObservableObject {
    static let shared = ChatHistoryStore()
    
    @Published var messages: [ChatMessage] = [
        ChatMessage(role: "agent", content: "Hello! I'm your BuddyMCP agent. How can I help you today?")
    ]
    
    private init() {}
    
    func transcript() -> String {
        messages.map { message in
            "[\(message.role.uppercased())] \(message.content)"
        }
        .joined(separator: "\n\n")
    }
}
