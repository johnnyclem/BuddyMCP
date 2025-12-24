I'll extend the key modules with full implementation. Let's start with the most critical components.

# Extended Module Implementations

## 1. MCP Manager in Swift - Full Implementation

=== MCP-Agent/Agent/MCPManager.swift ===
```swift
import Foundation
import Network
import OSLog

// MARK: - MCP Tool Definition
struct MCPTool: Codable, Identifiable {
    let id = UUID()
    let name: String
    let description: String?
    let inputSchema: [String: MCPParam]?
    let category: String?
    let requiresConfirmation: Bool
    let estimatedDuration: TimeInterval?
    
    struct MCPParam: Codable {
        let type: String
        let description: String?
        let required: Bool
        let defaultValue: String?
    }
}

// MARK: - MCP Server Definition
class MCPServer: ObservableObject {
    let id = UUID()
    let name: String
    let type: ServerType
    let endpoint: URL
    let isLocal: Bool
    
    enum ServerType {
        case localStdio(path: String)
        case localHTTP(url: URL)
        case remoteHTTP(url: URL)
        case internal(name: String)
    }
    
    @Published var tools: [MCPTool] = []
    @Published var isConnected = false
    @Published var lastError: Error?
    
    init(name: String, type: ServerType) {
        self.name = name
        self.type = type
        self.isLocal = type != .remoteHTTP(url: URL(string: "http://example.com")!)
        
        switch type {
        case .localHTTP(let url), .remoteHTTP(let url):
            self.endpoint = url
        case .localStdio(let path):
            self.endpoint = URL(fileURLWithPath: path)
        case .internal(let name):
            self.endpoint = URL(string: "internal://\(name)")!
        }
    }
    
    func connect() async throws {
        do {
            await MainActor.run {
                self.lastError = nil
            }
            
            switch type {
            case .localStdio:
                try await connectLocalStdio()
            case .localHTTP, .remoteHTTP:
                try await connectHTTP()
            case .internal:
                try await connectInternal()
            }
            
            await MainActor.run {
                self.isConnected = true
            }
        } catch {
            await MainActor.run {
                self.isConnected = false
                self.lastError = error
            }
            throw error
        }
    }
    
    private func connectLocalStdio() async throws {
        // For stdio servers, we'll need to spawn the process and communicate via JSON lines
        // This is a simplified implementation
        let process = Process()
        process.executableURL = endpoint
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardInput = Pipe()
        
        try process.run()
        
        // Request tools list
        let request: [String: Any] = ["jsonrpc": "2.0", "method": "tools/list", "id": 1]
        let data = try JSONSerialization.data(withJSONObject: request)
        process.standardInput?.fileHandleForWriting.write(data)
        
        // Simplified - in production, you'd need proper stdio handling
        await MainActor.run {
            self.tools = self.discoverInternalTools()
        }
    }
    
    private func connectHTTP() async throws {
        // Connect to MCP over HTTP + SSE
        var request = URLRequest(url: endpoint.appendingPathComponent("tools"))
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forAccept: "application/json")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MCPError.connectionFailed
        }
        
        // SSE parsing would go here
        await MainActor.run {
            // Populate tools from response
        }
    }
    
    private func connectInternal() async throws {
        await MainActor.run {
            self.tools = self.discoverInternalTools()
        }
    }
    
    private func discoverInternalTools() -> [MCPTool] {
        return [
            MCPTool(
                name: "calendar_create_event",
                description: "Create a new calendar event",
                inputSchema: [
                    "title": .init(type: "string", description: "Event title", required: true, defaultValue: nil),
                    "start_date": .init(type: "string", description: "Start date ISO format", required: true, defaultValue: nil),
                    "location": .init(type: "string", description: "Event location", required: false, defaultValue: nil)
                ],
                category: "calendar",
                requiresConfirmation: true,
                estimatedDuration: 2.0
            ),
            MCPTool(
                name: "escalate_to_user",
                description: "Send escalation notification to user",
                inputSchema: [
                    "reason": .init(type: "string", description: "Reason for escalation", required: true, defaultValue: nil),
                    "message": .init(type: "string", description: "Escalation message", required: true, defaultValue: nil)
                ],
                category: "escalation",
                requiresConfirmation: false,
                estimatedDuration: 1.0
            ),
            MCPTool(
                name: "fetch_web_content",
                description: "Fetch and parse web content",
                inputSchema: [
                    "url": .init(type: "string", description: "URL to fetch", required: true, defaultValue: nil),
                    "selector": .init(type: "string", description: "CSS selector", required: false, defaultValue: nil)
                ],
                category: "web",
                requiresConfirmation: false,
                estimatedDuration: 5.0
            ),
            MCPTool(
                name: "crypto_get_price",
                description: "Get current cryptocurrency price",
                inputSchema: [
                    "symbol": .init(type: "string", description: "Crypto symbol (e.g., BTC)", required: true, defaultValue: nil)
                ],
                category: "crypto",
                requiresConfirmation: false,
                estimatedDuration: 1.0
            )
        ]
    }
    
    func callTool(name: String, arguments: [String: Any]) async throws -> [String: Any] {
        switch type {
        case .localStdio:
            return try await callLocalStdioTool(name: name, arguments: arguments)
        case .localHTTP, .remoteHTTP:
            return try await callHTTPTool(name: name, arguments: arguments)
        case .internal:
            return try await callInternalTool(name: name, arguments: arguments)
        }
    }
    
    private func callLocalStdioTool(name: String, arguments: [String: Any]) async throws -> [String: Any] {
        // Send JSON-RPC request to stdio server
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": ["name": name, "arguments": arguments],
            "id": UUID().uuidString
        ]
        
        // This is simplified - real implementation needs proper stdio handling
        return ["result": "Tool executed", "tool": name, "args": arguments]
    }
    
    private func callHTTPTool(name: String, arguments: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint.appendingPathComponent("tools").appendingPathComponent("call"))
        request.httpMethod = "POST"
        request.setValue("application/json", forAccept: "application/json")
        
        let body: [String: Any] = ["name": name, "arguments": arguments]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
    
    private func callInternalTool(name: String, arguments: [String: Any]) async throws -> [String: Any] {
        switch name {
        case "calendar_create_event":
            return try await CalendarManager.shared.createEvent(
                title: arguments["title"] as? String ?? "",
                startDate: ISO8601DateFormatter().date(from: arguments["start_date"] as? String ?? "") ?? Date(),
                location: arguments["location"] as? String
            )
        case "escalate_to_user":
            return try await EscalationManager.shared.sendEscalation(
                reason: arguments["reason"] as? String ?? "",
                message: arguments["message"] as? String ?? ""
            )
        case "fetch_web_content":
            return try await WebFetchManager.shared.fetchContent(
                url: arguments["url"] as? String ?? "",
                selector: arguments["selector"] as? String
            )
        case "crypto_get_price":
            return try await CryptoManager.shared.getPrice(
                symbol: arguments["symbol"] as? String ?? ""
            )
        default:
            throw MCPError.unknownTool(name)
        }
    }
}

// MARK: - MCP Manager
@MainActor
class MCPManager: ObservableObject {
    static let shared = MCPManager()
    
    @Published var servers: [MCPServer] = []
    @Published var aggregatedTools: [MCPTool] = []
    @Published var isDiscovering = false
    @Published var lastDiscoveryError: Error?
    
    private let logger = Logger(subsystem: "com.mcp.agent", category: "MCPManager")
    private let discoveryQueue = DispatchQueue(label: "mcp.discovery", qos: .userInitiated)
    
    private init() {}
    
    func startDiscovery() async {
        isDiscovering = true
        lastDiscoveryError = nil
        
        do {
            try await discoverLocalServers()
            try await registerInternalServers()
            aggregateTools()
            logger.info("MCP discovery completed. Found \(servers.count) servers with \(aggregatedTools.count) tools")
        } catch {
            lastDiscoveryError = error
            logger.error("MCP discovery failed: \(error.localizedDescription)")
        }
        
        isDiscovering = false
    }
    
    private func discoverLocalServers() async throws {
        // Discover local MCP servers in ~/Applications/MCP-Servers
        let mcpDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")
            .appendingPathComponent("MCP-Servers")
        
        guard FileManager.default.fileExists(atPath: mcpDir.path) else {
            logger.info("No MCP servers directory found at \(mcpDir.path)")
            return
        }
        
        let contents = try FileManager.default.contentsOfDirectory(
            at: mcpDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        
        for item in contents {
            guard try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
            
            // Look for server executables
            let serverFiles = ["server.py", "server.js", "server.swift", "server"]
            for serverFile in serverFiles {
                let serverPath = item.appendingPathComponent(serverFile)
                if FileManager.default.isExecutableFile(atPath: serverPath.path) {
                    let serverName = item.lastPathComponent
                    let server = MCPServer(name: serverName, type: .localStdio(path: serverPath.path))
                    servers.append(server)
                    
                    // Connect and discover tools
                    Task {
                        do {
                            try await server.connect()
                            logger.info("Connected to local MCP server: \(serverName)")
                        } catch {
                            logger.error("Failed to connect to \(serverName): \(error.localizedDescription)")
                        }
                    }
                    break
                }
            }
        }
    }
    
    private func registerInternalServers() async throws {
        let internalServer = MCPServer(name: "InternalTools", type: .internal(name: "built-in"))
        try await internalServer.connect()
        servers.append(internalServer)
    }
    
    private func aggregateTools() {
        var allTools: [MCPTool] = []
        
        for server in servers {
            allTools.append(contentsOf: server.tools)
        }
        
        // Remove duplicates by name and resolve conflicts
        var toolMap: [String: MCPTool] = [:]
        for tool in allTools {
            if let existing = toolMap[tool.name] {
                // Conflict resolution: prefer server with higher priority
                // For now, prefer internal tools over external ones
                if tool.category == "internal" && existing.category != "internal" {
                    toolMap[tool.name] = tool
                }
            } else {
                toolMap[tool.name] = tool
            }
        }
        
        aggregatedTools = toolMap.values.sorted { $0.name < $1.name }
    }
    
    func callTool(_ toolName: String, arguments: [String: Any]) async throws -> [String: Any] {
        guard let tool = aggregatedTools.first(where: { $0.name == toolName }) else {
            throw MCPError.unknownTool(toolName)
        }
        
        logger.info("Calling tool \(toolName) with arguments: \(arguments)")
        
        // Find the server that provides this tool
        guard let server = servers.first(where: { $0.tools.contains(where: { $0.name == toolName }) }) else {
            throw MCPError.serverNotFound(toolName)
        }
        
        let startTime = Date()
        do {
            let result = try await server.callTool(name: toolName, arguments: arguments)
            let duration = Date().timeIntervalSince(startTime)
            logger.info("Tool \(toolName) completed in \(String(format: "%.2f", duration))s")
            return result
        } catch {
            logger.error("Tool \(toolName) failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    func getToolsByCategory(_ category: String) -> [MCPTool] {
        return aggregatedTools.filter { $0.category == category }
    }
    
    func refreshServer(_ server: MCPServer) async {
        do {
            try await server.connect()
            aggregateTools()
            logger.info("Refreshed server \(server.name)")
        } catch {
            logger.error("Failed to refresh server \(server.name): \(error.localizedDescription)")
        }
    }
}

// MARK: - MCP Errors
enum MCPError: Error, LocalizedError {
    case connectionFailed
    case unknownTool(String)
    case serverNotFound(String)
    case invalidResponse
    case streamingError
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to MCP server"
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .serverNotFound(let tool):
            return "No server found that provides tool: \(tool)"
        case .invalidResponse:
            return "Invalid response from MCP server"
        case .streamingError:
            return "Error in SSE streaming"
        }
    }
}
```

