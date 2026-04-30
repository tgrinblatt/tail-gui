import SwiftUI

struct SidebarView: View {
    @ObservedObject var monitor: TailMonitor
    @Binding var selectedID: TailSession.ID?
    let now: Date

    var body: some View {
        Group {
            if monitor.sessions.isEmpty {
                emptyState
            } else {
                List(monitor.sessions, selection: $selectedID) { session in
                    TailRowView(session: session, now: now)
                        .tag(session.id as TailSession.ID?)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Renders")
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "paintbrush.pointed")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Draw Things renders detected")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Tail Gui auto-detects active Draw Things renders writing to Claude Code task outputs. Start one — it will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
