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
