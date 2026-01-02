import AppKit
import SwiftUI

struct DebugSettingsView: View {
    @ObservedObject var chatHistory = ChatHistoryStore.shared
    @ObservedObject var logManager = DebugLogManager.shared
    @StateObject private var serviceMonitor = DebugServiceMonitor()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("DEBUG TOOLS")
                    .font(Theme.uiFont(size: 12, weight: .bold))
                    .tracking(2)
                    .padding(.bottom, 8)
                    .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.borderColor), alignment: .bottom)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("CHAT HISTORY")
                        .font(Theme.uiFont(size: 10, weight: .bold))
                    
                    Text("Messages: \(chatHistory.messages.count)")
                        .font(Theme.bodyFont(size: 12))
                        .foregroundColor(Theme.inkBlack.opacity(0.7))
                    
                    Button("COPY CHAT HISTORY") {
                        copyToPasteboard(chatHistory.transcript())
                    }
                    .newsprintButton(isPrimary: false)
                    .disabled(chatHistory.messages.isEmpty)
                }
                .padding(16)
                .newsprintCard()
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("DEBUG LOG")
                            .font(Theme.uiFont(size: 10, weight: .bold))
                        Spacer()
                        Button("COPY LOG") {
                            copyToPasteboard(logManager.exportText())
                        }
                        .newsprintButton(isPrimary: false)
                        .disabled(logManager.entries.isEmpty)
                        
                        Button("CLEAR LOG") {
                            logManager.clear()
                        }
                        .newsprintButton(isPrimary: false)
                        .disabled(logManager.entries.isEmpty)
                    }
                    
                    if logManager.entries.isEmpty {
                        Text("No debug entries yet.")
                            .font(Theme.bodyFont(size: 12))
                            .foregroundColor(Theme.inkBlack.opacity(0.7))
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(logManager.entries.reversed())) { entry in
                                DebugLogRow(entry: entry)
                            }
                        }
                    }
                }
                .padding(16)
                .newsprintCard()
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("SERVICES & PROVIDERS")
                            .font(Theme.uiFont(size: 10, weight: .bold))
                        Spacer()
                        Button("REFRESH") {
                            Task {
                                await serviceMonitor.refresh()
                            }
                        }
                        .newsprintButton(isPrimary: false)
                        
                        if serviceMonitor.isRefreshing {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                    
                    if let lastRefresh = serviceMonitor.lastRefresh {
                        Text("Last checked: \(serviceMonitor.formatTimestamp(lastRefresh))")
                            .font(Theme.bodyFont(size: 12))
                            .foregroundColor(Theme.inkBlack.opacity(0.7))
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PROCESSES")
                            .font(Theme.uiFont(size: 9, weight: .bold))
                        ForEach(serviceMonitor.processStatuses) { status in
                            StatusRow(title: status.name, status: status.statusLabel, detail: status.detail, isHealthy: status.isRunning)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LLM PROVIDERS")
                            .font(Theme.uiFont(size: 9, weight: .bold))
                        ForEach(serviceMonitor.providerStatuses) { status in
                            StatusRow(title: status.name, status: status.statusLabel, detail: status.detail, isHealthy: status.isHealthy)
                        }
                    }
                }
                .padding(16)
                .newsprintCard()
            }
            .padding()
        }
        .background(Theme.background)
        .onAppear {
            Task {
                await serviceMonitor.refresh()
            }
        }
    }
    
    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

struct DebugLogRow: View {
    let entry: DebugLogEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("[\(timestamp(entry.timestamp))] \(entry.level.rawValue) · \(entry.category)")
                .font(Theme.monoFont(size: 11))
                .foregroundColor(entry.level == .error ? Theme.editorialRed : Theme.inkBlack)
            Text(entry.message)
                .font(Theme.bodyFont(size: 12))
            if let details = entry.details, !details.isEmpty {
                Text(details)
                    .font(Theme.monoFont(size: 11))
                    .foregroundColor(Theme.inkBlack.opacity(0.75))
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .newsprintCard()
    }
    
    private func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct StatusRow: View {
    let title: String
    let status: String
    let detail: String
    let isHealthy: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(Theme.bodyFont(size: 13))
                Spacer()
                Text(status.uppercased())
                    .font(Theme.monoFont(size: 10))
                    .foregroundColor(isHealthy ? Theme.inkBlack : Theme.editorialRed)
            }
            Text(detail)
                .font(Theme.bodyFont(size: 11))
                .foregroundColor(Theme.inkBlack.opacity(0.7))
        }
        .padding(12)
        .newsprintCard()
    }
}

