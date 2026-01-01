import SwiftUI

struct ContentView: View {
    @ObservedObject var mcpManager = MCPManager.shared
    @ObservedObject var llmManager = LLMManager.shared
    @ObservedObject var watchdog = WatchdogService.shared
    @ObservedObject var themeManager = ThemeManager.shared
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack {
                Text("BUDDYMCP")
                    .font(Theme.headlineFont(size: 24))
                    .tracking(2) // Tracking for headline feel
                    .foregroundColor(Theme.inkBlack)
                
                Spacer()
                
                HStack(spacing: 16) {
                    StatusIndicator(label: "MCP", isActive: !mcpManager.servers.isEmpty)
                    StatusIndicator(label: "LLM", isActive: !llmManager.currentProvider.isEmpty)
                    StatusIndicator(label: "AGENT", isActive: watchdog.isServiceInstalled)
                }
                
                Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "gear")
                        .foregroundColor(Theme.inkBlack)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Theme.background)
            .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.inkBlack), alignment: .bottom)
            
            // Main Content
            TimelineView()
                .background(Theme.background)
        }
        .background(Theme.background)
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
            Rectangle()
                .fill(isActive ? Theme.inkBlack : Color.clear)
                .stroke(Theme.inkBlack, lineWidth: 1)
                .frame(width: 8, height: 8)
            Text(label.uppercased())
                .font(Theme.uiFont(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(Theme.inkBlack)
        }
    }
}