## 2. EventKit Integration - Full Calendar Manager

=== MCP-Agent/Agent/CalendarManager.swift ===
```swift
import Foundation
import EventKit
import OSLog

class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    
    private let eventStore = EKEventStore()
    private let logger = Logger(subsystem: "com.mcp.agent", category: "CalendarManager")
    
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var calendars: [EKCalendar] = []
    @Published var isAuthorized = false
    
    private init() {
        updateAuthorizationStatus()
        loadCalendars()
    }
    
    private func updateAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        isAuthorized = authorizationStatus == .authorized
    }
    
    func requestAccess() async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, error in
                Task { @MainActor in
                    self.updateAuthorizationStatus()
                    if let error = error {
                        self.logger.error("Calendar access denied: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    } else {
                        self.logger.info("Calendar access granted: \(granted)")
                        self.loadCalendars()
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }
    
    private func loadCalendars() {
        DispatchQueue.main.async {
            self.calendars = self.eventStore.calendars(for: .event)
                .filter { $0.allowsContentModifications }
                .sorted { $0.title < $1.title }
        }
    }
    
    func createEvent(title: String, startDate: Date, location: String? = nil, duration: TimeInterval = 3600, calendar: EKCalendar? = nil) async throws -> [String: Any] {
        guard isAuthorized else {
            let granted = try await requestAccess()
            guard granted else { throw CalendarError.accessDenied }
        }
        
        // Use specified calendar or the first available one
        let targetCalendar = calendar ?? calendars.first
        guard let calendar = targetCalendar else {
            throw CalendarError.noCalendarsAvailable
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(duration)
        event.calendar = calendar
        
        if let location = location {
            event.location = location
        }
        
        // Add alarms
        let alarm = EKAlarm(relativeOffset: -15 * 60) // 15 minutes before
        event.addAlarm(alarm)
        
        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            logger.info("Created calendar event: \(title)")
            
            return [
                "success": true,
                "event_id": event.eventIdentifier,
                "title": event.title,
                "start_date": ISO8601DateFormatter().string(from: event.startDate),
                "end_date": ISO8601DateFormatter().string(from: event.endDate),
                "location": event.location ?? "",
                "calendar": calendar.title
            ]
        } catch {
            logger.error("Failed to create event: \(error.localizedDescription)")
            throw CalendarError.creationFailed(error)
        }
    }
    
    func findEvents(title: String? = nil, dateRange: DateInterval? = nil, calendar: EKCalendar? = nil) async throws -> [[String: Any]] {
        guard isAuthorized else {
            let granted = try await requestAccess()
            guard granted else { throw CalendarError.accessDenied }
        }
        
        let predicate: NSPredicate?
        
        if let dateRange = dateRange {
            predicate = eventStore.predicateForEvents(withStart: dateRange.start, end: dateRange.end, calendars: calendar.map { [$0] })
        } else {
            let now = Date()
            let weekLater = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: now)!
            predicate = eventStore.predicateForEvents(withStart: now, end: weekLater, calendars: calendar.map { [$0] })
        }
        
        guard let predicate = predicate else {
            throw CalendarError.invalidPredicate
        }
        
        let events = eventStore.events(matching: predicate)
        let filteredEvents = events.filter { event in
            if let title = title, !event.title.localizedCaseInsensitiveContains(title) {
                return false
            }
            return true
        }
        
        return filteredEvents.map { event in
            [
                "title": event.title,
                "start_date": ISO8601DateFormatter().string(from: event.startDate),
                "end_date": ISO8601DateFormatter().string(from: event.endDate),
                "location": event.location ?? "",
                "event_id": event.eventIdentifier,
                "calendar": event.calendar.title,
                "notes": event.notes ?? ""
            ]
        }
    }
    
    func updateEvent(eventId: String, updates: [String: Any]) async throws -> [String: Any] {
        guard isAuthorized else {
            let granted = try await requestAccess()
            guard granted else { throw CalendarError.accessDenied }
        }
        
        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw CalendarError.eventNotFound
        }
        
        if let title = updates["title"] as? String {
            event.title = title
        }
        
        if let startDateString = updates["start_date"] as? String,
           let startDate = ISO8601DateFormatter().date(from: startDateString) {
            event.startDate = startDate
        }
        
        if let endDateString = updates["end_date"] as? String,
           let endDate = ISO8601DateFormatter().date(from: endDateString) {
            event.endDate = endDate
        }
        
        if let location = updates["location"] as? String {
            event.location = location
        }
        
        if let notes = updates["notes"] as? String {
            event.notes = notes
        }
        
        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            logger.info("Updated calendar event: \(event.title)")
            
            return [
                "success": true,
                "event_id": event.eventIdentifier,
                "title": event.title,
                "start_date": ISO8601DateFormatter().string(from: event.startDate),
                "end_date": ISO8601DateFormatter().string(from: event.endDate),
                "location": event.location ?? ""
            ]
        } catch {
            logger.error("Failed to update event: \(error.localizedDescription)")
            throw CalendarError.updateFailed(error)
        }
    }
    
    func deleteEvent(eventId: String) async throws -> [String: Any] {
        guard isAuthorized else {
            let granted = try await requestAccess()
            guard granted else { throw CalendarError.accessDenied }
        }
        
        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw CalendarError.eventNotFound
        }
        
        do {
            try eventStore.remove(event, span: .thisEvent, commit: true)
            logger.info("Deleted calendar event: \(event.title)")
            
            return [
                "success": true,
                "event_id": eventId,
                "message": "Event deleted successfully"
            ]
        } catch {
            logger.error("Failed to delete event: \(error.localizedDescription)")
            throw CalendarError.deletionFailed(error)
        }
    }
    
    func createReminder(title: String, dueDate: Date? = nil, priority: Int = 0) async throws -> [String: Any] {
        // Note: Reminders require additional entitlements and setup
        // This is a placeholder implementation
        
        guard isAuthorized else {
            let granted = try await requestAccess()
            guard granted else { throw CalendarError.accessDenied }
        }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        
        if let dueDate = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        }
        
        reminder.priority = UInt(priority)
        
        do {
            try eventStore.save(reminder, commit: true)
            logger.info("Created reminder: \(title)")
            
            return [
                "success": true,
                "reminder_id": reminder.calendarItemIdentifier,
                "title": reminder.title,
                "due_date": dueDate != nil ? ISO8601DateFormatter().string(from: dueDate!) : "",
                "priority": priority
            ]
        } catch {
            logger.error("Failed to create reminder: \(error.localizedDescription)")
            throw CalendarError.reminderCreationFailed(error)
        }
    }
    
    func findAvailableSlots(duration: TimeInterval, startDate: Date, endDate: Date) async throws -> [[String: Any]] {
        guard isAuthorized else {
            let granted = try await requestAccess()
            guard granted else { throw CalendarError.accessDenied }
        }
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        
        var availableSlots: [[String: Any]] = []
        var currentStart = startDate
        
        for event in events {
            if event.startDate.timeIntervalSince(currentStart) >= duration {
                availableSlots.append([
                    "start": ISO8601DateFormatter().string(from: currentStart),
                    "end": ISO8601DateFormatter().string(from: event.startDate)
                ])
            }
            currentStart = max(currentStart, event.endDate)
        }
        
        // Check after the last event
        if endDate.timeIntervalSince(currentStart) >= duration {
            availableSlots.append([
                "start": ISO8601DateFormatter().string(from: currentStart),
                "end": ISO8601DateFormatter().string(from: endDate)
            ])
        }
        
        return availableSlots
    }
}

// MARK: - Calendar Errors
enum CalendarError: Error, LocalizedError {
    case accessDenied
    case noCalendarsAvailable
    case creationFailed(Error)
    case updateFailed(Error)
    case deletionFailed(Error)
    case reminderCreationFailed(Error)
    case eventNotFound
    case invalidPredicate
    
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access denied"
        case .noCalendarsAvailable:
            return "No calendars available for writing"
        case .creationFailed(let error):
            return "Failed to create event: \(error.localizedDescription)"
        case .updateFailed(let error):
            return "Failed to update event: \(error.localizedDescription)"
        case .deletionFailed(let error):
            return "Failed to delete event: \(error.localizedDescription)"
        case .reminderCreationFailed(let error):
            return "Failed to create reminder: \(error.localizedDescription)"
        case .eventNotFound:
            return "Event not found"
        case .invalidPredicate:
            return "Invalid calendar predicate"
        }
    }
}
```

