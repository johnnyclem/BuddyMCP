import SwiftUI

struct ChatView: View {
    @State private var messageText = ""
    @State private var messages: [ChatMessage] = [
        ChatMessage(role: "agent", content: "Hello! I'm your BuddyMCP agent. How can I help you today?")
    ]
    @ObservedObject var llmManager = LLMManager.shared
    
    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: String
        var content: String
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Chat")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Message List
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { msg in
                            HStack {
                                if msg.role == "user" {
                                    Spacer()
                                    Text(msg.content)
                                        .padding(10)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                        .textSelection(.enabled)
                                } else {
                                    Text(msg.content)
                                        .padding(10)
                                        .background(Color(nsColor: .controlBackgroundColor))
                                        .cornerRadius(12)
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                            }
                            .id(msg.id)
                        }
                    }
                    .padding()
                }
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
            
            Divider()
            
            // Status Bar
            if !llmManager.statusMessage.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                    Text(llmManager.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            
            // Input Area
            HStack {
                TextField("Type a message...", text: $messageText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        sendMessage()
                    }
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(messageText.isEmpty || llmManager.isProcessing)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
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
        
        var messageHistory: [[String: String]] = [
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
