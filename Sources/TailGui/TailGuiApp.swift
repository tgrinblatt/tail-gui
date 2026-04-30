import SwiftUI

@main
struct TailGuiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = TailMonitor()
    @StateObject private var controller = WindowController()
    @AppStorage("TailGui.appearance") private var appearanceRaw: String = AppearanceMode.dark.rawValue

    private var preferredScheme: ColorScheme {
        (AppearanceMode(rawValue: appearanceRaw) ?? .dark).colorScheme
    }

    var body: some Scene {
        Window("Tail Gui", id: "main") {
            ContentView(monitor: monitor, controller: controller)
                .frame(minWidth: 720, minHeight: 480)
                .preferredColorScheme(preferredScheme)
                .onAppear {
                    monitor.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About Tail Gui") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
        }
    }
}