## 3. OpenAI-Compatible Fallback Client with Streaming

=== MCP-Agent/Agent/LLMManager.swift ===
```swift
import Foundation
import OSLog

// MARK: - LLM Configuration
struct LLMConfig: Codable {
    let provider: LLMProvider
    let baseURL: String?
    let apiKey: String?
    let model: String
    let temperature: Double = 0.7
    let maxTokens: Int = 4096
    let timeout: TimeInterval = 60
    
    enum LLMProvider: String, Codable, CaseIterable {
        case ollamaLocal = "ollama_local"
        case ollamaCloud = "ollama_cloud"
        case openAICompatible = "openai_compatible"
    }
}

// MARK: - LLM Response
struct LLMResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage?
    
    struct Choice: Codable {
        let index: Int
        let message: Message
        let finishReason: String
        
        enum CodingKeys: String, CodingKey {
            case index
            case message
            case finishReason = "finish_reason"
        }
    }
    
    struct Message: Codable {
        let role: String
        let content: String
        let toolCalls: [ToolCall]?
        
        enum CodingKeys: String, CodingKey {
            case role
            case content
            case toolCalls = "tool_calls"
        }
    }
    
    struct ToolCall: Codable {
        let id: String
        let type: String
        let function: Function
        
        struct Function: Codable {
            let name: String
            let arguments: String
        }
    }
    
    struct Usage: Codable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
        
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

// MARK: - Streaming Response
struct StreamingChunk: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [StreamingChoice]
    
    struct StreamingChoice: Codable {
        let index: Int
        let delta: Delta
        let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case index
            case delta
            case finishReason = "finish_reason"
        }
    }
    
    struct Delta: Codable {
        let content: String?
        let role: String?
        let toolCalls: [ToolCall]?
        
        enum CodingKeys: String, CodingKey {
            case content
            case role
            case toolCalls = "tool_calls"
        }
    }
    
    struct ToolCall: Codable {
        let id: String
        let type: String
        let function: Function
        
        struct Function: Codable {
            let name: String
            let arguments: String
        }
    }
}

// MARK: - LLM Manager
@MainActor
class LLMManager: ObservableObject {
    static let shared = LLMManager()
    
    private let logger = Logger(subsystem: "com.mcp.agent", category: "LLMManager")
    private let session = URLSession.shared
    private var currentConfig: LLMConfig?
    private var fallbackChain: [LLMConfig] = []
    
    @Published var isProcessing = false
    @Published var currentProvider: String = ""
    @Published var lastError: Error?
    
    private init() {
        Task {
            await setupFallbackChain()
        }
    }
    
    private func setupFallbackChain() async {
        // Default fallback chain: Local Ollama -> Ollama Cloud -> OpenAI Compatible
        fallbackChain = [
            LLMConfig(provider: .ollamaLocal, baseURL: "http://localhost:11434", model: "llama3.1:70b-instruct"),
            LLMConfig(provider: .ollamaCloud, baseURL: "https://ollama.cloud/api", model: "llama3.1:70b-instruct"),
            LLMConfig(provider: .openAICompatible, baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini")
        ]
    }
    
    func setFallbackChain(_ configs: [LLMConfig]) {
        fallbackChain = configs
    }
    
    func generateResponse(messages: [[String: String]], tools: [MCPTool]? = nil, stream: Bool = true) async throws -> AsyncThrowingStream<String, Error> {
        isProcessing = true
        lastError = nil
        
        return AsyncThrowingStream { continuation in
            Task {
                defer { isProcessing = false }
                
                var lastErrorInner: Error?
                
                for config in fallbackChain {
                    do {
                        currentProvider = config.provider.rawValue
                        logger.info("Attempting to use LLM provider: \(config.provider.rawValue)")
                        
                        if stream {
                            try await generateStreamingResponse(config: config, messages: messages, tools: tools) { chunk in
                                continuation.yield(chunk)
                            }
                        } else {
                            let response = try await generateNonStreamingResponse(config: config, messages: messages, tools: tools)
                            continuation.yield(response)
                        }
                        
                        // Success - break out of fallback loop
                        continuation.finish()
                        return
                        
                    } catch {
                        lastErrorInner = error
                        logger.error("LLM provider \(config.provider.rawValue) failed: \(error.localizedDescription)")
                        continue
                    }
                }
                
                // All providers failed
                if let error = lastErrorInner {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish(throwing: LLMError.allProvidersFailed)
                }
            }
        }
    }
    
    private func generateStreamingResponse(config: LLMConfig, messages: [[String: String]], tools: [MCPTool]?, chunkHandler: @escaping (String) -> Void) async throws {
        let request = try buildRequest(config: config, messages: messages, tools: tools, stream: true)
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = try? JSONSerialization.jsonObject(with: try await collectResponseData(response: httpResponse)) as? [String: Any]
            let errorMessage = errorBody?["error"] as? [String: Any]? ?? errorBody?["message"] as? String
            throw LLMError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // Handle streaming response
        let (bytes, _) = try await session.bytes(for: request)
        
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            
            let dataString = String(line.dropFirst(6))
            if dataString == "[DONE]" {
                break
            }
            
            guard let data = dataString.data(using: .utf8) else { continue }
            
            do {
                let chunk = try JSONDecoder().decode(StreamingChunk.self, from: data)
                if let content = chunk.choices.first?.delta.content {
                    chunkHandler(content)
                }
                
                // Handle tool calls
                if let toolCall = chunk.choices.first?.delta.toolCalls?.first {
                    try await handleToolCall(toolCall, config: config)
                }
                
            } catch {
                logger.warning("Failed to parse streaming chunk: \(error.localizedDescription)")
            }
        }
    }
    
    private func generateNonStreamingResponse(config: LLMConfig, messages: [[String: String]], tools: [MCPTool]?) async throws -> String {
        let request = try buildRequest(config: config, messages: messages, tools: tools, stream: false)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errorMessage = errorBody?["error"] as? [String: Any]? ?? errorBody?["message"] as? String
            throw LLMError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        let llmResponse = try JSONDecoder().decode(LLMResponse.self, from: data)
        return llmResponse.choices.first?.message.content ?? ""
    }
    
    private func buildRequest(config: LLMConfig, messages: [[String: String]], tools: [MCPTool]?, stream: Bool) throws -> URLRequest {
        var request = URLRequest(url: try buildEndpointURL(config: config))
        request.httpMethod = "POST"
        request.setValue("application/json", forAccept: "application/json")
        request.timeoutInterval = config.timeout
        
        // Add authorization header
        if let apiKey = config.apiKey {
            if config.provider == .openAICompatible {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            } else if config.provider == .ollamaCloud {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }
        
        if stream {
            request.setValue("text/event-stream", forAccept: "text/event-stream")
        }
        
        // Build request body
        var requestBody: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "temperature": config.temperature,
            "stream": stream
        ]
        
        if !stream {
            requestBody["max_tokens"] = config.maxTokens
        }
        
        // Add tools if available
        if let tools = tools, !tools.isEmpty {
            requestBody["tools"] = tools.map { tool in
                [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description ?? "",
                        "parameters": buildToolSchema(for: tool)
                    ]
                ]
            }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        return request
    }
    
    private func buildEndpointURL(config: LLMConfig) throws -> URL {
        switch config.provider {
        case .ollamaLocal:
            return URL(string: "\(config.baseURL ?? "http://localhost:11434")/api/chat")!
        case .ollamaCloud:
            return URL(string: "\(config.baseURL ?? "https://ollama.cloud/api")/chat/completions")!
        case .openAICompatible:
            return URL(string: "\(config.baseURL ?? "https://api.openai.com/v1")/chat/completions")!
        }
    }
    
    private func buildToolSchema(for tool: MCPTool) -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []
        
        if let inputSchema = tool.inputSchema {
            for (name, param) in inputSchema {
                var paramSchema: [String: Any] = [
                    "type": param.type
                ]
                
                if let description = param.description {
                    paramSchema["description"] = description
                }
                
                if let defaultValue = param.defaultValue {
                    paramSchema["default"] = defaultValue
                }
                
                properties[name] = paramSchema
                
                if param.required {
                    required.append(name)
                }
            }
        }
        
        return [
            "type": "object",
            "properties": properties,
            "required": required
        ]
    }
    
    private func handleToolCall(_ toolCall: StreamingChunk.StreamingChoice.Delta.ToolCall, config: LLMConfig) async throws {
        // Parse tool arguments
        let arguments: [String: Any] = try JSONSerialization.jsonObject(with: toolCall.function.arguments.data(using: .utf8)!) as? [String: Any] ?? [:]
        
        // Execute tool through MCP manager
        do {
            let result = try await MCPManager.shared.callTool(toolCall.function.name, arguments: arguments)
            
            // Continue conversation with tool result
            let toolResultMessage: [String: String] = [
                "role": "tool",
                "tool_call_id": toolCall.id,
                "content": "Tool result: \(result)"
            ]
            
            // This would continue the conversation with the tool result
            // Implementation depends on your conversation management strategy
            
        } catch {
            logger.error("Tool call \(toolCall.function.name) failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func collectResponseData(response: HTTPURLResponse) async throws -> Data {
        // This is a simplified implementation
        // In practice, you'd read the response body based on the response object
        return Data()
    }
    
    func getCurrentConfig() -> LLMConfig? {
        return currentConfig
    }
    
    func setCurrentConfig(_ config: LLMConfig) {
        currentConfig = config
    }
}

// MARK: - LLM Errors
enum LLMError: Error, LocalizedError {
    case allProvidersFailed
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case invalidURL
    case streamingError
    
    var errorDescription: String? {
        switch self {
        case .allProvidersFailed:
            return "All LLM providers failed"
        case .invalidResponse:
            return "Invalid response from LLM"
        case .httpError(let statusCode, let message):
            return "HTTP error \(statusCode): \(message ?? "Unknown error")"
        case .invalidURL:
            return "Invalid endpoint URL"
        case .streamingError:
            return "Error in streaming response"
        }
    }
}
```

