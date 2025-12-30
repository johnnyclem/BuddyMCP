import Foundation
import UserNotifications

struct ApprovalRequest: Identifiable {
    let id = UUID()
    let toolName: String
    let arguments: [String: Any]
    let timestamp: Date
    let continuation: CheckedContinuation<Bool, Never>
}

@MainActor
class ApprovalManager: ObservableObject {
    static let shared = ApprovalManager()
    
    @Published var pendingRequests: [ApprovalRequest] = []
    
    private init() {}
    
    func requestApproval(toolName: String, arguments: [String: Any]) async -> Bool {
        // Send notification
        sendNotification(toolName: toolName)
        
        return await withCheckedContinuation { continuation in
            let request = ApprovalRequest(
                toolName: toolName,
                arguments: arguments,
                timestamp: Date(),
                continuation: continuation
            )
            pendingRequests.append(request)
        }
    }
    
    func approveRequest(_ request: ApprovalRequest) {
        if let index = pendingRequests.firstIndex(where: { $0.id == request.id }) {
            pendingRequests.remove(at: index)
            request.continuation.resume(returning: true)
        }
    }
    
    func denyRequest(_ request: ApprovalRequest) {
        if let index = pendingRequests.firstIndex(where: { $0.id == request.id }) {
            pendingRequests.remove(at: index)
            request.continuation.resume(returning: false)
        }
    }
    
    private func sendNotification(toolName: String) {
        // Check if we can use notifications (valid bundle ID required)
        guard Bundle.main.bundleIdentifier != nil else {
            print("Approval needed for \(toolName) (Notification skipped: No bundle ID)")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Action Required"
        content.body = "Agent wants to execute: \(toolName)"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
