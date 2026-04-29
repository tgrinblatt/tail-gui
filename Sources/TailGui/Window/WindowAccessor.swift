import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    let controller: WindowController

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        v.wantsLayer = false
        DispatchQueue.main.async {
            if let window = v.window {
                controller.bind(window)
            }
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window, controller.window !== window {
                controller.bind(window)
            }
        }
    }
}
