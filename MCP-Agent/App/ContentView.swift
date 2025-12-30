import SwiftUI

struct ContentView: View {
    @ObservedObject var mcpManager = MCPManager.shared
    @ObservedObject var llmManager = LLMManager.shared
    @ObservedObject var watchdog = WatchdogService.shared
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack {
                Text("BuddyMCP")
                    .font(.headline)
                
                Spacer()
                
                HStack(spacing: 16) {
                    StatusIndicator(label: "MCP", isActive: !mcpManager.servers.isEmpty)
                    StatusIndicator(label: "LLM", isActive: !llmManager.currentProvider.isEmpty)
                    StatusIndicator(label: "Agent", isActive: watchdog.isServiceInstalled)
                }
                
                Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Main Content
            TimelineView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear {
            // Backup activation call
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

struct StatusIndicator: View {
    let label: String
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}