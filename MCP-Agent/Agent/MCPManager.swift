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
    var isEnabled: Bool = true
    
    struct MCPParam: Codable {
        let type: String
        let description: String?
        let required: Bool
        let defaultValue: String?
    }
}

// MARK: - MCP Server Definition
class MCPServer: ObservableObject, Identifiable {
    let id = UUID()
    let name: String
    let type: ServerType
    @Published var isEnabled: Bool = true
    
    enum ServerType: Equatable, Codable {
        case stdio(command: String, arguments: [String])
        case sse(url: URL)
        case `internal`(name: String)
    }
    
    @Published var tools: [MCPTool] = []
    @Published var isConnected = false
    @Published var lastError: Error?
    
    init(name: String, type: ServerType) {
        self.name = name
        self.type = type
    }
    
    func connect() async throws {
        guard isEnabled else { return }
        
        do {
            await MainActor.run {
                self.lastError = nil
            }
            
            switch type {
            case .stdio(let command, let arguments):
                try await connectStdio(command: command, arguments: arguments)
            case .sse(let url):
                try await connectSSE(url: url)
            case .`internal`:
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
    
    private func connectStdio(command: String, arguments: [String]) async throws {
        let process = Process()
        
        // Handle command resolution
        if command.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
        } else {
            // Use /usr/bin/env to find the command in PATH
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            var envArgs = [command]
            envArgs.append(contentsOf: arguments)
            process.arguments = envArgs
        }
        
        // Environment setup
        var env = ProcessInfo.processInfo.environment
        // Ensure PATH is set reasonably if missing (e.g. if launched from UI app)
        if env["PATH"] == nil {
            env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        } else {
             // Append standard paths just in case
             env["PATH"] = (env["PATH"] ?? "") + ":/usr/local/bin:/opt/homebrew/bin"
        }
        process.environment = env
        
        let pipeOut = Pipe()
        let pipeIn = Pipe()
        let pipeErr = Pipe()
        
        process.standardOutput = pipeOut
        process.standardInput = pipeIn
        process.standardError = pipeErr
        
        try process.run()
        
        // Request tools list
        let request: [String: Any] = ["jsonrpc": "2.0", "method": "tools/list", "id": 1]
        let data = try JSONSerialization.data(withJSONObject: request)
        
        // Write request with newline
        pipeIn.fileHandleForWriting.write(data)
        pipeIn.fileHandleForWriting.write("\n".data(using: .utf8)!)
        
        // Read response (Simplified for V1 - assumes single JSON line response or quick response)
        // In production, this needs a proper JSON-RPC stream reader
        
        // Wait a bit for response
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1s wait
        
        // Attempt to read data
        // This is a naive implementation that expects the tool list to be available quickly
        // A real implementation would use a background task to read stdout continuously
        
        await MainActor.run {
            // Placeholder: discovery needs real bidirectional JSON-RPC
            // For now, we'll try to use internal discovery if it's the internal server,
            // otherwise we might need to parse stdout
            
            // For the demo, if we can't parse real tools from stdio yet, we just mark connected.
            // But let's try to mock some tools if it's the memory server
             if command.contains("memory") {
                 self.tools = [
                     MCPTool(name: "read_graph", description: "Read from memory graph", inputSchema: nil, category: "memory", requiresConfirmation: false, estimatedDuration: nil),
                     MCPTool(name: "create_entities", description: "Create entities in memory", inputSchema: nil, category: "memory", requiresConfirmation: true, estimatedDuration: nil)
                 ]
             }
        }
    }
    
    private func connectSSE(url: URL) async throws {
        var request = URLRequest(url: url.appendingPathComponent("tools"))
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MCPError.connectionFailed
        }
        
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
        case .stdio(let command, let args):
            return try await callStdioTool(name: name, arguments: arguments, command: command, args: args)
        case .sse(let url):
            return try await callSSETool(name: name, arguments: arguments, url: url)
        case .`internal`:
            return try await callInternalTool(name: name, arguments: arguments)
        }
    }
    
    private func callStdioTool(name: String, arguments: [String: Any], command: String, args: [String]) async throws -> [String: Any] {
        // Real implementation would reuse the running process
        return ["result": "Tool executed", "tool": name, "args": arguments]
    }
    
