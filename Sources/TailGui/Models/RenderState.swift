import Foundation

enum RenderPhase: Equatable {
    case starting
    case sampling
    case encoding
    case betweenClips
    case done
}

struct RenderState: Equatable {
    var outputFolder: String?
    var totalPasses: Int?
    var clipsPerPass: Int?
    var totalClips: Int?
    var resolution: String?
    var totalSteps: Int?
    var totalFrames: Int?
    var sampler: String?
    var cfg: Double?
    var fps: Int?
    var grpcEndpoint: String?
    var grpcConnected: Bool = false

    var currentPass: Int?
    var passVariants: [String] = []
    var currentClipInPass: Int?
    var currentClipName: String?
    var currentClipSource: String?
    var currentPrompt: String?
    var currentStep: Int?

    var phase: RenderPhase = .starting

    var completedClips: [CompletedClip] = []
    var lastUpdate: Date = .init()

    var totalCompleted: Int { completedClips.count }

    var overallProgress: Double {
        guard let total = totalClips, total > 0 else { return 0 }
        return min(1.0, Double(totalCompleted) / Double(total))
    }

    var stepProgress: Double {
        guard let cur = currentStep, let total = totalSteps, total > 0 else { return 0 }
        return min(1.0, Double(cur) / Double(total))
    }

    var passProgress: Double {
        guard let inPass = currentClipInPass, let perPass = clipsPerPass, perPass > 0 else { return 0 }
        return min(1.0, Double(inPass) / Double(perPass))
    }

    var averageClipDuration: TimeInterval? {
        let durations = completedClips.compactMap { $0.durationSeconds }
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    var etaSeconds: TimeInterval? {
        guard let avg = averageClipDuration, let total = totalClips else { return nil }
        let remaining = max(0, total - totalCompleted)
        return avg * Double(remaining)
    }

    var isFinished: Bool {
        guard let total = totalClips else { return false }
        return totalCompleted >= total
    }

    var settingsLine: String {
        var parts: [String] = []
        if let r = resolution { parts.append(r) }
        if let s = totalSteps { parts.append("\(s) steps") }
        if let f = totalFrames { parts.append("\(f) frames") }
        if let fps { parts.append("\(fps) fps") }
        if let cfg { parts.append("cfg \(formatDouble(cfg))") }
        if let sampler { parts.append("sampler \(sampler)") }
        return parts.joined(separator: " · ")
    }

    var outputFolderName: String {
        guard let p = outputFolder else { return "—" }
        return (p as NSString).lastPathComponent
    }

    private func formatDouble(_ d: Double) -> String {
        if d == floor(d) { return String(Int(d)) }
        return String(format: "%.1f", d)
    }
}

struct CompletedClip: Equatable, Identifiable {
    let id = UUID()
    let label: String
    let frameCount: Int?
    let durationText: String?
    let durationSeconds: TimeInterval?
    let completedAt: Date

    static func == (lhs: CompletedClip, rhs: CompletedClip) -> Bool {
        lhs.id == rhs.id
    }
}
