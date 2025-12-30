import Foundation

class CryptoManager {
    static let shared = CryptoManager()
    
    private init() {}
    
    func getPrice(symbol: String) async throws -> [String: Any] {
        // Placeholder for crypto price fetch
        // In production, connect to CoinGecko or similar API
        
        let mockPrice = Double.random(in: 1000...60000)
        
        return [
            "symbol": symbol.uppercased(),
            "price_usd": mockPrice,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
    }
}