    private func callSSETool(name: String, arguments: [String: Any], url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url.appendingPathComponent("tools").appendingPathComponent("call"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
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

// MARK: - Persistence
struct PersistentServerConfig: Codable {
    let name: String
    let type: MCPServer.ServerType
    let isEnabled: Bool
    let disabledTools: [String]
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
    private let defaultsKey = "MCPServersConfig"
    
    private init() {
        loadConfig()
    }
    
    func startDiscovery() async {
        isDiscovering = true
        lastDiscoveryError = nil
        
        do {
            try await discoverLocalServers()
            
            // Always register internal tools if not already present
            if !servers.contains(where: { if case .`internal` = $0.type { return true } else { return false } }) {
                try await registerInternalServers()
            }
            
            // Connect to enabled servers
            for server in servers where server.isEnabled {
                try? await server.connect()
                applyToolStates(for: server)
            }
            
            aggregateTools()
            logger.info("MCP discovery completed. Found \(self.servers.count) servers with \(self.aggregatedTools.count) tools")
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
                    
                    // Check if we already have this server loaded (e.g. from persistence)
                    if !servers.contains(where: { $0.name == serverName }) {
                        // For auto-discovery, we assume stdio with just the path
                        let server = MCPServer(name: serverName, type: .stdio(command: serverPath.path, arguments: []))
                        servers.append(server)
                    }
                    break
                }
            }
        }
    }
    
    private func registerInternalServers() async throws {
        let internalServer = MCPServer(name: "InternalTools", type: .`internal`(name: "built-in"))
        servers.append(internalServer)
    }
    
    private func aggregateTools() {
        var allTools: [MCPTool] = []
        
        for server in servers where server.isEnabled {
            allTools.append(contentsOf: server.tools.filter { $0.isEnabled })
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
        
        guard tool.isEnabled else {
            throw MCPError.unknownTool("\(toolName) (Disabled)")
        }
        
        // Approval Check
        if tool.requiresConfirmation {
            let approved = await ApprovalManager.shared.requestApproval(toolName: toolName, arguments: arguments)
            guard approved else {
                throw MCPError.unknownTool("\(toolName) (Denied by user)")
            }
        }
        
        logger.info("Calling tool \(toolName) with arguments: \(arguments)")
        
        // Find the server that provides this tool
        guard let server = servers.first(where: { $0.tools.contains(where: { $0.name == toolName }) }) else {
            throw MCPError.serverNotFound(toolName)
        }
        
        guard server.isEnabled else {
            throw MCPError.serverNotFound("\(toolName) (Server Disabled)")
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
    
    // MARK: - Server Management
    
    func addServer(name: String, type: MCPServer.ServerType) {
        let server = MCPServer(name: name, type: type)
        servers.append(server)
        saveConfig()
        
        Task {
            try? await server.connect()
            applyToolStates(for: server)
            aggregateTools()
        }
    }
    
    func removeServer(_ server: MCPServer) {
        servers.removeAll { $0.id == server.id }
        aggregateTools()
        saveConfig()
    }
    
    func toggleServer(_ server: MCPServer) {
        server.isEnabled.toggle()
        if server.isEnabled {
            Task {
                try? await server.connect()
                applyToolStates(for: server)
                aggregateTools()
            }
        } else {
            aggregateTools()
        }
        saveConfig()
    }
    
    func toggleTool(_ tool: MCPTool, in server: MCPServer) {
        if let index = server.tools.firstIndex(where: { $0.name == tool.name }) {
            server.tools[index].isEnabled.toggle()
            aggregateTools()
            saveConfig()
        }
    }
    
    // MARK: - Persistence Logic
    
    private func saveConfig() {
        let configs = servers.map { server in
            PersistentServerConfig(
                name: server.name,
                type: server.type,
                isEnabled: server.isEnabled,
                disabledTools: server.tools.filter { !$0.isEnabled }.map { $0.name }
            )
        }
        
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
    
    private func loadConfig() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let configs = try? JSONDecoder().decode([PersistentServerConfig].self, from: data) else {
            return
        }
        
        var loadedServers: [MCPServer] = []
        
        for config in configs {
            let server = MCPServer(name: config.name, type: config.type)
            server.isEnabled = config.isEnabled
            loadedServers.append(server)
            server.lastError = nil
        }
        
        self.servers = loadedServers
    }
    
    // Helper to apply disabled tools after connection
    func applyToolStates(for server: MCPServer) {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let configs = try? JSONDecoder().decode([PersistentServerConfig].self, from: data),
              let config = configs.first(where: { $0.name == server.name && $0.type == server.type }) else {
            return
        }
        
        for i in 0..<server.tools.count {
            if config.disabledTools.contains(server.tools[i].name) {
                server.tools[i].isEnabled = false
            }
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
