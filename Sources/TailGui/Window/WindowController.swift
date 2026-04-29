import AppKit
import Combine

@MainActor
final class WindowController: ObservableObject {
    weak var window: NSWindow? {
        didSet { applyAll() }
    }

    @Published var isPinned: Bool {
        didSet {
            apply()
            Persistence.isPinned = isPinned
        }
    }

    @Published var alpha: Double {
        didSet {
            apply()
            Persistence.alpha = alpha
        }
    }

    init() {
        self.isPinned = Persistence.isPinned
        self.alpha = Persistence.alpha
    }

    func bind(_ window: NSWindow) {
        guard self.window !== window else { return }
        let firstBind = self.window == nil
        self.window = window
        if firstBind {
            window.setFrameAutosaveName("TailGuiMainWindow")
            if window.frame.origin == .zero || !isFrameOnScreen(window.frame) {
                let target = defaultFrame()
                window.setFrame(target, display: true)
                window.center()
            }
        }
    }

    private func defaultFrame() -> NSRect {
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let width: CGFloat = min(960, visible.width * 0.6)
            let height: CGFloat = min(620, visible.height * 0.7)
            let x = visible.midX - width / 2
            let y = visible.midY - height / 2
            return NSRect(x: x, y: y, width: width, height: height)
        }
        return NSRect(x: 200, y: 200, width: 960, height: 620)
    }

    private func isFrameOnScreen(_ frame: NSRect) -> Bool {
        for screen in NSScreen.screens where screen.visibleFrame.intersects(frame) {
            return true
        }
        return false
    }

    private func apply() {
        guard let window = window else { return }
        window.level = isPinned ? .floating : .normal
        var behavior: NSWindow.CollectionBehavior = [.managed]
        if isPinned {
            behavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
        window.collectionBehavior = behavior
        window.alphaValue = CGFloat(alpha)
        window.isOpaque = false
        if window.backgroundColor != .clear {
            window.backgroundColor = .clear
        }
    }

    private func applyAll() { apply() }
}