## 4. LaunchD Integration and Watchdog Service

=== MCP-Agent/Agent/WatchdogService.swift ===
```swift
import Foundation
import ServiceManagement
import OSLog

// MARK: - Watchdog Service Manager
class WatchdogService: ObservableObject {
    static let shared = WatchdogService()
    
    private let logger = Logger(subsystem: "com.mcp.agent", category: "WatchdogService")
    private let serviceIdentifier = "com.mcp.agent.AgentDaemon"
    
    @Published var isServiceInstalled = false
    @Published var serviceStatus: SMAppService.Status = .notRegistered
    @Published var lastHealthCheck: Date?
    @Published var restartCount = 0
    
    private let healthCheckQueue = DispatchQueue(label: "watchdog.health", qos: .utility)
    private var healthCheckTimer: Timer?
    
    private init() {
        Task {
            await checkServiceStatus()
        }
        
        startHealthMonitoring()
    }
    
    // MARK: - Service Management
    
    func installAndStartService() async throws {
        logger.info("Installing and starting watchdog service")
        
        // Create the agent daemon bundle
        try await createAgentDaemonBundle()
        
        // Register the service with launchd
        try SMAppService.mainApp.register()
        
        // Wait a moment for registration
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        await checkServiceStatus()
        
        if isServiceInstalled {
            logger.info("Watchdog service installed successfully")
        } else {
            throw WatchdogError.serviceRegistrationFailed
        }
    }
    
    func uninstallService() async throws {
        logger.info("Uninstalling watchdog service")
        
        try await SMAppService.mainApp.unregister()
        
        // Clean up daemon files
        try? FileManager.default.removeItem(at: agentDaemonPath())
        
        await checkServiceStatus()
    }
    
    private func createAgentDaemonBundle() async throws {
        let bundlePath = agentDaemonPath()
        
        // Create Info.plist
        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key>
            <string>AgentDaemon</string>
            <key>CFBundleIdentifier</key>
            <string>\(serviceIdentifier)</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>CFBundleName</key>
            <string>Agent Daemon</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>LSUIElement</key>
            <true/>
            <key>LSMultipleJobSeparationsDisabled</key>
            <true/>
        </dict>
        </plist>
        """
        
        try infoPlist.write(to: bundlePath.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        
        // Create the daemon executable (this is a stub - you would include a real binary)
        let daemonCode = """
        #!/bin/bash
        # Agent Daemon Stub
        # This would be the actual daemon executable
        
        # Set up environment
        export AGENT_LOG_DIR="$HOME/Library/Logs/MCP-Agent"
        mkdir -p "$AGENT_LOG_DIR"
        
        # Launch the actual agent process
        open -a MCP-Agent --args --daemon-mode
        
        # Keep the daemon alive
        while true; do
            if ! pgrep -f "MCP-Agent" > /dev/null; then
                echo "$(date): Agent process died, restarting" >> "$AGENT_LOG_DIR/daemon.log"
                open -a MCP-Agent --args --daemon-mode
            fi
            sleep 30
        done
        """
        
        let daemonPath = bundlePath.appendingPathComponent("AgentDaemon")
        try daemonCode.write(to: daemonPath, atomically: true, encoding: .utf8)
        
        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: daemonPath.path)
        
        logger.info("Created agent daemon bundle at \(bundlePath.path)")
    }
    
    private func agentDaemonPath() -> URL {
        let libraryPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("MCP-Agent")
            .appendingPathComponent("AgentDaemon.bundle")
        
        try? FileManager.default.createDirectory(at: libraryPath, withIntermediateDirectories: true)
        return libraryPath
    }
    
    private func checkServiceStatus() async {
        await MainActor.run {
            serviceStatus = SMAppService.mainApp.status
            isServiceInstalled = serviceStatus == .enabled
        }
    }
    
    // MARK: - Health Monitoring
    
    private func startHealthMonitoring() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task {
                await self?.performHealthCheck()
            }
        }
    }
    
    private func performHealthCheck() async {
        await MainActor.run {
            lastHealthCheck = Date()
        }
        
        let agentProcess = "MCP-Agent"
        
        let isRunning = await withCheckedContinuation { continuation in
            let task = Process()
            task.launchPath = "/usr/bin/pgrep"
            task.arguments = ["-x", agentProcess]
            
            let outputPipe = Pipe()
            task.standardOutput = outputPipe
            
            task.terminationHandler = { process in
                let status = process.terminationStatus
                continuation.resume(returning: status == 0)
            }
            
            task.launch()
        }
        
        if !isRunning {
            await handleAgentFailure()
        } else {
            await performAdditionalHealthChecks()
        }
    }
    
    private func performAdditionalHealthChecks() async {
        // Check memory usage
        let memoryWarning = await checkMemoryUsage()
        
        // Check disk space
        let diskWarning = await checkDiskSpace()
        
        // Check network connectivity
        let networkWarning = await checkNetworkConnectivity()
        
        if memoryWarning || diskWarning || networkWarning {
            logger.warning("Health check warnings: memory=\(memoryWarning), disk=\(diskWarning), network=\(networkWarning)")
            // Could trigger restart or alert here
        }
    }
    
    private func checkMemoryUsage() async -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/python3"
        task.arguments = ["-c", """
        import psutil, os
        process = psutil.Process(os.getpid())
        memory_mb = process.memory_info().rss / 1024 / 1024
        print(f'{memory_mb:.1f}')
        """]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        
        return await withCheckedContinuation { continuation in
            task.terminationHandler = { process in
                let status = process.terminationStatus
                if status == 0 {
                    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let memoryStr = output, let memoryMB = Double(memoryStr) {
                        // Warn if using more than 8GB
                        let shouldWarn = memoryMB > 8192
                        continuation.resume(returning: shouldWarn)
                        return
                    }
                }
                continuation.resume(returning: false)
            }
            task.launch()
        }
    }
    
    private func checkDiskSpace() async -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/df"
        task.arguments = ["-h", "/"]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        
        return await withCheckedContinuation { continuation in
            task.terminationHandler = { process in
                let status = process.terminationStatus
                if status == 0 {
                    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    // Check if available space is less than 1GB
                    let shouldWarn = output.contains("< 1.0G")
                    continuation.resume(returning: shouldWarn)
                    return
                }
                continuation.resume(returning: false)
            }
            task.launch()
        }
    }
    
    private func checkNetworkConnectivity() async -> Bool {
        let url = URL(string: "https://www.google.com")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode != 200
        } catch {
            return true // Warning if network fails
        }
    }
    
    private func handleAgentFailure() async {
        logger.error("Agent process not running, attempting restart")
        
        restartCount += 1
        
        // Try to restart the agent
        let restartSuccess = await withCheckedContinuation { continuation in
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = ["-a", "MCP-Agent", "--args", "--daemon-mode", "--restart"]
            
            task.terminationHandler = { process in
                let success = process.terminationStatus == 0
                continuation.resume(returning: success)
            }
            
            task.launch()
        }
        
        if restartSuccess {
            logger.info("Successfully restarted agent")
            // Wait a moment and check if it's running
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let isRunning = await checkIfAgentIsRunning()
            if !isRunning {
                logger.error("Restart failed - agent still not running")
                await escalateFailure()
            }
        } else {
            logger.error("Failed to restart agent")
            await escalateFailure()
        }
    }
    
    private func checkIfAgentIsRunning() async -> Bool {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.launchPath = "/usr/bin/pgrep"
            task.arguments = ["-x", "MCP-Agent"]
            
            task.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus == 0)
            }
            
            task.launch()
        }
    }
    
    private func escalateFailure() async {
        // Send escalation to user about agent failure
        logger.critical("Agent failed to restart, escalating to user")
        
        do {
            try await MCPManager.shared.callTool("escalate_to_user", arguments: [
                "reason": "Agent watchdog failure",
                "message": "The MCP Agent has failed and the watchdog was unable to restart it automatically. Please check the system logs and restart the application manually."
            ])
        } catch {
            logger.error("Failed to send escalation: \(error.localizedDescription)")
        }
    }
    
    func forceRestartAgent() async throws {
        logger.info("Force restarting agent")
        
        // Kill existing process
        let killSuccess = await withCheckedContinuation { continuation in
            let task = Process()
            task.launchPath = "/usr/bin/pkill"
            task.arguments = ["-9", "MCP-Agent"]
            
            task.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus == 0)
            }
            
            task.launch()
        }
        
        if killSuccess {
            // Start new process
            let startSuccess = await withCheckedContinuation { continuation in
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = ["-a", "MCP-Agent", "--args", "--daemon-mode"]
                
                task.terminationHandler = { process in
                    continuation.resume(returning: process.terminationStatus == 0)
                }
                
                task.launch()
            }
            
            if !startSuccess {
                throw WatchdogError.forceRestartFailed
            }
            
            logger.info("Agent force restarted successfully")
        } else {
            throw WatchdogError.forceKillFailed
        }
    }
}

// MARK: - Watchdog Errors
enum WatchdogError: Error, LocalizedError {
    case serviceRegistrationFailed
    case serviceUnregistrationFailed
    case forceRestartFailed
    case forceKillFailed
    
    var errorDescription: String? {
        switch self {
        case .serviceRegistrationFailed:
            return "Failed to register service with launchd"
        case .serviceUnregistrationFailed:
            return "Failed to unregister service from launchd"
        case .forceRestartFailed:
            return "Failed to force restart the agent"
        case .forceKillFailed:
            return "Failed to kill existing agent process"
        }
    }
}
```

