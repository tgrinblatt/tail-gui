import SwiftUI
import AppKit

struct DetailView: View {
    @ObservedObject var session: TailSession
    @State private var showRaw: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            if showRaw {
                rawScrollView
            } else {
                renderDashboard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.fileName)
                    .font(.system(.headline, design: .monospaced))
                Text(session.filePath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Toggle(isOn: $showRaw) {
                    Label("Raw", systemImage: "text.alignleft")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Switch between dashboard and raw log")

                Button {
                    let text = showRaw ? session.displayContent : session.displayContent
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .help("Copy log text")

                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: session.filePath))
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                .controlSize(.small)
                .help("Open file in default app")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var renderDashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                RenderHeaderCard(state: session.renderState)
                OverallProgressCard(state: session.renderState)
                CurrentClipCard(state: session.renderState, sessionStatus: session.status)
                if !session.renderState.completedClips.isEmpty {
                    RecentActivityCard(state: session.renderState)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var rawScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.content.isEmpty ? "Waiting for output…" : session.displayContent)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .id("content")
            }
            .scrollContentBackground(.hidden)
            .onChange(of: session.displayContent) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}

struct DetailEmptyView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "paintbrush.pointed")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Select a render")
                .font(.headline)
            Text("Pick a tail from the sidebar to watch its progress here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
