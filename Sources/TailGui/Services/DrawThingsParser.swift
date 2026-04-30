import Foundation

enum DrawThingsParser {
    static func parse(_ rawContent: String) -> RenderState {
        var state = RenderState()
        let normalized = rawContent.replacingOccurrences(of: "\r\n", with: "\n")
        let allLines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for rawLine in allLines {
            for sub in splitOnCarriageReturns(rawLine) {
                processLine(sub, into: &state)
            }
        }

        if state.totalClips == nil, let p = state.totalPasses, let c = state.clipsPerPass {
            state.totalClips = p * c
        }
        return state
    }

    private static func splitOnCarriageReturns(_ line: String) -> [String] {
        if !line.contains("\r") { return [line] }
        return line.split(separator: "\r", omittingEmptySubsequences: true).map(String.init)
    }

    private static func processLine(_ raw: String, into state: inout RenderState) {
        let line = raw
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return }

        if trimmed.hasPrefix("→ Output:") {
            state.outputFolder = trimmed.replacingOccurrences(of: "→ Output:", with: "")
                .trimmingCharacters(in: .whitespaces)
            return
        }
        if trimmed.hasPrefix("→ Passes:") {
            parsePassesLine(trimmed, into: &state)
            return
        }
        if trimmed.hasPrefix("→ Settings:") {
            parseSettingsLine(trimmed, into: &state)
            return
        }
        if trimmed.contains("Pinging gRPC") {
            parseGrpcLine(trimmed, into: &state)
            return
        }
        if let pass = matchPassHeader(trimmed) {
            state.currentPass = pass
            state.passVariants = []
            return
        }
        if trimmed.hasPrefix("Variants:") {
            let rhs = trimmed.replacingOccurrences(of: "Variants:", with: "").trimmingCharacters(in: .whitespaces)
            state.passVariants = rhs.split(whereSeparator: { $0 == "·" || $0 == "•" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return
        }
        if let clip = matchClipHeader(trimmed) {
            state.currentClipInPass = clip.index
            state.currentClipName = clip.name
            state.currentClipSource = clip.source
            state.currentPrompt = nil
            state.currentStep = nil
            state.phase = .betweenClips
            return
        }
        if trimmed.hasPrefix("prompt:") {
            let prompt = trimmed.replacingOccurrences(of: "prompt:", with: "").trimmingCharacters(in: .whitespaces)
            state.currentPrompt = prompt
            return
        }
        if let step = matchStep(trimmed) {
            state.currentStep = step
            state.phase = .sampling
            state.lastUpdate = Date()
            return
        }
        if let completion = matchCompletion(trimmed) {
            recordCompletion(completion, into: &state)
            state.phase = .encoding
            return
        }
        if isBatchComplete(trimmed) {
            state.phase = .done
            return
        }
    }

    private static func isBatchComplete(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("batch complete") || lower.contains("✓ done") || lower.hasPrefix("done in ")
    }

    private static let passHeaderRegex = try! NSRegularExpression(pattern: #"^=+\s*Pass\s+(\d+)/(\d+)\s*=+$"#)
    private static func matchPassHeader(_ line: String) -> Int? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = passHeaderRegex.firstMatch(in: line, range: range),
              let r = Range(m.range(at: 1), in: line),
              let pass = Int(line[r]) else { return nil }
        return pass
    }

    private struct ClipHeader {
        let index: Int
        let name: String
        let source: String?
    }

    private static let clipHeaderRegex = try! NSRegularExpression(
        pattern: #"^\[(\d+)\/(\d+)\]\s+(.+?)(?:\s+←\s+(.+))?$"#
    )
    private static func matchClipHeader(_ line: String) -> ClipHeader? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = clipHeaderRegex.firstMatch(in: line, range: range),
              let idxR = Range(m.range(at: 1), in: line),
              let nameR = Range(m.range(at: 3), in: line),
              let idx = Int(line[idxR]) else { return nil }
        let name = String(line[nameR]).trimmingCharacters(in: .whitespaces)
        var source: String? = nil
        if let srcR = Range(m.range(at: 4), in: line) {
            source = String(line[srcR]).trimmingCharacters(in: .whitespaces)
        }
        return ClipHeader(index: idx, name: name, source: source)
    }

    private static let stepRegex = try! NSRegularExpression(pattern: #"^step\s+(\d+)\/(\d+)$"#)
    private static func matchStep(_ line: String) -> Int? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = stepRegex.firstMatch(in: line, range: range),
              let r = Range(m.range(at: 1), in: line),
              let step = Int(line[r]) else { return nil }
        return step
    }

    private struct Completion {
        let frames: Int?
        let durationText: String
        let durationSeconds: TimeInterval?
    }

