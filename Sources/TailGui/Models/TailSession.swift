import Foundation
import Combine

@MainActor
final class TailSession: ObservableObject, Identifiable {
    enum Status: Equatable {
        case live
        case sampling
        case encoding
        case idle
        case stale
        case terminated
    }

    enum Verdict: Equatable {
        case pending
        case confirmed
        case rejected
    }

    let filePath: String
    let startedAt: Date

    @Published var pids: Set<Int32>
    @Published var content: String = ""
    @Published var status: Status = .live
    @Published var verdict: Verdict = .pending
    @Published var lastWriteAt: Date
    @Published var renderState: RenderState = RenderState()
    @Published var health: RenderHealth = .unknown

    nonisolated var id: String { filePath }

    nonisolated var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    var displayContent: String {
        TailSession.sanitize(content)
    }

    static func sanitize(_ text: String) -> String {
        guard text.contains("\r") else { return text }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var out = ""
        out.reserveCapacity(normalized.count)
        var lineStart = out.endIndex
        for ch in normalized {
            if ch == "\r" {
                out.removeSubrange(lineStart..<out.endIndex)
            } else if ch == "\n" {
                out.append(ch)
                lineStart = out.endIndex
            } else {
                out.append(ch)
            }
        }
        return out
    }

    private(set) var tailer: FileTailer?

    init(filePath: String, pid: Int32, discoveredAt: Date) {
        self.filePath = filePath
        self.startedAt = discoveredAt
        self.pids = [pid]
        self.lastWriteAt = discoveredAt
    }

    func attach(_ tailer: FileTailer) {
        self.tailer = tailer
    }

    func recomputeStatus(now: Date = Date()) {
        guard status != .terminated else { return }
        let delta = now.timeIntervalSince(lastWriteAt)

        // External signals win when we have actual data and they're red.
        if health.hasBeenChecked && !health.isAlive {
            status = .stale
            return
        }

        // Otherwise, log silence is interpreted relative to the render's phase.
        let phase = renderState.phase
        switch (phase, delta) {
        case (_, ..<10):
            status = .live
        case (.sampling, ..<180):
            status = .sampling
        case (.encoding, ..<30):
            status = .encoding
        case (.betweenClips, ..<60):
            status = .live
        case (.done, _):
            status = .live
        default:
            status = .idle
        }
    }

    func updateHealth(_ newHealth: RenderHealth) {
        health = newHealth
        recomputeStatus()
    }

    func appendChunk(_ data: Data) {
        guard let str = String(data: data, encoding: .utf8) else { return }
        content.append(str)
        let cap = 256 * 1024
        if content.count > cap {
            let overflow = content.count - cap
            content.removeFirst(overflow)
        }
        lastWriteAt = Date()
        recomputeStatus()
        reparse()
    }

    func resetContent(_ data: Data) {
        guard let str = String(data: data, encoding: .utf8) else { return }
        content = str
        lastWriteAt = Date()
        recomputeStatus()
        reparse()
    }

    private func reparse() {
        renderState = DrawThingsParser.parse(content)
    }

    func markTerminated() {
        status = .terminated
        tailer?.stop()
        tailer = nil
    }
}