@MainActor
final class DebugServiceMonitor: ObservableObject {
    @Published var processStatuses: [ProcessStatus] = []
    @Published var providerStatuses: [ProviderStatus] = []
    @Published var lastRefresh: Date?
    @Published var isRefreshing = false
    
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        async let processes = fetchProcessStatuses()
        async let providers = fetchProviderStatuses()
        
        processStatuses = await processes
        providerStatuses = await providers
        lastRefresh = Date()
    }
    
    func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func fetchProcessStatuses() async -> [ProcessStatus] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let statuses = [
                    Self.processStatus(name: "BuddyMCP", pattern: "BuddyMCP"),
                    Self.processStatus(name: "Agent Core (agent_core.py)", pattern: "agent_core.py"),
                    Self.processStatus(name: "AgentDaemon", pattern: "AgentDaemon")
                ]
                continuation.resume(returning: statuses)
            }
        }
    }
    
    private func fetchProviderStatuses() async -> [ProviderStatus] {
        var statuses: [ProviderStatus] = []
        
        let ollamaStatus = await checkEndpoint(
            name: "Ollama (local)",
            urlString: "http://localhost:11434/api/tags",
            headers: [:]
        )
        statuses.append(ollamaStatus)
        
        let lmStudioStatus = await checkEndpoint(
            name: "LM Studio (local)",
            urlString: "http://localhost:1234/v1/models",
            headers: [:]
        )
        statuses.append(lmStudioStatus)
        
        let llmManager = LLMManager.shared
        let remoteBase = llmManager.remoteBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if remoteBase.isEmpty {
            statuses.append(ProviderStatus(name: "Remote LLM (OpenAI-compatible)", status: .unknown, detail: "Not configured"))
        } else if let apiKey = KeychainManager.shared.retrieveOpenAICompatibleKey() {
            if let modelsURL = URL(string: remoteBase)?.appendingPathComponent("models").absoluteString {
                let remote = await checkEndpoint(
                    name: "Remote LLM (OpenAI-compatible)",
                    urlString: modelsURL,
                    headers: ["Authorization": "Bearer \(apiKey)"]
                )
                statuses.append(remote)
            } else {
                statuses.append(ProviderStatus(name: "Remote LLM (OpenAI-compatible)", status: .unknown, detail: "Invalid base URL"))
            }
        } else {
            statuses.append(ProviderStatus(name: "Remote LLM (OpenAI-compatible)", status: .degraded, detail: "Missing API key"))
        }
        
        return statuses
    }
    
    private nonisolated static func processStatus(name: String, pattern: String) -> ProcessStatus {
        let pids = matchingPids(pattern: pattern)
        let isRunning = !pids.isEmpty
        let detail = isRunning ? "Running (PID \(pids.joined(separator: ", ")))" : "Not running"
        return ProcessStatus(name: name, isRunning: isRunning, detail: detail)
    }
    
    private nonisolated static func matchingPids(pattern: String) -> [String] {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-f", pattern]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
        } catch {
            return []
        }
        
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return [] }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(separator: "\n").map { String($0) }
    }
    
    private func checkEndpoint(name: String, urlString: String, headers: [String: String]) async -> ProviderStatus {
        guard let url = URL(string: urlString) else {
            return ProviderStatus(name: name, status: .unknown, detail: "Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 3.0
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        DebugLogManager.shared.logNetworkRequest(context: "\(name) health", request: request)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return ProviderStatus(name: name, status: .unknown, detail: "No HTTP response")
            }
            DebugLogManager.shared.logNetworkResponse(context: "\(name) health", response: httpResponse)
            let ok = (200...299).contains(httpResponse.statusCode)
            return ProviderStatus(
                name: name,
                status: ok ? .healthy : .degraded,
                detail: "HTTP \(httpResponse.statusCode)"
            )
        } catch {
            DebugLogManager.shared.logNetworkError(context: "\(name) health", error: error)
            return ProviderStatus(name: name, status: .down, detail: error.localizedDescription)
        }
    }
}

struct ProcessStatus: Identifiable {
    let id = UUID()
    let name: String
    let isRunning: Bool
    let detail: String
    
    var statusLabel: String {
        isRunning ? "Running" : "Stopped"
    }
}

enum ServiceHealth: String {
    case healthy
    case degraded
    case down
    case unknown
}

struct ProviderStatus: Identifiable {
    let id = UUID()
    let name: String
    let status: ServiceHealth
    let detail: String
    
    var statusLabel: String {
        switch status {
        case .healthy: return "Healthy"
        case .degraded: return "Degraded"
        case .down: return "Down"
        case .unknown: return "Unknown"
        }
    }
    
    var isHealthy: Bool {
        status == .healthy
    }
}