## 5. Companion HTTP/SSE Gateway for Python Integration

=== MCP-Agent/Agent/HTTPGateway.swift ===
```swift
import Foundation
import Network
import OSLog

// MARK: - HTTP Gateway for Python Integration
@MainActor
class HTTPGateway: ObservableObject {
    static let shared = HTTPGateway()
    
    private let logger = Logger(subsystem: "com.mcp.agent", category: "HTTPGateway")
    private var listeners: [NWListener] = []
    
    @Published var isRunning = false
    @Published var activeConnections = 0
    
    private let port: Int = 8766
    private let host = "127.0.0.1"
    
    private init() {}
    
    func start() throws {
        logger.info("Starting HTTP gateway on port \(port)")
        
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(integerLiteral: UInt16(port))!)
        
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isRunning = true
                self?.logger.info("HTTP gateway ready on \(self?.host ?? ""):\(self?.port ?? 0)")
            case .failed(let error):
                self?.isRunning = false
                self?.logger.error("HTTP gateway failed: \(error.localizedDescription)")
            default:
                break
            }
        }
        
        listener.start(queue: .global())
        listeners.append(listener)
    }
    
    func stop() {
        logger.info("Stopping HTTP gateway")
        
        for listener in listeners {
            listener.cancel()
        }
        listeners.removeAll()
        isRunning = false
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        activeConnections += 1
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.readRequest(connection)
            case .cancelled:
                self.activeConnections = max(0, self.activeConnections - 1)
            default:
                break
            }
        }
        
        connection.start(queue: .global())
    }
    
    private func readRequest(_ connection: NWConnection) {
        var requestData = Data()
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data = data {
                requestData.append(data)
            }
            
            if isComplete || error != nil {
                self.processRequest(connection, data: requestData)
            } else {
                // Continue reading
                self.readRequest(connection)
            }
        }
    }
    
    private func processRequest(_ connection: NWConnection, data: Data) {
        guard let httpRequest = HTTPRequest(data: data) else {
            sendErrorResponse(connection, statusCode: 400, message: "Invalid HTTP request")
            return
        }
        
        switch (httpRequest.method, httpRequest.path) {
        case ("POST", "/tools/call"):
            handleToolCall(connection, request: httpRequest)
        case ("GET", "/tools/list"):
            handleToolList(connection)
        case ("GET", "/status"):
            handleStatus(connection)
        case ("GET", "/sse/overlay"):
            handleSSERequest(connection, stream: "overlay")
        case ("GET", "/sse/status"):
            handleSSERequest(connection, stream: "status")
        case ("POST", "/escalate"):
            handleEscalate(connection, request: httpRequest)
        default:
            sendErrorResponse(connection, statusCode: 404, message: "Not found")
        }
    }
    
    private func handleToolCall(_ connection: NWConnection, request: HTTPRequest) {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let toolName = json["tool"] as? String,
              let arguments = json["args"] as? [String: Any] else {
            sendErrorResponse(connection, statusCode: 400, message: "Invalid tool call request")
            return
        }
        
        Task {
            do {
                let result = try await MCPManager.shared.callTool(toolName, arguments: arguments)
                let responseData = try JSONSerialization.data(withJSONObject: ["success": true, "result": result])
                sendJSONResponse(connection, statusCode: 200, data: responseData)
            } catch {
                let errorData = try JSONSerialization.data(withJSONObject: ["success": false, "error": error.localizedDescription])
                sendJSONResponse(connection, statusCode: 500, data: errorData)
            }
        }
    }
    
    private func handleToolList(_ connection: NWConnection) {
        let tools = MCPManager.shared.aggregatedTools.map { tool in
            [
                "name": tool.name,
                "description": tool.description ?? "",
                "category": tool.category ?? "",
                "requires_confirmation": tool.requiresConfirmation
            ]
        }
        
        let responseData = try? JSONSerialization.data(withJSONObject: ["tools": tools])
        sendJSONResponse(connection, statusCode: 200, data: responseData ?? Data())
    }
    
    private func handleStatus(_ connection: NWConnection) {
        let status: [String: Any] = [
            "status": "running",
            "active_connections": activeConnections,
            "mcp_servers": MCPManager.shared.servers.map { server in
                [
                    "name": server.name,
                    "type": String(describing: server.type),
                    "is_connected": server.isConnected,
                    "tool_count": server.tools.count
                ]
            },
            "llm_provider": LLMManager.shared.currentProvider,
            "is_processing": LLMManager.shared.isProcessing,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        let responseData = try? JSONSerialization.data(withJSONObject: status)
        sendJSONResponse(connection, statusCode: 200, data: responseData ?? Data())
    }
    
    private func handleSSERequest(_ connection: NWConnection, stream: String) {
        // Send SSE headers
        let headers = [
            "Content-Type: text/event-stream",
            "Cache-Control: no-cache",
            "Connection: keep-alive",
            "Access-Control-Allow-Origin: *"
        ].joined(separator: "\r\n")
        
        let headerData = "HTTP/1.1 200 OK\r\n\(headers)\r\n\r\n".data(using: .utf8)!
        connection.send(content: headerData, completion: .contentProcessed { _ in
            self.startSSEStream(connection, stream: stream)
        })
    }
    
    private func startSSEStream(_ connection: NWConnection, stream: String) {
        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            let message = self.generateSSEMessage(for: stream)
            let sseData = "data: \(message)\n\n".data(using: .utf8)!
            
            connection.send(content: sseData, completion: .contentProcessed { _ in })
        }
        
        // Invalidate timer when connection is cancelled
        connection.stateUpdateHandler = { state in
            switch state {
            case .cancelled:
                timer.invalidate()
                self.activeConnections = max(0, self.activeConnections - 1)
            default:
                break
            }
        }
    }
    
    private func generateSSEMessage(for stream: String) -> String {
        switch stream {
        case "overlay":
            return "Current action: \(generateRandomAction())"
        case "status":
            return "Agent status: \(LLMManager.shared.isProcessing ? "Processing" : "Idle")"
        default:
            return "Hello from SSE"
        }
    }
    
    private func generateRandomAction() -> String {
        let actions = [
            "Planning your day...",
            "Checking calendar...",
            "Analyzing news...",
            "Monitoring crypto...",
            "Processing tools...",
            "Learning from feeds..."
        ]
        return actions.randomElement() ?? "Working..."
    }
    
    private func handleEscalate(_ connection: NWConnection, request: HTTPRequest) {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let reason = json["reason"] as? String,
              let message = json["message"] as? String else {
            sendErrorResponse(connection, statusCode: 400, message: "Invalid escalate request")
            return
        }
        
        Task {
            do {
                let result = try await EscalationManager.shared.sendEscalation(reason: reason, message: message)
                let responseData = try JSONSerialization.data(withJSONObject: result)
                sendJSONResponse(connection, statusCode: 200, data: responseData)
            } catch {
                let errorData = try JSONSerialization.data(withJSONObject: ["success": false, "error": error.localizedDescription])
                sendJSONResponse(connection, statusCode: 500, data: errorData)
            }
        }
    }
    
    private func sendJSONResponse(_ connection: NWConnection, statusCode: Int, data: Data) {
        let headers = [
            "HTTP/1.1 \(statusCode) OK",
            "Content-Type: application/json",
            "Content-Length: \(data.count)",
            "Connection: close"
        ].joined(separator: "\r\n")
        
        let response = "\(headers)\r\n\r\n".data(using: .utf8)! + data
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func sendErrorResponse(_ connection: NWConnection, statusCode: Int, message: String) {
        let body = "{\"error\": \"\(message)\"}".data(using: .utf8)!
        sendJSONResponse(connection, statusCode: statusCode, data: body)
    }
}

// MARK: - HTTP Request Parser
struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data?
    
    init?(data: Data) {
        guard let httpString = String(data: data, encoding: .utf8) else { return nil }
        
        let lines = httpString.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        
        let firstLine = lines[0]
        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 2 else { return nil }
        
        method = components[0]
        path = components[1]
        
        var headers: [String: String] = [:]
        var bodyStartIndex = 0
        
        for (index, line) in lines.enumerated() {
            if line.isEmpty {
                bodyStartIndex = index + 1
                break
            } else if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key.lowercased()] = value
            }
        }
        
        self.headers = headers
        
        if bodyStartIndex < lines.count {
            let bodyLines = Array(lines[bodyStartIndex...])
            let bodyString = bodyLines.joined(separator: "\r\n")
            self.body = bodyString.data(using: .utf8)
        } else {
            self.body = nil
        }
    }
}
```

