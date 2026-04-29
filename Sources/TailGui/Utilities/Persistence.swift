import Foundation
import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum Persistence {
    private static let pinnedKey = "TailGui.window.isPinned"
    private static let alphaKey = "TailGui.window.alpha"

    static var isPinned: Bool {
        get { UserDefaults.standard.bool(forKey: pinnedKey) }
        set { UserDefaults.standard.set(newValue, forKey: pinnedKey) }
    }

    static var alpha: Double {
        get {
            let raw = UserDefaults.standard.object(forKey: alphaKey) as? Double
            let value = raw ?? 1.0
            return max(0.3, min(1.0, value))
        }
        set { UserDefaults.standard.set(max(0.3, min(1.0, newValue)), forKey: alphaKey) }
    }
}
