import SwiftUI

struct TailRowView: View {
    @ObservedObject var session: TailSession
    let now: Date

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            badge
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.fileName)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                if let hint = PathParsing.parse(session.filePath) {
                    Text("\(hint.sessionPrefix) · \(hint.projectSlug)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    statusPill
                    Text(DateFormatting.relativeString(from: session.startedAt, to: now))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var badge: some View {
        switch session.verdict {
        case .confirmed:
            Image(systemName: "paintbrush.pointed.fill")
                .foregroundStyle(.tint)
                .imageScale(.medium)
                .frame(width: 18)
        case .pending:
            Image(systemName: "hourglass")
                .foregroundStyle(.secondary)
                .imageScale(.medium)
                .frame(width: 18)
        case .rejected:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.tertiary)
                .imageScale(.medium)
                .frame(width: 18)
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .modifier(PulseIfLive(active: session.status == .live))
            Text(statusLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
        .help(statusTooltip)
    }

    private var statusColor: Color {
        switch session.status {
        case .live: return .green
        case .sampling: return .green
        case .encoding: return .blue
        case .idle: return .yellow
        case .stale: return .red
        case .terminated: return .gray
        }
    }

    private var statusLabel: String {
        switch session.status {
        case .live: return "live"
        case .sampling: return "sampling"
        case .encoding: return "encoding"
        case .idle: return "idle"
        case .stale: return "stale"
        case .terminated: return "ended"
        }
    }

    private var statusTooltip: String {
        switch session.status {
        case .live: return "Bytes written within the last 10s"
        case .sampling: return "Sampling — Draw Things writes one step every 60–90s"
        case .encoding: return "Encoding MP4 — brief silence is normal"
        case .idle: return "Quiet, but Draw Things and gRPC look healthy"
        case .stale: return "Draw Things process gone or gRPC unreachable"
        case .terminated: return "Tail process ended"
        }
    }
}

private struct PulseIfLive: ViewModifier {
    let active: Bool
    @State private var on = false

    func body(content: Content) -> some View {
        if active {
            content
                .opacity(on ? 0.55 : 1.0)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
                .onAppear { on = true }
        } else {
            content
        }
    }
}
