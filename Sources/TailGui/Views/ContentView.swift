import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: TailMonitor
    @ObservedObject var controller: WindowController

    @State private var selectedID: TailSession.ID? = nil
    @State private var now: Date = Date()

    private let clock = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            SidebarView(monitor: monitor, selectedID: $selectedID, now: now)
        } detail: {
            if let session = currentSession {
                DetailView(session: session)
            } else {
                DetailEmptyView()
            }
        }
        .background(VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow).ignoresSafeArea())
        .background(WindowAccessor(controller: controller))
        .toolbar { TailToolbar(controller: controller) }
        .navigationTitle("")
        .onReceive(clock) { _ in
            now = Date()
        }
        .onChange(of: monitor.sessions.map(\.id)) { _, ids in
            if let sel = selectedID, !ids.contains(sel) {
                selectedID = ids.first
            } else if selectedID == nil {
                selectedID = ids.first
            }
        }
        .animation(.smooth(duration: 0.25), value: monitor.sessions.map(\.id))
    }

    private var currentSession: TailSession? {
        guard let id = selectedID else { return nil }
        return monitor.sessions.first(where: { $0.id == id })
    }
}