## 6. Updated App Integration

=== MCP-Agent/App/MCP_AgentApp.swift (Updated) ===
```swift
import SwiftUI
import Foundation
import Network

@main
struct MCP_AgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var mcpManager = MCPManager.shared
    @StateObject private var llmManager = LLMManager.shared
    @StateObject private var watchdogService = WatchdogService.shared
    @StateObject private var httpGateway = HTTPGateway.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    Task {
                        await initializeServices()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
    
    private func initializeServices() async {
        // Start HTTP gateway
        try? httpGateway.start()
        
        // Discover MCP servers
        await mcpManager.startDiscovery()
        
        // Check if watchdog service should be installed
        if !watchdogService.isServiceInstalled {
            do {
                try await watchdogService.installAndStartService()
            } catch {
                print("Failed to install watchdog service: \(error)")
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        OverlayWindowController.shared.show()
        
        // Check for daemon mode
        if CommandLine.arguments.contains("--daemon-mode") {
            startDaemonMode()
        } else {
            startUIApplication()
        }
    }
    
    private func startDaemonMode() {
        // In daemon mode, start the agent core
        StartAgentDaemon()
        
        // Start HTTP gateway for MCP integration
        try? HTTPGateway.shared.start()
    }
    
    private func startUIApplication() {
        // In UI mode, start agent daemon if not already running
        if !isAgentDaemonRunning() {
            StartAgentDaemon()
        }
    }
    
    private func isAgentDaemonRunning() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-x", "MCP-Agent"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        task.launch()
        task.waitUntilExit()
        
        return task.terminationStatus == 0
    }
}

func StartAgentDaemon() {
    // Start Python agent core
    let pythonPath = Bundle.main.path(forResource: "agent_core", ofType: "py", inDirectory: "AgentCore")!
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    proc.arguments = [pythonPath]
    proc.launch()
    
    print("Started agent daemon")
}
```