    private static let completionRegex = try! NSRegularExpression(
        pattern: #"got\s+(\d+)\s+frames?\s+in\s+([0-9hms\s]+?)(?:,|$|\s+encoding)"#,
        options: [.caseInsensitive]
    )
    private static func matchCompletion(_ line: String) -> Completion? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = completionRegex.firstMatch(in: line, range: range),
              let framesR = Range(m.range(at: 1), in: line),
              let durR = Range(m.range(at: 2), in: line) else { return nil }
        let frames = Int(line[framesR])
        let durText = String(line[durR]).trimmingCharacters(in: .whitespaces)
        return Completion(frames: frames, durationText: durText, durationSeconds: parseDuration(durText))
    }

    private static func recordCompletion(_ c: Completion, into state: inout RenderState) {
        let label = state.currentClipName ?? "clip"
        let clip = CompletedClip(
            label: label,
            frameCount: c.frames,
            durationText: c.durationText,
            durationSeconds: c.durationSeconds,
            completedAt: Date()
        )
        let alreadyCounted = state.completedClips.last.map { last in
            last.label == clip.label && last.durationText == clip.durationText
        } ?? false
        if !alreadyCounted {
            state.completedClips.append(clip)
        }
        state.currentStep = state.totalSteps
        state.lastUpdate = Date()
    }

    private static func parsePassesLine(_ line: String, into state: inout RenderState) {
        let rhs = line.replacingOccurrences(of: "→ Passes:", with: "")
        let segments = rhs.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        for seg in segments {
            if let n = firstInt(in: seg) {
                if seg.lowercased().contains("clips per") {
                    state.clipsPerPass = n
                } else if seg.lowercased().contains("total") {
                    state.totalClips = n
                } else {
                    state.totalPasses = n
                }
            }
        }
    }

    private static func parseSettingsLine(_ line: String, into state: inout RenderState) {
        let rhs = line.replacingOccurrences(of: "→ Settings:", with: "")
        let parts = rhs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for part in parts {
            let lower = part.lowercased()
            if part.contains("×") || part.contains("x") {
                if let _ = part.firstIndex(of: "×") ?? part.firstIndex(where: { "x" == $0 }),
                   part.contains(where: { $0.isNumber }) {
                    let cleaned = part.replacingOccurrences(of: " ", with: "")
                    if cleaned.contains("×") || cleaned.contains("x") {
                        state.resolution = cleaned.replacingOccurrences(of: "x", with: "×")
                        continue
                    }
                }
            }
            if lower.contains("step") {
                if let n = firstInt(in: part) { state.totalSteps = n }
            } else if lower.contains("frame") {
                if let n = firstInt(in: part) { state.totalFrames = n }
            } else if lower.hasPrefix("sampler=") {
                state.sampler = String(part.dropFirst("sampler=".count))
            } else if lower.hasPrefix("cfg=") {
                let v = String(part.dropFirst("cfg=".count))
                state.cfg = Double(v)
            } else if lower.hasPrefix("fps=") {
                let v = String(part.dropFirst("fps=".count))
                state.fps = Int(v)
            }
        }
    }

    private static func parseGrpcLine(_ line: String, into state: inout RenderState) {
        if let atRange = line.range(of: "at ") {
            let rest = line[atRange.upperBound...]
            let endpoint = rest.split(whereSeparator: { $0 == "…" || $0 == "." && rest.firstIndex(of: $0) != nil || $0.isWhitespace }).first
            if let ep = endpoint {
                state.grpcEndpoint = String(ep)
            } else {
                let parts = rest.split(separator: "…")
                if let first = parts.first {
                    state.grpcEndpoint = String(first).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        let lower = line.lowercased()
        if lower.contains("ok") || lower.contains("connected") {
            state.grpcConnected = true
        }
    }

    private static func firstInt(in s: String) -> Int? {
        var current = ""
        var found: Int? = nil
        for ch in s {
            if ch.isNumber { current.append(ch) }
            else if !current.isEmpty {
                found = Int(current)
                break
            }
        }
        if found == nil, !current.isEmpty { found = Int(current) }
        return found
    }

    private static func parseDuration(_ s: String) -> TimeInterval? {
        var hours = 0, minutes = 0, seconds = 0
        var current = ""
        for ch in s {
            if ch.isNumber { current.append(ch); continue }
            switch ch {
            case "h", "H":
                hours = Int(current) ?? 0
                current = ""
            case "m", "M":
                minutes = Int(current) ?? 0
                current = ""
            case "s", "S":
                seconds = Int(current) ?? 0
                current = ""
            default:
                continue
            }
        }
        if !current.isEmpty {
            seconds = Int(current) ?? seconds
        }
        let total = TimeInterval(hours * 3600 + minutes * 60 + seconds)
        return total > 0 ? total : nil
    }
}
