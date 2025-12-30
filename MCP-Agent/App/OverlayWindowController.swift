import Cocoa
import SwiftUI

class OverlayWindowController: NSObject {
    static let shared = OverlayWindowController()
    
    private var window: NSWindow?
    
    override private init() {
        super.init()
    }
    
    func show() {
        if window == nil {
            let contentView = OverlayView()
            
            // Create a transparent window
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            window?.contentView = NSHostingView(rootView: contentView)
            window?.backgroundColor = .clear
            window?.isOpaque = false
            window?.hasShadow = false
            window?.level = .floating
            window?.center()
            window?.isReleasedWhenClosed = false
        }
        
        window?.orderFront(nil)
    }
    
    func hide() {
        window?.orderOut(nil)
    }
}

struct OverlayView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.7))
            
            Text("BuddyMCP Active")
                .foregroundColor(.white)
                .padding()
        }
        .frame(width: 200, height: 50)
    }
}
