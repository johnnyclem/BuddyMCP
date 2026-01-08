import Foundation

@MainActor
final class ToolUsageManager: ObservableObject {
    static let shared = ToolUsageManager()
    
    @Published var isActive = false
    @Published var activeToolName: String = ""
    @Published var activeServerName: String = ""
    @Published var activeTintHex: String?
    @Published private(set) var logEntries: [ToolUsageLogEntry] = []
    @Published private(set) var agentSummaries: [AgentUsageSummary] = []
    @Published var activeAgentName: String = ""
    
    private var activeEntry: ToolUsageLogEntry?
    private let maxLogEntries = 200
    
    private init() {}
    
    func start(agentName: String, serverName: String, toolName: String, tintHex: String?) {
        activeServerName = serverName
        activeToolName = toolName
        activeTintHex = tintHex
        activeAgentName = agentName
        isActive = true
        
        activeEntry = ToolUsageLogEntry(
            agentName: agentName,
            serverName: serverName,
            toolName: toolName,
            tintHex: tintHex,
            startedAt: Date(),
            endedAt: nil,
            succeeded: nil
        )
        
        rebuildAgentSummaries()
    }
    
    func stop(succeeded: Bool? = nil) {
        isActive = false
        activeToolName = ""
        activeServerName = ""
        activeTintHex = nil
        activeAgentName = ""
        
        if var entry = activeEntry {
            entry.endedAt = Date()
            if let succeeded {
                entry.succeeded = succeeded
            }
            logEntries.append(entry)
            if logEntries.count > maxLogEntries {
                logEntries.removeFirst(logEntries.count - maxLogEntries)
            }
            rebuildAgentSummaries()
        }
        
        activeEntry = nil
    }
    
    private func rebuildAgentSummaries() {
        var summaries: [String: AgentUsageSummary] = [:]
        
        func add(tool: String, for agent: String, timestamp: Date?) {
            var summary = summaries[agent] ?? AgentUsageSummary(agentName: agent, tools: [], lastUsedAt: nil)
            if !summary.tools.contains(tool) {
                summary.tools.append(tool)
                summary.tools.sort()
            }
            if let timestamp {
                if let existing = summary.lastUsedAt {
                    summary.lastUsedAt = max(existing, timestamp)
                } else {
                    summary.lastUsedAt = timestamp
                }
            }
            summaries[agent] = summary
        }
        
        for entry in logEntries {
            add(tool: entry.toolName, for: entry.agentName, timestamp: entry.completedAt ?? entry.startedAt)
        }
        
        if let entry = activeEntry {
            add(tool: entry.toolName, for: entry.agentName, timestamp: entry.startedAt)
        }
        
        agentSummaries = summaries.values.sorted { lhs, rhs in
            let lhsDate = lhs.lastUsedAt ?? .distantPast
            let rhsDate = rhs.lastUsedAt ?? .distantPast
            return lhsDate > rhsDate
        }
    }
}

struct ToolUsageLogEntry: Identifiable {
    let id = UUID()
    let agentName: String
    let serverName: String
    let toolName: String
    let tintHex: String?
    let startedAt: Date
    var endedAt: Date?
    var succeeded: Bool?
    
    var completedAt: Date? {
        endedAt
    }
    
    var durationDescription: String {
        guard let endedAt else { return "in progress" }
        let interval = endedAt.timeIntervalSince(startedAt)
        if interval < 1 {
            return "<1s"
        } else if interval < 60 {
            return "\(Int(interval))s"
        } else {
            let minutes = Int(interval) / 60
            let seconds = Int(interval) % 60
            return "\(minutes)m \(seconds)s"
        }
    }
    
    var statusLabel: String {
        if let succeeded {
            return succeeded ? "SUCCESS" : "FAILED"
        }
        return "COMPLETED"
    }
}

struct AgentUsageSummary: Identifiable {
    let id = UUID()
    let agentName: String
    var tools: [String]
    var lastUsedAt: Date?
}
