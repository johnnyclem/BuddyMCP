import SwiftUI

struct ChatView: View {
    @State private var messageText = ""
    @State private var messages: [ChatMessage] = [
        ChatMessage(role: "agent", content: "Hello! I'm your BuddyMCP agent. How can I help you today?")
    ]
    @ObservedObject var llmManager = LLMManager.shared
    @ObservedObject var themeManager = ThemeManager.shared
    
    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: String
        var content: String
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("LIVE CHAT")
                    .font(Theme.headlineFont(size: 16))
                    .tracking(1)
                Spacer()
            }
            .padding()
            .background(Theme.background)
            .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.inkBlack), alignment: .bottom)
            
            // Message List
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(messages) { msg in
                            HStack(alignment: .top) {
                                if msg.role == "user" {
                                    Spacer()
                                    Text(msg.content)
                                        .font(Theme.bodyFont(size: 15))
                                        .padding(12)
                                        .background(Theme.inkBlack)
                                        .foregroundColor(Theme.background)
                                        .textSelection(.enabled)
                                } else {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("AGENT")
                                            .font(Theme.monoFont(size: 10))
                                            .foregroundColor(Theme.inkBlack.opacity(0.6))
                                        
                                        Text(msg.content)
                                            .font(Theme.bodyFont(size: 15))
                                            .padding(12)
                                            .background(Theme.background)
                                            .overlay(Rectangle().stroke(Theme.inkBlack, lineWidth: 1))
                                            .foregroundColor(Theme.inkBlack)
                                            .textSelection(.enabled)
                                    }
                                    Spacer()
                                }
                            }
                            .id(msg.id)
                        }
                    }
                    .padding()
                }
                .background(Theme.background)
                .onChange(of: messages.count) { _ in
                    if let lastId = messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
                .onChange(of: messages.last?.content) { _ in
                    if let lastId = messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            
            Rectangle().frame(height: 1).foregroundColor(Theme.inkBlack)
            
            // Status Bar
            if !llmManager.statusMessage.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                    Text(llmManager.statusMessage.uppercased())
                        .font(Theme.monoFont(size: 10))
                        .foregroundColor(Theme.inkBlack)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .background(Theme.background)
            }
            
            // Input Area
            HStack(spacing: 0) {
                TextField("TYPE A MESSAGE...", text: $messageText)
                    .textFieldStyle(.plain)
                    .font(Theme.monoFont(size: 14))
                    .padding(12)
                    .background(Theme.background)
                    .onSubmit {
                        sendMessage()
                    }
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.right")
                        .foregroundColor(Theme.inkBlack)
                        .padding(12)
                }
                .buttonStyle(.plain)
                .disabled(messageText.isEmpty || llmManager.isProcessing)
                .border(width: 1, edges: [.leading], color: Theme.inkBlack)
            }
            .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.inkBlack), alignment: .top)
            .background(Theme.background)
        }
        .background(Theme.background)
    }
    
    func sendMessage() {
        guard !messageText.isEmpty else { return }
        
        let userMsg = messageText
        messages.append(ChatMessage(role: "user", content: userMsg))
        messageText = ""
        
        // Prepare context
        let context = TaskManager.shared.getContextString()
        let systemPrompt = """
        You are BuddyMCP, a helpful AI agent.
        You have access to the user's task list and calendar.
        
        CURRENT CONTEXT:
        \(context)
        
        Use the available tools to help the user. If you need approval, ask for it.
        """
        
        var messageHistory: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        // Add recent history (last 10 messages)
        for msg in messages.suffix(10) {
            messageHistory.append(["role": msg.role == "agent" ? "assistant" : "user", "content": msg.content])
        }
        
        // Add placeholder for agent response
        messages.append(ChatMessage(role: "agent", content: ""))
        let responseIndex = messages.count - 1
        
        Task {
            do {
                // Get tools
                let availableTools = MCPManager.shared.aggregatedTools.filter { $0.isEnabled }
                
                // Stream response
                let stream = try await LLMManager.shared.generateResponse(messages: messageHistory, tools: availableTools)
                
                for try await chunk in stream {
                    await MainActor.run {
                        messages[responseIndex].content += chunk
                    }
                }
            } catch {
                await MainActor.run {
                    messages[responseIndex].content += "\n[Error: \(error.localizedDescription)]"
                }
            }
        }
    }
}
