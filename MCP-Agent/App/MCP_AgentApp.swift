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
        // Explicitly set the app as a regular GUI app to ensure it can receive focus and key events
        NSApp.setActivationPolicy(.regular)
        
        // OverlayWindowController.shared.show()
        
        // Check for daemon mode
        if CommandLine.arguments.contains("--daemon-mode") {
            startDaemonMode()
        } else {
            startUIApplication()
        }
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        // Force app to foreground and make main window key
        NSApp.activate(ignoringOtherApps: true)
        
        // Find the main window (not the overlay if it exists) and focus it
        if let window = NSApp.windows.first(where: { $0.styleMask.contains(.titled) }) {
            window.makeKeyAndOrderFront(nil)
            window.makeMain()
        }
    }
    
    private func startDaemonMode() {
        // In daemon mode, start the agent core
        StartAgentDaemon()
        
        // Start HTTP gateway for MCP integration
        Task {
            try? HTTPGateway.shared.start()
        }
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
    // In a real app bundle, this would be in Resources/AgentCore
    // For development, we'll assume it's relative or in a known location
    var pythonPath = Bundle.main.path(forResource: "agent_core", ofType: "py", inDirectory: "AgentCore")
    
    if pythonPath == nil {
        // Fallback for development/swift run
        let cwd = FileManager.default.currentDirectoryPath
        let devPath = URL(fileURLWithPath: cwd).appendingPathComponent("AgentCore/agent_core.py")
        if FileManager.default.fileExists(atPath: devPath.path) {
            pythonPath = devPath.path
        } else {
            // Try one level up if we are inside MCP-Agent dir
            let upPath = URL(fileURLWithPath: cwd).appendingPathComponent("MCP-Agent/AgentCore/agent_core.py")
             if FileManager.default.fileExists(atPath: upPath.path) {
                pythonPath = upPath.path
            }
        }
    }
    
    guard let scriptPath = pythonPath else {
        print("Error: Could not find agent_core.py")
        return
    }
    
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    proc.arguments = [scriptPath]
    
    do {
        try proc.run()
        print("Started agent daemon at \(scriptPath)")
    } catch {
        print("Failed to start agent daemon: \(error)")
    }
}
