import SwiftUI

private struct CardContainer<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }
}

private struct ChipView: View {
    let label: String
    let icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(label)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
        .foregroundStyle(.secondary)
    }
}

struct RenderHeaderCard: View {
    let state: RenderState

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.tint)
                    Text(state.outputFolderName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if state.grpcEndpoint != nil {
                        ChipView(
                            label: state.grpcConnected ? "gRPC connected" : "connecting…",
                            icon: state.grpcConnected ? "checkmark.circle.fill" : "circle.dashed"
                        )
                        .foregroundStyle(state.grpcConnected ? Color.green : Color.orange)
                    }
                }
                if !state.settingsLine.isEmpty {
                    Text(state.settingsLine)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

struct OverallProgressCard: View {
    let state: RenderState

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Overall", systemImage: "chart.bar.fill")
                        .font(.subheadline.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                    Spacer()
                    if let total = state.totalClips {
                        Text("\(state.totalCompleted) / \(total) clips")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else if state.totalCompleted > 0 {
                        Text("\(state.totalCompleted) clips")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressBar(value: state.overallProgress, height: 10)

                HStack(spacing: 12) {
                    if let pass = state.currentPass, let total = state.totalPasses {
                        ChipView(label: "Pass \(pass) of \(total)", icon: "rectangle.stack")
                    }
                    if state.overallProgress > 0 {
                        ChipView(label: "\(Int(state.overallProgress * 100))%", icon: "percent")
                    }
                    if let eta = state.etaSeconds, eta > 0, !state.isFinished {
                        ChipView(label: "ETA " + formatETA(eta), icon: "hourglass")
                    }
                    if state.isFinished {
                        ChipView(label: "Finished", icon: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    private func formatETA(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h\(String(format: "%02d", m))m" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }
}

struct CurrentClipCard: View {
    let state: RenderState
    let sessionStatus: TailSession.Status

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Current clip", systemImage: "film.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if let perPass = state.clipsPerPass, let inPass = state.currentClipInPass {
                        Text("[\(inPass)/\(perPass)]")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                if let name = state.currentClipName {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(name)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let src = state.currentClipSource {
                            ChipView(label: src, icon: "arrow.left")
                        }
                    }
                } else {
                    Text(sessionStatus == .terminated ? "Render ended" : "Waiting for next clip…")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let prompt = state.currentPrompt, !prompt.isEmpty {
                    Text(prompt)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                stepRow
            }
        }
    }

    @ViewBuilder
    private var stepRow: some View {
        if state.totalSteps != nil {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Steps")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(state.currentStep ?? 0) / \(state.totalSteps ?? 0)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ProgressBar(value: state.stepProgress, height: 6)
            }
        }
    }
}

struct RecentActivityCard: View {
    let state: RenderState

    private var recent: [CompletedClip] {
        Array(state.completedClips.suffix(5).reversed())
    }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Label("Recent clips", systemImage: "clock.fill")
                    .font(.subheadline.weight(.semibold))
                ForEach(recent) { clip in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text(clip.label)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        if let frames = clip.frameCount {
                            Text("\(frames) frames")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let dur = clip.durationText {
                            Text(dur)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}

struct ProgressBar: View {
    let value: Double
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.quaternary.opacity(0.6))
                Capsule(style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: max(0, geo.size.width * CGFloat(min(1, max(0, value)))))
                    .animation(.easeOut(duration: 0.25), value: value)
            }
        }
        .frame(height: height)
    }
}
