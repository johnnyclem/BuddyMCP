import Combine
import Foundation
import OSLog

// MARK: - LLM Configuration
struct LLMConfig: Codable {
    let provider: LLMProvider
    let baseURL: String?
    let apiKey: String?
    let model: String
    var temperature: Double = 0.7
    var maxTokens: Int = 4096
    var timeout: TimeInterval = 60
    
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
        let index: Int?
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
    private var isLoadingSettings = false
    
    private enum DefaultsKeys {
        static let useRemote = "llm_use_remote"
        static let remoteBaseURL = "llm_remote_base_url"
        static let remoteModel = "llm_remote_model"
        static let veniceIncludeSystemPrompt = "llm_venice_include_system_prompt"
        static let veniceWebSearchMode = "llm_venice_web_search_mode"
    }
    
    private let localBaseURL = "http://localhost:11434/v1"
    private let localAPIKey = "ollama"
    private let localModel = "qwen3:8b"
    
    @Published var isProcessing = false
    @Published var currentProvider: String = ""
    @Published var lastError: Error?
    @Published var statusMessage: String = ""
    
    @Published var useRemote = false {
        didSet {
            guard !isLoadingSettings else { return }
            persistSettings()
            applyFallbackChain()
        }
    }
    
    @Published var remoteBaseURL = "" {
        didSet {
            guard !isLoadingSettings else { return }
            persistSettings()
            applyFallbackChain()
        }
    }
    
    @Published var remoteModel = "" {
        didSet {
            guard !isLoadingSettings else { return }
            persistSettings()
            applyFallbackChain()
        }
    }
    
    @Published var remoteModels: [String] = []
    @Published var isRefreshingModels = false
    @Published var remoteModelsError: String = ""
    @Published var remoteKeyStored = false
    
    @Published var veniceIncludeSystemPrompt = true {
        didSet {
            guard !isLoadingSettings else { return }
            persistSettings()
        }
    }
    
    @Published var veniceWebSearchMode = "auto" {
        didSet {
            guard !isLoadingSettings else { return }
            persistSettings()
        }
    }
    
    private init() {
        Task {
            await setupFallbackChain()
        }
    }
    
    private func setupFallbackChain() async {
        bootstrapRemoteDefaultsIfNeeded()
        loadSettings()
        applyFallbackChain()
    }

    private func bootstrapRemoteDefaultsIfNeeded() {
        let env = EnvLoader.loadMergedEnvironment()
        if UserDefaults.standard.string(forKey: DefaultsKeys.remoteBaseURL) == nil {
            if let baseURL = env["VENICE_BASE_URL"] ?? env["OPENAI_BASE_URL"] {
                UserDefaults.standard.set(baseURL, forKey: DefaultsKeys.remoteBaseURL)
            }
        }
        
        if KeychainManager.shared.retrieveOpenAICompatibleKey() == nil {
            if let apiKey = env["VENICE_API_KEY"] ?? env["OPENAI_API_KEY"] {
                _ = KeychainManager.shared.storeOpenAICompatibleKey(apiKey)
            }
        }
    }

    private func loadSettings() {
        isLoadingSettings = true
        defer { isLoadingSettings = false }
        
        useRemote = UserDefaults.standard.bool(forKey: DefaultsKeys.useRemote)
        remoteBaseURL = UserDefaults.standard.string(forKey: DefaultsKeys.remoteBaseURL) ?? ""
        remoteModel = UserDefaults.standard.string(forKey: DefaultsKeys.remoteModel) ?? ""
        if UserDefaults.standard.object(forKey: DefaultsKeys.veniceIncludeSystemPrompt) == nil {
            UserDefaults.standard.set(true, forKey: DefaultsKeys.veniceIncludeSystemPrompt)
        }
        veniceIncludeSystemPrompt = UserDefaults.standard.bool(forKey: DefaultsKeys.veniceIncludeSystemPrompt)
        
        if UserDefaults.standard.string(forKey: DefaultsKeys.veniceWebSearchMode) == nil {
            UserDefaults.standard.set("auto", forKey: DefaultsKeys.veniceWebSearchMode)
        }
        veniceWebSearchMode = UserDefaults.standard.string(forKey: DefaultsKeys.veniceWebSearchMode) ?? "auto"
        refreshRemoteKeyStatus()
    }
    
