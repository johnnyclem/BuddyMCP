import Foundation
import OSLog

class MessagesManager: ObservableObject {
    static let shared = MessagesManager()
    private let logger = Logger(subsystem: "com.mcp.agent", category: "MessagesManager")
    
    private init() {}
    
    // MARK: - Public Methods
    
    func sendMessage(to recipientQuery: String, message: String) async throws -> [String: Any] {
        // AppleScript to find buddy/chat and send message
        // We prioritize finding an existing chat to ensure we reply in the right thread
        let script = """
tell application "Messages"
    try
        set targetService to first service whose service type is iMessage
        set targetChat to first chat whose name contains \"\(recipientQuery)\" 
        send \"\(message)\" to targetChat
        return "Sent to chat: " & name of targetChat
    on error
        -- Fallback: try finding a buddy and creating a new chat/sending directly
        try
            set targetBuddy to first buddy whose name contains \"\(recipientQuery)\" 
            send \"\(message)\" to targetBuddy
            return "Sent to buddy: " & name of targetBuddy
        on error
            return "Error: Could not find recipient matching '\(recipientQuery)'"
        end try
    end try
end tell
"""
        
        let result = try runAppleScript(script)
        if result.starts(with: "Error:") {
            return ["success": false, "message": result]
        }
        return ["success": true, "message": result]
    }
    
    func readMessages(from senderQuery: String, limit: Int = 5) async throws -> [String: Any] {
        let script = """
tell application "Messages"
    try
        set targetChat to first chat whose name contains \"\(senderQuery)\" 
        
        -- Get last N messages
        set msgList to {}
        set recentMessages to (messages of targetChat)
        
        -- AppleScript lists are 1-based. We want the last 'limit' items.
        set msgCount to count of recentMessages
        if msgCount is 0 then return "[]"
        
        set startIndex to msgCount - \(limit) + 1
        if startIndex < 1 then set startIndex to 1
        
        set resultList to {}
        repeat with i from startIndex to msgCount
            set msg to item i of recentMessages
            set msgContent to content of msg
            set msgSender to "Me"
            
            try
                set buddyName to name of (buddy of msg)
                if buddyName is not missing value then
                    set msgSender to buddyName
                end if
            end try
            
            if msgContent is missing value then set msgContent to "[Attachment/Empty]"
            
            -- Simple JSON construction in AppleScript is painful, passing raw string
            set end of resultList to "{" & "\"sender\": \"" & msgSender & "\", \"content\": \"" & msgContent & "\"}"
        end repeat
        
        -- Join with commas
        set jsonString to "["
        repeat with i from 1 to count of resultList
            set jsonString to jsonString & item i of resultList
            if i < count of resultList then set jsonString to jsonString & ","
        end repeat
        set jsonString to jsonString & "]"
        
        return jsonString
    on error
        return "Error: Could not find chat with '\(senderQuery)'"
    end try
end tell
"""
        
        let jsonString = try runAppleScript(script)
        
        if jsonString.starts(with: "Error:") {
            return ["success": false, "message": jsonString]
        }
        
        // Parse the crude JSON string returned by AppleScript
        // We clean up escaped quotes if necessary, though the script tries to be safe
        if let data = jsonString.data(using: .utf8),
           let messages = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            return ["success": true, "messages": messages, "count": messages.count]
        }
        
        // Fallback if JSON parsing fails (AppleScript JSON generation is fragile)
        return ["success": false, "raw_output": jsonString, "message": "Failed to parse messages"]
    }
    
    // MARK: - Private Helper
    
    private func runAppleScript(_ source: String) throws -> String {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: source) {
            let output: NSAppleEventDescriptor = scriptObject.executeAndReturnError(&error)
            
            if let error = error {
                let errorMessage = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown AppleScript error"
                logger.error("AppleScript failed: \(errorMessage)")
                throw NSError(domain: "AppleScript", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            }
            
            return output.stringValue ?? ""
        }
        throw NSError(domain: "AppleScript", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize NSAppleScript"])
    }
}
