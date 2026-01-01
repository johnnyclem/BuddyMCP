import SwiftUI

// MARK: - Theme Management

enum ThemeType: String, CaseIterable, Identifiable {
    case newsprint
    case minimalist
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .newsprint: return "Newsprint"
        case .minimalist: return "Minimalist Mono"
        }
    }
}

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @AppStorage("selectedTheme") var currentTheme: ThemeType = .newsprint {
        didSet {
            objectWillChange.send()
        }
    }
}

// MARK: - Theme Definition

struct Theme {
    static var manager = ThemeManager.shared
    
    // MARK: - Colors
    static var background: Color {
        switch manager.currentTheme {
        case .newsprint: return Color(hex: "F9F9F7")
        case .minimalist: return Color(hex: "FFFFFF")
        }
    }
    
    static var inkBlack: Color {
        switch manager.currentTheme {
        case .newsprint: return Color(hex: "111111")
        case .minimalist: return Color(hex: "000000")
        }
    }
    
    static var dividerGrey: Color {
        switch manager.currentTheme {
        case .newsprint: return Color(hex: "E5E5E0")
        case .minimalist: return Color(hex: "E5E5E5")
        }
    }
    
    static var editorialRed: Color {
        switch manager.currentTheme {
        case .newsprint: return Color(hex: "CC0000")
        case .minimalist: return Color(hex: "000000") // Black is the accent
        }
    }
    
    static var hoverGrey: Color {
        switch manager.currentTheme {
        case .newsprint: return Color(hex: "F5F5F5")
        case .minimalist: return Color(hex: "F5F5F5")
        }
    }
    
    // MARK: - Typography
    static func headlineFont(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }
    
    static func bodyFont(size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
    
    static func uiFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch manager.currentTheme {
        case .newsprint:
            return .system(size: size, weight: weight, design: .default)
        case .minimalist:
            // Minimalist uses Serif for almost everything, but Mono/Sans for UI is okay.
            // Doc says "Display/Headlines: Playfair", "Body: Source Serif 4", "Mono/Labels: JetBrains Mono"
            // So mostly Serif. But for small UI elements, System is safer or Serif if we want to be strict.
            // Let's stick to System for UI legibility in this iteration.
            return .system(size: size, weight: weight, design: .default)
        }
    }
    
    static func monoFont(size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
}

// MARK: - Extensions

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers

struct NewsprintCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.background)
            .border(Theme.inkBlack, width: 1)
    }
}

struct NewsprintInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(8)
            .font(Theme.monoFont(size: 14))
            .background(Color.clear)
            .overlay(Rectangle().frame(height: 2).padding(.top, 30).foregroundColor(Theme.inkBlack), alignment: .bottom)
    }
}

struct NewsprintButtonModifier: ViewModifier {
    let isPrimary: Bool
    
    func body(content: Content) -> some View {
        content
            .font(Theme.uiFont(size: 14, weight: .bold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isPrimary ? Theme.inkBlack : Color.clear)
            .foregroundColor(isPrimary ? Theme.background : Theme.inkBlack)
            .overlay(Rectangle().stroke(Theme.inkBlack, lineWidth: 1))
    }
}

extension View {
    func newsprintCard() -> some View {
        modifier(NewsprintCardModifier())
    }
    
    func newsprintInput() -> some View {
        modifier(NewsprintInputModifier())
    }
    
    func newsprintButton(isPrimary: Bool = true) -> some View {
        modifier(NewsprintButtonModifier(isPrimary: isPrimary))
    }
    
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
    }
}

struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var w: CGFloat = 0
            var h: CGFloat = 0
            
            switch edge {
            case .top:
                x = rect.minX; y = rect.minY; w = rect.width; h = width
            case .bottom:
                x = rect.minX; y = rect.maxY - width; w = rect.width; h = width
            case .leading:
                x = rect.minX; y = rect.minY; w = width; h = rect.height
            case .trailing:
                x = rect.maxX - width; y = rect.minY; w = width; h = rect.height
            }
            path.addRect(CGRect(x: x, y: y, width: w, height: h))
        }
        return path
    }
}