    private func persistSettings() {
        UserDefaults.standard.set(useRemote, forKey: DefaultsKeys.useRemote)
        UserDefaults.standard.set(remoteBaseURL, forKey: DefaultsKeys.remoteBaseURL)
        UserDefaults.standard.set(remoteModel, forKey: DefaultsKeys.remoteModel)
        UserDefaults.standard.set(veniceIncludeSystemPrompt, forKey: DefaultsKeys.veniceIncludeSystemPrompt)
        UserDefaults.standard.set(veniceWebSearchMode, forKey: DefaultsKeys.veniceWebSearchMode)
    }
    
    private func applyFallbackChain() {
        var configs: [LLMConfig] = []
        if let remoteConfig = buildRemoteConfig() {
            configs.append(remoteConfig)
        }
        configs.append(buildLocalConfig())
        fallbackChain = configs
    }
    
    private func buildLocalConfig() -> LLMConfig {
        LLMConfig(
            provider: .ollamaLocal,
            baseURL: localBaseURL,
            apiKey: localAPIKey,
            model: localModel
        )
    }
    
    private func buildRemoteConfig() -> LLMConfig? {
        guard useRemote else { return nil }
        let baseURL = remoteBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = remoteModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty, !model.isEmpty else { return nil }
        guard let apiKey = KeychainManager.shared.retrieveOpenAICompatibleKey() else { return nil }
        
        return LLMConfig(
            provider: .openAICompatible,
            baseURL: baseURL,
            apiKey: apiKey,
            model: model
        )
    }

    func refreshRemoteKeyStatus() {
        remoteKeyStored = KeychainManager.shared.retrieveOpenAICompatibleKey() != nil
    }
    
    func storeRemoteAPIKey(_ key: String) {
        guard !key.isEmpty else { return }
        _ = KeychainManager.shared.storeOpenAICompatibleKey(key)
        refreshRemoteKeyStatus()
        applyFallbackChain()
    }
    
    func clearRemoteAPIKey() {
        _ = KeychainManager.shared.deleteOpenAICompatibleKey()
        refreshRemoteKeyStatus()
        applyFallbackChain()
    }

    struct RemoteModelsResponse: Codable {
        let data: [RemoteModel]
        
        struct RemoteModel: Codable {
            let id: String
        }
    }
    
