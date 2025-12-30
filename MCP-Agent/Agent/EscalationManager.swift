import Foundation
import UserNotifications
import OSLog

class EscalationManager {
    static let shared = EscalationManager()
    private let logger = Logger(subsystem: "com.mcp.agent", category: "EscalationManager")
    private var canUseNotifications: Bool = false
    
    private init() {
        // UNUserNotificationCenter requires a valid bundle identifier.
        // When running via 'swift run', bundle identifier might be nil or the binary is not in a bundle.
        if Bundle.main.bundleIdentifier != nil {
            canUseNotifications = true
            requestAuthorization()
        } else {
            logger.warning("Running in non-bundled environment. Notifications disabled.")
        }
    }
    
    private func requestAuthorization() {
        guard canUseNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                self.logger.error("Notification permission denied: \(error.localizedDescription)")
            }
        }
    }
    
    func sendEscalation(reason: String, message: String) async throws -> [String: Any] {
        logger.warning("Escalation: \(reason) - \(message)")
        
        if canUseNotifications {
            let content = UNMutableNotificationContent()
            content.title = "Agent Escalation: \(reason)"
            content.body = message
            content.sound = .defaultCritical
            
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            
            try await UNUserNotificationCenter.current().add(request)
        } else {
            // Fallback: Just log it (already done above) or maybe print to stdout
            print("Escalation (No Notification): \(reason): \(message)")
        }
        
        return ["success": true, "status": "sent"]
    }
}