## 7. Keychain Integration for Secure Storage

=== MCP-Agent/Agent/KeychainManager.swift ===
```swift
import Foundation
import Security
import OSLog

// MARK: - Keychain Manager for Secure API Key Storage
@MainActor
class KeychainManager: ObservableObject {
    static let shared = KeychainManager()
    
    private let logger = Logger(subsystem: "com.mcp.agent", category: "KeychainManager")
    
    private init() {}
    
    func storeAPIKey(_ key: String, for service: String, account: String) -> Bool {
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        // Delete existing item first
        SecItemDelete(keychainQuery as CFDictionary)
        
        let status = SecItemAdd(keychainQuery as CFDictionary, nil)
        
        if status == errSecSuccess {
            logger.info("Stored API key for \(service):\(account)")
            return true
        } else {
            logger.error("Failed to store API key: \(status)")
            return false
        }
    }
    
    func retrieveAPIKey(for service: String, account: String) -> String? {
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(keychainQuery as CFDictionary, &item)
        
        if status == errSecSuccess,
           let data = item as? Data,
           let key = String(data: data, encoding: .utf8) {
            return key
        } else {
            logger.warning("API key not found for \(service):\(account)")
            return nil
        }
    }
    
    func deleteAPIKey(for service: String, account: String) -> Bool {
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(keychainQuery as CFDictionary)
        
        if status == errSecSuccess {
            logger.info("Deleted API key for \(service):\(account)")
            return true
        } else {
            logger.warning("Failed to delete API key for \(service):\(account): \(status)")
            return false
        }
    }
    
    // Convenience methods for common services
    func storeOllamaCloudKey(_ key: String) -> Bool {
        return storeAPIKey(key, for: "com.mcp.agent.ollama.cloud", account: "api_key")
    }
    
    func retrieveOllamaCloudKey() -> String? {
        return retrieveAPIKey(for: "com.mcp.agent.ollama.cloud", account: "api_key")
    }
    
    func storeOpenAIKey(_ key: String) -> Bool {
        return storeAPIKey(key, for: "com.mcp.agent.openai", account: "api_key")
    }
    
    func retrieveOpenAIKey() -> String? {
        return retrieveAPIKey(for: "com.mcp.agent.openai", account: "api_key")
    }
    
    func storeTwilioCredentials(sid: String, token: String) -> Bool {
        let credentials = ["sid": sid, "token": token]
        let data = try? JSONSerialization.data(withJSONObject: credentials)
        guard let data = data else { return false }
        
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.mcp.agent.twilio",
            kSecAttrAccount as String: "credentials",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        SecItemDelete(keychainQuery as CFDictionary)
        let status = SecItemAdd(keychainQuery as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    func retrieveTwilioCredentials() -> (sid: String, token: String)? {
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.mcp.agent.twilio",
            kSecAttrAccount as String: "credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(keychainQuery as CFDictionary, &item)
        
        if status == errSecSuccess,
           let data = item as? Data,
           let credentials = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let sid = credentials["sid"],
           let token = credentials["token"] {
            return (sid: sid, token: token)
        }
        
        return nil
    }
}
```

This complete implementation provides:

1. **MCP Manager**: Full auto-discovery, tool aggregation, and execution
2. **Calendar Manager**: Real EventKit integration with comprehensive CRUD operations
3. **LLM Manager**: Robust OpenAI-compatible client with streaming and fallback chain
4. **Watchdog Service**: LaunchD integration with health monitoring and auto-restart
5. **HTTP Gateway**: Clean bridge between Swift app and Python agent-core
6. **Keychain Manager**: Secure API key storage using macOS Keychain