    func refreshRemoteModels() async {
        remoteModelsError = ""
        isRefreshingModels = true
        defer { isRefreshingModels = false }
        
        let baseURL = remoteBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty else {
            remoteModelsError = "Enter a base URL to fetch models."
            return
        }
        guard let apiKey = KeychainManager.shared.retrieveOpenAICompatibleKey() else {
            remoteModelsError = "Add an API key to fetch models."
            return
        }
        guard let url = buildModelsURL(baseURL: baseURL) else {
            remoteModelsError = "Invalid base URL."
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                remoteModelsError = "Invalid response from model list."
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorBody = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                var message = errorBody["message"] as? String ?? errorBody["error"] as? String
                if message == nil, let errorDict = errorBody["error"] as? [String: Any] {
                    message = errorDict["message"] as? String
                }
                remoteModelsError = "HTTP \(httpResponse.statusCode): \(message ?? "Model list failed")"
                return
            }
            
            let modelResponse = try JSONDecoder().decode(RemoteModelsResponse.self, from: data)
            let models = modelResponse.data.map { $0.id }.sorted()
            remoteModels = models
            if remoteModel.isEmpty || !models.contains(remoteModel) {
                remoteModel = models.first ?? ""
            }
        } catch {
            remoteModelsError = error.localizedDescription
        }
    }

    var remoteSettingsIssue: String? {
        guard useRemote else { return nil }
        if remoteBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Remote base URL is required."
        }
        if !remoteKeyStored {
            return "API key is required for remote inference."
        }
        if remoteModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Select a remote model."
        }
        return nil
    }
    
    func setFallbackChain(_ configs: [LLMConfig]) {
        fallbackChain = configs
    }
    
    func generateResponse(messages: [[String: Any]], tools: [MCPTool]? = nil, stream: Bool = true) async throws -> AsyncThrowingStream<String, Error> {
        isProcessing = true
        lastError = nil
        statusMessage = "Thinking..."
        
        return AsyncThrowingStream { continuation in
            Task {
                defer { 
                    isProcessing = false 
                    statusMessage = ""
                }
                
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
    
    private func generateStreamingResponse(config: LLMConfig, messages: [[String: Any]], tools: [MCPTool]?, chunkHandler: @escaping (String) -> Void) async throws {
        let request = try buildRequest(config: config, messages: messages, tools: tools, stream: true)
        
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            // Try to read error body if possible (bytes stream doesn't allow easy reading of body without consuming)
             throw LLMError.httpError(statusCode: httpResponse.statusCode, message: "Stream failed")
        }
        
        var accumulatedContent = ""
        var accumulatedToolCalls: [Int: (id: String, name: String, args: String)] = [:]
        
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
                    accumulatedContent += content
                    chunkHandler(content)
                }
                
                // Buffer tool calls
                if let toolCalls = chunk.choices.first?.delta.toolCalls {
                    for toolCall in toolCalls {
                        let index = toolCall.index ?? 0 // Index might be missing in some implementations, assume 0
                        
                        if accumulatedToolCalls[index] == nil {
                            accumulatedToolCalls[index] = (id: "", name: "", args: "")
                        }
                        
                        if !toolCall.id.isEmpty {
                            accumulatedToolCalls[index]?.id = toolCall.id
                        }
                        
                        if !toolCall.function.name.isEmpty {
                            accumulatedToolCalls[index]?.name += toolCall.function.name
                        }
                        
                        if !toolCall.function.arguments.isEmpty {
                            accumulatedToolCalls[index]?.args += toolCall.function.arguments
                        }
                    }
                }
                
            } catch {
                logger.warning("Failed to parse streaming chunk: \(error.localizedDescription)")
            }
        }
        
        // Process buffered tool calls
        if !accumulatedToolCalls.isEmpty {
            var nextMessages = messages
            
            // 1. Append Assistant Message with Tool Calls
            var toolCallsList: [[String: Any]] = []
            let sortedCalls = accumulatedToolCalls.sorted { $0.key < $1.key }
            
            for (_, call) in sortedCalls {
                toolCallsList.append([
                    "id": call.id,
                    "type": "function",
                    "function": [
                        "name": call.name,
                        "arguments": call.args
                    ]
                ])
            }
            
            var assistantMsg: [String: Any] = [
                "role": "assistant",
                "tool_calls": toolCallsList
            ]
            if !accumulatedContent.isEmpty {
                assistantMsg["content"] = accumulatedContent
            }
            nextMessages.append(assistantMsg)
            
            // 2. Execute Tools and Append Results
            for (_, call) in sortedCalls {
                statusMessage = "Calling tool: \(call.name)..."
                
                // Parse args
                let argsData = call.args.data(using: .utf8) ?? Data()
                let arguments = (try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]) ?? [:]
                
                do {
                    let result = try await MCPManager.shared.callTool(call.name, arguments: arguments)
                    
                    // JSON stringify the result for the message content
                    let resultData = try JSONSerialization.data(withJSONObject: result)
                    let resultString = String(data: resultData, encoding: .utf8) ?? "{}"
                    
                    nextMessages.append([
                        "role": "tool",
                        "tool_call_id": call.id,
                        "content": resultString
                    ])
                    
                } catch {
                    nextMessages.append([
                        "role": "tool",
                        "tool_call_id": call.id,
                        "content": "Error: \(error.localizedDescription)"
                    ])
                }
            }
            
            // 3. Recurse
            statusMessage = "Thinking..."
            try await generateStreamingResponse(config: config, messages: nextMessages, tools: tools, chunkHandler: chunkHandler)
        }
    }
    
    private func generateNonStreamingResponse(config: LLMConfig, messages: [[String: Any]], tools: [MCPTool]?) async throws -> String {
        let request = try buildRequest(config: config, messages: messages, tools: tools, stream: false)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            // ... (Error handling same as before)
            let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            var errorMessage: String?
            if let errorStr = errorBody?["error"] as? String {
                errorMessage = errorStr
            } else if let errorDict = errorBody?["error"] as? [String: Any], let msg = errorDict["message"] as? String {
                errorMessage = msg
            } else {
                errorMessage = errorBody?["message"] as? String
            }
            throw LLMError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        let llmResponse = try JSONDecoder().decode(LLMResponse.self, from: data)
        let message = llmResponse.choices.first?.message
        
        // Check for tool calls
        if let toolCalls = message?.toolCalls, !toolCalls.isEmpty {
            var nextMessages = messages
            
            // Reconstruct assistant message
            var assistantMsg: [String: Any] = [
                "role": "assistant",
                "tool_calls": toolCalls.map { [
                    "id": $0.id,
                    "type": $0.type,
                    "function": [
                        "name": $0.function.name,
                        "arguments": $0.function.arguments
                    ]
                ]}
            ]
            if let content = message?.content {
                assistantMsg["content"] = content
            }
            nextMessages.append(assistantMsg)
            
            // Execute tools
            for toolCall in toolCalls {
                statusMessage = "Calling tool: \(toolCall.function.name)..."
                let argsData = toolCall.function.arguments.data(using: .utf8) ?? Data()
                let arguments = (try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]) ?? [:]
                
                do {
                    let result = try await MCPManager.shared.callTool(toolCall.function.name, arguments: arguments)
                     let resultData = try JSONSerialization.data(withJSONObject: result)
                    let resultString = String(data: resultData, encoding: .utf8) ?? "{}"
                    
                    nextMessages.append([
                        "role": "tool",
                        "tool_call_id": toolCall.id,
                        "content": resultString
                    ])
                } catch {
                     nextMessages.append([
                        "role": "tool",
                        "tool_call_id": toolCall.id,
                        "content": "Error: \(error.localizedDescription)"
                    ])
                }
            }
            
            // Recurse
            statusMessage = "Thinking..."
            return try await generateNonStreamingResponse(config: config, messages: nextMessages, tools: tools)
        }
        
        return message?.content ?? ""
    }
    
    private func buildRequest(config: LLMConfig, messages: [[String: Any]], tools: [MCPTool]?, stream: Bool) throws -> URLRequest {
        var request = URLRequest(url: try buildEndpointURL(config: config))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = config.timeout
        
        // Add authorization header
        if let apiKey = config.apiKey {
            if config.provider == .openAICompatible || config.provider == .ollamaCloud || config.provider == .ollamaLocal {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }
        
        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
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

        if config.provider == .openAICompatible, isVeniceBaseURL(config.baseURL) {
            var veniceParameters: [String: Any] = [
                "include_venice_system_prompt": veniceIncludeSystemPrompt
            ]
            let webSearchMode = veniceWebSearchMode.trimmingCharacters(in: .whitespacesAndNewlines)
            if !webSearchMode.isEmpty {
                veniceParameters["enable_web_search"] = webSearchMode
            }
            requestBody["venice_parameters"] = veniceParameters
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        return request
    }
    
    private func buildEndpointURL(config: LLMConfig) throws -> URL {
        let baseString: String
        switch config.provider {
        case .ollamaLocal:
            baseString = config.baseURL ?? localBaseURL
        case .ollamaCloud:
            baseString = config.baseURL ?? "https://ollama.cloud/api"
        case .openAICompatible:
            baseString = config.baseURL ?? "https://api.openai.com/v1"
        }
        
        guard let baseURL = URL(string: baseString) else {
            throw LLMError.invalidURL
        }
        return baseURL.appendingPathComponent("chat/completions")
    }

    private func buildModelsURL(baseURL: String) -> URL? {
        guard let url = URL(string: baseURL) else { return nil }
        return url.appendingPathComponent("models")
    }

    private func isVeniceBaseURL(_ baseURL: String?) -> Bool {
        guard let baseURL = baseURL, let url = URL(string: baseURL) else { return false }
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("venice.ai")
    }
    
    var isUsingVeniceRemote: Bool {
        isVeniceBaseURL(remoteBaseURL)
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
