import Foundation
import Network
import OSLog
import Combine

// MARK: - HTTP Gateway for Python Integration
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
        logger.info("Starting HTTP gateway on port \(self.port)")
        
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(integerLiteral: UInt16(port)))
        
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener.stateUpdateHandler = { [weak self] (state: NWListener.State) in
            guard let self = self else { return }
            switch state {
            case .ready:
                Task { @MainActor in
                    self.isRunning = true
                }
                self.logger.info("HTTP gateway ready on \(self.host):\(self.port)")
            case .failed(let error):
                Task { @MainActor in
                    self.isRunning = false
                }
                self.logger.error("HTTP gateway failed: \(error.localizedDescription)")
            default:
                break
            }
        }
        
        listener.start(queue: DispatchQueue.global())
        listeners.append(listener)
    }
    
    func stop() {
        logger.info("Stopping HTTP gateway")
        
        for listener in listeners {
            listener.cancel()
        }
        listeners.removeAll()
        Task { @MainActor in
            self.isRunning = false
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        Task { @MainActor in
            self.activeConnections += 1
        }
        
        connection.stateUpdateHandler = { [weak self] (state: NWConnection.State) in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.readRequest(connection)
            case .cancelled:
                Task { @MainActor in
                    self.activeConnections = max(0, self.activeConnections - 1)
                }
            default:
                break
            }
        }
        
        connection.start(queue: DispatchQueue.global())
    }
    
    private func readRequest(_ connection: NWConnection) {
        var requestData = Data()
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
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
        
        let agentName = (json["agent"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let caller = (agentName?.isEmpty == false ? agentName : nil) ?? "HTTP Gateway"
        
        Task {
            do {
                let result = try await MCPManager.shared.callTool(toolName, arguments: arguments, agentName: caller)
                let responseData = try JSONSerialization.data(withJSONObject: ["success": true, "result": result])
                self.sendJSONResponse(connection, statusCode: 200, data: responseData)
            } catch {
                let errorData = try JSONSerialization.data(withJSONObject: ["success": false, "error": error.localizedDescription])
                self.sendJSONResponse(connection, statusCode: 500, data: errorData)
            }
        }
    }
    
    private func handleToolList(_ connection: NWConnection) {
        Task { @MainActor in
            let tools = MCPManager.shared.aggregatedTools.map { tool in
                [
                    "name": tool.name,
                    "description": tool.description ?? "",
                    "category": tool.category ?? "",
                    "requires_confirmation": tool.requiresConfirmation
                ] as [String : Any]
            }
            
            let responseData = try? JSONSerialization.data(withJSONObject: ["tools": tools])
            self.sendJSONResponse(connection, statusCode: 200, data: responseData ?? Data())
        }
    }
    
    private func handleStatus(_ connection: NWConnection) {
        Task { @MainActor in
            let status: [String: Any] = [
                "status": "running",
                "active_connections": self.activeConnections,
                "mcp_servers": MCPManager.shared.servers.map {
                    server in
                    [
                        "name": server.name,
                        "type": String(describing: server.type),
                        "is_connected": server.isConnected,
                        "tool_count": server.tools.count
                    ] as [String : Any]
                },
                "llm_provider": LLMManager.shared.currentProvider,
                "is_processing": LLMManager.shared.isProcessing,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
            
            let responseData = try? JSONSerialization.data(withJSONObject: status)
            self.sendJSONResponse(connection, statusCode: 200, data: responseData ?? Data())
        }
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
        // Timers should be scheduled on a run loop, or use task sleep
        // Using Task.sleep for async loop
        Task {
            while connection.state == .ready {
                let message = await self.generateSSEMessage(for: stream)
                let sseData = "data: \(message)\n\n".data(using: .utf8)!
                
                let sent = await withCheckedContinuation { continuation in
                    connection.send(content: sseData, completion: .contentProcessed { error in
                        continuation.resume(returning: error == nil)
                    })
                }
                
                if !sent { break }
                
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }
    
    private func generateSSEMessage(for stream: String) async -> String {
        switch stream {
        case "overlay":
            return "Current action: \(generateRandomAction())"
        case "status":
            return await MainActor.run {
                "Agent status: \(LLMManager.shared.isProcessing ? "Processing" : "Idle")"
            }
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
                self.sendJSONResponse(connection, statusCode: 200, data: responseData)
            } catch {
                let errorData = try JSONSerialization.data(withJSONObject: ["success": false, "error": error.localizedDescription])
                self.sendJSONResponse(connection, statusCode: 500, data: errorData)
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
