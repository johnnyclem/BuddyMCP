import Foundation

@MainActor
final class ToolUsageManager: ObservableObject {
    static let shared = ToolUsageManager()
    
    @Published var isActive = false
    @Published var activeToolName: String = ""
    @Published var activeServerName: String = ""
    @Published var activeTintHex: String?
    
    private init() {}
    
    func start(serverName: String, toolName: String, tintHex: String?) {
        activeServerName = serverName
        activeToolName = toolName
        activeTintHex = tintHex
        isActive = true
    }
    
    func stop() {
        isActive = false
        activeToolName = ""
        activeServerName = ""
        activeTintHex = nil
    }
}
